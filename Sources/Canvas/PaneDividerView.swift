import AppKit

/// Short rounded capsule shown on draggable pane borders. Fades in on hover and
/// stretches along its long axis during active drag for tactile feedback.
final class PaneGrabberIndicator {
    enum LongAxis {
        case vertical
        case horizontal
    }

    private static let length: CGFloat = 40
    private static let thickness: CGFloat = 5

    var accentColor: NSColor = .systemBlue {
        didSet { layer?.backgroundColor = accentColor.cgColor }
    }

    var longAxis: LongAxis = .vertical {
        didSet {
            if let host { updateFrame(in: host.bounds) }
        }
    }

    private weak var host: NSView?
    private var layer: CALayer?

    func attach(to host: NSView) {
        self.host = host
        host.wantsLayer = true
        guard layer == nil, let hostLayer = host.layer else { return }
        let created = CALayer()
        created.backgroundColor = accentColor.cgColor
        created.opacity = 0
        created.zPosition = 10
        hostLayer.addSublayer(created)
        layer = created
    }

    func updateFrame(in bounds: CGRect) {
        guard let indicator = layer else { return }
        let length = Self.length
        let thickness = Self.thickness
        let indicatorBounds = switch longAxis {
        case .vertical: CGRect(x: 0, y: 0, width: thickness, height: length)
        case .horizontal: CGRect(x: 0, y: 0, width: length, height: thickness)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        indicator.bounds = indicatorBounds
        indicator.position = CGPoint(x: bounds.midX, y: bounds.midY)
        indicator.cornerRadius = thickness / 2
        CATransaction.commit()
    }

    func apply(isHovering: Bool, isTracking: Bool, in bounds: CGRect) {
        updateFrame(in: bounds)
        guard let indicator = layer else { return }

        let opacity: Float
        let longAxisScale: CGFloat
        if isTracking {
            opacity = 1.0
            longAxisScale = 1.35
        } else if isHovering {
            opacity = 1.0
            longAxisScale = 1.0
        } else {
            opacity = 0.2
            longAxisScale = 0.8
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        indicator.opacity = opacity
        indicator.transform = switch longAxis {
        case .vertical: CATransform3DMakeScale(1, longAxisScale, 1)
        case .horizontal: CATransform3DMakeScale(longAxisScale, 1, 1)
        }
        CATransaction.commit()
    }
}

/// Invisible hit strip in the gutter; drag and resize cursors only (no drawn chrome).
final class PaneDividerView: NSView {
    enum FocusSide {
        case first
        case second
    }

    enum Orientation {
        /// Split is horizontal, so the divider moves left/right.
        case horizontal
        /// Split is vertical, so the divider moves up/down.
        case vertical
    }

    static let hitThickness: CGFloat = 8

    var orientation: Orientation = .horizontal {
        didSet {
            window?.invalidateCursorRects(for: self)
            grabber.longAxis = orientation == .horizontal ? .vertical : .horizontal
        }
    }

    /// Length of the split parent region in the drag axis.
    var parentSpanInDragAxis: CGFloat = 1

    /// Current normalized divider position (0.0-1.0) in the parent split.
    var position: CGFloat = 0.5

    /// Normalized drag bounds in the parent split.
    var minPosition: CGFloat = 0.1
    var maxPosition: CGFloat = 0.9

    var accentColor: NSColor {
        get { grabber.accentColor }
        set { grabber.accentColor = newValue }
    }

    var onPressFocus: ((FocusSide) -> Void)?
    var onDragBegan: ((FocusSide) -> Void)?
    var onDragDeltaPixels: ((CGFloat) -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: ((Bool, FocusSide) -> Void)?

    private var isTrackingPointer = false
    private var dragStartPointInParent: CGPoint?
    private var dragStartPosition: CGFloat = 0.5
    private var interactionFocusSide: FocusSide = .first
    private var hasDragMovement = false
    private var didDispatchPressFocus = false
    private var deferredPressFocus: DispatchWorkItem?

    private let grabber = PaneGrabberIndicator()
    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        grabber.longAxis = .vertical
        grabber.attach(to: self)
    }

    override var frame: NSRect {
        didSet { grabber.updateFrame(in: bounds) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        isHovering = true
        updateGrabber()
    }

    override func mouseExited(with _: NSEvent) {
        isHovering = false
        updateGrabber()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func resetCursorRects() {
        let cursor: NSCursor = orientation == .horizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        isTrackingPointer = true
        dragStartPosition = position
        dragStartPointInParent = dragPoint(inParentFor: event)
        interactionFocusSide = focusSide(for: event)
        hasDragMovement = false
        didDispatchPressFocus = false
        scheduleDeferredPressFocus()
        updateGrabber()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPointer, parentSpanInDragAxis > 0 else { return }
        guard let startPoint = dragStartPointInParent else { return }
        let currentPoint = dragPoint(inParentFor: event)

        let deltaPixels: CGFloat = if orientation == .horizontal {
            currentPoint.x - startPoint.x
        } else {
            currentPoint.y - startPoint.y
        }
        if !hasDragMovement, abs(deltaPixels) >= 1 {
            hasDragMovement = true
            deferredPressFocus?.cancel()
            deferredPressFocus = nil
            onDragBegan?(interactionFocusSide)
        }
        onDragDeltaPixels?(deltaPixels)

        let deltaNormalized = deltaPixels / parentSpanInDragAxis
        guard abs(deltaNormalized) > 0.0001 else { return }

        let clamped = (dragStartPosition + deltaNormalized).clamped(to: minPosition ... maxPosition)
        guard abs(clamped - position) > 0.0001 else { return }

        position = clamped
        onDrag?(clamped)
    }

    override func mouseUp(with _: NSEvent) {
        finishDragging()
    }

    private func finishDragging() {
        guard isTrackingPointer else { return }
        isTrackingPointer = false
        deferredPressFocus?.cancel()
        deferredPressFocus = nil
        if !hasDragMovement, !didDispatchPressFocus {
            onPressFocus?(interactionFocusSide)
            didDispatchPressFocus = true
        }
        dragStartPointInParent = nil
        onDragEnd?(hasDragMovement, interactionFocusSide)
        updateGrabber()
    }

    private func dragPoint(inParentFor event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return superview?.convert(localPoint, from: self) ?? localPoint
    }

    private func focusSide(for event: NSEvent) -> FocusSide {
        let localPoint = convert(event.locationInWindow, from: nil)
        if orientation == .horizontal {
            return localPoint.x < bounds.midX ? .first : .second
        }
        return localPoint.y < bounds.midY ? .first : .second
    }

    private func scheduleDeferredPressFocus() {
        deferredPressFocus?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, isTrackingPointer, !self.hasDragMovement else { return }
            didDispatchPressFocus = true
            onPressFocus?(interactionFocusSide)
        }
        deferredPressFocus = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }

    private func updateGrabber() {
        grabber.apply(isHovering: isHovering, isTracking: isTrackingPointer, in: bounds)
    }
}
