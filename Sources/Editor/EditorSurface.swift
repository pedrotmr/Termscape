import AppKit
import Foundation
import SwiftUI

@MainActor
private enum EditorPaneAlert: Identifiable, Equatable {
    case closeDirty(documentId: UUID, title: String)
    /// `closeAfterResolve`: true when the user was closing a dirty tab and save hit a disk conflict.
    case saveConflict(documentId: UUID, diskPreview: String, closeAfterResolve: Bool)
    case userMessage(title: String, detail: String)

    var id: String {
        switch self {
        case let .closeDirty(id, _): "close-\(id.uuidString)"
        case let .saveConflict(id, _, close): "conflict-\(id.uuidString)-\(close)"
        case let .userMessage(title, detail): "msg-\(title)-\(detail.hashValue)"
        }
    }
}

/// Drives `EditorSurfaceRootView` without replacing `NSHostingView.rootView`, so SwiftUI `@State`
/// (tabs, expansion, hover) stays stable across editor state and file-tree refreshes.
@MainActor
private final class EditorSurfaceViewModel: ObservableObject {
    let standardizedRootPath: String
    @Published var editorState: EditorSurface.State = .initializing
    /// `false` until `EditorSurface.ensureInitialized()` runs (first AppKit focus of this pane). Drives idle copy instead of fake “loading”.
    @Published var hasStartedEditorBootstrap = false
    @Published var fileTreeIndex: FileTreeIndex?
    /// Bumped only when the shared index clears its cache (watcher / invalidation). Drives `LazyVStack` `.id`
    /// and rescheduling loads for expanded folders — not per-directory async loads.
    @Published var treeCacheInvalidationEpoch: UInt = 0
    /// Bumped after each successful `scheduleLoadChildren` merge so SwiftUI refreshes rows without remounting the tree.
    @Published var fileTreeContentRevision: UInt = 0
    @Published var sidebarSearchText: String = ""

    let documentStore = EditorDocumentStore()
    @Published var documentTabs: [EditorDocumentBuffer] = []
    @Published var selectedDocumentId: UUID?
    @Published var pendingAlert: EditorPaneAlert?
    private var didSeedInitialDocuments = false

    var onFocus: () -> Void = {}
    var onContextMenu: (NSEvent) -> Void = { _ in }
    var onRetry: () -> Void = {}
    var onOpenTerminalHere: () -> Void = {}
    var onShowDiagnostics: () -> Void = {}

    init(standardizedRootPath: String) {
        self.standardizedRootPath = standardizedRootPath
    }
}

@MainActor
final class EditorSurface {
    enum State {
        case initializing
        case ready
        case unavailableRoot
        case initFailed
    }

    let id: UUID
    let workspaceId: UUID
    /// Path supplied when the surface was created (may differ from `standardizedRootPath` only by normalization).
    let rootPath: String
    /// Canonical filesystem path for this editor root; used for `FileTreeIndexPool` and tree queries.
    private let standardizedRootPath: String
    let hostedView: NSHostingView<EditorSurfaceRootView>

    var onFocused: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    var onRequestRetry: (() -> Void)?
    var onOpenTerminalHere: (() -> Void)?
    var onShowDiagnostics: ((String) -> Void)?

    private let viewModel: EditorSurfaceViewModel
    private var didAttemptInitialization = false
    private var fileTreeIndex: FileTreeIndex?

    init(workspaceId: UUID, rootPath: String) {
        id = UUID()
        self.workspaceId = workspaceId
        self.rootPath = rootPath
        let standardized = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        standardizedRootPath = standardized
        let vm = EditorSurfaceViewModel(standardizedRootPath: standardized)
        viewModel = vm
        hostedView = NSHostingView(rootView: EditorSurfaceRootView(model: vm))
        wireViewModelCallbacks()
        syncFileTreeToViewModel()
    }

    private func wireViewModelCallbacks() {
        viewModel.onFocus = { [weak self] in self?.onFocused?() }
        viewModel.onContextMenu = { [weak self] event in self?.onContextMenu?(event) }
        viewModel.onRetry = { [weak self] in
            self?.retryInitialization()
            self?.onRequestRetry?()
        }
        viewModel.onOpenTerminalHere = { [weak self] in self?.onOpenTerminalHere?() }
        viewModel.onShowDiagnostics = { [weak self] in
            guard let self else { return }
            onShowDiagnostics?(diagnosticsText)
        }
    }

    private func setPaneState(_ newState: State) {
        viewModel.editorState = newState
        syncFileTreeToViewModel()
    }

    private func syncFileTreeToViewModel() {
        viewModel.fileTreeIndex = fileTreeIndex
    }

    func ensureInitialized() {
        guard !didAttemptInitialization else { return }
        didAttemptInitialization = true
        viewModel.hasStartedEditorBootstrap = true
        retryInitialization()
    }

    func setFocused(_ focused: Bool) {
        fileTreeIndex?.setActive(focused)
    }

    func retryInitialization() {
        setPaneState(.initializing)

        let rootURL = URL(fileURLWithPath: standardizedRootPath, isDirectory: true)
        var isDir = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            setPaneState(.unavailableRoot)
            return
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            if fileTreeIndex == nil {
                let index = FileTreeIndexPool.retainIndex(for: standardizedRootPath)
                index.addInvalidationObserver(id: id) { [weak self] in
                    self?.viewModel.treeCacheInvalidationEpoch += 1
                }
                fileTreeIndex = index
            }
            fileTreeIndex?.setChildrenDidChangeHandler { [weak self] in
                self?.viewModel.fileTreeContentRevision += 1
            }
            setPaneState(.ready)
        } catch {
            setPaneState(.initFailed)
        }
    }

    func teardown() {
        if let index = fileTreeIndex {
            index.setChildrenDidChangeHandler(nil)
            index.removeInvalidationObserver(id: id)
            FileTreeIndexPool.releaseIndex(for: standardizedRootPath)
            fileTreeIndex = nil
            syncFileTreeToViewModel()
        }
    }

    var diagnosticsText: String {
        "editor_root=\(standardizedRootPath)\neditor_state=\(String(describing: viewModel.editorState))"
    }
}

// MARK: - IDE chrome (static colors; editor pane is always dark)

