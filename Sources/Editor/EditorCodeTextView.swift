import AppKit
import SwiftUI

/// Body + gutter sizes (reference: slightly larger than system 12 for readability).
private enum EditorCodeTypography {
  static let bodyFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
  static let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
  static let gutterThickness: CGFloat = 46
  static let textContainerInset = NSSize(width: 10, height: 12)
  /// Extra vertical gap between rendered lines (TextKit line fragments).
  private static let bodyLineSpacing: CGFloat = 5

  static var defaultParagraphStyle: NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.lineSpacing = bodyLineSpacing
    p.paragraphSpacing = 0
    p.lineBreakMode = .byCharWrapping
    return p
  }

  /// Ensures new typing and bulk loads keep relaxed line height.
  static func applyParagraphStyleToDocument(_ tv: NSTextView) {
    tv.defaultParagraphStyle = defaultParagraphStyle
    var typing = tv.typingAttributes
    typing[.paragraphStyle] = defaultParagraphStyle
    typing[.font] = bodyFont
    if let color = tv.textColor {
      typing[.foregroundColor] = color
    }
    tv.typingAttributes = typing

    guard let ts = tv.textStorage, ts.length > 0 else { return }
    let full = NSRange(location: 0, length: ts.length)
    ts.beginEditing()
    ts.addAttribute(.paragraphStyle, value: defaultParagraphStyle, range: full)
    ts.endEditing()
  }
}

/// Naive bracket scan (ignores strings/comments); good enough for JSON/YAML-style editing.
private enum EditorBracketMatcher {
  private static let openToClose: [UInt16: UInt16] = [
    0x007B: 0x007D,  // { }
    0x005B: 0x005D,  // [ ]
    0x0028: 0x0029,  // ( )
  ]
  private static let closeToOpen: [UInt16: UInt16] = [
    0x007D: 0x007B,
    0x005D: 0x005B,
    0x0029: 0x0028,
  ]

  /// UTF-16 indices; returns two single-character ranges (open, close) in document order.
  static func matchingPairUTF16(in string: String, insertionUTF16: Int) -> (NSRange, NSRange)? {
    let ns = string as NSString
    let len = ns.length
    guard len > 0 else { return nil }

    let before = min(insertionUTF16, len) - 1
    if before >= 0 {
      let c = UInt16(ns.character(at: before))
      if let open = closeToOpen[c] {
        if let openIdx = scanBackward(ns: ns, closePos: before, closeChar: c, openChar: open) {
          return (NSRange(location: openIdx, length: 1), NSRange(location: before, length: 1))
        }
      }
    }

    let at = min(max(0, insertionUTF16), len - 1)
    let c2 = UInt16(ns.character(at: at))
    if let close = openToClose[c2] {
      if let closeIdx = scanForward(ns: ns, openPos: at, openChar: c2, closeChar: close) {
        return (NSRange(location: at, length: 1), NSRange(location: closeIdx, length: 1))
      }
    }
    return nil
  }

  private static func scanBackward(
    ns: NSString,
    closePos: Int,
    closeChar: UInt16,
    openChar: UInt16
  ) -> Int? {
    var balance = 0
    var i = closePos
    while i >= 0 {
      let c = UInt16(ns.character(at: i))
      if c == closeChar {
        balance += 1
      } else if c == openChar {
        balance -= 1
        if balance == 0 {
          return i
        }
      }
      i -= 1
    }
    return nil
  }

  private static func scanForward(
    ns: NSString,
    openPos: Int,
    openChar: UInt16,
    closeChar: UInt16
  ) -> Int? {
    guard openPos < ns.length, UInt16(ns.character(at: openPos)) == openChar else { return nil }
    var balance = 1
    let len = ns.length
    var i = openPos + 1
    while i < len {
      let c = UInt16(ns.character(at: i))
      if c == openChar {
        balance += 1
      } else if c == closeChar {
        balance -= 1
        if balance == 0 {
          return i
        }
      }
      i += 1
    }
    return nil
  }
}

extension String {
  /// 1-based line number for a UTF-16 offset (NSTextView / NSString indexing).
  fileprivate func logicalLineNumber(utf16Offset: Int) -> Int {
    let ns = self as NSString
    let len = ns.length
    guard len > 0 else { return 1 }
    let i = min(max(0, utf16Offset), len)
    var line = 1
    var idx = 0
    while idx < i {
      let c = ns.character(at: idx)
      if c == 10 || c == 13 { line += 1 }
      idx += 1
    }
    return line
  }
}

