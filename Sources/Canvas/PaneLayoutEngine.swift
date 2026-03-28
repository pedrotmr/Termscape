import AppKit
import Bonsplit

/// Computes the canvas width needed to maintain minimum pane widths.
/// Works with Bonsplit's LayoutSnapshot to get absolute pane frames.
struct PaneLayoutEngine {
    let minPaneWidth: CGFloat

    init(minPaneWidth: CGFloat = 400) {
        self.minPaneWidth = minPaneWidth
    }

    /// Count the number of horizontal columns in the split tree.
    /// This determines how wide the canvas needs to be.
    func columnCount(from tree: ExternalTreeNode) -> Int {
        switch tree {
        case .pane:
            return 1
        case .split(let s) where s.orientation == "horizontal":
            return columnCount(from: s.first) + columnCount(from: s.second)
        case .split(let s):
            // Vertical split: panes stack, same column count as the widest child
            return max(columnCount(from: s.first), columnCount(from: s.second))
        }
    }

    /// Compute the canvas width required to fit all columns at minimum pane width.
    func requiredCanvasWidth(for tree: ExternalTreeNode, viewportWidth: CGFloat) -> CGFloat {
        let columns = columnCount(from: tree)
        let minRequired = CGFloat(columns) * minPaneWidth
        return max(minRequired, viewportWidth)
    }
}