private enum EditorIDEChrome {
    static let canvas = Color(red: 0.07, green: 0.07, blue: 0.08)
    /// Intentionally matches `canvas` so the file column and editor read as one surface (divider + chrome provide structure).
    static let sidebar = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let tabInactive = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let tabActive = Color(red: 0.15, green: 0.15, blue: 0.16)
    /// Inactive tab hover — visibly softer than `tabActive` so selection stays strongest.
    static let tabHoverFill = Color(red: 0.118, green: 0.118, blue: 0.125)
    static let hairline = Color.white.opacity(0.085)
    static let muted = Color.white.opacity(0.48)
    static let text = Color.white.opacity(0.93)
    static let searchFieldFill = Color.white.opacity(0.055)
    static let searchFieldStroke = Color.white.opacity(0.10)
    static let searchCornerRadius: CGFloat = 6
    /// Disclosure triangles beside folders (fixed-width column avoids layout shift).
    static let disclosureTint = Color.white.opacity(0.45)
    static let treeDimmed = Color.white.opacity(0.32)
    /// Subtle row hover / selection (files and folders).
    static let fileRowHoverFill = Color.white.opacity(0.065)
    static let fileRowSelectedFill = Color.white.opacity(0.085)
    /// Breadcrumb separators — high enough contrast to read on dark chrome.
    static let breadcrumbChevron = Color.white.opacity(0.58)
    /// Breadcrumb hover: brighter text only (same font weight as idle — avoids layout shift).
    static let breadcrumbHoverMuted = Color.white.opacity(0.78)
    /// Fixed width for the sidebar tree icon column (triangle / file glyph); keeps labels aligned when toggling expand.
    static let treeIconColumn: CGFloat = 14
    static let treeIndentStep: CGFloat = 8
    static let treeEdgeInset: CGFloat = 8
    static let sidebarHeaderPaddingH: CGFloat = 18
    static let sidebarHeaderPaddingTop: CGFloat = 18
    static let sidebarHeaderPaddingBottom: CGFloat = 14
    static let sidebarHeaderSectionSpacing: CGFloat = 14
    static let fileSidebarMinWidth: CGFloat = 220
    static let fileSidebarDefaultWidth: CGFloat = 260
    static let fileSidebarMaxWidth: CGFloat = 560
    static let fileSidebarDividerHover = Color.white.opacity(0.26)
}

private struct SidebarSearchTreeNode: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let isSearchMatch: Bool
    let children: [SidebarSearchTreeNode]

    var id: String {
        path
    }
}

/// Recursive search-result row without `AnyView` type erasure (see review: SwiftUI diffing).
private struct SidebarSearchTreeRowView: View {
    let node: SidebarSearchTreeNode
    let level: Int
    @Binding var hoveredPath: String?
    let selectedFilePath: String?
    let onDirectoryTap: (SidebarSearchTreeNode) -> Void
    let onFileTap: (SidebarSearchTreeNode) -> Void

    var body: some View {
        let path = URL(fileURLWithPath: node.path).standardizedFileURL.path
        let isSelectedFile =
            selectedFilePath.map { $0 == path } ?? false
        let isHovered = hoveredPath == node.path
        let isDimmed = node.isDirectory && !node.isSearchMatch
        let labelColor = Self.labelColor(
            isSelected: isSelectedFile, isHovered: isHovered, dimmed: isDimmed
        )
        let iconColor = Self.iconColor(
            isSelected: isSelectedFile, isHovered: isHovered, dimmed: isDimmed
        )
        let disclosureTint: Color =
            (isDimmed && !isHovered)
                ? EditorIDEChrome.treeDimmed
                : Self.disclosureTint(isHovered: isHovered)

        VStack(alignment: .leading, spacing: 2) {
            Button {
                if node.isDirectory {
                    onDirectoryTap(node)
                } else {
                    onFileTap(node)
                }
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    if node.isDirectory {
                        SidebarDisclosureTriangle(
                            expanded: !node.children.isEmpty,
                            tint: disclosureTint
                        )
                    } else {
                        Self.fileIcon(for: node.name)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(iconColor)
                            .frame(width: EditorIDEChrome.treeIconColumn, alignment: .center)
                    }
                    Text(node.name)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(
                    .leading,
                    EditorIDEChrome.treeEdgeInset + CGFloat(level) * EditorIDEChrome.treeIndentStep
                )
                .padding(.vertical, 4)
                .padding(.trailing, EditorIDEChrome.treeEdgeInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Self.rowBackground(isSelected: isSelectedFile, isHovered: isHovered))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .id(node.path)
            .onHover { isHovering in
                if isHovering {
                    hoveredPath = node.path
                } else if hoveredPath == node.path {
                    hoveredPath = nil
                }
            }

            if node.isDirectory {
                ForEach(node.children) { child in
                    SidebarSearchTreeRowView(
                        node: child,
                        level: level + 1,
                        hoveredPath: $hoveredPath,
                        selectedFilePath: selectedFilePath,
                        onDirectoryTap: onDirectoryTap,
                        onFileTap: onFileTap
                    )
                }
            }
        }
    }

    private static func labelColor(isSelected: Bool, isHovered: Bool, dimmed: Bool) -> Color {
        if dimmed, !isSelected, !isHovered { return EditorIDEChrome.treeDimmed }
        if isSelected { return EditorIDEChrome.text }
        if isHovered { return EditorIDEChrome.breadcrumbHoverMuted }
        return EditorIDEChrome.muted
    }

    private static func iconColor(isSelected: Bool, isHovered: Bool, dimmed: Bool) -> Color {
        if dimmed, !isSelected, !isHovered { return EditorIDEChrome.treeDimmed }
        if isSelected { return EditorIDEChrome.text.opacity(0.88) }
        if isHovered { return EditorIDEChrome.breadcrumbHoverMuted.opacity(0.95) }
        return EditorIDEChrome.muted.opacity(0.92)
    }

    private static func disclosureTint(isHovered: Bool) -> Color {
        if isHovered { return EditorIDEChrome.muted.opacity(1.05) }
        return EditorIDEChrome.disclosureTint
    }

    @ViewBuilder
    private static func rowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(EditorIDEChrome.fileRowSelectedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(EditorIDEChrome.hairline, lineWidth: 1)
                )
        } else if isHovered {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(EditorIDEChrome.fileRowHoverFill)
        } else {
            Color.clear
        }
    }

    private static func fileIcon(for name: String) -> Image {
        let ext =
            (name as NSString).pathExtension.isEmpty
                ? ""
                : (name as NSString).pathExtension.lowercased()
        switch ext {
        case "tsx", "jsx":
            return Image(systemName: "atom")
        case "ts", "js", "swift":
            return Image(systemName: "curlybraces")
        case "editorconfig", "dockerignore":
            return Image(systemName: "gearshape")
        default:
            return Image(systemName: "doc.text")
        }
    }
}

private struct EditorBreadcrumbItem: Identifiable {
    let id: String
    let title: String
    /// Expand the sidebar through this directory (standardized absolute path).
    let revealDirectory: String
}

/// Small filled triangle: right when collapsed, down when expanded (fixed-width slot).
private struct SidebarDisclosureTriangle: View {
    let expanded: Bool
    var tint: Color = EditorIDEChrome.disclosureTint

    var body: some View {
        Image(systemName: "triangle.fill")
            .font(.system(size: 5.5, weight: .semibold))
            .foregroundStyle(tint)
            .rotationEffect(.degrees(expanded ? 180 : 90))
            .frame(width: EditorIDEChrome.treeIconColumn, height: 11)
            .accessibilityLabel(expanded ? "Folder, expanded" : "Folder, collapsed")
    }
}

