import AppKit
import Darwin
import Foundation
import WebKit

private final class BrowserToolbarChromeView: NSView {
    var onFocused: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocused?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFocused?()
        onContextMenu?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onFocused?()
        onContextMenu?(event)
        return nil
    }
}

private final class BrowserAddressField: NSTextField {
    var onFocused: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureSingleLinePresentation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSingleLinePresentation()
    }

    override func mouseDown(with event: NSEvent) {
        onFocused?()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            configureEditorForSingleLineInput()
            normalizeFieldContents()
        }
        return becameFirstResponder
    }

    override func rightMouseDown(with event: NSEvent) {
        onFocused?()
        onContextMenu?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onFocused?()
        onContextMenu?(event)
        return nil
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        configureEditorForSingleLineInput()
        normalizeFieldContents()
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        configureEditorForSingleLineInput()
        normalizeFieldContents()
    }

    private func configureSingleLinePresentation() {
        guard let cell = cell as? NSTextFieldCell else { return }
        cell.usesSingleLineMode = true
        cell.wraps = false
        cell.isScrollable = true
        cell.lineBreakMode = .byTruncatingMiddle
    }

    private func configureEditorForSingleLineInput() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.minSize = NSSize(width: 0, height: bounds.height)
        editor.maxSize = NSSize(width: .greatestFiniteMagnitude, height: bounds.height)
        editor.textContainerInset = NSSize(width: 0, height: 0)
        guard let container = editor.textContainer else { return }
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.containerSize = NSSize(width: .greatestFiniteMagnitude, height: bounds.height)
        container.lineBreakMode = .byClipping
        container.maximumNumberOfLines = 1
    }

    private func normalizeFieldContents() {
        let normalized = Self.oneLine(stringValue)
        guard normalized != stringValue else { return }
        stringValue = normalized
        if let editor = currentEditor() as? NSTextView {
            editor.selectedRange = NSRange(location: normalized.utf16.count, length: 0)
        }
    }

    static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}

private final class BrowserToolbarButton: NSButton {
    var onFocused: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocused?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFocused?()
        onContextMenu?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onFocused?()
        onContextMenu?(event)
        return nil
    }
}

/// WKWebView that reports focus/context events back to the canvas controller.
final class FocusableWKWebView: WKWebView {
    var onFocused: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocused?()
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onFocused?()
        onContextMenu?(event)
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        // Force the shared pane context menu (instead of WKWebView's native Reload/Inspect menu).
        onFocused?()
        onContextMenu?(event)
    }

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let horizontalPrimary = abs(dx) >= abs(dy) && abs(dx) > 0.01
        let shiftVertical = event.modifierFlags.contains(.shift) && abs(dy) > 0.01 && !horizontalPrimary

        if let canvas = enclosingTermscapeCanvasScrollView(),
           canvas.documentCanvasView.frame.width > canvas.documentVisibleRect.width + 0.5
        {
            // Mirror terminal behavior: horizontal gestures pan the workspace canvas, not the web content.
            if horizontalPrimary {
                canvas.applyHorizontalScrollDelta(-dx)
                return
            }
            if shiftVertical {
                canvas.applyHorizontalScrollDelta(-dy)
                return
            }
        }

        super.scrollWheel(with: event)
    }

    private func enclosingTermscapeCanvasScrollView() -> CanvasScrollView? {
        var view: NSView? = self
        while let v = view {
            if let canvas = v as? CanvasScrollView {
                return canvas
            }
            view = v.superview
        }
        return nil
    }
}

/// AppKit view hierarchy for a browser pane: toolbar + web content.
final class BrowserSurfaceContainerView: NSView {
    private let chromeView = NSView()
    private let toolbarView = BrowserToolbarChromeView()
    private let separator = NSBox()
    private let backButton: BrowserToolbarButton
    private let forwardButton: BrowserToolbarButton
    private let reloadButton: BrowserToolbarButton
    private let developerToolsButton: BrowserToolbarButton
    private let addressField = BrowserAddressField()

    let webView: FocusableWKWebView
    var onFocused: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    var onSubmitAddress: ((String) -> Void)?
    var onToggleDeveloperTools: (() -> Void)?
    var addressFocusView: NSView {
        addressField
    }

