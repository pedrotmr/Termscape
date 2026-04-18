import Foundation
import XCTest

@testable import Termscape

@MainActor
final class FileTreeIndexTests: XCTestCase {
  func testRootLoadIsShallowAndChildrenLoadLazily() async throws {
    let root = try makeTempDirectory()
    let src = root.appendingPathComponent("Sources", isDirectory: true)
    let nested = src.appendingPathComponent("Nested", isDirectory: true)
    let file = root.appendingPathComponent("README.md")

    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("hi".utf8).write(to: file)

    let index = FileTreeIndex(rootPath: root.path)
    let rootChildren = try await loadChildrenAndWait(index, path: root.path)

    XCTAssertTrue(rootChildren.contains(where: { $0.name == "Sources" && $0.isDirectory }))
    XCTAssertTrue(rootChildren.contains(where: { $0.name == "README.md" && !$0.isDirectory }))

    let sourceNode = try XCTUnwrap(rootChildren.first(where: { $0.name == "Sources" }))
    let sourceChildren = try await loadChildrenAndWait(index, path: sourceNode.path)
    XCTAssertTrue(sourceChildren.contains(where: { $0.name == "Nested" && $0.isDirectory }))
  }

  func testInvalidationNotifiesAllRegisteredObservers() throws {
    let root = try makeTempDirectory()
    let index = FileTreeIndex(rootPath: root.path)
    var firstCount = 0
    var secondCount = 0
    let firstId = UUID()
    let secondId = UUID()
    index.addInvalidationObserver(id: firstId) { firstCount += 1 }
    index.addInvalidationObserver(id: secondId) { secondCount += 1 }

    index.test_invalidateTreeCache()

    XCTAssertEqual(firstCount, 1)
    XCTAssertEqual(secondCount, 1)

    index.removeInvalidationObserver(id: firstId)
    index.test_invalidateTreeCache()

    XCTAssertEqual(firstCount, 1)
    XCTAssertEqual(secondCount, 2)
  }

  func testUnreadablePathIsNotCachedAsEmptyAndCanRetry() async throws {
    let root = try makeTempDirectory()
    let tricky = root.appendingPathComponent("tricky")
    try Data("x".utf8).write(to: tricky)

    let index = FileTreeIndex(rootPath: root.path)
    index.scheduleLoadChildren(for: tricky.path)
    try await Task.sleep(nanoseconds: 80_000_000)

    XCTAssertNil(
      index.cachedChildren(for: tricky.path),
      "A failed directory read must not be stored as an empty listing"
    )

    try FileManager.default.removeItem(at: tricky)
    try FileManager.default.createDirectory(at: tricky, withIntermediateDirectories: true)
    let child = tricky.appendingPathComponent("child.txt")
    try Data().write(to: child)

    index.scheduleLoadChildren(for: tricky.path)
    let children = try await loadChildrenAndWait(index, path: tricky.path)
    XCTAssertTrue(children.contains { $0.name == "child.txt" && !$0.isDirectory })
  }

  func testPoolSharesIndexByRootPath() throws {
    let root = try makeTempDirectory()
    let first = FileTreeIndexPool.retainIndex(for: root.path)
    let second = FileTreeIndexPool.retainIndex(for: root.path)
    XCTAssertTrue(first === second)

    FileTreeIndexPool.releaseIndex(for: root.path)
    FileTreeIndexPool.releaseIndex(for: root.path)

    let third = FileTreeIndexPool.retainIndex(for: root.path)
    XCTAssertFalse(first === third)
    FileTreeIndexPool.releaseIndex(for: root.path)
  }

  @MainActor
  private func loadChildrenAndWait(_ index: FileTreeIndex, path: String) async throws -> [FileTreeIndex.Node] {
    index.scheduleLoadChildren(for: path)
    for _ in 0..<500 {
      if let children = index.cachedChildren(for: path) {
        return children
      }
      try await Task.sleep(nanoseconds: 4_000_000)
    }
    XCTFail("Timed out waiting for children of \(path)")
    return []
  }

  private func makeTempDirectory() throws -> URL {
    let base = FileManager.default.temporaryDirectory
    let url = base.appendingPathComponent("termscape-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }
}
