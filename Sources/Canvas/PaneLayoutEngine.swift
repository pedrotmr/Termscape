import AppKit
import Bonsplit

/// Computes minimum canvas size from the split tree and Bonsplit divider ratios
/// so every pane can satisfy minimum width/height after layout.
struct PaneLayoutEngine {
    let minPaneWidth: CGFloat
    let minPaneHeight: CGFloat

    init(minPaneWidth: CGFloat = 600, minPaneHeight: CGFloat = 200) {
        self.minPaneWidth = minPaneWidth
        self.minPaneHeight = minPaneHeight
    }

    /// Minimum document width so horizontal splits respect `minPaneWidth` at current divider positions.
    func requiredCanvasWidth(for tree: ExternalTreeNode, viewportWidth: CGFloat) -> CGFloat {
        let needed = minSubtreeWidth(tree)
        return max(needed, viewportWidth)
    }

    /// Minimum document height so vertical splits respect `minPaneHeight` at current divider positions.
    func requiredCanvasHeight(for tree: ExternalTreeNode, viewportHeight: CGFloat) -> CGFloat {
        let needed = minSubtreeHeight(tree)
        return max(needed, viewportHeight)
    }

    private func minSubtreeWidth(_ node: ExternalTreeNode) -> CGFloat {
        switch node {
        case .pane:
            return minPaneWidth
        case .split(let s) where s.orientation == "horizontal":
            let p = CGFloat(s.dividerPosition)
            let pSafe = min(max(p, 0.001), 0.999)
            let oneMinus = 1 - pSafe
            let leftMin = minSubtreeWidth(s.first)
            let rightMin = minSubtreeWidth(s.second)
            return max(leftMin / pSafe, rightMin / oneMinus)
        case .split(let s):
            return max(minSubtreeWidth(s.first), minSubtreeWidth(s.second))
        }
    }

    private func minSubtreeHeight(_ node: ExternalTreeNode) -> CGFloat {
        switch node {
        case .pane:
            return minPaneHeight
        case .split(let s) where s.orientation == "vertical":
            let p = CGFloat(s.dividerPosition)
            let pSafe = min(max(p, 0.001), 0.999)
            let oneMinus = 1 - pSafe
            let topMin = minSubtreeHeight(s.first)
            let bottomMin = minSubtreeHeight(s.second)
            return max(topMin / pSafe, bottomMin / oneMinus)
        case .split(let s):
            return max(minSubtreeHeight(s.first), minSubtreeHeight(s.second))
        }
    }
}