struct EditorSurfaceRootView: View {
    @ObservedObject private var model: EditorSurfaceViewModel

    fileprivate init(model: EditorSurfaceViewModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    @State private var expandedPaths: Set<String> = []
    @State private var didSeedRootExpansion = false
    @State private var hoveredPath: String?
    @State private var sidebarScrollTarget: String?
    @State private var hoveredBreadcrumbId: String?
    @State private var hoveredDocumentTabId: UUID?
    @State private var breadcrumbItems: [EditorBreadcrumbItem] = []
    /// Coalesces `rescheduleTreeLoadsForExpandedFolders` when `treeCacheInvalidationEpoch` bumps in quick succession.
    @State private var treeExpandedLoadRescheduleToken: UInt = 0
    @State private var fileSidebarWidth: CGFloat = EditorIDEChrome.fileSidebarDefaultWidth
    @State private var sidebarSearchResults: [FileTreeIndex.SearchResult] = []
    @State private var sidebarSearchTreeRoots: [SidebarSearchTreeNode] = []
    @State private var sidebarSearchTask: Task<Void, Never>?
    @State private var sidebarSearchRequestToken: UInt = 0
    @State private var sidebarSearchInFlight = false
    @State private var sidebarSearchIncludeHiddenEntries = false
    @State private var sidebarSearchIncludeGitIgnoredEntries = false
    @State private var sidebarSearchScopePopoverPresented = false

    private var standardizedRoot: String {
        model.standardizedRootPath
    }

    private var selectedDocument: EditorDocumentBuffer? {
        if let id = model.selectedDocumentId {
            return model.documentTabs.first { $0.id == id }
        }
        return model.documentTabs.first
    }

    private var breadcrumbRefreshToken: String {
        "\(standardizedRoot)|\(selectedDocument?.standardizedPath ?? standardizedRoot)"
    }

    private var editorAlertTitle: String {
        switch model.pendingAlert {
        case .closeDirty: "Save changes?"
        case .saveConflict: "File changed on disk"
        case let .userMessage(title, _): title
        case .none: ""
        }
    }

    private var sidebarSearchQuery: String {
        model.sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSidebarSearchActive: Bool {
        !sidebarSearchQuery.isEmpty
    }

    private var sidebarSearchOptions: FileTreeIndex.SearchOptions {
        FileTreeIndex.SearchOptions(
            includeHiddenEntries: sidebarSearchIncludeHiddenEntries,
            includeGitIgnoredEntries: sidebarSearchIncludeGitIgnoredEntries
        )
    }

    private var hasNonDefaultSidebarSearchScope: Bool {
        sidebarSearchIncludeHiddenEntries
            || sidebarSearchIncludeGitIgnoredEntries
    }

    /// Editor UI is visible but `ensureInitialized` has not run yet (pane not focused in AppKit).
    private var editorIsIdleAwaitingBootstrap: Bool {
        model.editorState == .initializing && !model.hasStartedEditorBootstrap
    }

    /// `retryInitialization` is running after the first focus hand-off.
    private var editorIsBootstrapping: Bool {
        model.editorState == .initializing && model.hasStartedEditorBootstrap
    }

    var body: some View {
        editorChromeStack
            .contentShape(Rectangle())
            .onTapGesture { model.onFocus() }
            .background(EditorContextMenuBridge(onContextMenu: model.onContextMenu))
            .onAppear {
                if !didSeedRootExpansion {
                    expandedPaths.insert(standardizedRoot)
                    didSeedRootExpansion = true
                    scheduleRootTreeLoadIfReady()
                }
                rebuildBreadcrumbItems()
                scheduleSidebarSearchIfNeeded()
            }
            .onChange(of: model.editorState) { _, new in
                guard new == .ready else { return }
                model.seedInitialDocumentsIfNeeded()
                scheduleRootTreeLoadIfReady()
                scheduleSidebarSearchIfNeeded()
            }
            .onChange(of: model.treeCacheInvalidationEpoch) { _, _ in
                treeExpandedLoadRescheduleToken &+= 1
                let token = treeExpandedLoadRescheduleToken
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(48))
                    guard token == treeExpandedLoadRescheduleToken else { return }
                    rescheduleTreeLoadsForExpandedFolders()
                    if isSidebarSearchActive {
                        scheduleSidebarSearchIfNeeded()
                    }
                }
            }
            .onChange(of: breadcrumbRefreshToken) { _, _ in
                rebuildBreadcrumbItems()
            }
            .onChange(of: model.sidebarSearchText) { _, _ in
                scheduleSidebarSearchIfNeeded()
            }
            .onChange(of: sidebarSearchIncludeHiddenEntries) { _, _ in
                scheduleSidebarSearchIfNeeded()
            }
            .onChange(of: sidebarSearchIncludeGitIgnoredEntries) { _, _ in
                scheduleSidebarSearchIfNeeded()
            }
            .onDisappear {
                sidebarSearchTask?.cancel()
                sidebarSearchTask = nil
                sidebarSearchInFlight = false
            }
            .alert(
                Text(editorAlertTitle),
                isPresented: Binding(
                    get: { model.pendingAlert != nil },
                    set: { if !$0 { model.cancelPendingAlert() } }
                ),
                presenting: model.pendingAlert
            ) { alert in
                switch alert {
                case let .closeDirty(id, _):
                    Button("Save") { Task { await model.saveAndCloseTab(id: id) } }
                    Button("Don’t Save", role: .destructive) { model.discardAndCloseTab(id: id) }
                    Button("Cancel", role: .cancel) { model.cancelPendingAlert() }
                case let .saveConflict(id, _, closeAfter):
                    Button("Reload from Disk", role: .destructive) {
                        model.resolveConflictReloadFromDisk(documentId: id, closeAfterResolve: closeAfter)
                    }
                    Button("Overwrite") {
                        Task {
                            await model.resolveConflictOverwrite(documentId: id, closeAfterResolve: closeAfter)
                        }
                    }
                    Button("Cancel", role: .cancel) { model.cancelPendingAlert() }
                case .userMessage:
                    Button("OK", role: .cancel) { model.cancelPendingAlert() }
                }
            } message: { alert in
                switch alert {
                case let .closeDirty(_, title):
                    Text("You have unsaved changes in “\(title)”.")
                case let .saveConflict(_, preview, _):
                    Text("Disk contents:\n\n\(preview)")
                case let .userMessage(_, detail):
                    Text(detail)
                }
            }
    }

