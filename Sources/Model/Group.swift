import Bonsplit
import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceGroup: Identifiable, Codable {
    let id: UUID
    var name: String
    var isCollapsed: Bool
    var isImplicit: Bool
    var workspaces: [Workspace]

    init(name: String, id: UUID = UUID(), isCollapsed: Bool = false, isImplicit: Bool = false) {
        self.id = id
        self.name = name
        self.isCollapsed = isCollapsed
        self.isImplicit = isImplicit
        workspaces = []
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, isCollapsed, isImplicit, workspaceSnapshots
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try container.encode(isImplicit, forKey: .isImplicit)
        let snapshots = workspaces.map(WorkspaceSnapshot.init)
        try container.encode(snapshots, forKey: .workspaceSnapshots)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        isImplicit = try container.decodeIfPresent(Bool.self, forKey: .isImplicit) ?? false
        let snapshots =
            try container.decodeIfPresent([WorkspaceSnapshot].self, forKey: .workspaceSnapshots) ?? []
        workspaces = snapshots.map { Workspace(snapshot: $0) }
    }
}

struct WorkspaceTabSnapshot: Codable {
    let id: UUID
    let title: String
    let isPinned: Bool
    /// 0 means canvas width follows viewport (stretch mode).
    let canvasWidthPts: Double
    let tree: ExternalTreeNode
    let focusedPaneId: String?
    /// Bonsplit terminal tab id (UUID string) → normalized working directory for surfaces that exist or were tracked.
    let workingDirectoryByTerminalTabId: [String: String]?
    /// Bonsplit tab id (UUID string) -> pane content kind ("terminal" | "browser").
    let tabKindByTabId: [String: String]?
    /// Bonsplit browser tab id (UUID string) -> current URL string.
    let browserURLByTabId: [String: String]?

    @MainActor
    init(_ tab: WorkspaceTab) {
        id = tab.id
        title = tab.title
        isPinned = tab.isPinned
        canvasWidthPts = tab.canvasWidth <= 0 ? 0 : Double(tab.canvasWidth)
        tree = tab.bonsplitController.treeSnapshot()
        focusedPaneId = tab.bonsplitController.layoutSnapshot().focusedPaneId

        let tabIdStrings = Set(Self.collectTabIdStrings(from: tree))
        var cwdMap: [String: String] = [:]
        var kindMap: [String: String] = [:]
        var browserURLMap: [String: String] = [:]

        for idStr in tabIdStrings {
            guard let u = UUID(uuidString: idStr) else { continue }

            let kind = tab.paneContentKind(for: u)
            kindMap[idStr] = kind.rawValue

            if let path = tab.surfaces[u]?.splitWorkingDirectory {
                cwdMap[idStr] = path
            }

            if kind == .browser,
               let browserURL = tab.browserURL(for: u)?.absoluteString,
               !browserURL.isEmpty
            {
                browserURLMap[idStr] = browserURL
            }
        }
        workingDirectoryByTerminalTabId = cwdMap.isEmpty ? nil : cwdMap
        tabKindByTabId = kindMap.isEmpty ? nil : kindMap
        browserURLByTabId = browserURLMap.isEmpty ? nil : browserURLMap
    }

    private static func collectTabIdStrings(from node: ExternalTreeNode) -> [String] {
        switch node {
        case let .pane(pane):
            return pane.tabs.map(\.id)
        case let .split(split):
            return collectTabIdStrings(from: split.first)
                + collectTabIdStrings(from: split.second)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        canvasWidthPts = try c.decodeIfPresent(Double.self, forKey: .canvasWidthPts) ?? 0
        tree = try c.decode(ExternalTreeNode.self, forKey: .tree)
        focusedPaneId = try c.decodeIfPresent(String.self, forKey: .focusedPaneId)
        workingDirectoryByTerminalTabId = try c.decodeIfPresent(
            [String: String].self, forKey: .workingDirectoryByTerminalTabId
        )
        tabKindByTabId = try c.decodeIfPresent([String: String].self, forKey: .tabKindByTabId)
        browserURLByTabId = try c.decodeIfPresent([String: String].self, forKey: .browserURLByTabId)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isPinned
        case canvasWidthPts
        case tree
        case focusedPaneId
        case workingDirectoryByTerminalTabId
        case tabKindByTabId
        case browserURLByTabId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(canvasWidthPts, forKey: .canvasWidthPts)
        try c.encode(tree, forKey: .tree)
        try c.encodeIfPresent(focusedPaneId, forKey: .focusedPaneId)
        try c.encodeIfPresent(workingDirectoryByTerminalTabId, forKey: .workingDirectoryByTerminalTabId)
        try c.encodeIfPresent(tabKindByTabId, forKey: .tabKindByTabId)
        try c.encodeIfPresent(browserURLByTabId, forKey: .browserURLByTabId)
    }
}

struct WorkspaceSnapshot: Codable {
    let id: UUID
    let name: String
    let isNameManuallyCustomized: Bool?
    let rootURL: URL?
    let color: String?
    let tabSnapshots: [WorkspaceTabSnapshot]?
    let selectedTabId: UUID?

    @MainActor
    init(_ workspace: Workspace) {
        id = workspace.id
        name = workspace.name
        isNameManuallyCustomized = workspace.isNameManuallyCustomized ? true : nil
        rootURL = workspace.rootURL
        color = workspace.color
        tabSnapshots = workspace.tabs.map { WorkspaceTabSnapshot($0) }
        selectedTabId = workspace.selectedTabId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isNameManuallyCustomized = try c.decodeIfPresent(Bool.self, forKey: .isNameManuallyCustomized)
        rootURL = try c.decodeIfPresent(URL.self, forKey: .rootURL)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        tabSnapshots = try c.decodeIfPresent([WorkspaceTabSnapshot].self, forKey: .tabSnapshots)
        selectedTabId = try c.decodeIfPresent(UUID.self, forKey: .selectedTabId)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, isNameManuallyCustomized, rootURL, color, tabSnapshots, selectedTabId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(isNameManuallyCustomized, forKey: .isNameManuallyCustomized)
        try c.encodeIfPresent(rootURL, forKey: .rootURL)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(tabSnapshots, forKey: .tabSnapshots)
        try c.encodeIfPresent(selectedTabId, forKey: .selectedTabId)
    }
}

/// Root JSON payload for `workspaces.json` (includes `selectedWorkspaceId`).
struct TermscapePersistence: Codable {
    var groups: [WorkspaceGroup]
    var selectedWorkspaceId: UUID?
}