    init(webView: FocusableWKWebView) {
        self.webView = webView
        backButton = Self.makeToolbarButton(symbol: "chevron.left")
        forwardButton = Self.makeToolbarButton(symbol: "chevron.right")
        reloadButton = Self.makeToolbarButton(symbol: "arrow.clockwise")
        developerToolsButton = Self.makeToolbarButton(symbol: "wrench.and.screwdriver")
        super.init(frame: .zero)
        setupLayout()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private static func makeToolbarButton(symbol: String) -> BrowserToolbarButton {
        let button = BrowserToolbarButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(),
            target: nil,
            action: nil
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentTintColor = .secondaryLabelColor
        return button
    }

    private func setupLayout() {
        wantsLayer = true

        chromeView.wantsLayer = true
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chromeView)

        toolbarView.wantsLayer = true
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.onFocused = { [weak self] in
            self?.onFocused?()
        }
        toolbarView.onContextMenu = { [weak self] event in
            self?.onContextMenu?(event)
        }
        chromeView.addSubview(toolbarView)

        separator.boxType = .separator
        separator.titlePosition = .noTitle
        separator.translatesAutoresizingMaskIntoConstraints = false
        chromeView.addSubview(separator)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        chromeView.addSubview(webView)

        addressField.font = .systemFont(ofSize: 12, weight: .regular)
        addressField.focusRingType = .none
        addressField.bezelStyle = .roundedBezel
        addressField.maximumNumberOfLines = 1
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.placeholderString = "Enter URL or search..."
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.onFocused = { [weak self] in
            self?.onFocused?()
        }
        addressField.onContextMenu = { [weak self] event in
            self?.onContextMenu?(event)
        }
        toolbarView.addSubview(addressField)

        toolbarView.addSubview(backButton)
        toolbarView.addSubview(forwardButton)
        toolbarView.addSubview(reloadButton)
        toolbarView.addSubview(developerToolsButton)

        NSLayoutConstraint.activate([
            chromeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chromeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chromeView.topAnchor.constraint(equalTo: topAnchor),
            chromeView.bottomAnchor.constraint(equalTo: bottomAnchor),

            toolbarView.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
            toolbarView.topAnchor.constraint(equalTo: chromeView.topAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 32),

            backButton.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 22),
            backButton.heightAnchor.constraint(equalToConstant: 22),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            forwardButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 22),
            forwardButton.heightAnchor.constraint(equalToConstant: 22),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 2),
            reloadButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 22),
            reloadButton.heightAnchor.constraint(equalToConstant: 22),

            developerToolsButton.trailingAnchor.constraint(
                equalTo: toolbarView.trailingAnchor, constant: -8
            ),
            developerToolsButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            developerToolsButton.widthAnchor.constraint(equalToConstant: 22),
            developerToolsButton.heightAnchor.constraint(equalToConstant: 22),

            addressField.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 8),
            addressField.trailingAnchor.constraint(
                equalTo: developerToolsButton.leadingAnchor, constant: -8
            ),
            addressField.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            addressField.heightAnchor.constraint(equalToConstant: 24),

            separator.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
            separator.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            webView.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor),
        ])
    }

    private func wireActions() {
        let focusHandler = { [weak self] in
            guard let self else { return }
            self.onFocused?()
        }
        let contextHandler = { [weak self] (event: NSEvent) in
            guard let self else { return }
            self.onContextMenu?(event)
        }
        backButton.onFocused = focusHandler
        forwardButton.onFocused = focusHandler
        reloadButton.onFocused = focusHandler
        developerToolsButton.onFocused = focusHandler
        backButton.onContextMenu = contextHandler
        forwardButton.onContextMenu = contextHandler
        reloadButton.onContextMenu = contextHandler
        developerToolsButton.onContextMenu = contextHandler

        backButton.target = self
        backButton.action = #selector(goBack)
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
        reloadButton.target = self
        reloadButton.action = #selector(reload)
        developerToolsButton.target = self
        developerToolsButton.action = #selector(toggleDeveloperTools)
        addressField.target = self
        addressField.action = #selector(submitAddress)
    }

    @objc private func goBack() {
        webView.goBack()
        onFocused?()
    }

    @objc private func goForward() {
        webView.goForward()
        onFocused?()
    }

    @objc private func reload() {
        webView.reload()
        onFocused?()
    }

    @objc private func toggleDeveloperTools() {
        onToggleDeveloperTools?()
        onFocused?()
    }

    @objc private func submitAddress() {
        onSubmitAddress?(BrowserAddressField.oneLine(addressField.stringValue))
    }

    func updateAddressField(_ text: String) {
        guard addressField.currentEditor() == nil else { return }
        let oneLine = BrowserAddressField.oneLine(text)
        if addressField.stringValue != oneLine {
            addressField.stringValue = oneLine
        }
    }

    func setThemeBackground(_ color: NSColor) {
        chromeView.layer?.backgroundColor = color.cgColor
        toolbarView.layer?.backgroundColor = color.blended(withFraction: 0.10, of: .black)?.cgColor
        separator.borderColor = NSColor.labelColor.withAlphaComponent(0.2)
    }

    func updateNavigationButtonState(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }

    func updateDeveloperToolsButtonState(isActive: Bool) {
        developerToolsButton.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
    }
}

