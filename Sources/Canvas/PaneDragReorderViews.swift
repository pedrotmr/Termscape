import AppKit
import Bonsplit

// MARK: - Pane drag handle style

//
// All variants sit on the **top-right** of each pane (clear of shell prompts on the left).
//
// UserDefaults key `termscape.paneDragHandleStyle` (raw value):
//   subtleDots     — default: tiny “⋯” on a whisper-light chip (calm)
//   softPill       — slightly larger pill + faint grip lines
//   lineBadge      — small square, SF Symbol horizontal lines only
//   microGrip      — narrow three-bar strip
//
// Legacy raw values `prominentPill`, `arrowsBadge`, `gripStrip` still map to the new quieter drawings.

enum PaneDragHandleStyle: String, CaseIterable {
    static let defaultsKey = "termscape.paneDragHandleStyle"

    case subtleDots
    case softPill
    case lineBadge
    case microGrip

    static var current: PaneDragHandleStyle {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        if let s = Self(rawValue: raw) { return s }
        // Map old names so existing defaults installs keep working.
        switch raw {
        case "prominentPill": return .softPill
        case "arrowsBadge": return .lineBadge
        case "gripStrip": return .microGrip
        default: return .subtleDots
        }
    }

    /// Frame in CanvasDocumentView coordinates; always aligned to the pane’s **trailing** top corner.
    func layoutFrame(in paneFrame: CGRect) -> CGRect {
        switch self {
        case .subtleDots:
            Self.rightEdge(in: paneFrame, width: 28, height: 16)
        case .softPill:
            Self.rightEdge(in: paneFrame, width: 52, height: 20)
        case .lineBadge:
            Self.rightEdge(in: paneFrame, width: 26, height: 26)
        case .microGrip:
            Self.rightEdge(in: paneFrame, width: 44, height: 14)
        }
    }

    fileprivate var toolTipText: String {
        "Drag to move this pane — center on another pane merges tabs; edges create a split"
    }

    /// Kept off by default so handles stay unobtrusive; set `true` for a style if you re-enable a hint later.
    fileprivate var usesAttentionAnimation: Bool {
        false
    }

    /// Top-right in flipped coordinates: `x` grows right, `y` grows down.
    private static func rightEdge(
        in pane: CGRect,
        width: CGFloat,
        height: CGFloat,
        trailing: CGFloat = 8,
        top: CGFloat = 5
    ) -> CGRect {
        let maxW = max(24, pane.width - trailing - 8)
        let w = min(width, maxW)
        let x = pane.maxX - trailing - w
        return CGRect(x: max(pane.minX + 4, x), y: pane.minY + top, width: w, height: height)
    }
}

// MARK: - Drop zone (mirrors Bonsplit’s split-edge affordances; local so we stay on public APIs only)

enum CanvasPaneDropZone: Equatable {
    case center
    case left
    case right
    case top
    case bottom

    static func zone(at pointInDocument: CGPoint, in paneFrame: CGRect) -> CanvasPaneDropZone {
        let lx = pointInDocument.x - paneFrame.minX
        let ly = pointInDocument.y - paneFrame.minY
        let w = paneFrame.width
        let h = paneFrame.height
        guard w > 0, h > 0 else { return .center }

        let edgeRatio: CGFloat = 0.25
        let horizontalEdge = max(80, w * edgeRatio)
        let verticalEdge = max(80, h * edgeRatio)

        if lx < horizontalEdge { return .left }
        if lx > w - horizontalEdge { return .right }
        if ly < verticalEdge { return .top }
        if ly > h - verticalEdge { return .bottom }
        return .center
    }

    var splitOrientation: SplitOrientation {
        switch self {
        case .left, .right: .horizontal
        case .top, .bottom: .vertical
        case .center:
            fatalError("center has no split orientation")
        }
    }

    var insertsFirst: Bool {
        switch self {
        case .left, .top: true
        case .right, .bottom, .center: false
        }
    }
}

// MARK: - Highlight overlay

@MainActor
final class PaneDropHighlightOverlay: NSView {
    var paneFrames: [String: CGRect] = [:]
    var targetPaneId: String?
    var zone: CanvasPaneDropZone?

    private var accent: NSColor = .controlAccentColor

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func applyAccent(_ color: NSColor) {
        accent = color
    }