final class EditorSourceTextView: NSTextView {
  var onSaveRequest: () -> Void = {}

  func refreshAuxiliaryHighlights() {
    guard let lm = layoutManager, let ts = textStorage else { return }
    let len = ts.length
    let full = NSRange(location: 0, length: len)
    lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)

    guard len > 0 else {
      needsDisplay = true
      return
    }

    let insertion = selectedRange().location
    let lineAnchor = min(max(0, insertion), max(0, len - 1))
    let ns = ts.string as NSString
    let lineRange = ns.lineRange(for: NSRange(location: lineAnchor, length: 0))
    let lineFill = NSColor.white.withAlphaComponent(0.055)
    lm.addTemporaryAttribute(.backgroundColor, value: lineFill, forCharacterRange: lineRange)

    if let (openRange, closeRange) = EditorBracketMatcher.matchingPairUTF16(
      in: ts.string,
      insertionUTF16: insertion
    ) {
      let bracketFill = NSColor.white.withAlphaComponent(0.12)
      lm.addTemporaryAttribute(.backgroundColor, value: bracketFill, forCharacterRange: openRange)
      lm.addTemporaryAttribute(.backgroundColor, value: bracketFill, forCharacterRange: closeRange)
    }

    needsDisplay = true
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.command),
      let chars = event.charactersIgnoringModifiers?.lowercased(),
      chars == "s" {
      onSaveRequest()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// Vertical line-number gutter paired with `EditorSourceTextView`.
final class EditorLineNumberRulerView: NSRulerView {
  weak var lineTextView: NSTextView?

  init(scrollView: NSScrollView) {
    super.init(scrollView: scrollView, orientation: .verticalRuler)
  }

  required init(coder: NSCoder) {
    super.init(coder: coder)
  }

  override var requiredThickness: CGFloat { EditorCodeTypography.gutterThickness }

  override func drawHashMarksAndLabels(in rect: NSRect) {
    NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 0.55).setFill()
    NSBezierPath(rect: bounds).fill()

    guard let tv = lineTextView,
      let lm = tv.layoutManager,
      let tc = tv.textContainer
    else { return }

    let visible = tv.visibleRect
    let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
    let font = EditorCodeTypography.gutterFont
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .right
    paragraph.lineSpacing = EditorCodeTypography.defaultParagraphStyle.lineSpacing
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.white.withAlphaComponent(0.28),
      .paragraphStyle: paragraph,
    ]

    let origin = tv.textContainerOrigin
    let docNSString = tv.string as NSString
    let insertion = tv.selectedRange().location
    let activeLogicalLine: Int = {
      guard docNSString.length > 0 else { return 1 }
      let anchor = min(max(0, insertion), max(0, docNSString.length - 1))
      return tv.string.logicalLineNumber(utf16Offset: anchor)
    }()

    lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, fragGlyphRange, _ in
      let charIdx = lm.characterIndexForGlyph(at: fragGlyphRange.location)
      let lineNumber = tv.string.logicalLineNumber(utf16Offset: charIdx)
      // `usedRect` is in text-container coordinates; `textContainerOrigin` maps into the text view (includes inset).
      let rectInTextView = usedRect.offsetBy(dx: origin.x, dy: origin.y)
      let midInTextView = NSPoint(x: NSMidX(rectInTextView), y: NSMidY(rectInTextView))
      let midInRuler = self.convert(midInTextView, from: tv)
      // `usedRect.height` reflects paragraph `lineSpacing`; keeps gutter bands aligned with text lines.
      let lineHeight = max(usedRect.height, lm.defaultLineHeight(for: tv.font ?? EditorCodeTypography.bodyFont))
      if lineNumber == activeLogicalLine {
        NSColor.white.withAlphaComponent(0.045).setFill()
        NSBezierPath(
          rect: NSRect(
            x: 0,
            y: midInRuler.y - lineHeight / 2,
            width: self.bounds.width,
            height: lineHeight
          )
        ).fill()
      }
      let s = "\(lineNumber)" as NSString
      let size = s.size(withAttributes: attrs)
      let drawX = self.bounds.width - 8 - size.width
      let drawRect = NSRect(
        x: drawX,
        y: midInRuler.y - lineHeight / 2,
        width: max(size.width, self.bounds.width - 8 - drawX),
        height: lineHeight
      )
      s.draw(
        with: drawRect,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attrs
      )
    }
  }
}

