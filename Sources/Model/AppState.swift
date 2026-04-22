import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var groups: [WorkspaceGroup] = []
    var selectedWorkspaceId: UUID?
    var editingWorkspaceId: UUID?
    var editingGroupId: UUID?
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

    @discardableResult
    func createGroup(
        name: String,
        isImplicit: Bool = false,
        createInitialWorkspace: Bool = true
    ) -> WorkspaceGroup {
        let group = WorkspaceGroup(name: name, isImplicit: isImplicit)
        groups.append(group)

        if createInitialWorkspace {
            let workspace = addWorkspace(in: group, url: nil)
            selectedWorkspaceId = workspace.id
            workspace.ensureHasTab()
        } else {
            schedulePersist()
        }

        return group
    }

    func removeGroup(_ group: WorkspaceGroup) {
        let groupWorkspaceIds = Set(group.workspaces.map(\.id))
        for workspace in group.workspaces {
            workspace.teardown()
        }
        groups.removeAll { $0.id == group.id }

        if let selectedWorkspaceId, groupWorkspaceIds.contains(selectedWorkspaceId) {
            self.selectedWorkspaceId = groups.first?.workspaces.first?.id
        }

        schedulePersist()
    }

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
        if group.workspaces.isEmpty {
            groups.removeAll { $0.id == group.id }
        }
        schedulePersist()
    }

    /// Moves a workspace between groups or reorders within a group. `toIndex` is the desired index in the target group's array **before** this call (same semantics as `move(fromOffsets:toOffset:)`).
    func relocateWorkspace(
        workspaceId: UUID,
        fromGroupId: UUID,
        fromIndex: Int,
        toGroupId: UUID,
        toIndex: Int
    ) {
        guard let fromGroup = groups.first(where: { $0.id == fromGroupId }),
              let toGroup = groups.first(where: { $0.id == toGroupId }),
              fromIndex >= 0, fromIndex < fromGroup.workspaces.count,
              fromGroup.workspaces[fromIndex].id == workspaceId
        else { return }

        let workspace = fromGroup.workspaces.remove(at: fromIndex)

        var insertAt = toIndex
        if fromGroup.id == toGroup.id {
            if fromIndex < toIndex {
                insertAt = toIndex - 1
            }
        }
        insertAt = min(max(0, insertAt), toGroup.workspaces.count)
        toGroup.workspaces.insert(workspace, at: insertAt)

        if fromGroup.workspaces.isEmpty, !fromGroup.isImplicit {
            groups.removeAll { $0.id == fromGroupId }
        }

        schedulePersist()
    }

    func selectWorkspace(_ id: UUID) {
        selectedWorkspaceId = id
        selectedWorkspace?.ensureHasTab()
        schedulePersist()
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

        let repoLeaf = trimmed.split(separator: "/").last.map(String.init) ?? "repo"
        let repoName =
            repoLeaf.hasSuffix(".git")
                ? String(repoLeaf.dropLast(4))
                : repoLeaf
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

    func maybeAutoRenameWorkspaceFromTerminalPathChange(
        _ notification: NotificationCenter.Publisher.Output
    ) {
        let key = Notification.Name.TerminalWorkingDirectoryDidChangeKey.self
        guard let workspaceId = notification.userInfo?[key.workspaceId] as? UUID,
              let surfaceId = notification.userInfo?[key.surfaceId] as? UUID,
              let path = notification.userInfo?[key.path] as? String
        else {
            return
        }
        guard let workspace = groups.lazy.flatMap(\.workspaces).first(where: { $0.id == workspaceId })
        else {
            return
        }
        guard !workspace.isNameManuallyCustomized else { return }
        guard let selectedTab = workspace.selectedTab else { return }
        // `surfaces` is keyed by Bonsplit tab id, not `TerminalSurface.id`.
        guard selectedTab.surfaces.values.contains(where: { $0.id == surfaceId }) else { return }
        guard selectedTab.bonsplitController.allPaneIds.count == 1 else { return }

        let candidateName = defaultWorkspaceName(
            for: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        )
        guard !candidateName.isEmpty, candidateName != workspace.name else { return }

        workspace.name = candidateName
        schedulePersist()
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
        if let existing = groups.first(where: { $0.isImplicit }) { return existing }
        let group = createGroup(name: "Workspaces", isImplicit: true, createInitialWorkspace: false)
        if normalizeImplicitGroupToFirst() {
            schedulePersist()
        }
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
        guard fileManager.fileExists(atPath: cwdURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
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
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("termscape")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspaces.json")
    }

    func persist() {
        guard let url = persistenceURL else { return }
        do {
            let payload = TermscapePersistence(groups: groups, selectedWorkspaceId: selectedWorkspaceId)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url)
        } catch {
            print("Failed to persist workspaces: \(error)")
        }
    }

    func load() {
        guard let url = persistenceURL,
              let data = try? Data(contentsOf: url)
        else {
            return
        }

        let decoder = JSONDecoder()
        let savedGroups: [WorkspaceGroup]
        let savedSelection: UUID?
        let loadedLegacyArray: Bool

        if let payload = try? decoder.decode(TermscapePersistence.self, from: data) {
            savedGroups = payload.groups
            savedSelection = payload.selectedWorkspaceId
            loadedLegacyArray = false
        } else if let legacy = try? decoder.decode([WorkspaceGroup].self, from: data) {
            savedGroups = legacy
            savedSelection = nil
            loadedLegacyArray = true
        } else {
            return
        }

        groups = savedGroups
        groups.removeAll(where: { $0.workspaces.isEmpty })
        // Migration: legacy array saves have no isImplicit field (defaults to false).
        // If every group appears non-implicit, treat the first as the implicit default.
        if loadedLegacyArray, !groups.isEmpty, groups.allSatisfy({ !$0.isImplicit }) {
            groups[0].isImplicit = true
        }
        if normalizeImplicitGroupToFirst() {
            schedulePersist()
        }

        let workspaceIds = Set(groups.flatMap(\.workspaces).map(\.id))
        if let sel = savedSelection, workspaceIds.contains(sel) {
            selectedWorkspaceId = sel
        } else {
            selectedWorkspaceId = groups.flatMap(\.workspaces).first?.id
        }
    }

    /// Ungrouped workspaces stay in the first section; fixes saves where groups were reordered above the implicit bucket.
    @discardableResult
    private func normalizeImplicitGroupToFirst() -> Bool {
        guard let i = groups.firstIndex(where: { $0.isImplicit }), i > 0 else { return false }
        let g = groups.remove(at: i)
        groups.insert(g, at: 0)
        return true
    }
}