    func setHighlight(targetPaneId: String?, zone: CanvasPaneDropZone?, frames: [String: CGRect]) {
        self.targetPaneId = targetPaneId
        self.zone = zone
        paneFrames = frames
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let targetPaneId, let zone, let paneFrame = paneFrames[targetPaneId] else { return }

        let inset: CGFloat = 4
        let highlight: NSRect = {
            switch zone {
            case .center:
                return paneFrame.insetBy(dx: inset, dy: inset)
            case .left:
                return CGRect(
                    x: paneFrame.minX + inset,
                    y: paneFrame.minY + inset,
                    width: max(paneFrame.width / 2 - inset * 1.5, 1),
                    height: max(paneFrame.height - inset * 2, 1)
                )
            case .right:
                let w = max(paneFrame.width / 2 - inset * 1.5, 1)
                return CGRect(
                    x: paneFrame.maxX - inset - w,
                    y: paneFrame.minY + inset,
                    width: w,
                    height: max(paneFrame.height - inset * 2, 1)
                )
            case .top:
                return CGRect(
                    x: paneFrame.minX + inset,
                    y: paneFrame.minY + inset,
                    width: max(paneFrame.width - inset * 2, 1),
                    height: max(paneFrame.height / 2 - inset * 1.5, 1)
                )
            case .bottom:
                let h = max(paneFrame.height / 2 - inset * 1.5, 1)
                return CGRect(
                    x: paneFrame.minX + inset,
                    y: paneFrame.maxY - inset - h,
                    width: max(paneFrame.width - inset * 2, 1),
                    height: h
                )
            }
        }()

        let path = NSBezierPath(roundedRect: highlight, xRadius: 8, yRadius: 8)
        accent.withAlphaComponent(0.22).setFill()
        path.fill()
        accent.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

// MARK: - Drag handle

@MainActor
final class PaneDragHandleView: NSView {
    weak var document: CanvasDocumentView?
    let paneId: String
    let style: PaneDragHandleStyle

    private var mouseDownLocation: CGPoint?
    private var monitorInstalled = false
    private var accentColor: NSColor = .controlAccentColor

    override var isFlipped: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    init(paneId: String, style: PaneDragHandleStyle) {
        self.paneId = paneId
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = style == .lineBadge ? 5 : 5
        toolTip = style.toolTipText
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Move pane")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func applyAccent(_ color: NSColor) {
        accentColor = color
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            restartAttentionAnimation()
        } else {
            layer?.removeAllAnimations()
        }
    }

    override func removeFromSuperview() {
        layer?.removeAllAnimations()
        super.removeFromSuperview()
    }

    private func restartAttentionAnimation() {
        layer?.removeAnimation(forKey: "paneDragPulseOpacity")
        guard style.usesAttentionAnimation, let layer else { return }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.92
        pulse.toValue = 1.0
        pulse.duration = 2.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "paneDragPulseOpacity")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard hypot(dx, dy) > 5 else { return }
        if !monitorInstalled {
            monitorInstalled = true
            document?.beginPaneDragSession(sourcePaneId: paneId, seedEvent: event)
        }
    }

    override func mouseUp(with _: NSEvent) {
        if !monitorInstalled {
            mouseDownLocation = nil
        }
        document?.paneDragHandleMouseUpIfIdle()
    }

    func resetAfterSession() {
        mouseDownLocation = nil
        monitorInstalled = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch style {
        case .subtleDots:
            drawSubtleDots()
        case .softPill:
            drawSoftPill()
        case .lineBadge:
            drawLineBadge()
        case .microGrip:
            drawMicroGrip()
        }
    }

    private func drawSubtleDots() {
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()

        NSColor.white.withAlphaComponent(0.28).setFill()
        let dotR: CGFloat = 1.15
        let midY = bounds.midY
        let baseX = bounds.midX - dotR * 2.4
        for i in 0 ..< 3 {
            let cx = baseX + CGFloat(i) * dotR * 2.4
            NSBezierPath(ovalIn: CGRect(x: cx - dotR, y: midY - dotR, width: dotR * 2, height: dotR * 2)).fill()
        }
    }

    private func drawSoftPill() {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: inset, xRadius: inset.height / 2, yRadius: inset.height / 2)
        NSColor.white.withAlphaComponent(0.07).setFill()
        path.fill()

        accentColor.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        NSColor.white.withAlphaComponent(0.32).setFill()
        let lineW = bounds.width - 14
        let lineH: CGFloat = 1.35
        let gap: CGFloat = 2.5
        let left = bounds.midX - lineW / 2
        var y = bounds.midY - gap - lineH
        for _ in 0 ..< 3 {
            NSBezierPath(roundedRect: CGRect(x: left, y: y, width: lineW, height: lineH), xRadius: 0.5, yRadius: 0.5)
                .fill()
            y += gap + lineH
        }
    }

    private func drawLineBadge() {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let bg = NSBezierPath(roundedRect: inset, xRadius: 5, yRadius: 5)
        NSColor.white.withAlphaComponent(0.07).setFill()
        bg.fill()

        accentColor.withAlphaComponent(0.22).setStroke()
        bg.lineWidth = 0.75
        bg.stroke()

        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        if let img = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        {
            img.isTemplate = true
            NSColor.white.withAlphaComponent(0.38).set()
            let pad: CGFloat = 6
            img.draw(
                in: bounds.insetBy(dx: pad, dy: pad),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }
    }

    private func drawMicroGrip() {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.06).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.3).setFill()
        let barH: CGFloat = 1.6
        let barW = bounds.width - 12
        let left = bounds.minX + 6
        var y = bounds.midY - barH - 3
        for _ in 0 ..< 3 {
            NSBezierPath(roundedRect: CGRect(x: left, y: y, width: barW, height: barH), xRadius: 0.5, yRadius: 0.5)
                .fill()
            y += barH + 2.5
        }
    }
}
