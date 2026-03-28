import Foundation
import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class AppState {
    var groups: [WorkspaceGroup] = []
    var selectedWorkspaceId: UUID?
    var showCloneSheet: Bool = false
    var cloneURL: String = ""

    var selectedWorkspace: Workspace? {
        groups.flatMap(\.workspaces).first { $0.id == selectedWorkspaceId }
    }

    // MARK: - Workspace management

    func addWorkspace(in group: WorkspaceGroup, url: URL?, name: String? = nil) -> Workspace {
        let workspaceName = name ?? url?.lastPathComponent ?? "New Workspace"
        let workspace = Workspace(name: workspaceName, rootURL: url)
        group.workspaces.append(workspace)
        return workspace
    }

    func removeWorkspace(_ workspace: Workspace, from group: WorkspaceGroup) {
        workspace.teardown()
        group.workspaces.removeAll { $0.id == workspace.id }
        if selectedWorkspaceId == workspace.id {
            selectedWorkspaceId = groups.flatMap(\.workspaces).first?.id
        }
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

    func openWorkspace(at url: URL) {
        let group = groups.first ?? {
            let g = WorkspaceGroup(name: "Workspaces")
            groups.append(g)
            return g
        }()
        let workspace = addWorkspace(in: group, url: url)
        selectedWorkspaceId = workspace.id
        workspace.ensureHasTab()
    }

    func cloneRepository(urlString: String) {
        guard !urlString.isEmpty else { return }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let cloneDir = homeURL.appendingPathComponent("Developer")
        try? FileManager.default.createDirectory(at: cloneDir, withIntermediateDirectories: true)

        let group = groups.first ?? {
            let g = WorkspaceGroup(name: "Workspaces")
            groups.append(g)
            return g
        }()

        let repoName = urlString.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: ".git", with: "") ?? "repo"
        let destURL = cloneDir.appendingPathComponent(repoName)

        let workspace = addWorkspace(in: group, url: destURL, name: repoName)
        selectedWorkspaceId = workspace.id
        workspace.ensureHasTab()

        if let tab = workspace.tabs.first, let surface = tab.surfaces.values.first {
            let cloneCommand = "git clone \(urlString) \(destURL.path) && cd \(destURL.path)\n"
            surface.sendText(cloneCommand)
        }

        showCloneSheet = false
        cloneURL = ""
    }

    // MARK: - Persistence

    private var persistenceURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("muxon")
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
        selectedWorkspaceId = groups.flatMap(\.workspaces).first?.id
    }
}
