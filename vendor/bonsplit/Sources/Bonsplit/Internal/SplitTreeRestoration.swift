import Foundation

/// Rebuilds internal split tree state from `ExternalTreeNode` (from `treeSnapshot()`).
enum SplitTreeRestoration {
    @MainActor
    static func splitNode(from external: ExternalTreeNode) -> SplitNode {
        switch external {
        case let .pane(paneNode):
            let paneID = PaneID(id: UUID(uuidString: paneNode.id) ?? UUID())
            var tabItems: [TabItem] = paneNode.tabs.compactMap { ext in
                guard let tid = UUID(uuidString: ext.id) else { return nil }
                return TabItem(id: tid, title: ext.title)
            }
            if tabItems.isEmpty {
                tabItems = [TabItem(title: "Terminal")]
            }
            let selectedUUID = paneNode.selectedTabId.flatMap(UUID.init(uuidString:))
            let selected =
                selectedUUID.flatMap { id in tabItems.contains(where: { $0.id == id }) ? id : nil }
                    ?? tabItems.first?.id
            let pane = PaneState(id: paneID, tabs: tabItems, selectedTabId: selected)
            return .pane(pane)

        case let .split(split):
            let splitID = UUID(uuidString: split.id) ?? UUID()
            let orientation: SplitOrientation = split.orientation == "vertical" ? .vertical : .horizontal
            let first = splitNode(from: split.first)
            let second = splitNode(from: split.second)
            let state = SplitState(
                id: splitID,
                orientation: orientation,
                first: first,
                second: second,
                dividerPosition: CGFloat(split.dividerPosition)
            )
            return .split(state)
        }
    }
}