/// Monospace `NSTextView` in a scroll view with a line-number ruler and ⌘S forwarding.
struct EditorCodeTextView: NSViewRepresentable {
  @Binding var text: String
  var isEditable: Bool
  var onSave: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    scroll.clipsToBounds = true
    scroll.contentView.clipsToBounds = true
    scroll.focusRingType = .none

    let tv = EditorSourceTextView()
    tv.clipsToBounds = true
    tv.focusRingType = .none
    tv.drawsBackground = true
    tv.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    tv.textColor = NSColor.white.withAlphaComponent(0.93)
    tv.insertionPointColor = NSColor.white
    tv.font = EditorCodeTypography.bodyFont
    tv.isAutomaticQuoteSubstitutionEnabled = false
    tv.isAutomaticDashSubstitutionEnabled = false
    tv.isAutomaticTextReplacementEnabled = false
    tv.isRichText = false
    tv.usesFontPanel = false
    tv.allowsUndo = true
    tv.textContainerInset = EditorCodeTypography.textContainerInset
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false
    tv.autoresizingMask = [.width]
    tv.textContainer?.widthTracksTextView = true
    tv.textContainer?.containerSize = NSSize(
      width: scroll.contentSize.width,
      height: CGFloat.greatestFiniteMagnitude
    )
    tv.minSize = NSSize(width: 0, height: 0)
    tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

    scroll.documentView = tv

    scroll.hasVerticalRuler = true
    scroll.rulersVisible = true
    let ruler = EditorLineNumberRulerView(scrollView: scroll)
    ruler.lineTextView = tv
    ruler.clientView = tv
    scroll.verticalRulerView = ruler

    context.coordinator.textView = tv
    context.coordinator.rulerView = ruler
    context.coordinator.textBinding = $text
    context.coordinator.onSave = onSave
    tv.textStorage?.delegate = context.coordinator
    tv.delegate = context.coordinator
    let coordinatorRef = context.coordinator
    tv.onSaveRequest = { [weak coordinatorRef] in
      coordinatorRef?.onSave()
    }

    context.coordinator.observeScrollBounds(scroll: scroll)

    context.coordinator.suppressCallbacks = true
    tv.string = text
    EditorCodeTypography.applyParagraphStyleToDocument(tv)
    context.coordinator.suppressCallbacks = false
    tv.isEditable = isEditable
    tv.refreshAuxiliaryHighlights()
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let tv = scroll.documentView as? EditorSourceTextView else { return }
    context.coordinator.textView = tv
    context.coordinator.rulerView = scroll.verticalRulerView as? EditorLineNumberRulerView
    context.coordinator.textBinding = $text
    context.coordinator.onSave = onSave

    context.coordinator.suppressCallbacks = true
    if tv.string != text {
      tv.string = text
      EditorCodeTypography.applyParagraphStyleToDocument(tv)
    }
    context.coordinator.suppressCallbacks = false
    tv.isEditable = isEditable
    tv.refreshAuxiliaryHighlights()
    scroll.verticalRulerView?.needsDisplay = true

    if let w = scroll.window?.contentView?.bounds.width, w > 0 {
      tv.textContainer?.containerSize = NSSize(width: max(200, scroll.contentSize.width), height: CGFloat.greatestFiniteMagnitude)
    }
  }

  static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
    coordinator.teardown()
  }

  final class Coordinator: NSObject, NSTextStorageDelegate, NSTextViewDelegate {
    weak var textView: EditorSourceTextView?
    weak var rulerView: EditorLineNumberRulerView?
    var textBinding: Binding<String> = .constant("")
    var onSave: () -> Void = {}
    var suppressCallbacks = false
    private var boundsObserver: NSObjectProtocol?

    func observeScrollBounds(scroll: NSScrollView) {
      boundsObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: scroll.contentView,
        queue: .main
      ) { [weak self] _ in
        self?.rulerView?.needsDisplay = true
      }
      scroll.contentView.postsBoundsChangedNotifications = true
    }

    func teardown() {
      if let boundsObserver {
        NotificationCenter.default.removeObserver(boundsObserver)
      }
      textView?.delegate = nil
      textView?.textStorage?.delegate = nil
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      (notification.object as? EditorSourceTextView)?.refreshAuxiliaryHighlights()
      rulerView?.needsDisplay = true
    }

    func textStorage(
      _ storage: NSTextStorage,
      didProcessEdited editedMask: NSTextStorageEditActions,
      in range: NSRange,
      changeInLength delta: Int
    ) {
      guard !suppressCallbacks else { return }
      textBinding.wrappedValue = storage.string
      textView?.refreshAuxiliaryHighlights()
      rulerView?.needsDisplay = true
    }
  }
}
