import AppKit
import Bonsplit

struct HorizontalSizingPlan {
    let rootWidth: CGFloat
    let splitPositions: [UUID: CGFloat]
}

enum HorizontalPaneSizingEngine {
    static let defaultFallbackPaneWidth: CGFloat = 200

    static func paneWidths(from snapshot: LayoutSnapshot) -> [String: CGFloat] {
        var widths: [String: CGFloat] = [:]
        widths.reserveCapacity(snapshot.panes.count)
        for pane in snapshot.panes {
            widths[pane.paneId] = CGFloat(pane.frame.width)
        }
        return widths
    }

    static func paneIDs(in node: ExternalTreeNode) -> Set<String> {
        switch node {
        case let .pane(pane):
            return [pane.id]
        case let .split(split):
            return paneIDs(in: split.first).union(paneIDs(in: split.second))
        }
    }

    static func findSplit(in node: ExternalTreeNode, splitId: String) -> ExternalSplitNode? {
        switch node {
        case .pane:
            return nil
        case let .split(split):
            if split.id == splitId { return split }
            if let first = findSplit(in: split.first, splitId: splitId) { return first }
            return findSplit(in: split.second, splitId: splitId)
        }
    }

    static func containsHorizontalSplit(in node: ExternalTreeNode) -> Bool {
        switch node {
        case .pane:
            return false
        case let .split(split):
            if split.orientation == "horizontal" {
                return true
            }
            return containsHorizontalSplit(in: split.first) || containsHorizontalSplit(in: split.second)
        }
    }

    static func targetPaneHasHorizontalAncestor(
        in node: ExternalTreeNode,
        paneId: String
    ) -> Bool {
        hasHorizontalAncestor(in: node, paneId: paneId, hasAncestor: false) ?? false
    }

    static func splitIDContainingPanes(
        in node: ExternalTreeNode,
        firstPaneId: String,
        secondPaneId: String,
        orientation: String? = nil
    ) -> UUID? {
        switch node {
        case .pane:
            return nil
        case let .split(split):
            if let orientation, split.orientation != orientation {
                // keep searching children
            } else {
                let firstIDs = paneIDs(in: split.first)
                let secondIDs = paneIDs(in: split.second)
                let isMatch =
                    (firstIDs.contains(firstPaneId) && secondIDs.contains(secondPaneId))
                        || (firstIDs.contains(secondPaneId) && secondIDs.contains(firstPaneId))
                if isMatch, let splitUUID = UUID(uuidString: split.id) {
                    return splitUUID
                }
            }
            if let found = splitIDContainingPanes(
                in: split.first,
                firstPaneId: firstPaneId,
                secondPaneId: secondPaneId,
                orientation: orientation
            ) {
                return found
            }
            return splitIDContainingPanes(
                in: split.second,
                firstPaneId: firstPaneId,
                secondPaneId: secondPaneId,
                orientation: orientation
            )
        }
    }

    static func splitIDs(in node: ExternalTreeNode, orientation: String? = nil) -> [UUID] {
        switch node {
        case .pane:
            return []
        case let .split(split):
            var ids: [UUID] = []
            if orientation == nil || split.orientation == orientation,
               let splitUUID = UUID(uuidString: split.id)
            {
                ids.append(splitUUID)
            }
            ids += splitIDs(in: split.first, orientation: orientation)
            ids += splitIDs(in: split.second, orientation: orientation)
            return ids
        }
    }

    private static func hasHorizontalAncestor(
        in node: ExternalTreeNode,
        paneId: String,
        hasAncestor: Bool
    ) -> Bool? {
        switch node {
        case let .pane(pane):
            return pane.id == paneId ? hasAncestor : nil
        case let .split(split):
            let nextHasAncestor = hasAncestor || split.orientation == "horizontal"
            if let inFirst = hasHorizontalAncestor(
                in: split.first,
                paneId: paneId,
                hasAncestor: nextHasAncestor
            ) {
                return inFirst
            }
            return hasHorizontalAncestor(
                in: split.second,
                paneId: paneId,
                hasAncestor: nextHasAncestor
            )
        }
    }

    static func minimumRequiredWidth(for node: ExternalTreeNode, minimumPaneWidth: CGFloat) -> CGFloat {
        switch node {
        case .pane:
            return minimumPaneWidth
        case let .split(split):
            let first = minimumRequiredWidth(for: split.first, minimumPaneWidth: minimumPaneWidth)
            let second = minimumRequiredWidth(for: split.second, minimumPaneWidth: minimumPaneWidth)
            if split.orientation == "horizontal" {
                return first + second
            }
            return max(first, second)
        }
    }

    static func buildPlan(
        tree: ExternalTreeNode,
        desiredPaneWidths: [String: CGFloat],
        fallbackPaneWidth: CGFloat = defaultFallbackPaneWidth
    ) -> HorizontalSizingPlan {
        var splitPositions: [UUID: CGFloat] = [:]
        let rootWidth = computeWidth(
            node: tree,
            desiredPaneWidths: desiredPaneWidths,
            fallbackPaneWidth: fallbackPaneWidth,
            splitPositions: &splitPositions
        )
        return HorizontalSizingPlan(
            rootWidth: max(rootWidth, 1),
            splitPositions: splitPositions
        )
    }

    private static func computeWidth(
        node: ExternalTreeNode,
        desiredPaneWidths: [String: CGFloat],
        fallbackPaneWidth: CGFloat,
        splitPositions: inout [UUID: CGFloat]
    ) -> CGFloat {
        switch node {
        case let .pane(pane):
            return max(desiredPaneWidths[pane.id] ?? fallbackPaneWidth, 1)
        case let .split(split):
            let firstWidth = computeWidth(
                node: split.first,
                desiredPaneWidths: desiredPaneWidths,
                fallbackPaneWidth: fallbackPaneWidth,
                splitPositions: &splitPositions
            )
            let secondWidth = computeWidth(
                node: split.second,
                desiredPaneWidths: desiredPaneWidths,
                fallbackPaneWidth: fallbackPaneWidth,
                splitPositions: &splitPositions
            )

            if split.orientation == "horizontal" {
                let total = max(firstWidth + secondWidth, 1)
                var position = firstWidth / total
                position = min(max(position, 0.0001), 0.9999)
                if let splitUUID = UUID(uuidString: split.id) {
                    splitPositions[splitUUID] = position
                }
                return total
            }

            return max(firstWidth, secondWidth)
        }
    }
}
