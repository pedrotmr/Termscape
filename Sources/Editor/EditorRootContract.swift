import Foundation

enum EditorRootContract {
  static func resolvePinnedRoot(
    focusedKind: WorkspacePaneContentKind?,
    terminalWorkingDirectory: String?,
    editorRootPath: String?,
    workspaceRootPath: String?,
    fallbackHomePath: String,
    normalizePath: (String?) -> String?
  ) -> String {
    if focusedKind == .terminal,
      let normalizedTerminal = normalizePath(terminalWorkingDirectory)
    {
      return normalizedTerminal
    }

    if focusedKind == .editor,
      let normalizedEditorRoot = normalizePath(editorRootPath)
    {
      return normalizedEditorRoot
    }

    if let normalizedWorkspace = normalizePath(workspaceRootPath) {
      return normalizedWorkspace
    }

    return normalizePath(fallbackHomePath) ?? fallbackHomePath
  }
}
