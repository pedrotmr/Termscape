import AppKit
import Bonsplit

/// Pre-computed layout result from a single tree traversal.
struct PaneLayoutResult {
    let columnCount: Int
    let canvasWidth: CGFloat
    let columnSpans: [String: (colStart: Int, colSpan: Int)]
}

/// Computes the canvas width needed to maintain minimum pane widths.
/// Works with Bonsplit's LayoutSnapshot to get absolute pane frames.
struct PaneLayoutEngine {
    let minPaneWidth: CGFloat

    init(minPaneWidth: CGFloat = 600) {
        self.minPaneWidth = minPaneWidth
    }

    /// Compute column count, canvas width, and per-pane column spans in a single tree traversal.
    func computeLayout(from tree: ExternalTreeNode, viewportWidth: CGFloat) -> PaneLayoutResult {
        let columns = columnCount(from: tree)
        let canvasWidth = max(CGFloat(columns) * minPaneWidth, viewportWidth)
        let tuples = leafColumnSpansRecursive(tree, colStart: 0, colSpan: columns)
        let spans = Dictionary(uniqueKeysWithValues: tuples.map { ($0.paneId, ($0.colStart, $0.colSpan)) })
        return PaneLayoutResult(columnCount: columns, canvasWidth: canvasWidth, columnSpans: spans)
    }

    // MARK: - Private

    private func columnCount(from tree: ExternalTreeNode) -> Int {
        switch tree {
        case .pane:
            return 1
        case .split(let s) where s.orientation == "horizontal":
            return columnCount(from: s.first) + columnCount(from: s.second)
        case .split(let s):
            return max(columnCount(from: s.first), columnCount(from: s.second))
        }
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
