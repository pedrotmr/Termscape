import Foundation
import XCTest

@testable import Termscape

@MainActor
final class FileTreeIndexTests: XCTestCase {
  func testRootLoadIsShallowAndChildrenLoadLazily() throws {
    let root = try makeTempDirectory()
    let src = root.appendingPathComponent("Sources", isDirectory: true)
    let nested = src.appendingPathComponent("Nested", isDirectory: true)
    let file = root.appendingPathComponent("README.md")

    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("hi".utf8).write(to: file)

    let index = FileTreeIndex(rootPath: root.path)
    let rootChildren = index.rootChildren()

    XCTAssertTrue(rootChildren.contains(where: { $0.name == "Sources" && $0.isDirectory }))
    XCTAssertTrue(rootChildren.contains(where: { $0.name == "README.md" && !$0.isDirectory }))

    let sourceNode = try XCTUnwrap(rootChildren.first(where: { $0.name == "Sources" }))
    let sourceChildren = index.children(for: sourceNode.path)
    XCTAssertTrue(sourceChildren.contains(where: { $0.name == "Nested" && $0.isDirectory }))
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

  private func makeTempDirectory() throws -> URL {
    let base = FileManager.default.temporaryDirectory
    let url = base.appendingPathComponent("termscape-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
