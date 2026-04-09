import AppKit

/// Draggable canvas divider with an expanded hit target and a thin visible line.
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
    static let lineThickness: CGFloat = 1

    var orientation: Orientation = .horizontal {
        didSet {
            needsLayout = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var accentColor: NSColor = .controlAccentColor {
        didSet { updateAppearance() }
    }

    /// Length of the split parent region in the drag axis.
    var parentSpanInDragAxis: CGFloat = 1

    /// Current normalized divider position (0.0-1.0) in the parent split.
    var position: CGFloat = 0.5

    /// Normalized drag bounds in the parent split.
    var minPosition: CGFloat = 0.1
    var maxPosition: CGFloat = 0.9

    var onPressFocus: ((FocusSide) -> Void)?
    var onDragBegan: ((FocusSide) -> Void)?
    var onDragDeltaPixels: ((CGFloat) -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: ((Bool, FocusSide) -> Void)?

    private let lineView = NSView(frame: .zero)
    private var trackingAreaRef: NSTrackingArea?
    private var dragStartPointInParent: CGPoint?
    private var dragStartPosition: CGFloat = 0.5
    private var interactionFocusSide: FocusSide = .first
    private var hasDragMovement = false
    private var didDispatchPressFocus = false
    private var deferredPressFocus: DispatchWorkItem?

    private var isHovered = false {
        didSet { updateAppearance() }
    }

    private var isDragging = false {
        didSet { updateAppearance() }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        lineView.wantsLayer = true
        lineView.layer?.cornerRadius = 0.5
        addSubview(lineView)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func layout() {
        super.layout()
        if orientation == .horizontal {
            lineView.frame = CGRect(
                x: (bounds.width - Self.lineThickness) / 2,
                y: 0,
                width: Self.lineThickness,
                height: bounds.height
            )
        } else {
            lineView.frame = CGRect(
                x: 0,
                y: (bounds.height - Self.lineThickness) / 2,
                width: bounds.width,
                height: Self.lineThickness
            )
        }
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        let cursor: NSCursor = orientation == .horizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            isHovered = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        isHovered = true
        dragStartPosition = position
        dragStartPointInParent = dragPoint(inParentFor: event)
        interactionFocusSide = focusSide(for: event)
        hasDragMovement = false
        didDispatchPressFocus = false
        scheduleDeferredPressFocus()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, parentSpanInDragAxis > 0 else { return }
        guard let startPoint = dragStartPointInParent else { return }
        let currentPoint = dragPoint(inParentFor: event)

        let deltaPixels: CGFloat
        if orientation == .horizontal {
            deltaPixels = currentPoint.x - startPoint.x
        } else {
            // Parent canvas is flipped, so +Y is down and follows natural divider movement.
            deltaPixels = currentPoint.y - startPoint.y
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

        let clamped = (dragStartPosition + deltaNormalized).clamped(to: minPosition...maxPosition)
        guard abs(clamped - position) > 0.0001 else { return }

        position = clamped
        onDrag?(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        finishDragging()
    }

    private func finishDragging() {
        guard isDragging else { return }
        deferredPressFocus?.cancel()
        deferredPressFocus = nil
        if !hasDragMovement, !didDispatchPressFocus {
            onPressFocus?(interactionFocusSide)
            didDispatchPressFocus = true
        }
        isDragging = false
        dragStartPointInParent = nil
        onDragEnd?(hasDragMovement, interactionFocusSide)
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

    private func updateAppearance() {
        let shouldShowLine = isHovered || isDragging
        lineView.layer?.backgroundColor = accentColor.withAlphaComponent(shouldShowLine ? 0.5 : 0.0).cgColor
    }

    private func scheduleDeferredPressFocus() {
        deferredPressFocus?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isDragging, !self.hasDragMovement else { return }
            self.didDispatchPressFocus = true
            self.onPressFocus?(self.interactionFocusSide)
        }
        deferredPressFocus = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }
}
