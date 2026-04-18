@testable import Termscape
import XCTest

@MainActor
final class EditorDocumentStoreTests: XCTestCase {
    private var tempDirsToCleanup: [URL] = []

    override func tearDown() {
        let fm = FileManager.default
        for url in tempDirsToCleanup {
            try? fm.removeItem(at: url)
        }
        tempDirsToCleanup.removeAll()
        super.tearDown()
    }

    private func tempDir() throws -> URL {
        let url =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("termscape-doc-store-\(UUID().uuidString)", isDirectory: true)
        tempDirsToCleanup.append(url)
        return url
    }

    func testOpenAndSaveClean() async throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sample.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let store = EditorDocumentStore()
        let id = try store.openDocument(at: file)
        XCTAssertFalse(try XCTUnwrap(store.buffer(id: id)?.isDirty))

        _ = try await store.saveDocument(id: id)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello")
    }

    func testDirtyAfterEditAndSave() async throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("edit.txt")
        try "a".write(to: file, atomically: true, encoding: .utf8)

        let store = EditorDocumentStore()
        let id = try store.openDocument(at: file)
        store.updateWorkingText(id: id, text: "ab")
        XCTAssertTrue(try XCTUnwrap(store.buffer(id: id)?.isDirty))

        let outcome = try await store.saveDocument(id: id)
        XCTAssertEqual(outcome, .wrote)
        XCTAssertFalse(try XCTUnwrap(store.buffer(id: id)?.isDirty))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "ab")
    }

    func testSaveConflictWhenDirtyAndDiskChanged() async throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("race.txt")
        try "v1".write(to: file, atomically: true, encoding: .utf8)

        let store = EditorDocumentStore()
        let id = try store.openDocument(at: file)
        store.updateWorkingText(id: id, text: "v1-local")

        try "v2-remote".write(to: file, atomically: true, encoding: .utf8)

        do {
            _ = try await store.saveDocument(id: id)
            XCTFail("expected conflict")
        } catch let error as EditorDocumentSaveError {
            guard case let .conflict(c) = error else {
                XCTFail("expected conflict, got \(error)")
                return
            }
            XCTAssertEqual(c.diskText, "v2-remote")
        }
    }

    func testCleanBufferAutoReloadsWhenDiskContentChanges() async throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sync.txt")
        try "one".write(to: file, atomically: true, encoding: .utf8)

        let store = EditorDocumentStore()
        let id = try store.openDocument(at: file)
        XCTAssertFalse(try XCTUnwrap(store.buffer(id: id)?.isDirty))

        try "two".write(to: file, atomically: true, encoding: .utf8)

        let outcome = try await store.saveDocument(id: id)
        XCTAssertEqual(outcome, .reloadedCleanFromDisk)
        XCTAssertEqual(store.buffer(id: id)?.workingText, "two")
        XCTAssertFalse(try XCTUnwrap(store.buffer(id: id)?.isDirty))
    }

    func testOpenSameFileTwiceReturnsSameTab() throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("dup.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let store = EditorDocumentStore()
        let a = try store.openDocument(at: file)
        let b = try store.openDocument(at: file)
        XCTAssertEqual(a, b)
        XCTAssertEqual(store.buffersInTabOrder.count, 1)
    }

    func testNonUTF8OpenFails() throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("binary.dat")
        let bytes: [UInt8] = [0xFF, 0xFE, 0xFD]
        try Data(bytes).write(to: file)

        let store = EditorDocumentStore()
        XCTAssertThrowsError(try store.openDocument(at: file)) { err in
            XCTAssertEqual(err as? EditorDocumentOpenError, .unreadableUTF8(file.standardizedFileURL))
        }
    }

    func testForcedOverwriteAfterConflict() async throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("force.txt")
        try "remote".write(to: file, atomically: true, encoding: .utf8)

        let store = EditorDocumentStore()
        let id = try store.openDocument(at: file)
        store.updateWorkingText(id: id, text: "mine")
        try "other".write(to: file, atomically: true, encoding: .utf8)

        do {
            _ = try await store.saveDocument(id: id)
            XCTFail("expected conflict before overwrite")
        } catch let error as EditorDocumentSaveError {
            guard case .conflict = error else {
                XCTFail("expected conflict, got \(error)")
                return
            }
        }

        let outcome = try await store.saveDocumentForcedOverwrite(id: id)
        XCTAssertEqual(outcome, .wrote)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "mine")
        XCTAssertFalse(try XCTUnwrap(store.buffer(id: id)?.isDirty))
    }
}