private extension NSObject {
    @discardableResult
    func termscapeCallVoid(selector: Selector, object: Any? = nil) -> Bool {
        guard responds(to: selector) else { return false }
        if NSStringFromSelector(selector).hasSuffix(":") {
            _ = perform(selector, with: object)
        } else {
            _ = perform(selector)
        }
        return true
    }
}

private extension WKWebView {
    func termscapeInspectorObject() -> NSObject? {
        let selector = NSSelectorFromString("_inspector")
        guard responds(to: selector),
              let inspector = perform(selector)?.takeUnretainedValue() as? NSObject
        else {
            return nil
        }
        return inspector
    }
}

/// Owns an embedded browser view for a pane tab.
@MainActor
final class BrowserSurface: NSObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let workspaceId: UUID

    let hostedView: BrowserSurfaceContainerView
    private let webView: FocusableWKWebView
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var forwardedOnFocused: (() -> Void)?
    private var forwardedOnContextMenu: ((NSEvent) -> Void)?
    private var developerToolsVisible = false

    private(set) var currentURL: URL?
    var onTitleChange: ((String) -> Void)?
    var onURLChange: ((URL?) -> Void)?

    var focusTargetView: NSView {
        webView
    }

    var addressBarFocusTargetView: NSView {
        hostedView.addressFocusView
    }

    var onFocused: (() -> Void)? {
        get { forwardedOnFocused }
        set { forwardedOnFocused = newValue }
    }

    var onContextMenu: ((NSEvent) -> Void)? {
        get { forwardedOnContextMenu }
        set { forwardedOnContextMenu = newValue }
    }

    init(workspaceId: UUID, initialURL: URL?) {
        id = UUID()
        self.workspaceId = workspaceId

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        hostedView = BrowserSurfaceContainerView(webView: webView)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.onFocused = { [weak self] in
            self?.forwardedOnFocused?()
        }
        webView.onContextMenu = { [weak self] event in
            self?.forwardedOnContextMenu?(event)
        }
        hostedView.onFocused = { [weak self] in
            self?.forwardedOnFocused?()
        }
        hostedView.onContextMenu = { [weak self] event in
            self?.forwardedOnContextMenu?(event)
        }

        hostedView.onSubmitAddress = { [weak self] input in
            self?.loadAddress(input)
        }
        hostedView.onToggleDeveloperTools = { [weak self] in
            _ = self?.toggleDeveloperTools()
        }

        observeWebViewState()
        hostedView.updateDeveloperToolsButtonState(isActive: developerToolsVisible)
        if let initialURL {
            load(initialURL)
        }
    }

    func load(_ url: URL) {
        currentURL = url
        hostedView.updateAddressField(url.absoluteString)
        webView.load(URLRequest(url: url))
    }

    func loadAddress(_ input: String) {
        guard let url = Self.resolveAddressInput(input) else { return }
        load(url)
    }

    func setBackgroundColor(_ color: NSColor) {
        hostedView.setThemeBackground(color)
    }

    func teardown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        titleObservation = nil
        urlObservation = nil
        backObservation = nil
        forwardObservation = nil
    }

    /// Some sites open links via target="_blank"/window.open.
    /// Keep browser behavior predictable by loading those requests in-place.
    func webView(
        _ webView: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        if let requestURL = navigationAction.request.url {
            load(requestURL)
        } else {
            webView.load(navigationAction.request)
        }
        return nil
    }

    private func observeWebViewState() {
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let resolvedTitle = (webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                if !resolvedTitle.isEmpty {
                    self.onTitleChange?(resolvedTitle)
                }
            }
        }

        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentURL = webView.url
                let display = webView.url?.absoluteString ?? ""
                self.hostedView.updateAddressField(display)
                self.onURLChange?(webView.url)
            }
        }

        backObservation = webView.observe(\.canGoBack, options: [.new, .initial]) {
            [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.hostedView.updateNavigationButtonState(
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward
                )
            }
        }

        forwardObservation = webView.observe(\.canGoForward, options: [.new, .initial]) {
            [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.hostedView.updateNavigationButtonState(
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward
                )
            }
        }
    }

    @discardableResult
    private func toggleDeveloperTools() -> Bool {
        let targetVisibility = !developerToolsVisible
        let changed = setDeveloperToolsVisible(targetVisibility)
        if changed {
            developerToolsVisible = targetVisibility
            hostedView.updateDeveloperToolsButtonState(isActive: targetVisibility)
        }
        return developerToolsVisible
    }

    private func setDeveloperToolsVisible(_ visible: Bool) -> Bool {
        if visible {
            if let inspector = webView.termscapeInspectorObject() {
                _ = inspector.termscapeCallVoid(selector: NSSelectorFromString("attach"))
                let shown =
                    inspector.termscapeCallVoid(selector: NSSelectorFromString("show"))
                        || inspector.termscapeCallVoid(selector: NSSelectorFromString("open"))
                if shown {
                    return true
                }
            }
            return webView.termscapeCallVoid(
                selector: NSSelectorFromString("_showWebInspector:"), object: nil
            )
        }

        if let inspector = webView.termscapeInspectorObject() {
            let hidden =
                inspector.termscapeCallVoid(selector: NSSelectorFromString("close"))
                    || inspector.termscapeCallVoid(selector: NSSelectorFromString("hide"))
                    || inspector.termscapeCallVoid(selector: NSSelectorFromString("detach"))
            if hidden {
                return true
            }
        }

        return webView.termscapeCallVoid(
            selector: NSSelectorFromString("_closeWebInspector:"), object: nil
        )
    }

    static func resolveAddressInput(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicit = URL(string: trimmed),
           let scheme = explicit.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            return explicit
        }

        if isLikelyHostOrDomain(trimmed) {
            let isLocalhostOrIP = isLocalhostOrIPAddress(trimmed)
            let scheme = isLocalhostOrIP ? "http" : "https"
            return URL(string: "\(scheme)://\(trimmed)")
        }

        return googleSearchURL(query: trimmed)
    }

    private static func googleSearchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    private static func isLikelyHostOrDomain(_ input: String) -> Bool {
        if input.contains(" ") {
            return false
        }
        if isLocalhostOrIPAddress(input) {
            return true
        }

        let hostWithoutPort = extractedHost(from: input)

        guard hostWithoutPort.contains(".") else {
            return false
        }
        guard !hostWithoutPort.hasPrefix("."), !hostWithoutPort.hasSuffix(".") else {
            return false
        }

        // Require at least two non-empty labels for a likely public domain.
        let labels = hostWithoutPort.split(separator: ".", omittingEmptySubsequences: true)
        return labels.count >= 2
    }

    private static func isLocalhostOrIPAddress(_ input: String) -> Bool {
        let hostWithoutPort = extractedHost(from: input).lowercased()

        if hostWithoutPort == "localhost" {
            return true
        }

        var ipv4Address = in_addr()
        if hostWithoutPort.withCString({ inet_pton(AF_INET, $0, &ipv4Address) }) == 1 {
            return true
        }

        var ipv6Address = in6_addr()
        return hostWithoutPort.withCString { inet_pton(AF_INET6, $0, &ipv6Address) } == 1
    }

    private static func extractedHost(from input: String) -> String {
        let hostCandidate =
            input
                .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? input

        if hostCandidate.hasPrefix("["),
           let closingBracket = hostCandidate.firstIndex(of: "]")
        {
            return String(
                hostCandidate[hostCandidate.index(after: hostCandidate.startIndex) ..< closingBracket]
            )
        }

        let colonCount = hostCandidate.filter { $0 == ":" }.count
        if colonCount > 1 {
            return hostCandidate
        }

        if colonCount == 1 {
            return hostCandidate
                .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? hostCandidate
        }

        return hostCandidate
    }
}
