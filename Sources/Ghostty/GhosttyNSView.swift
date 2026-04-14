import AppKit
import Foundation

/// Metal-backed NSView that renders a Ghostty terminal surface and handles all input.
/// Adapted from cmux's GhosttyNSView — stripped of keyboard copy mode, scroll lag telemetry,
/// and other non-essential features.
final class GhosttyNSView: NSView, NSTextInputClient {
    weak var terminalSurface: TerminalSurface?
    var tabId: UUID?

    /// Called when this terminal pane receives focus via mouse click or keyboard.
    /// CanvasDocumentView sets this to notify BonsplitController of the focused pane.
    var onFocused: (() -> Void)?

    /// Called when the user right-clicks this pane.
    /// If set, suppresses the default Ghostty right-click forwarding and lets the
    /// caller (CanvasDocumentView) build and show a context menu instead.
    var onContextMenu: ((NSEvent) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var windowObserver: NSObjectProtocol?
    private var markedText: NSAttributedString = .init()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        updateTrackingAreas()
    }

    deinit {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Window attachment

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }

        guard window != nil else { return }

        // Surface creation is deferred until we have a real window
        terminalSurface?.attachToView(self)

        if let surface = terminalSurface?.surface,
           let displayID = window?.screen?.displayID,
           displayID != 0 {
            ghostty_surface_set_display_id(surface, displayID)
        }

        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        updateSurfaceSize()
    }

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    override var isOpaque: Bool {
        false
    }

    func updateSurfaceSize() {
        guard let surface = terminalSurface?.surface else { return }
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let w = pixelDimension(from: bounds.width * scale)
        let h = pixelDimension(from: bounds.height * scale)
        guard w > 0, h > 0 else { return }
        ghostty_surface_set_size(surface, w, h)
        ghostty_surface_set_content_scale(surface, scale, scale)
        needsDisplay = true
    }

    private func pixelDimension(from value: CGFloat) -> UInt32 {
        guard value.isFinite else { return 0 }
        let floored = floor(max(0, value))
        guard floored < CGFloat(UInt32.max) else { return UInt32.max }
        return UInt32(floored)
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        guard let surface = terminalSurface?.surface else { return }
        ghostty_surface_draw(surface)
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        terminalSurface?.setFocused(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        terminalSurface?.setFocused(false)
        return true
    }

    // MARK: - Keyboard input

    /// Key codes that should always bypass IME and go directly to Ghostty.
    private static let directKeyCodes: Set<UInt16> = [
        36, // Return
        48, // Tab
        51, // Backspace / Delete
        53, // Escape
        76, // Numpad Enter
        117, // Forward Delete
        // Arrow keys
        123, 124, 125, 126,
        // Home, End, Page Up, Page Down
        115, 116, 119, 121,
        // F1–F20
        96, 97, 98, 99, 100, 101, 103, 109, 111, 118, 120, 122
    ]

    override func keyDown(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else {
            super.keyDown(with: event)
            return
        }

        ghostty_surface_set_focus(surface, true)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Send directly to Ghostty (bypassing IME) for:
        //  • any Control / Command / Option modified key
        //  • non-printable / special keys (Return, Backspace, arrows, Esc, …)
        // Always use IME while a composition is in progress (marked text).
        let hasSystemMod = !flags.intersection([.control, .command, .option]).isEmpty
        let isSpecialKey = Self.directKeyCodes.contains(event.keyCode)

        if hasSystemMod || isSpecialKey, !hasMarkedText() {
            sendKeyDirectly(event, surface: surface, includeText: !isSpecialKey)
            return
        }

        // Normal path: IME / NSTextInputClient for regular printable text
        inputContext?.handleEvent(event)
    }

    private func sendKeyDirectly(_ event: NSEvent, surface: ghostty_surface_t, includeText: Bool) {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)

        let text = includeText ? (event.charactersIgnoringModifiers ?? event.characters ?? "") : ""
        if text.isEmpty {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        } else {
            _ = text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = 0

        // Determine if modifier was pressed or released
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 56, 60: flag = .shift // left/right shift
        case 59, 62: flag = .control // left/right control
        case 58, 61: flag = .option // left/right option
        case 55, 54: flag = .command // left/right command
        default: flag = []
        }
        keyEvent.action = event.modifierFlags.contains(flag) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        _ = ghostty_surface_key(surface, keyEvent)
    }

    // MARK: - NSTextInputClient (for composed input / IME)

    func insertText(_ string: Any, replacementRange _: NSRange) {
        guard let surface = terminalSurface?.surface else { return }
        let text: String
        if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else if let str = string as? String {
            text = str
        } else { return }

        markedText = NSAttributedString()
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = 0
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = 0
        _ = text.withCString { ptr in
            keyEvent.text = ptr
            return ghostty_surface_key(surface, keyEvent)
        }
    }

    func setMarkedText(_ string: Any, selectedRange _: NSRange, replacementRange _: NSRange) {
        if let attrStr = string as? NSAttributedString {
            markedText = attrStr
        } else if let str = string as? String {
            markedText = NSAttributedString(string: str)
        }
    }

    func unmarkText() {
        markedText = NSAttributedString()
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func attributedSubstring(forProposedRange _: NSRange, actualRange _: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange _: NSRange, actualRange _: NSRangePointer?) -> NSRect {
        .zero
    }

    func characterIndex(for _: NSPoint) -> Int {
        NSNotFound
    }

    // MARK: - Mouse input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        if let area = trackingArea { addTrackingArea(area) }
    }

    override func mouseDown(with event: NSEvent) {
        // Match rightMouseDown: focus Bonsplit + first responder even if surface not ready yet.
        onFocused?()
        window?.makeFirstResponder(self)
        if terminalSurface?.surface == nil {
            terminalSurface?.attachToView(self)
        }
        guard let surface = terminalSurface?.surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mods = modsFromEvent(event)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mods = modsFromEvent(event)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        // Always focus the right-clicked pane first so any menu action targets it.
        onFocused?()
        window?.makeFirstResponder(self)

        if let handler = onContextMenu {
            handler(event)
        } else {
            guard let surface = terminalSurface?.surface else { return }
            let point = convert(event.locationInWindow, from: nil)
            let mods = modsFromEvent(event)
            ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        // Skip forwarding if onContextMenu handled the paired press — Ghostty never saw
        // the down event so sending only the up would leave it with an unpaired release.
        guard onContextMenu == nil else { return }
        guard let surface = terminalSurface?.surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mods = modsFromEvent(event)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, modsFromEvent(event))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, modsFromEvent(event))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = terminalSurface?.surface else { return }
        let x = Double(event.scrollingDeltaX)
        let y = Double(event.scrollingDeltaY)

        // Route predominantly horizontal (or Shift+vertical) scroll to the termscape canvas so it can pan
        // when the document is wider than the viewport. Otherwise the inner terminal eats all deltas.
        let dx = CGFloat(x)
        let dy = CGFloat(y)
        let horizontalPrimary = abs(dx) >= abs(dy) && abs(dx) > 0.01
        let shiftVertical = event.modifierFlags.contains(.shift) && abs(dy) > 0.01 && !horizontalPrimary

        if let canvas = enclosingTermscapeCanvasScrollView(),
           canvas.documentCanvasView.frame.width > canvas.documentVisibleRect.width + 0.5 {
            // Negate so Shift+scroll down pans left (matches typical macOS horizontal-scroll expectation).
            if horizontalPrimary {
                canvas.applyHorizontalScrollDelta(-dx)
                return
            }
            if shiftVertical {
                canvas.applyHorizontalScrollDelta(-dy)
                return
            }
        }

        let mods = modsFromEvent(event)
        ghostty_surface_mouse_scroll(surface, x, y, ghostty_input_scroll_mods_t(mods.rawValue))
    }

    private func enclosingTermscapeCanvasScrollView() -> CanvasScrollView? {
        var view: NSView? = self
        while let v = view {
            if let canvas = v as? CanvasScrollView { return canvas }
            view = v.superview
        }
        return nil
    }

    // MARK: - Helpers

    private func modsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if event.modifierFlags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if event.modifierFlags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if event.modifierFlags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if event.modifierFlags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    private func unshiftedCodepoint(from event: NSEvent) -> UInt32 {
        guard let chars = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? event.characters,
              chars.count == 1,
              let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20,
              !(scalar.value >= 0xF700 && scalar.value <= 0xF8FF)
        else {
            return 0
        }
        return scalar.value
    }
}
