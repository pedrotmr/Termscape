import XCTest

@testable import Termscape

@MainActor
final class EditorDocumentStoreTests: XCTestCase {
  private func tempDir() throws -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("termscape-doc-store-\(UUID().uuidString)", isDirectory: true)
  }

  func testOpenAndSaveClean() throws {
    let dir = try tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("sample.txt")
    try "hello".write(to: file, atomically: true, encoding: .utf8)

    let store = EditorDocumentStore()
    let id = try store.openDocument(at: file)
    XCTAssertFalse(store.buffer(id: id)!.isDirty)

    _ = try store.saveDocument(id: id)
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello")
  }

  func testDirtyAfterEditAndSave() throws {
    let dir = try tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("edit.txt")
    try "a".write(to: file, atomically: true, encoding: .utf8)

    let store = EditorDocumentStore()
    let id = try store.openDocument(at: file)
    store.updateWorkingText(id: id, text: "ab")
    XCTAssertTrue(store.buffer(id: id)!.isDirty)

    let outcome = try store.saveDocument(id: id)
    XCTAssertEqual(outcome, .wrote)
    XCTAssertFalse(store.buffer(id: id)!.isDirty)
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "ab")
  }

  func testSaveConflictWhenDirtyAndDiskChanged() throws {
    let dir = try tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("race.txt")
    try "v1".write(to: file, atomically: true, encoding: .utf8)

    let store = EditorDocumentStore()
    let id = try store.openDocument(at: file)
    store.updateWorkingText(id: id, text: "v1-local")

    try "v2-remote".write(to: file, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(try store.saveDocument(id: id)) { error in
      guard case EditorDocumentSaveError.conflict(let c) = error else {
        XCTFail("expected conflict, got \(error)")
        return
      }
      XCTAssertEqual(c.diskText, "v2-remote")
    }
  }

  func testCleanBufferAutoReloadsWhenDiskContentChanges() throws {
    let dir = try tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("sync.txt")
    try "one".write(to: file, atomically: true, encoding: .utf8)

    let store = EditorDocumentStore()
    let id = try store.openDocument(at: file)
    XCTAssertFalse(store.buffer(id: id)!.isDirty)

    try "two".write(to: file, atomically: true, encoding: .utf8)

    let outcome = try store.saveDocument(id: id)
    XCTAssertEqual(outcome, .reloadedCleanFromDisk)
    XCTAssertEqual(store.buffer(id: id)?.workingText, "two")
    XCTAssertFalse(store.buffer(id: id)!.isDirty)
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

  func testForcedOverwriteAfterConflict() throws {
    let dir = try tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("force.txt")
    try "remote".write(to: file, atomically: true, encoding: .utf8)

    let store = EditorDocumentStore()
    let id = try store.openDocument(at: file)
    store.updateWorkingText(id: id, text: "mine")
    try "other".write(to: file, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(try store.saveDocument(id: id))

    let outcome = try store.saveDocumentForcedOverwrite(id: id)
    XCTAssertEqual(outcome, .wrote)
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "mine")
    XCTAssertFalse(store.buffer(id: id)!.isDirty)
  }
}
