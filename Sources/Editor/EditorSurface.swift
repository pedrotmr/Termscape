import AppKit
import Foundation
import SwiftUI

/// Drives `EditorSurfaceRootView` without replacing `NSHostingView.rootView`, so SwiftUI `@State`
/// (tabs, expansion, hover) stays stable across editor state and file-tree refreshes.
@MainActor
private final class EditorSurfaceViewModel: ObservableObject {
  let standardizedRootPath: String
  @Published var editorState: EditorSurface.State = .initializing
  @Published var fileTreeIndex: FileTreeIndex?
  /// Bumped only when the shared index clears its cache (watcher / invalidation). Drives `LazyVStack` `.id`
  /// and rescheduling loads for expanded folders — not per-directory async loads.
  @Published var treeCacheInvalidationEpoch: UInt = 0
  /// Bumped after each successful `scheduleLoadChildren` merge so SwiftUI refreshes rows without remounting the tree.
  @Published var fileTreeContentRevision: UInt = 0
  @Published var sidebarSearchText: String = ""

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
      self.onShowDiagnostics?(self.diagnosticsText)
    }
  }

  private func setPaneState(_ newState: State) {
    viewModel.editorState = newState
    viewModel.fileTreeIndex = fileTreeIndex
  }

  private func syncFileTreeToViewModel() {
    viewModel.fileTreeIndex = fileTreeIndex
  }

  func ensureInitialized() {
    guard !didAttemptInitialization else { return }
    didAttemptInitialization = true
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
  /// Sidebar sits one step above the main canvas so the file column reads as its own surface.
  static let sidebar = Color(red: 0.095, green: 0.096, blue: 0.102)
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
  static let lineNumber = Color.white.opacity(0.28)
  static let lineHighlight = Color.white.opacity(0.04)
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

private struct EditorDocumentTab: Identifiable, Equatable {
  let id: UUID
  var title: String
  var fullPath: String
}

private struct SidebarSearchTreeNode: Identifiable, Hashable {
  let path: String
  let name: String
  let isDirectory: Bool
  let isSearchMatch: Bool
  let children: [SidebarSearchTreeNode]

  var id: String { path }
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
  @State private var documentTabs: [EditorDocumentTab] = []
  @State private var selectedTabId: UUID?
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

  private var selectedTab: EditorDocumentTab? {
    guard let selectedTabId else { return documentTabs.first }
    return documentTabs.first { $0.id == selectedTabId }
  }

  private var breadcrumbRefreshToken: String {
    "\(standardizedRoot)|\(selectedTab?.fullPath ?? standardizedRoot)"
  }

  private var sidebarSearchQuery: String {
    model.sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isSidebarSearchActive: Bool {
    !sidebarSearchQuery.isEmpty
  }

  private var sidebarSearchOptions: FileTreeIndex.SearchOptions {
    let includeGitignoredScope = sidebarSearchIncludeGitIgnoredEntries
    return FileTreeIndex.SearchOptions(
      includeHiddenEntries: sidebarSearchIncludeHiddenEntries,
      includeNodeModules: includeGitignoredScope,
      includeGitIgnoredEntries: includeGitignoredScope
    )
  }

  private var hasNonDefaultSidebarSearchScope: Bool {
    sidebarSearchIncludeHiddenEntries
      || sidebarSearchIncludeGitIgnoredEntries
  }

  var body: some View {
    ZStack {
      EditorIDEChrome.canvas
      HStack(spacing: 0) {
        fileTreePanel
          .frame(width: fileSidebarWidth)
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
      if documentTabs.isEmpty {
        documentTabs = Self.defaultDocumentTabs(rootPath: standardizedRoot)
        selectedTabId = documentTabs.first?.id
      }
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
  }

  // MARK: Sidebar

  @ViewBuilder
  private var fileTreePanel: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        sidebarSearchField
      }
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
        Text(sidebarPlaceholderMessage)
          .font(.system(size: 12))
          .foregroundStyle(EditorIDEChrome.muted)
          .lineSpacing(2)
          .padding(.horizontal, EditorIDEChrome.treeEdgeInset + 2)
          .padding(.top, 4)
      }
    }
  }

  private var sidebarPlaceholderMessage: String {
    switch model.editorState {
    case .initializing:
      return "Loading this folder…"
    case .ready:
      return "File tree unavailable."
    case .unavailableRoot, .initFailed:
      return "Open a valid folder to browse files."
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

  @ViewBuilder
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
            sidebarSearchTreeRow(node, level: 0)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, max(4, EditorIDEChrome.treeEdgeInset - 2))
      .padding(.bottom, 8)
    }
    .scrollIndicators(.hidden)
  }

  private func sidebarSearchTreeRow(_ node: SidebarSearchTreeNode, level: Int) -> AnyView {
    let path = URL(fileURLWithPath: node.path).standardizedFileURL.path
    let isSelectedFile =
      selectedTab.map {
        URL(fileURLWithPath: $0.fullPath).standardizedFileURL.path == path
      } ?? false
    let isHovered = hoveredPath == node.path
    let isDimmed = node.isDirectory && !node.isSearchMatch
    let labelColor = treeRowLabelColor(
      isSelected: isSelectedFile,
      isHovered: isHovered,
      dimmed: isDimmed
    )
    let iconColor = treeRowIconColor(
      isSelected: isSelectedFile,
      isHovered: isHovered,
      dimmed: isDimmed
    )
    let disclosureTint: Color =
      (isDimmed && !isHovered)
      ? EditorIDEChrome.treeDimmed
      : treeDisclosureTint(isHovered: isHovered)
    return AnyView(
      VStack(alignment: .leading, spacing: 2) {
        Button {
          model.onFocus()
          if node.isDirectory {
            revealDirectoryChain(endingAt: node.path)
            model.sidebarSearchText = ""
            Task { @MainActor in
              sidebarScrollTarget = node.path
            }
          } else {
            selectOrOpenFileTab(path: node.path, title: node.name)
          }
        } label: {
          HStack(alignment: .center, spacing: 6) {
            if node.isDirectory {
              SidebarDisclosureTriangle(
                expanded: !node.children.isEmpty,
                tint: disclosureTint
              )
            } else {
              fileIcon(for: node.name)
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
          .background(sidebarRowBackground(isSelected: isSelectedFile, isHovered: isHovered))
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
            sidebarSearchTreeRow(child, level: level + 1)
          }
        }
      })
  }

  // MARK: Main column

  @ViewBuilder
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
    VStack(alignment: .leading, spacing: 10) {
      Label("Preparing this editor pane…", systemImage: "hourglass")
        .font(.system(size: 12))
        .foregroundStyle(EditorIDEChrome.muted)
        .padding(20)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
      editorBodyStub
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var tabStrip: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 3) {
          ForEach(documentTabs) { tab in
            tabChip(tab)
          }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
      }
      HStack(spacing: 12) {
        Image(systemName: "arrow.up.document")
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

  private func tabChip(_ tab: EditorDocumentTab) -> some View {
    let isSelected = tab.id == (selectedTabId ?? documentTabs.first?.id)
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
      Button {
        closeTab(tab.id)
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(closeColor)
          .padding(2)
      }
      .buttonStyle(.plain)
      .opacity(documentTabs.count > 1 ? 1 : 0.35)
      .disabled(documentTabs.count <= 1)
      .allowsHitTesting(documentTabs.count > 1)
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
      selectedTabId = tab.id
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
      revealDirectoryChain(endingAt: item.revealDirectory)
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

  private var editorBodyStub: some View {
    HStack(alignment: .top, spacing: 0) {
      VStack(alignment: .trailing, spacing: 0) {
        ForEach(1..<8, id: \.self) { line in
          Text("\(line)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(EditorIDEChrome.lineNumber)
            .frame(width: 40, alignment: .trailing)
            .padding(.vertical, 1)
            .background(line == 1 ? EditorIDEChrome.lineHighlight : Color.clear)
        }
        Spacer(minLength: 0)
      }
      .padding(.top, 10)
      .frame(width: 44)
      .background(EditorIDEChrome.canvas.opacity(0.55))

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("// \(selectedTab?.title ?? "Untitled")")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 0.48))
            .padding(.top, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EditorIDEChrome.lineHighlight)
          Text("Select a file in the sidebar or a breadcrumb segment to expand folders here.")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(EditorIDEChrome.muted)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
      }
    }
    .background(EditorIDEChrome.canvas)
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
        })
    } else {
      let nodePath = URL(fileURLWithPath: node.path).standardizedFileURL.path
      let isSelected =
        selectedTab.map {
          URL(fileURLWithPath: $0.fullPath).standardizedFileURL.path == nodePath
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
        })
    }
  }

  /// Sidebar tree labels: breadcrumb-like muted idle, brighten on hover; selected file = full text. Same weight always.
  private func treeRowLabelColor(isSelected: Bool, isHovered: Bool, dimmed: Bool) -> Color {
    if dimmed && !isSelected && !isHovered { return EditorIDEChrome.treeDimmed }
    if isSelected { return EditorIDEChrome.text }
    if isHovered { return EditorIDEChrome.breadcrumbHoverMuted }
    return EditorIDEChrome.muted
  }

  private func treeRowIconColor(isSelected: Bool, isHovered: Bool, dimmed: Bool) -> Color {
    if dimmed && !isSelected && !isHovered { return EditorIDEChrome.treeDimmed }
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
    // Keep only a tiny coalescing window so typing feels immediate.
    query.count >= 3 ? 6 : 14
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
    let path = selectedTab?.fullPath ?? standardizedRoot
    breadcrumbItems = computeBreadcrumbItems(forFilePath: path)
  }

  // MARK: Tabs & breadcrumbs behavior

  private static func defaultDocumentTabs(rootPath: String) -> [EditorDocumentTab] {
    let fm = FileManager.default
    let nsRoot = rootPath as NSString
    var tabs: [EditorDocumentTab] = []
    for (fileName, title) in [(".gitignore", ".gitignore"), (".prettierignore", ".prettierignore")]
    {
      let fullPath = nsRoot.appendingPathComponent(fileName)
      guard fm.fileExists(atPath: fullPath) else { continue }
      tabs.append(EditorDocumentTab(id: UUID(), title: title, fullPath: fullPath))
    }
    return tabs
  }

  private func closeTab(_ id: UUID) {
    guard documentTabs.count > 1 else { return }
    documentTabs.removeAll { $0.id == id }
    if selectedTabId == id {
      selectedTabId = documentTabs.first?.id
    }
  }

  private func selectOrOpenFileTab(path: String, title: String) {
    let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
    if let existing = documentTabs.firstIndex(where: {
      URL(fileURLWithPath: $0.fullPath).standardizedFileURL.path == standardized
    }) {
      selectedTabId = documentTabs[existing].id
    } else {
      let tab = EditorDocumentTab(id: UUID(), title: title, fullPath: standardized)
      documentTabs.append(tab)
      selectedTabId = tab.id
    }
    revealDirectoryChain(endingAt: (standardized as NSString).deletingLastPathComponent)
    sidebarScrollTarget = (standardized as NSString).deletingLastPathComponent
  }

  /// Builds breadcrumb segments for `rawPath` using filesystem metadata; call from `onChange` / `onAppear`, not SwiftUI `body`.
  private func computeBreadcrumbItems(forFilePath rawPath: String) -> [EditorBreadcrumbItem] {
    let root = standardizedRoot
    let file = URL(fileURLWithPath: rawPath).standardizedFileURL.path
    let rootName = URL(fileURLWithPath: root).lastPathComponent

    guard file == root || file.hasPrefix(root + "/") else {
      return [
        EditorBreadcrumbItem(id: root, title: rootName, revealDirectory: root)
      ]
    }

    var rel = String(file.dropFirst(root.count))
    if rel.hasPrefix("/") { rel.removeFirst() }
    if rel.isEmpty {
      return [
        EditorBreadcrumbItem(id: root, title: rootName, revealDirectory: root)
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
  private func revealDirectoryChain(endingAt directoryPath: String) {
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
        shouldPrefetchChildren: true
      )
    }
  }

  @ViewBuilder
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