    private var editorChromeStack: some View {
        ZStack {
            EditorIDEChrome.canvas
            HStack(alignment: .top, spacing: 0) {
                fileTreePanel
                    .frame(width: fileSidebarWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(EditorIDEChrome.sidebar)
                HorizontalResizeDivider(
                    width: $fileSidebarWidth,
                    minWidth: EditorIDEChrome.fileSidebarMinWidth,
                    maxWidth: EditorIDEChrome.fileSidebarMaxWidth,
                    idleColor: EditorIDEChrome.hairline,
                    hoverColor: EditorIDEChrome.fileSidebarDividerHover
                )
                mainEditorChrome
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Sidebar

    private var fileTreePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarSearchField
                .padding(.horizontal, EditorIDEChrome.sidebarHeaderPaddingH)
                .padding(.top, EditorIDEChrome.sidebarHeaderPaddingTop)
                .padding(.bottom, EditorIDEChrome.sidebarHeaderPaddingBottom)

            if model.editorState == .ready, model.fileTreeIndex != nil {
                if isSidebarSearchActive {
                    sidebarSearchResultsList
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                fileNodeRow(rootNode, level: 0)
                            }
                            .id(model.treeCacheInvalidationEpoch)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, max(4, EditorIDEChrome.treeEdgeInset - 2))
                            .padding(.bottom, 8)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: sidebarScrollTarget) { _, target in
                            guard let target else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                            sidebarScrollTarget = nil
                        }
                    }
                }
            } else {
                sidebarPlaceholderBlock
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarPlaceholderBlock: some View {
        HStack(alignment: .top, spacing: 8) {
            sidebarPlaceholderLeadingGlyph
                .padding(.top, 1)
            Text(sidebarPlaceholderMessage)
                .font(.system(size: 12))
                .foregroundStyle(EditorIDEChrome.muted)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, EditorIDEChrome.sidebarHeaderPaddingH)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var sidebarPlaceholderLeadingGlyph: some View {
        switch model.editorState {
        case .initializing:
            if editorIsBootstrapping {
                ProgressView()
                    .controlSize(.small)
                    .tint(EditorIDEChrome.muted.opacity(0.9))
            } else {
                Image(systemName: "hand.tap")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(EditorIDEChrome.muted.opacity(0.95))
            }
        case .ready, .unavailableRoot, .initFailed:
            EmptyView()
        }
    }

    private var sidebarPlaceholderMessage: String {
        switch model.editorState {
        case .initializing:
            editorIsIdleAwaitingBootstrap
                ? "Focus this editor (click the pane) to load the file tree."
                : "Loading this folder…"
        case .ready:
            "File tree unavailable."
        case .unavailableRoot, .initFailed:
            "Open a valid folder to browse files."
        }
    }

    private var sidebarSearchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorIDEChrome.muted.opacity(0.95))
            TextField("Search files", text: $model.sidebarSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(EditorIDEChrome.text.opacity(0.92))
                .tint(EditorIDEChrome.text.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
            sidebarSearchScopeMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: EditorIDEChrome.searchCornerRadius, style: .continuous)
                .fill(EditorIDEChrome.searchFieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: EditorIDEChrome.searchCornerRadius, style: .continuous)
                        .stroke(EditorIDEChrome.searchFieldStroke, lineWidth: 1)
                )
        )
        .contentShape(Rectangle().inset(by: -4))
        .onHover { isHovering in
            guard isHovering else { return }
            prefetchSidebarSearchContext()
        }
    }

    private var sidebarSearchScopeMenu: some View {
        Button {
            sidebarSearchScopePopoverPresented.toggle()
        } label: {
            HStack(spacing: 2) {
                Image(
                    systemName: hasNonDefaultSidebarSearchScope
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    hasNonDefaultSidebarSearchScope
                        ? EditorIDEChrome.text.opacity(0.92)
                        : EditorIDEChrome.muted.opacity(0.9)
                )
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(EditorIDEChrome.muted.opacity(0.9))
            }
            .frame(height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Search scope")
        .popover(
            isPresented: $sidebarSearchScopePopoverPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            VStack(alignment: .leading, spacing: 2) {
                sidebarSearchScopeToggleRow(
                    title: "Hidden files",
                    isOn: $sidebarSearchIncludeHiddenEntries
                )
                sidebarSearchScopeToggleRow(
                    title: "Gitignored files",
                    isOn: $sidebarSearchIncludeGitIgnoredEntries
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 172, alignment: .leading)
            .onExitCommand {
                sidebarSearchScopePopoverPresented = false
            }
        }
    }

    private func sidebarSearchScopeToggleRow(
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        isOn.wrappedValue ? Color.accentColor : EditorIDEChrome.muted.opacity(0.9)
                    )
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EditorIDEChrome.text.opacity(0.96))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebarSearchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if sidebarSearchInFlight, sidebarSearchResults.isEmpty {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(EditorIDEChrome.muted.opacity(0.9))
                        Text("One sec while we index files…")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(EditorIDEChrome.muted.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.leading, EditorIDEChrome.treeEdgeInset + 2)
                    .padding(.trailing, EditorIDEChrome.treeEdgeInset)
                    .padding(.top, 4)
                } else if sidebarSearchResults.isEmpty {
                    Text("No files matching “\(sidebarSearchQuery)”")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(EditorIDEChrome.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, EditorIDEChrome.treeEdgeInset + 2)
                        .padding(.trailing, EditorIDEChrome.treeEdgeInset)
                        .padding(.top, 4)
                } else {
                    ForEach(sidebarSearchTreeRoots) { node in
                        SidebarSearchTreeRowView(
                            node: node,
                            level: 0,
                            hoveredPath: $hoveredPath,
                            selectedFilePath: selectedDocument?.standardizedPath,
                            onDirectoryTap: { n in
                                model.onFocus()
                                revealDirectoryChain(
                                    endingAt: n.path,
                                    includeHiddenEntries: sidebarSearchIncludeHiddenEntries
                                )
                                model.sidebarSearchText = ""
                                Task { @MainActor in
                                    sidebarScrollTarget = n.path
                                }
                            },
                            onFileTap: { n in
                                model.onFocus()
                                selectOrOpenFileTab(path: n.path, title: n.name)
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, max(4, EditorIDEChrome.treeEdgeInset - 2))
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Main column

    private var mainEditorChrome: some View {
        VStack(spacing: 0) {
            switch model.editorState {
            case .initializing:
                loadingMainColumn
            case .ready:
                readyMainColumn
            case .unavailableRoot:
                failureSection(
                    title: "Root folder unavailable",
                    detail: "The pinned root no longer exists or is not accessible."
                )
                .padding(20)
            case .initFailed:
                failureSection(
                    title: "Editor initialization failed",
                    detail: "Failed to initialize the editor for this root."
                )
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EditorIDEChrome.canvas)
    }

    private var loadingMainColumn: some View {
        Group {
            if editorIsIdleAwaitingBootstrap {
                editorIdleMainColumn
            } else {
                HStack(alignment: .center, spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(EditorIDEChrome.muted.opacity(0.9))
                    Text("Opening this editor…")
                        .font(.system(size: 12))
                        .foregroundStyle(EditorIDEChrome.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, EditorIDEChrome.sidebarHeaderPaddingH)
        .padding(.top, EditorIDEChrome.sidebarHeaderPaddingTop + 5)
    }

    private var editorIdleMainColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Editor idle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EditorIDEChrome.text.opacity(0.9))
            } icon: {
                Image(systemName: "hand.tap")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(EditorIDEChrome.muted.opacity(0.95))
            }
            Text(
                "This pane does not load your folder or open files until it is focused. "
                    + "Click anywhere here, or select this pane, to start the editor."
            )
            .font(.system(size: 12))
            .foregroundStyle(EditorIDEChrome.muted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var readyMainColumn: some View {
        VStack(spacing: 0) {
            tabStrip
            Rectangle()
                .fill(EditorIDEChrome.hairline)
                .frame(height: 1)
            breadcrumbStrip
            Rectangle()
                .fill(EditorIDEChrome.hairline)
                .frame(height: 1)
            editorBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(model.documentTabs) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            HStack(spacing: 12) {
                Button(action: {
                    Task { await model.saveSelectedDocument() }
                }) {
                    Image(systemName: "arrow.up.document")
                }
                .buttonStyle(.plain)
                .help("Save (⌘S)")
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Image(systemName: "rectangle.split.2x1")
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(EditorIDEChrome.muted)
            .padding(.trailing, 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(EditorIDEChrome.tabInactive.opacity(0.35))
    }

    private func tabChip(_ tab: EditorDocumentBuffer) -> some View {
        let isSelected = tab.id == (model.selectedDocumentId ?? model.documentTabs.first?.id)
        let isHovered = hoveredDocumentTabId == tab.id
        let labelColor = tabChipLabelColor(isSelected: isSelected, isHovered: isHovered)
        let closeColor =
            isSelected
                ? EditorIDEChrome.muted.opacity(0.95)
                : (isHovered ? EditorIDEChrome.breadcrumbHoverMuted : EditorIDEChrome.muted)
        return HStack(spacing: 5) {
            fileIcon(for: tab.title)
                .font(.system(size: 10))
                .foregroundStyle(labelColor)
            Text(tab.title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular, design: .monospaced))
                .foregroundStyle(labelColor)
                .lineLimit(1)
            if tab.isDirty {
                Text("●")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(EditorIDEChrome.muted.opacity(0.9))
                    .accessibilityLabel("Unsaved changes")
            }
            Button {
                model.requestCloseTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(closeColor)
                    .padding(2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tabChipBackground(isSelected: isSelected, isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(tabChipStroke(isSelected: isSelected, isHovered: isHovered), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onHover { inside in
            if inside {
                hoveredDocumentTabId = tab.id
            } else if hoveredDocumentTabId == tab.id {
                hoveredDocumentTabId = nil
            }
        }
        .onTapGesture {
            model.selectDocumentTab(id: tab.id)
        }
    }

    private func tabChipLabelColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return EditorIDEChrome.text }
        if isHovered { return EditorIDEChrome.breadcrumbHoverMuted }
        return EditorIDEChrome.muted
    }

    private func tabChipBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return EditorIDEChrome.tabActive }
        if isHovered { return EditorIDEChrome.tabHoverFill }
        return Color.clear
    }

    private func tabChipStroke(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return EditorIDEChrome.hairline.opacity(1.05) }
        if isHovered { return EditorIDEChrome.hairline.opacity(0.95) }
        return Color.clear
    }

    private func fileIcon(for filename: String) -> Image {
        let lower = filename.lowercased()
        if lower == ".gitignore" || lower == ".prettierignore" || lower.hasSuffix("ignore") {
            return Image(systemName: "gearshape")
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "tsx", "jsx":
            return Image(systemName: "atom")
        case "ts", "js", "swift":
            return Image(systemName: "curlybraces")
        case "editorconfig", "dockerignore":
            return Image(systemName: "gearshape")
        default:
            return Image(systemName: "doc.text")
        }
    }

    private var breadcrumbStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(breadcrumbItems.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EditorIDEChrome.breadcrumbChevron)
                            .padding(.horizontal, 6)
                            .fixedSize()
                    }
                    breadcrumbSegment(item: item, index: index, total: breadcrumbItems.count)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorIDEChrome.canvas)
    }

    private func breadcrumbSegment(item: EditorBreadcrumbItem, index: Int, total: Int) -> some View {
        let isLast = index == total - 1
        let hovered = hoveredBreadcrumbId == item.id
        let textColor = breadcrumbLabelColor(isLast: isLast, hovered: hovered)
        return Button {
            model.onFocus()
            revealDirectoryChain(
                endingAt: item.revealDirectory,
                includeHiddenEntries: directoryPathIncludesHiddenSegment(item.revealDirectory)
            )
            sidebarScrollTarget = item.revealDirectory
        } label: {
            Text(item.title)
                .font(.system(size: 11, weight: isLast ? .medium : .regular, design: .monospaced))
                .foregroundStyle(textColor)
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hoveredBreadcrumbId = item.id
            } else if hoveredBreadcrumbId == item.id {
                hoveredBreadcrumbId = nil
            }
        }
    }

    private func breadcrumbLabelColor(isLast: Bool, hovered: Bool) -> Color {
        if isLast {
            return hovered ? Color.white.opacity(0.98) : EditorIDEChrome.text
        }
        return hovered ? EditorIDEChrome.breadcrumbHoverMuted : EditorIDEChrome.muted
    }

    private var editorBody: some View {
        Group {
            if let id = model.selectedDocumentId, model.documentStore.buffer(id: id) != nil {
                EditorCodeTextView(
                    text: model.workingTextBinding(for: id),
                    isEditable: true,
                    onSave: { Task { await model.saveSelectedDocument() } }
                )
                .id(id)
                .clipShape(Rectangle())
            } else {
                emptyEditorPlaceholder
            }
        }
        .background(EditorIDEChrome.canvas)
    }

    private var emptyEditorPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No file open")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorIDEChrome.text)
            Text("Choose a file in the sidebar to start editing.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(EditorIDEChrome.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }

    // MARK: File tree rows

    private func fileNodeRow(_ node: FileTreeIndex.Node, level: Int) -> AnyView {
        if node.isDirectory {
            let isExpanded = expandedPaths.contains(node.path)
            let isHovered = hoveredPath == node.path
            return AnyView(
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        if isExpanded {
                            expandedPaths.remove(node.path)
                        } else {
                            expandedPaths.insert(node.path)
                            model.fileTreeIndex?.scheduleLoadChildren(
                                for: node.path,
                                priority: .userInitiated,
                                shouldPrefetchChildren: true
                            )
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 6) {
                            SidebarDisclosureTriangle(
                                expanded: isExpanded,
                                tint: treeDisclosureTint(isHovered: isHovered)
                            )
                            Text(node.name)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(
                                    treeRowLabelColor(isSelected: false, isHovered: isHovered, dimmed: false)
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(
                            .leading,
                            EditorIDEChrome.treeEdgeInset + CGFloat(level) * EditorIDEChrome.treeIndentStep
                        )
                        .padding(.vertical, 4)
                        .padding(.trailing, EditorIDEChrome.treeEdgeInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sidebarRowBackground(isSelected: false, isHovered: isHovered))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(node.path)
                    .onHover { isHovering in
                        if isHovering {
                            hoveredPath = node.path
                        } else if hoveredPath == node.path {
                            hoveredPath = nil
                        }
                    }

                    if isExpanded {
                        ForEach(childrenForNode(node)) { child in
                            fileNodeRow(child, level: level + 1)
                        }
                    }
                }
            )
        } else {
            let nodePath = URL(fileURLWithPath: node.path).standardizedFileURL.path
            let isSelected =
                selectedDocument.map {
                    $0.standardizedPath == nodePath
                } ?? false
            let isHovered = hoveredPath == node.path
            let isDotfile = node.name.hasPrefix(".")
            return AnyView(
                Button {
                    selectOrOpenFileTab(path: node.path, title: node.name)
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        fileIcon(for: node.name)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(
                                treeRowIconColor(isSelected: isSelected, isHovered: isHovered, dimmed: isDotfile)
                            )
                            .frame(width: EditorIDEChrome.treeIconColumn, alignment: .center)
                        Text(node.name)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(
                                treeRowLabelColor(isSelected: isSelected, isHovered: isHovered, dimmed: isDotfile)
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(
                        .leading,
                        EditorIDEChrome.treeEdgeInset + CGFloat(level) * EditorIDEChrome.treeIndentStep
                    )
                    .padding(.vertical, 4)
                    .padding(.trailing, EditorIDEChrome.treeEdgeInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(sidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(node.path)
                .onHover { isHovering in
                    if isHovering {
                        hoveredPath = node.path
                    } else if hoveredPath == node.path {
                        hoveredPath = nil
                    }
                }
            )
        }
    }

    /// Sidebar tree labels: breadcrumb-like muted idle, brighten on hover; selected file = full text. Same weight always.
    private func treeRowLabelColor(isSelected: Bool, isHovered: Bool, dimmed: Bool) -> Color {
        if dimmed, !isSelected, !isHovered { return EditorIDEChrome.treeDimmed }
        if isSelected { return EditorIDEChrome.text }
        if isHovered { return EditorIDEChrome.breadcrumbHoverMuted }
        return EditorIDEChrome.muted
    }

    private func treeRowIconColor(isSelected: Bool, isHovered: Bool, dimmed: Bool) -> Color {
        if dimmed, !isSelected, !isHovered { return EditorIDEChrome.treeDimmed }
        if isSelected { return EditorIDEChrome.text.opacity(0.88) }
        if isHovered { return EditorIDEChrome.breadcrumbHoverMuted.opacity(0.95) }
        return EditorIDEChrome.muted.opacity(0.92)
    }

    private func treeDisclosureTint(isHovered: Bool) -> Color {
        if isHovered { return EditorIDEChrome.muted.opacity(1.05) }
        return EditorIDEChrome.disclosureTint
    }

    @ViewBuilder
    private func sidebarRowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(EditorIDEChrome.fileRowSelectedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(EditorIDEChrome.hairline, lineWidth: 1)
                )
        } else if isHovered {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(EditorIDEChrome.fileRowHoverFill)
        } else {
            Color.clear
        }
    }

    private var rootNode: FileTreeIndex.Node {
        let name = URL(fileURLWithPath: standardizedRoot).lastPathComponent
        return FileTreeIndex.Node(
            path: standardizedRoot,
            name: name.isEmpty ? standardizedRoot : name,
            isDirectory: true,
            hasUnloadedChildren: true
        )
    }

    private func childrenForNode(_ node: FileTreeIndex.Node) -> [FileTreeIndex.Node] {
        guard node.path == standardizedRoot || node.path.hasPrefix(standardizedRoot + "/") else {
            return []
        }
        return model.fileTreeIndex?.cachedChildren(for: node.path) ?? []
    }

    private func scheduleRootTreeLoadIfReady() {
        guard model.editorState == .ready else { return }
        model.fileTreeIndex?.prewarmSearchCatalog(priority: .utility)
        model.fileTreeIndex?.scheduleLoadChildren(
            for: standardizedRoot,
            priority: .userInitiated,
            shouldPrefetchChildren: true
        )
    }

    private func prefetchSidebarSearchContext() {
        guard let index = model.fileTreeIndex else { return }
        index.prewarmSearchCatalog(priority: .utility)
        index.scheduleLoadChildren(
            for: standardizedRoot,
            priority: .utility,
            shouldPrefetchChildren: true
        )
    }

    private func rescheduleTreeLoadsForExpandedFolders() {
        guard let index = model.fileTreeIndex else { return }
        for path in expandedPaths {
            index.scheduleLoadChildren(for: path, priority: .utility, shouldPrefetchChildren: false)
        }
    }

    private func scheduleSidebarSearchIfNeeded() {
        sidebarSearchTask?.cancel()
        sidebarSearchTask = nil

        guard model.editorState == .ready else {
            sidebarSearchInFlight = false
            sidebarSearchResults = []
            sidebarSearchTreeRoots = []
            return
        }
        guard let index = model.fileTreeIndex else {
            sidebarSearchInFlight = false
            sidebarSearchResults = []
            sidebarSearchTreeRoots = []
            return
        }
        let query = sidebarSearchQuery
        guard !query.isEmpty else {
            sidebarSearchInFlight = false
            sidebarSearchResults = []
            sidebarSearchTreeRoots = []
            return
        }
        let options = sidebarSearchOptions
        let debounceMilliseconds = sidebarSearchDebounceMilliseconds(for: query)

        sidebarSearchInFlight = true
        sidebarSearchRequestToken &+= 1
        let requestToken = sidebarSearchRequestToken
        sidebarSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(debounceMilliseconds))
            guard !Task.isCancelled else { return }
            guard requestToken == sidebarSearchRequestToken else { return }

            let results = await index.search(matching: query, limit: 600, options: options)
            guard !Task.isCancelled else { return }
            guard requestToken == sidebarSearchRequestToken else { return }

            sidebarSearchResults = results
            sidebarSearchTreeRoots = Self.buildSidebarSearchTree(
                results: results,
                rootPath: standardizedRoot
            )
            sidebarSearchInFlight = false
        }
    }

    private func sidebarSearchDebounceMilliseconds(for query: String) -> Int {
        // Short queries get a slightly longer pause to avoid churn; longer queries coalesce cheaply.
        query.count >= 3 ? 100 : 180
    }

    private static func buildSidebarSearchTree(
        results: [FileTreeIndex.SearchResult],
        rootPath: String
    ) -> [SidebarSearchTreeNode] {
        guard !results.isEmpty else { return [] }

        final class BuilderNode {
            let path: String
            let name: String
            var isDirectory: Bool
            var isSearchMatch: Bool
            var childPaths: Set<String> = []

            init(path: String, name: String, isDirectory: Bool, isSearchMatch: Bool) {
                self.path = path
                self.name = name
                self.isDirectory = isDirectory
                self.isSearchMatch = isSearchMatch
            }
        }

        let standardizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        var nodes: [String: BuilderNode] = [:]

        @discardableResult
        func ensureNode(
            at path: String,
            preferredName: String?,
            isDirectory: Bool,
            isSearchMatch: Bool
        ) -> BuilderNode {
            if let existing = nodes[path] {
                existing.isDirectory = existing.isDirectory || isDirectory
                existing.isSearchMatch = existing.isSearchMatch || isSearchMatch
                return existing
            }
            let fallbackName = URL(fileURLWithPath: path).lastPathComponent
            let node = BuilderNode(
                path: path,
                name: preferredName ?? (fallbackName.isEmpty ? path : fallbackName),
                isDirectory: isDirectory,
                isSearchMatch: isSearchMatch
            )
            nodes[path] = node
            return node
        }

        _ = ensureNode(
            at: standardizedRoot,
            preferredName: URL(fileURLWithPath: standardizedRoot).lastPathComponent,
            isDirectory: true,
            isSearchMatch: false
        )

        for result in results {
            let resultPath = URL(fileURLWithPath: result.path).standardizedFileURL.path
            guard resultPath == standardizedRoot || resultPath.hasPrefix(standardizedRoot + "/") else {
                continue
            }

            _ = ensureNode(
                at: resultPath,
                preferredName: result.name,
                isDirectory: result.isDirectory,
                isSearchMatch: true
            )

            var cursor = resultPath
            while cursor != standardizedRoot {
                let parent = (cursor as NSString).deletingLastPathComponent
                guard parent == standardizedRoot || parent.hasPrefix(standardizedRoot + "/") else {
                    break
                }
                let parentNode = ensureNode(
                    at: parent,
                    preferredName: URL(fileURLWithPath: parent).lastPathComponent,
                    isDirectory: true,
                    isSearchMatch: false
                )
                parentNode.childPaths.insert(cursor)
                cursor = parent
            }
        }

        guard let rootNode = nodes[standardizedRoot] else { return [] }

        func sortPaths(_ lhs: String, _ rhs: String) -> Bool {
            guard let lhsNode = nodes[lhs], let rhsNode = nodes[rhs] else { return lhs < rhs }
            if lhsNode.isDirectory != rhsNode.isDirectory {
                return lhsNode.isDirectory && !rhsNode.isDirectory
            }
            let byName = lhsNode.name.localizedCaseInsensitiveCompare(rhsNode.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhsNode.path < rhsNode.path
        }

        func materialize(_ path: String) -> SidebarSearchTreeNode {
            guard let builder = nodes[path] else {
                return SidebarSearchTreeNode(
                    path: path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    isDirectory: false,
                    isSearchMatch: true,
                    children: []
                )
            }
            let children = builder.childPaths
                .sorted(by: sortPaths)
                .map(materialize)
            return SidebarSearchTreeNode(
                path: builder.path,
                name: builder.name,
                isDirectory: builder.isDirectory,
                isSearchMatch: builder.isSearchMatch,
                children: children
            )
        }

        return rootNode.childPaths
            .sorted(by: sortPaths)
            .map(materialize)
    }

    private func rebuildBreadcrumbItems() {
        let path = selectedDocument?.standardizedPath ?? standardizedRoot
        breadcrumbItems = computeBreadcrumbItems(forFilePath: path)
    }

    // MARK: Tabs & breadcrumbs behavior

    private func selectOrOpenFileTab(path: String, title: String) {
        model.openFile(path: path, title: title)
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let parentDirectory = (standardized as NSString).deletingLastPathComponent
        revealDirectoryChain(
            endingAt: parentDirectory,
            includeHiddenEntries: directoryPathIncludesHiddenSegment(parentDirectory)
        )
        sidebarScrollTarget = parentDirectory
    }

    /// Builds breadcrumb segments for `rawPath` using filesystem metadata; call from `onChange` / `onAppear`, not SwiftUI `body`.
    private func computeBreadcrumbItems(forFilePath rawPath: String) -> [EditorBreadcrumbItem] {
        let root = standardizedRoot
        let file = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let rootName = URL(fileURLWithPath: root).lastPathComponent

        guard file == root || file.hasPrefix(root + "/") else {
            return [
                EditorBreadcrumbItem(id: root, title: rootName, revealDirectory: root),
            ]
        }

        var rel = String(file.dropFirst(root.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty {
            return [
                EditorBreadcrumbItem(id: root, title: rootName, revealDirectory: root),
            ]
        }

        let parts = rel.split(separator: "/").map(String.init)
        var acc = root
        var items: [EditorBreadcrumbItem] = []
        var directoryMemo: [String: Bool] = [:]
        func onDiskIsDirectory(_ path: String) -> Bool {
            if let cached = directoryMemo[path] { return cached }
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            let value = exists && isDir.boolValue
            directoryMemo[path] = value
            return value
        }

        for (i, part) in parts.enumerated() {
            acc = (acc as NSString).appendingPathComponent(part)
            let isLast = i == parts.count - 1
            let onDiskAsDir = onDiskIsDirectory(acc)
            if isLast, !onDiskAsDir {
                let parent = (acc as NSString).deletingLastPathComponent
                items.append(EditorBreadcrumbItem(id: acc, title: part, revealDirectory: parent))
            } else {
                items.append(EditorBreadcrumbItem(id: acc, title: part, revealDirectory: acc))
            }
        }
        return items
    }

    private func isDirectoryPath(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Expands every ancestor from workspace root through `directoryPath` and loads directory listings.
    private func revealDirectoryChain(
        endingAt directoryPath: String, includeHiddenEntries: Bool = false
    ) {
        let root = standardizedRoot
        var target = URL(fileURLWithPath: directoryPath, isDirectory: true).standardizedFileURL.path
        if !isDirectoryPath(target) {
            target = (target as NSString).deletingLastPathComponent
        }
        guard !target.isEmpty, target == root || target.hasPrefix(root + "/") else { return }

        var chain: [String] = []
        var cursor = target
        while true {
            chain.append(cursor)
            if cursor == root { break }
            let parent = (cursor as NSString).deletingLastPathComponent
            if parent == cursor || !(parent == root || parent.hasPrefix(root + "/")) { break }
            cursor = parent
        }

        for path in chain.reversed() {
            expandedPaths.insert(path)
            model.fileTreeIndex?.scheduleLoadChildren(
                for: path,
                priority: .userInitiated,
                shouldPrefetchChildren: true,
                includeHiddenEntries: includeHiddenEntries
            )
        }
    }

    /// `true` when `directoryPath` (under the workspace root) contains a `.hidden` path segment, so directory scans must not skip hidden entries.
    private func directoryPathIncludesHiddenSegment(_ directoryPath: String) -> Bool {
        let root = standardizedRoot
        let standardized =
            URL(fileURLWithPath: directoryPath, isDirectory: true).standardizedFileURL.path
        guard standardized == root || standardized.hasPrefix(root + "/") else { return false }
        var rel = String(standardized.dropFirst(root.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { return false }
        return rel.split(separator: "/").contains { component in
            component.hasPrefix(".") && component != "." && component != ".."
        }
    }

    private func failureSection(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EditorIDEChrome.text)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(EditorIDEChrome.muted)
            HStack(spacing: 10) {
                Button("Retry", action: model.onRetry)
                    .buttonStyle(.borderedProminent)
                Button("Open Terminal Here", action: model.onOpenTerminalHere)
                    .buttonStyle(.bordered)
                Button("Copy Diagnostics") {
                    let value =
                        "editor_root=\(model.standardizedRootPath)\neditor_state=\(String(describing: model.editorState))"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                .buttonStyle(.bordered)
                Button("Show Diagnostics", action: model.onShowDiagnostics)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
    }
}

@MainActor
private extension EditorSurfaceViewModel {
    func syncTabsFromStore() {
        documentTabs = documentStore.buffersInTabOrder
    }

    func seedInitialDocumentsIfNeeded() {
        guard !didSeedInitialDocuments else { return }
        didSeedInitialDocuments = true
        let fm = FileManager.default
        let nsRoot = standardizedRootPath as NSString
        for fileName in [".gitignore", ".prettierignore"] {
            let fullPath = nsRoot.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: fullPath) else { continue }
            _ = try? documentStore.openDocument(at: URL(fileURLWithPath: fullPath))
        }
        syncTabsFromStore()
        selectedDocumentId = documentTabs.first?.id
    }

    func openFile(path: String, title: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        do {
            let id = try documentStore.openDocument(at: URL(fileURLWithPath: standardized))
            syncTabsFromStore()
            selectedDocumentId = id
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            pendingAlert = .userMessage(title: "Could not open \(title)", detail: msg)
        }
    }

    func selectDocumentTab(id: UUID) {
        selectedDocumentId = id
    }

    func workingTextBinding(for documentId: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.documentStore.buffer(id: documentId)?.workingText ?? ""
            },
            set: { [weak self] newValue in
                self?.updateDocumentText(id: documentId, text: newValue)
            }
        )
    }

    func updateDocumentText(id: UUID, text: String) {
        documentStore.updateWorkingText(id: id, text: text)
        syncTabsFromStore()
    }

    func saveSelectedDocument() async {
        guard let id = selectedDocumentId else { return }
        await saveDocument(id: id, conflictClosesTab: false)
    }

    func saveDocument(id: UUID, conflictClosesTab: Bool) async {
        do {
            _ = try await documentStore.saveDocument(id: id)
            syncTabsFromStore()
        } catch let save as EditorDocumentSaveError {
            switch save {
            case let .conflict(c):
                pendingAlert = .saveConflict(
                    documentId: id,
                    diskPreview: saveConflictDiskPreview(c.diskText),
                    closeAfterResolve: conflictClosesTab
                )
            default:
                pendingAlert = .userMessage(title: "Save failed", detail: save.localizedDescription)
            }
        } catch {
            pendingAlert = .userMessage(title: "Save failed", detail: error.localizedDescription)
        }
    }

    func resolveConflictReloadFromDisk(documentId: UUID, closeAfterResolve: Bool) {
        do {
            try documentStore.reloadFromDisk(id: documentId)
            syncTabsFromStore()
            if closeAfterResolve {
                closeTabDiscardingBuffer(id: documentId)
            }
            pendingAlert = nil
        } catch {
            pendingAlert = .userMessage(title: "Reload failed", detail: error.localizedDescription)
        }
    }

    func resolveConflictOverwrite(documentId: UUID, closeAfterResolve: Bool) async {
        do {
            _ = try await documentStore.saveDocumentForcedOverwrite(id: documentId)
            syncTabsFromStore()
            if closeAfterResolve {
                closeTabDiscardingBuffer(id: documentId)
            }
            pendingAlert = nil
        } catch {
            pendingAlert = .userMessage(title: "Overwrite failed", detail: error.localizedDescription)
        }
    }

    func requestCloseTab(id: UUID) {
        guard let buffer = documentStore.buffer(id: id) else { return }
        if buffer.isDirty {
            pendingAlert = .closeDirty(documentId: id, title: buffer.title)
            return
        }
        closeTabDiscardingBuffer(id: id)
    }

    func saveAndCloseTab(id: UUID) async {
        do {
            _ = try await documentStore.saveDocument(id: id)
            syncTabsFromStore()
            pendingAlert = nil
            closeTabDiscardingBuffer(id: id)
        } catch let save as EditorDocumentSaveError {
            switch save {
            case let .conflict(c):
                pendingAlert = .saveConflict(
                    documentId: id,
                    diskPreview: saveConflictDiskPreview(c.diskText),
                    closeAfterResolve: true
                )
            default:
                pendingAlert = .userMessage(title: "Save failed", detail: save.localizedDescription)
            }
        } catch {
            pendingAlert = .userMessage(title: "Save failed", detail: error.localizedDescription)
        }
    }

    func discardAndCloseTab(id: UUID) {
        closeTabDiscardingBuffer(id: id)
        pendingAlert = nil
    }

    func cancelPendingAlert() {
        pendingAlert = nil
    }

    private func closeTabDiscardingBuffer(id: UUID) {
        documentStore.closeBuffer(id: id)
        syncTabsFromStore()
        if selectedDocumentId == id {
            selectedDocumentId = documentTabs.first?.id
        }
    }

    private func saveConflictDiskPreview(_ diskText: String) -> String {
        diskText.count > 1200 ? String(diskText.prefix(1200)) + "…" : diskText
    }
}

private struct EditorContextMenuBridge: NSViewRepresentable {
    let onContextMenu: (NSEvent) -> Void

    func makeNSView(context _: Context) -> EditorContextMenuNSView {
        let view = EditorContextMenuNSView()
        view.onContextMenu = onContextMenu
        return view
    }

    func updateNSView(_ nsView: EditorContextMenuNSView, context _: Context) {
        nsView.onContextMenu = onContextMenu
    }
}

private final class EditorContextMenuNSView: NSView {
    var onContextMenu: ((NSEvent) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onContextMenu?(event)
        return nil
    }
}
