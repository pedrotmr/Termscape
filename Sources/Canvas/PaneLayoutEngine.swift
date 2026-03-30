import AppKit
import Bonsplit

/// Computes the canvas width needed to maintain minimum pane widths.
/// Works with Bonsplit's LayoutSnapshot to get absolute pane frames.
struct PaneLayoutEngine {
    let minPaneWidth: CGFloat

    init(minPaneWidth: CGFloat = 600) {
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

    /// Horizontal column span per leaf pane for the spatial canvas.
    /// Bonsplit stores nested splits with divider ratios (e.g. repeated 0.5 → 50%, 25%, 12.5%…); we ignore those for x/width and use equal columns instead.
    func leafColumnSpans(from tree: ExternalTreeNode) -> [String: (colStart: Int, colSpan: Int)] {
        let total = columnCount(from: tree)
        let tuples = leafColumnSpansRecursive(tree, colStart: 0, colSpan: total)
        return Dictionary(
            uniqueKeysWithValues: tuples.map { ($0.paneId, ($0.colStart, $0.colSpan)) }
        )
    }

    private func leafColumnSpansRecursive(
        _ node: ExternalTreeNode,
        colStart: Int,
        colSpan: Int
    ) -> [(paneId: String, colStart: Int, colSpan: Int)] {
        switch node {
        case .pane(let p):
            return [(p.id, colStart, colSpan)]
        case .split(let s) where s.orientation == "horizontal":
            let leftCols = columnCount(from: s.first)
            let rightCols = columnCount(from: s.second)
            return leafColumnSpansRecursive(s.first, colStart: colStart, colSpan: leftCols)
                + leafColumnSpansRecursive(s.second, colStart: colStart + leftCols, colSpan: rightCols)
        case .split(let s):
            return leafColumnSpansRecursive(s.first, colStart: colStart, colSpan: colSpan)
                + leafColumnSpansRecursive(s.second, colStart: colStart, colSpan: colSpan)
        }
    }
}
