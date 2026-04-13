import AppKit

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
    didSet { window?.invalidateCursorRects(for: self) }
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

  private var isTrackingPointer = false
  private var dragStartPointInParent: CGPoint?
  private var dragStartPosition: CGFloat = 0.5
  private var interactionFocusSide: FocusSide = .first
  private var hasDragMovement = false
  private var didDispatchPressFocus = false
  private var deferredPressFocus: DispatchWorkItem?

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
  }

  required init?(coder: NSCoder) {
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
  }

  override func mouseDragged(with event: NSEvent) {
    guard isTrackingPointer, parentSpanInDragAxis > 0 else { return }
    guard let startPoint = dragStartPointInParent else { return }
    let currentPoint = dragPoint(inParentFor: event)

    let deltaPixels: CGFloat
    if orientation == .horizontal {
      deltaPixels = currentPoint.x - startPoint.x
    } else {
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
      guard let self, self.isTrackingPointer, !self.hasDragMovement else { return }
      self.didDispatchPressFocus = true
      self.onPressFocus?(self.interactionFocusSide)
    }
    deferredPressFocus = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
  }
}
