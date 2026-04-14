import AppKit
import Bonsplit

/// Pre-computed layout result from a single tree traversal.
struct PaneLayoutResult {
    let canvasWidth: CGFloat
    let paneHorizontalSpans: [String: (xFraction: CGFloat, widthFraction: CGFloat)]
}

/// Computes proportional horizontal spans and the canvas width required to maintain minimum pane widths.
struct PaneLayoutEngine {
    let minPaneWidth: CGFloat

    init(minPaneWidth: CGFloat = 600) {
        self.minPaneWidth = minPaneWidth
    }

    /// Compute canvas width and per-pane horizontal spans in one tree traversal.
    func computeLayout(from tree: ExternalTreeNode, viewportWidth: CGFloat) -> PaneLayoutResult {
        var spans: [String: (xFraction: CGFloat, widthFraction: CGFloat)] = [:]
        appendHorizontalFractions(
            for: tree,
            xFraction: 0,
            widthFraction: 1,
            spans: &spans
        )
        let requiredCanvasWidth = minimumCanvasWidth(for: spans)
        let canvasWidth = max(viewportWidth, requiredCanvasWidth)

        return PaneLayoutResult(
            canvasWidth: canvasWidth,
            paneHorizontalSpans: spans
        )
    }

    // MARK: - Private

    /// Derives the minimum canvas width required to keep every pane at or above `minPaneWidth`
    /// while preserving the current divider ratios.
    private func minimumCanvasWidth(for spans: [String: (xFraction: CGFloat, widthFraction: CGFloat)]) -> CGFloat {
        guard !spans.isEmpty else { return minPaneWidth }

        var requiredWidth: CGFloat = minPaneWidth
        for (_, span) in spans {
            // Guard against tiny numerical drift near zero.
            let widthFraction = max(span.widthFraction, 0.0001)
            let paneRequiredWidth = minPaneWidth / widthFraction
            requiredWidth = max(requiredWidth, paneRequiredWidth)
        }
        return requiredWidth
    }

    private func appendHorizontalFractions(
        for node: ExternalTreeNode,
        xFraction: CGFloat,
        widthFraction: CGFloat,
        spans: inout [String: (xFraction: CGFloat, widthFraction: CGFloat)]
    ) {
        switch node {
        case let .pane(pane):
            spans[pane.id] = (
                xFraction: xFraction,
                widthFraction: widthFraction
            )
        case let .split(split) where split.orientation == "horizontal":
            let divider = CGFloat(split.dividerPosition).clamped(to: 0.0001 ... 0.9999)
            let firstWidthFraction = widthFraction * divider
            let secondWidthFraction = widthFraction - firstWidthFraction

            appendHorizontalFractions(
                for: split.first,
                xFraction: xFraction,
                widthFraction: firstWidthFraction,
                spans: &spans
            )
            appendHorizontalFractions(
                for: split.second,
                xFraction: xFraction + firstWidthFraction,
                widthFraction: secondWidthFraction,
                spans: &spans
            )
        case let .split(split):
            appendHorizontalFractions(
                for: split.first,
                xFraction: xFraction,
                widthFraction: widthFraction,
                spans: &spans
            )
            appendHorizontalFractions(
                for: split.second,
                xFraction: xFraction,
                widthFraction: widthFraction,
                spans: &spans
            )
        }
    }
}
