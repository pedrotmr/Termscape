import XCTest

@testable import Termscape

final class EditorRootContractTests: XCTestCase {
  /// Unit-test resolver logic without touching the filesystem.
  private func identityNormalize(_ path: String?) -> String? {
    guard let path, !path.isEmpty else { return nil }
    return path
  }

  func testTerminalFocusUsesWorkingDirectory() {
    let resolved = EditorRootContract.resolvePinnedRoot(
      focusedKind: .terminal,
      terminalWorkingDirectory: "/repo",
      editorRootPath: "/editor",
      workspaceRootPath: "/ws",
      fallbackHomePath: "/home",
      normalizePath: identityNormalize
    )
    XCTAssertEqual(resolved, "/repo")
  }

  func testTerminalFocusFallsBackWhenCwdMissing() {
    let resolved = EditorRootContract.resolvePinnedRoot(
      focusedKind: .terminal,
      terminalWorkingDirectory: nil,
      editorRootPath: "/editor",
      workspaceRootPath: "/ws",
      fallbackHomePath: "/home",
      normalizePath: identityNormalize
    )
    XCTAssertEqual(resolved, "/ws")
  }

  func testEditorFocusUsesPinnedEditorRoot() {
    let resolved = EditorRootContract.resolvePinnedRoot(
      focusedKind: .editor,
      terminalWorkingDirectory: "/repo",
      editorRootPath: "/pinned",
      workspaceRootPath: "/ws",
      fallbackHomePath: "/home",
      normalizePath: identityNormalize
    )
    XCTAssertEqual(resolved, "/pinned")
  }

  func testBrowserFocusSkipsToWorkspace() {
    let resolved = EditorRootContract.resolvePinnedRoot(
      focusedKind: .browser,
      terminalWorkingDirectory: "/repo",
      editorRootPath: "/editor",
      workspaceRootPath: "/ws",
      fallbackHomePath: "/home",
      normalizePath: identityNormalize
    )
    XCTAssertEqual(resolved, "/ws")
  }

  func testHomeFallbackWhenWorkspaceMissing() {
    let resolved = EditorRootContract.resolvePinnedRoot(
      focusedKind: .browser,
      terminalWorkingDirectory: nil,
      editorRootPath: nil,
      workspaceRootPath: nil,
      fallbackHomePath: "/home",
      normalizePath: identityNormalize
    )
    XCTAssertEqual(resolved, "/home")
  }
}
