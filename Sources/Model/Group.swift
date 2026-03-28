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
        self.workspaces = []
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
        let snapshots = try container.decodeIfPresent([WorkspaceSnapshot].self, forKey: .workspaceSnapshots) ?? []
        workspaces = snapshots.map { Workspace(snapshot: $0) }
    }
}

struct WorkspaceSnapshot: Codable {
    let id: UUID
    let name: String
    let rootURL: URL?

    @MainActor
    init(_ workspace: Workspace) {
        id = workspace.id
        name = workspace.name
        rootURL = workspace.rootURL
    }
}
