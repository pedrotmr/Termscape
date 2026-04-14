import Foundation

/// Represents a tab's metadata (read-only snapshot for library consumers)
public struct Tab: Identifiable, Hashable, Sendable {
    public let id: TabID
    public let title: String
    public let hasCustomTitle: Bool
    public let icon: String?
    /// Optional image data (PNG recommended) for the tab icon. When present, this takes precedence over `icon`.
    public let iconImageData: Data?
    /// Consumer-defined tab kind identifier (for example, "terminal" or "browser").
    public let kind: String?
    public let isDirty: Bool
    /// Whether the tab should show an "unread/activity" badge (library consumer-defined meaning).
    public let showsNotificationBadge: Bool
    /// Whether the tab should show an activity/loading indicator (e.g. spinning icon).
    public let isLoading: Bool
    /// Whether the tab is pinned in its pane.
    public let isPinned: Bool

    public init(
        id: TabID = TabID(),
        title: String,
        hasCustomTitle: Bool = false,
        icon: String? = nil,
        iconImageData: Data? = nil,
        kind: String? = nil,
        isDirty: Bool = false,
        showsNotificationBadge: Bool = false,
        isLoading: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.icon = icon
        self.iconImageData = iconImageData
        self.kind = kind
        self.isDirty = isDirty
        self.showsNotificationBadge = showsNotificationBadge
        self.isLoading = isLoading
        self.isPinned = isPinned
    }

    init(from tabItem: TabItem) {
        id = TabID(id: tabItem.id)
        title = tabItem.title
        hasCustomTitle = tabItem.hasCustomTitle
        icon = tabItem.icon
        iconImageData = tabItem.iconImageData
        kind = tabItem.kind
        isDirty = tabItem.isDirty
        showsNotificationBadge = tabItem.showsNotificationBadge
        isLoading = tabItem.isLoading
        isPinned = tabItem.isPinned
    }
}
