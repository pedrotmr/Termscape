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

  func testDirectLoadPrefetchesImmediateDirectories() async throws {
    let root = try makeTempDirectory()
    let src = root.appendingPathComponent("Sources", isDirectory: true)
    let docs = root.appendingPathComponent("Docs", isDirectory: true)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: src.appendingPathComponent("main.swift"))
    try Data("y".utf8).write(to: docs.appendingPathComponent("README.md"))

    let index = FileTreeIndex(rootPath: root.path)
    let rootChildren = try await loadChildrenAndWait(index, path: root.path)
    let sourceNode = try XCTUnwrap(rootChildren.first(where: { $0.name == "Sources" }))
    let docsNode = try XCTUnwrap(rootChildren.first(where: { $0.name == "Docs" }))

    _ = try await waitForChildrenCached(index, path: sourceNode.path)
    _ = try await waitForChildrenCached(index, path: docsNode.path)
  }

  func testPrefetchDoesNotCascadeToGrandchildren() async throws {
    let root = try makeTempDirectory()
    let level1 = root.appendingPathComponent("Level1", isDirectory: true)
    let level2 = level1.appendingPathComponent("Level2", isDirectory: true)
    try FileManager.default.createDirectory(at: level2, withIntermediateDirectories: true)
    try Data("z".utf8).write(to: level2.appendingPathComponent("leaf.txt"))

    let index = FileTreeIndex(rootPath: root.path)
    let rootChildren = try await loadChildrenAndWait(index, path: root.path)
    let level1Node = try XCTUnwrap(rootChildren.first(where: { $0.name == "Level1" }))

    let level1Children = try await waitForChildrenCached(index, path: level1Node.path)
    let level2Node = try XCTUnwrap(level1Children.first(where: { $0.name == "Level2" }))

    XCTAssertNil(index.cachedChildren(for: level2Node.path))
  }

  func testSearchFindsFilesAndDirectoriesCaseInsensitive() async throws {
    let root = try makeTempDirectory()
    let readings = root.appendingPathComponent("Readings", isDirectory: true)
    let readme = readings.appendingPathComponent("README.MD")
    try FileManager.default.createDirectory(at: readings, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: readme)

    let index = FileTreeIndex(rootPath: root.path)
    let results = await index.search(matching: "read", limit: 20)

    XCTAssertTrue(results.contains { $0.name == "README.MD" && !$0.isDirectory })
    XCTAssertTrue(results.contains { $0.name == "Readings" && $0.isDirectory })
  }

  func testSearchRespectsLimit() async throws {
    let root = try makeTempDirectory()
    for i in 0..<12 {
      let file = root.appendingPathComponent("alpha-\(i).txt")
      try Data("x".utf8).write(to: file)
    }

    let index = FileTreeIndex(rootPath: root.path)
    let results = await index.search(matching: "alpha", limit: 5)
    XCTAssertEqual(results.count, 5)
  }

  func testSearchIgnoresWhitespaceQuery() async throws {
    let root = try makeTempDirectory()
    let index = FileTreeIndex(rootPath: root.path)
    let results = await index.search(matching: "   ", limit: 10)
    XCTAssertTrue(results.isEmpty)
  }

  func testSearchDefaultsExcludeHiddenAndNodeModules() async throws {
    let root = try makeTempDirectory()
    let hidden = root.appendingPathComponent(".env")
    let nodeModules = root.appendingPathComponent("node_modules", isDirectory: true)
    let nested = nodeModules.appendingPathComponent("pkg", isDirectory: true)
    let moduleFile = nested.appendingPathComponent("module-entry.js")
    try Data("TOKEN=x".utf8).write(to: hidden)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("export default 1".utf8).write(to: moduleFile)

    let index = FileTreeIndex(rootPath: root.path)
    let hiddenResults = await index.search(matching: "env", limit: 20)
    let nodeModuleResults = await index.search(matching: "module-entry", limit: 20)

    XCTAssertFalse(hiddenResults.contains { $0.name == ".env" })
    XCTAssertFalse(nodeModuleResults.contains { $0.name == "module-entry.js" })
  }

  func testSearchCanIncludeHiddenAndNodeModules() async throws {
    let root = try makeTempDirectory()
    let hidden = root.appendingPathComponent(".env")
    let nodeModules = root.appendingPathComponent("node_modules", isDirectory: true)
    let nested = nodeModules.appendingPathComponent("pkg", isDirectory: true)
    let moduleFile = nested.appendingPathComponent("module-entry.js")
    try Data("TOKEN=x".utf8).write(to: hidden)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("export default 1".utf8).write(to: moduleFile)

    let index = FileTreeIndex(rootPath: root.path)
    let options = FileTreeIndex.SearchOptions(includeHiddenEntries: true, includeNodeModules: true)
    let hiddenResults = await index.search(matching: "env", limit: 20, options: options)
    let nodeModuleResults = await index.search(
      matching: "module-entry",
      limit: 20,
      options: options
    )

    XCTAssertTrue(hiddenResults.contains { $0.name == ".env" })
    XCTAssertTrue(nodeModuleResults.contains { $0.name == "module-entry.js" })
  }

  func testSearchDefaultsExcludeGitIgnoredFiles() async throws {
    let root = try makeTempDirectory()
    try runGit(arguments: ["init", "-q"], at: root)

    let ignoredDirectory = root.appendingPathComponent("ignored", isDirectory: true)
    let ignoredNested = ignoredDirectory.appendingPathComponent("nested", isDirectory: true)
    let ignoredFile = ignoredNested.appendingPathComponent("match-in-ignored.txt")
    let ignoredByPattern = root.appendingPathComponent("debug-match.log")
    let visibleFile = root.appendingPathComponent("keep-match.txt")
    let gitignore = root.appendingPathComponent(".gitignore")

    try FileManager.default.createDirectory(at: ignoredNested, withIntermediateDirectories: true)
    try Data("ignored/\n*.log\n".utf8).write(to: gitignore)
    try Data("x".utf8).write(to: ignoredFile)
    try Data("x".utf8).write(to: ignoredByPattern)
    try Data("x".utf8).write(to: visibleFile)

    let index = FileTreeIndex(rootPath: root.path)
    let baseline = await index.search(matching: "match", limit: 40)
    XCTAssertFalse(baseline.contains { $0.name == "match-in-ignored.txt" })
    XCTAssertFalse(baseline.contains { $0.name == "debug-match.log" })
    XCTAssertTrue(baseline.contains { $0.name == "keep-match.txt" })
  }

  func testSearchCanIncludeGitIgnoredFiles() async throws {
    let root = try makeTempDirectory()
    try runGit(arguments: ["init", "-q"], at: root)

    let ignoredDirectory = root.appendingPathComponent("ignored", isDirectory: true)
    let ignoredNested = ignoredDirectory.appendingPathComponent("nested", isDirectory: true)
    let ignoredFile = ignoredNested.appendingPathComponent("match-in-ignored.txt")
    let ignoredByPattern = root.appendingPathComponent("debug-match.log")
    let visibleFile = root.appendingPathComponent("keep-match.txt")
    let gitignore = root.appendingPathComponent(".gitignore")

    try FileManager.default.createDirectory(at: ignoredNested, withIntermediateDirectories: true)
    try Data("ignored/\n*.log\n".utf8).write(to: gitignore)
    try Data("x".utf8).write(to: ignoredFile)
    try Data("x".utf8).write(to: ignoredByPattern)
    try Data("x".utf8).write(to: visibleFile)

    let index = FileTreeIndex(rootPath: root.path)
    let filtered = await index.search(
      matching: "match",
      limit: 40,
      options: FileTreeIndex.SearchOptions(includeGitIgnoredEntries: true)
    )
    XCTAssertTrue(filtered.contains { $0.name == "match-in-ignored.txt" })
    XCTAssertTrue(filtered.contains { $0.name == "debug-match.log" })
    XCTAssertTrue(filtered.contains { $0.name == "keep-match.txt" })
  }

  func testSearchDoesNotReportFalseNoMatchWhenTopCandidatesAreIgnored() async throws {
    let root = try makeTempDirectory()
    try runGit(arguments: ["init", "-q"], at: root)

    let ignoredDirectory = root.appendingPathComponent("ignored", isDirectory: true)
    let gitignore = root.appendingPathComponent(".gitignore")
    try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
    try Data("ignored/\n".utf8).write(to: gitignore)

    for index in 0..<480 {
      let file = ignoredDirectory.appendingPathComponent(String(format: "root-%03d.txt", index))
      try Data("x".utf8).write(to: file)
    }
    let visibleMatch = root.appendingPathComponent("root-visible-target.txt")
    try Data("x".utf8).write(to: visibleMatch)

    let index = FileTreeIndex(rootPath: root.path)
    let results = await index.search(matching: "root", limit: 60)

    XCTAssertTrue(results.contains { $0.name == "root-visible-target.txt" })
    XCTAssertFalse(results.contains { $0.name == "root-000.txt" })
  }

  func testSearchIncludedGitIgnoredEntriesAreRankedAfterVisibleMatches() async throws {
    let root = try makeTempDirectory()
    try runGit(arguments: ["init", "-q"], at: root)

    let ignoredDirectory = root.appendingPathComponent("ignored", isDirectory: true)
    let gitignore = root.appendingPathComponent(".gitignore")
    try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
    try Data("ignored/\n".utf8).write(to: gitignore)

    let ignoredFile = ignoredDirectory.appendingPathComponent("a-root-ignored.txt")
    let visibleFile = root.appendingPathComponent("z-root-visible.txt")
    try Data("x".utf8).write(to: ignoredFile)
    try Data("x".utf8).write(to: visibleFile)

    let index = FileTreeIndex(rootPath: root.path)
    let results = await index.search(
      matching: "root",
      limit: 20,
      options: FileTreeIndex.SearchOptions(includeGitIgnoredEntries: true)
    )

    let visibleIndex = try XCTUnwrap(results.firstIndex(where: { $0.name == "z-root-visible.txt" }))
    let ignoredIndex = try XCTUnwrap(results.firstIndex(where: { $0.name == "a-root-ignored.txt" }))
    XCTAssertLessThan(visibleIndex, ignoredIndex)
  }

  func testSearchIncludedHiddenEntriesAreRankedAfterVisibleMatches() async throws {
    let root = try makeTempDirectory()
    let hidden = root.appendingPathComponent(".root-hidden.txt")
    let visible = root.appendingPathComponent("a-root-visible.txt")
    try Data("x".utf8).write(to: hidden)
    try Data("x".utf8).write(to: visible)

    let index = FileTreeIndex(rootPath: root.path)
    let results = await index.search(
      matching: "root",
      limit: 20,
      options: FileTreeIndex.SearchOptions(includeHiddenEntries: true)
    )

    let visibleIndex = try XCTUnwrap(results.firstIndex(where: { $0.name == "a-root-visible.txt" }))
    let hiddenIndex = try XCTUnwrap(results.firstIndex(where: { $0.name == ".root-hidden.txt" }))
    XCTAssertLessThan(visibleIndex, hiddenIndex)
  }

  @MainActor
  private func loadChildrenAndWait(_ index: FileTreeIndex, path: String) async throws -> [FileTreeIndex.Node] {
    index.scheduleLoadChildren(for: path)
    return try await waitForChildrenCached(index, path: path)
  }

  @MainActor
  private func waitForChildrenCached(_ index: FileTreeIndex, path: String) async throws -> [FileTreeIndex.Node] {
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

  private func runGit(arguments: [String], at root: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", root.path] + arguments
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorText =
        String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? "unknown git error"
      XCTFail("git \(arguments.joined(separator: " ")) failed: \(errorText)")
      return
    }
  }
}
