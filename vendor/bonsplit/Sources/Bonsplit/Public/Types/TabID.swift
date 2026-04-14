import Foundation

/// Opaque identifier for tabs
public struct TabID: Hashable, Codable, Sendable {
    let id: UUID

    public init() {
        id = UUID()
    }

    public init(uuid: UUID) {
        id = uuid
    }

    public var uuid: UUID {
        id
    }

    init(id: UUID) {
        self.id = id
    }
}
