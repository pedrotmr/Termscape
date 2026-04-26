import AppKit
import SwiftUI
import WebKit

struct CodeMirrorThemePayload: Encodable, Equatable {
    let background: String
    let foreground: String
    let muted: String
    let accent: String
    let border: String
    let chrome: String
    let hover: String
    let selection: String
    let activeLine: String
    let bracket: String
    let isDark: Bool
}

struct CodeMirrorDocumentPayload: Encodable, Equatable {
    let id: String
    let path: String
    let text: String
    let editable: Bool
}

private enum CodeMirrorJSON {
    static func encodeJavaScriptArgument(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }
}

final class CodeMirrorWebView: WKWebView {
    var onFocused: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocused?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFocused?()
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onFocused?()
        onContextMenu?(event)
        return nil
    }
}

final class CodeMirrorHostView: NSView {
    let webView: CodeMirrorWebView

    init(webView: CodeMirrorWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }
}

struct CodeMirrorEditorView: NSViewRepresentable {
    var theme: AppTheme
    var documentId: UUID
    var filePath: String
    @Binding var text: String
    var isEditable: Bool
    var onSave: () -> Void
    var onFocus: () -> Void = {}
    var onContextMenu: ((NSEvent) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSave: onSave, onFocus: onFocus)
    }

    func makeNSView(context: Context) -> CodeMirrorHostView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "termscapeEditor")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.suppressesIncrementalRendering = false

        let webView = CodeMirrorWebView(frame: .zero, configuration: configuration)
        // WKWebView does not expose a supported public API for a transparent backing
        // store on macOS; `drawsBackground` is the common WebKit pattern used here.
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.onFocused = { [weak coordinator = context.coordinator] in
            coordinator?.onFocus()
        }
        webView.onContextMenu = { [weak coordinator = context.coordinator] event in
            coordinator?.onContextMenu?(event)
        }
        #if DEBUG
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
            }
        #endif

        context.coordinator.webView = webView
        context.coordinator.textBinding = $text
        context.coordinator.onSave = onSave
        context.coordinator.onFocus = onFocus
        context.coordinator.onContextMenu = onContextMenu
        context.coordinator.currentDocumentId = documentId
        context.coordinator.currentFilePath = filePath
        context.coordinator.currentEditable = isEditable
        context.coordinator.pendingTheme = Self.themePayload(from: theme)
        context.coordinator.pendingDocument = documentPayload()

        if let url = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "Editor/CodeMirror"
        ) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            context.coordinator.markLoadFailure("Missing bundled CodeMirror index.html")
        }

        let host = CodeMirrorHostView(webView: webView)
        host.layer?.backgroundColor = theme.canvasBackground.cgColor
        return host
    }

    func updateNSView(_ host: CodeMirrorHostView, context: Context) {
        host.layer?.backgroundColor = theme.canvasBackground.cgColor
        context.coordinator.textBinding = $text
        context.coordinator.onSave = onSave
        context.coordinator.onFocus = onFocus
        context.coordinator.onContextMenu = onContextMenu

        let themePayload = Self.themePayload(from: theme)
        context.coordinator.applyTheme(themePayload)

        let payload = documentPayload()
        if context.coordinator.currentDocumentId != documentId
            || context.coordinator.currentFilePath != filePath
            || context.coordinator.currentEditable != isEditable
        {
            context.coordinator.currentDocumentId = documentId
            context.coordinator.currentFilePath = filePath
            context.coordinator.currentEditable = isEditable
            context.coordinator.applyDocument(payload)
        } else {
            let lastSent = context.coordinator.lastTextSentToJavaScript
            let lastReceived = context.coordinator.lastTextReceivedFromJavaScript
            let editorBehindModelWhileSentMatchesModel =
                lastSent == text && lastReceived.map { $0 != text } == true
            let modelDiffersFromTrackedEditorAndSent =
                lastSent != text && lastReceived != text
            if editorBehindModelWhileSentMatchesModel || modelDiffersFromTrackedEditorAndSent {
                context.coordinator.applyDocument(payload)
            }
        }
    }

    static func dismantleNSView(_: CodeMirrorHostView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    private func documentPayload() -> CodeMirrorDocumentPayload {
        CodeMirrorDocumentPayload(
            id: documentId.uuidString,
            path: filePath,
            text: text,
            editable: isEditable
        )
    }

    private static func themePayload(from theme: AppTheme) -> CodeMirrorThemePayload {
        let selection = Self.rgbaString(
            theme.accentNSColor,
            alpha: theme.isDark ? 0.28 : 0.24
        )
        let active = theme.isDark ? "rgba(255,255,255,0.045)" : "rgba(0,0,0,0.045)"
        let bracket = theme.isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.09)"
        return CodeMirrorThemePayload(
            background: theme.canvasBackground.hexString(),
            foreground: Self.cssColorString(NSColor(theme.text)),
            muted: Self.cssColorString(NSColor(theme.textMuted)),
            accent: Self.cssColorString(theme.accentNSColor),
            border: Self.cssColorString(theme.borderNSColor),
            chrome: theme.canvasBackground.hexString(),
            hover: Self.cssColorString(NSColor(theme.hover)),
            selection: selection,
            activeLine: active,
            bracket: bracket,
            isDark: theme.isDark
        )
    }

    private static func rgbaString(_ color: NSColor, alpha: CGFloat) -> String {
        guard let c = color.usingColorSpace(.sRGB) else {
            return "rgba(0,0,0,\(alpha))"
        }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return "rgba(\(r),\(g),\(b),\(alpha))"
    }

    private static func cssColorString(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        let alpha = max(0, min(1, c.alphaComponent))
        if alpha >= 0.995 {
            return String(format: "#%02x%02x%02x", r, g, b)
        }
        return "rgba(\(r),\(g),\(b),\(alpha))"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var textBinding: Binding<String>
        var onSave: () -> Void
        var onFocus: () -> Void
        var onContextMenu: ((NSEvent) -> Void)?
        var currentDocumentId: UUID?
        var currentFilePath: String?
        var currentEditable = true
        var lastTextSentToJavaScript: String?
        var lastTextReceivedFromJavaScript: String?
        var pendingTheme: CodeMirrorThemePayload?
        var pendingDocument: CodeMirrorDocumentPayload?
        private var appliedTheme: CodeMirrorThemePayload?
        private var isReady = false
        private var didReportLoadFailure = false

        init(text: Binding<String>, onSave: @escaping () -> Void, onFocus: @escaping () -> Void) {
            textBinding = text
            self.onSave = onSave
            self.onFocus = onFocus
        }

        func teardown() {
            guard let webView else { return }
            let flushScript =
                "(function(){try{if(window.termscapeEditor&&window.termscapeEditor.flushText){window.termscapeEditor.flushText('teardown');}}catch(e){}})();"
            webView.evaluateJavaScript(flushScript) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.finishTeardown(webView: webView)
                }
            }
        }

        private func finishTeardown(webView: WKWebView) {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "termscapeEditor")
            webView.navigationDelegate = nil
            webView.stopLoading()
        }

        func markLoadFailure(_ message: String) {
            guard !didReportLoadFailure else { return }
            didReportLoadFailure = true
            print("CodeMirror editor load failure: \(message)")
        }

        private func messageDocumentMatchesCurrent(_ body: [String: Any]) -> Bool {
            guard let idString = body["documentId"] as? String,
                  let incoming = UUID(uuidString: idString),
                  let current = currentDocumentId
            else { return false }
            return incoming == current
        }

        private func applyRemoteTextIfChanged(_ text: String) {
            lastTextReceivedFromJavaScript = text
            if textBinding.wrappedValue != text {
                textBinding.wrappedValue = text
            }
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            flushPendingStateIfReady()
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            markLoadFailure(error.localizedDescription)
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            markLoadFailure(error.localizedDescription)
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "termscapeEditor",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            switch type {
            case "ready":
                isReady = true
                flushPendingStateIfReady()
            case "focused":
                onFocus()
            case "documentChanged":
                guard let text = body["text"] as? String else { return }
                guard messageDocumentMatchesCurrent(body) else { return }
                applyRemoteTextIfChanged(text)
            case "saveRequested":
                guard messageDocumentMatchesCurrent(body) else { return }
                if let text = body["text"] as? String {
                    applyRemoteTextIfChanged(text)
                }
                onSave()
            default:
                break
            }
        }

        func applyTheme(_ payload: CodeMirrorThemePayload) {
            pendingTheme = payload
            guard appliedTheme != payload else { return }
            guard isReady else { return }
            guard let json = CodeMirrorJSON.encodeJavaScriptArgument(payload) else { return }
            appliedTheme = payload
            webView?.evaluateJavaScript("window.termscapeEditor.setTheme(\(json));")
        }

        func applyDocument(_ payload: CodeMirrorDocumentPayload) {
            pendingDocument = payload
            lastTextSentToJavaScript = payload.text
            guard isReady else { return }
            guard let json = CodeMirrorJSON.encodeJavaScriptArgument(payload) else { return }
            webView?.evaluateJavaScript("window.termscapeEditor.setDocument(\(json));")
        }

        private func flushPendingStateIfReady() {
            guard isReady else { return }
            if let pendingTheme {
                applyTheme(pendingTheme)
            }
            if let pendingDocument {
                applyDocument(pendingDocument)
            }
        }
    }
}
