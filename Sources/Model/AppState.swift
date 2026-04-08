import Foundation
import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class AppState {
    var groups: [WorkspaceGroup] = []
    var selectedWorkspaceId: UUID?
    var editingWorkspaceId: UUID? = nil
    var editingGroupId: UUID? = nil
    var showCloneSheet: Bool = false
    var cloneURL: String = ""

    var selectedWorkspace: Workspace? {
        guard let id = selectedWorkspaceId else { return nil }
        for group in groups {
            if let ws = group.workspaces.first(where: { $0.id == id }) { return ws }
        }
        return nil
    }

    // MARK: - Workspace management

    func addWorkspace(in group: WorkspaceGroup, url: URL?, name: String? = nil) -> Workspace {
        let rootURL = url ?? defaultWorkspaceRootURL()
        let workspaceName = name ?? defaultWorkspaceName(for: rootURL)
        let workspace = Workspace(name: workspaceName, rootURL: rootURL)
        group.workspaces.append(workspace)
        schedulePersist()
        return workspace
    }

    func removeWorkspace(_ workspace: Workspace, from group: WorkspaceGroup) {
        workspace.teardown()
        group.workspaces.removeAll { $0.id == workspace.id }
        if selectedWorkspaceId == workspace.id {
            selectedWorkspaceId = groups.flatMap(\.workspaces).first?.id
        }
        schedulePersist()
    }

    func selectWorkspace(_ id: UUID) {
        selectedWorkspaceId = id
        selectedWorkspace?.ensureHasTab()
    }

    // MARK: - Opening workspaces

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder to open as a workspace"

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                self.openWorkspace(at: url)
            }
        }
    }

    func openWorkspace() {
        let group = getOrCreateDefaultGroup()
        let workspace = addWorkspace(in: group, url: nil)
        selectedWorkspaceId = workspace.id
        workspace.ensureHasTab()
    }

    func openWorkspace(at url: URL) {
        let group = getOrCreateDefaultGroup()
        let workspace = addWorkspace(in: group, url: url.standardizedFileURL)
        selectedWorkspaceId = workspace.id
        workspace.ensureHasTab()
    }

    func cloneRepository(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Validate URL scheme to prevent shell injection
        let allowedPrefixes = ["https://", "http://", "git@", "ssh://", "git://"]
        guard allowedPrefixes.contains(where: { trimmed.hasPrefix($0) }) else { return }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let cloneDir = homeURL.appendingPathComponent("Developer")
        do {
            try FileManager.default.createDirectory(at: cloneDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create clone directory at \(cloneDir.path): \(error)")
            return
        }

        let group = getOrCreateDefaultGroup()

        let repoName = trimmed.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: ".git", with: "") ?? "repo"
        let destURL = cloneDir.appendingPathComponent(repoName).standardizedFileURL

        let workspace = addWorkspace(in: group, url: destURL, name: repoName)
        selectedWorkspaceId = workspace.id
        workspace.ensureHasTab()

        // Defer clone command until the surface exists and attaches to a window.
        // Surfaces are created lazily during the next render cycle.
        if let tab = workspace.tabs.first {
            let quotedURL = shellQuote(trimmed)
            let quotedPath = shellQuote(destURL.path)
            let cloneCommand = "git clone \(quotedURL) \(quotedPath) && cd \(quotedPath)\n"
            tab.pendingInputOnceAttached = cloneCommand
        }

        showCloneSheet = false
        cloneURL = ""
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Helpers

    func ensureStartupWorkspaceIfNeeded() {
        let workspaces = groups.flatMap(\.workspaces)
        if workspaces.isEmpty {
            let group = getOrCreateDefaultGroup()
            let workspace = addWorkspace(in: group, url: nil)
            selectedWorkspaceId = workspace.id
            workspace.ensureHasTab()
            return
        }

        if selectedWorkspace == nil, let firstWorkspace = workspaces.first {
            selectWorkspace(firstWorkspace.id)
        }
    }

    private func getOrCreateDefaultGroup() -> WorkspaceGroup {
        if let existing = groups.first { return existing }
        let group = WorkspaceGroup(name: "Workspaces", isImplicit: true)
        groups.append(group)
        return group
    }

    private func defaultWorkspaceName(for url: URL) -> String {
        let folderName = url.lastPathComponent
        if !folderName.isEmpty { return folderName }
        return url.path
    }

    private func defaultWorkspaceRootURL() -> URL {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let cwdPath = fileManager.currentDirectoryPath

        guard !cwdPath.isEmpty, cwdPath != "/" else { return homeURL }

        let cwdURL = URL(fileURLWithPath: cwdPath, isDirectory: true).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: cwdURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return homeURL
        }

        return cwdURL
    }

    // MARK: - Persistence

    private var persistWorkItem: DispatchWorkItem?

    /// Debounced persist — schedules a write after a short delay, coalescing rapid mutations.
    func schedulePersist() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persist() }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private var persistenceURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("termscape")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspaces.json")
    }

    func persist() {
        guard let url = persistenceURL else { return }
        do {
            let data = try JSONEncoder().encode(groups)
            try data.write(to: url)
        } catch {
            print("Failed to persist workspaces: \(error)")
        }
    }

    func load() {
        guard let url = persistenceURL,
              let data = try? Data(contentsOf: url),
              let savedGroups = try? JSONDecoder().decode([WorkspaceGroup].self, from: data) else {
            return
        }
        groups = savedGroups
        // Migration: old saves have no isImplicit field (defaults to false).
        // If every group appears non-implicit, treat the first as the implicit default.
        if !groups.isEmpty && groups.allSatisfy({ !$0.isImplicit }) {
            groups[0].isImplicit = true
        }
        selectedWorkspaceId = groups.flatMap(\.workspaces).first?.id
    }
}
