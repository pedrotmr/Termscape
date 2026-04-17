import AppKit
import Foundation
import SwiftUI

/// Holds sidebar search text outside `EditorSurfaceRootView` so it survives `render()` refresh.
private final class SidebarSearchDraftHolder {
  var text: String = ""
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
  let rootPath: String
  let hostedView: NSHostingView<EditorSurfaceRootView>

  var onFocused: (() -> Void)?
  var onContextMenu: ((NSEvent) -> Void)?
  var onRequestRetry: (() -> Void)?
  var onOpenTerminalHere: (() -> Void)?
  var onShowDiagnostics: ((String) -> Void)?

  private var didAttemptInitialization = false
  private var fileTreeIndex: FileTreeIndex?
  private let sidebarSearchDraftHolder = SidebarSearchDraftHolder()
  private var state: State = .initializing {
    didSet { render() }
  }

  private var sidebarSearchBinding: Binding<String> {
    Binding(
      get: { self.sidebarSearchDraftHolder.text },
      set: { self.sidebarSearchDraftHolder.text = $0 }
    )
  }

  init(workspaceId: UUID, rootPath: String) {
    id = UUID()
    self.workspaceId = workspaceId
    self.rootPath = rootPath
    let sidebarSearchDraft = sidebarSearchDraftHolder
    hostedView = NSHostingView(
      rootView: EditorSurfaceRootView(
        rootPath: rootPath,
        state: .initializing,
        sidebarSearchText: Binding(
          get: { sidebarSearchDraft.text },
          set: { sidebarSearchDraft.text = $0 }
        ),
        onFocus: {},
        onContextMenu: { _ in },
        onRetry: {},
        onOpenTerminalHere: {},
        onShowDiagnostics: {},
        fileTreeIndex: nil
      )
    )
    render()
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
    state = .initializing

    let url = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
    var isDir = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
      isDir.boolValue
    else {
      state = .unavailableRoot
      return
    }

    do {
      _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
      if fileTreeIndex == nil {
        let index = FileTreeIndexPool.retainIndex(for: rootPath)
        index.onTreeDidInvalidate = { [weak self] in
          self?.render()
        }
        fileTreeIndex = index
      }
      state = .ready
    } catch {
      state = .initFailed
    }
  }

  func teardown() {
    if fileTreeIndex != nil {
      FileTreeIndexPool.releaseIndex(for: rootPath)
      fileTreeIndex = nil
    }
  }

  var diagnosticsText: String {
    "editor_root=\(rootPath)\neditor_state=\(String(describing: state))"
  }

  private func render() {
    hostedView.rootView = EditorSurfaceRootView(
      rootPath: rootPath,
      state: state,
      sidebarSearchText: sidebarSearchBinding,
      onFocus: { [weak self] in self?.onFocused?() },
      onContextMenu: { [weak self] event in self?.onContextMenu?(event) },
      onRetry: { [weak self] in
        self?.retryInitialization()
        self?.onRequestRetry?()
      },
      onOpenTerminalHere: { [weak self] in self?.onOpenTerminalHere?() },
      onShowDiagnostics: { [weak self] in
        guard let self else { return }
        self.onShowDiagnostics?(self.diagnosticsText)
      },
      fileTreeIndex: fileTreeIndex
    )
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
}

private struct EditorDocumentTab: Identifiable, Equatable {
  let id: UUID
  var title: String
  var fullPath: String
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
  let rootPath: String
  let state: EditorSurface.State
  @Binding var sidebarSearchText: String
  let onFocus: () -> Void
  let onContextMenu: (NSEvent) -> Void
  let onRetry: () -> Void
  let onOpenTerminalHere: () -> Void
  let onShowDiagnostics: () -> Void
  let fileTreeIndex: FileTreeIndex?

  @State private var expandedPaths: Set<String> = []
  @State private var didSeedRootExpansion = false
  @State private var hoveredPath: String?
  @State private var documentTabs: [EditorDocumentTab] = []
  @State private var selectedTabId: UUID?
  @State private var sidebarScrollTarget: String?
  @State private var hoveredBreadcrumbId: String?
  @State private var hoveredDocumentTabId: UUID?

  private var standardizedRoot: String {
    URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
  }

  private var selectedTab: EditorDocumentTab? {
    guard let selectedTabId else { return documentTabs.first }
    return documentTabs.first { $0.id == selectedTabId }
  }

  var body: some View {
    ZStack {
      EditorIDEChrome.canvas
      HStack(spacing: 0) {
        fileTreePanel
          .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
          .background(EditorIDEChrome.sidebar)
        Rectangle()
          .fill(EditorIDEChrome.hairline)
          .frame(width: 1)
        mainEditorChrome
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { onFocus() }
    .background(EditorContextMenuBridge(onContextMenu: onContextMenu))
    .onAppear {
      guard !didSeedRootExpansion else { return }
      expandedPaths.insert(standardizedRoot)
      didSeedRootExpansion = true
    }
    .onChange(of: state) { _, new in
      guard new == .ready, documentTabs.isEmpty else { return }
      documentTabs = Self.defaultDocumentTabs(rootPath: standardizedRoot)
      selectedTabId = documentTabs.first?.id
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
        
      if state == .ready, fileTreeIndex != nil {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
              fileNodeRow(rootNode, level: 0)
            }
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
    switch state {
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
      TextField("Search files", text: $sidebarSearchText)
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(EditorIDEChrome.text.opacity(0.92))
        .tint(EditorIDEChrome.text.opacity(0.75))
      Spacer(minLength: 0)
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
  }

  // MARK: Main column

  @ViewBuilder
  private var mainEditorChrome: some View {
    VStack(spacing: 0) {
      switch state {
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
      if inside { hoveredDocumentTabId = tab.id }
      else if hoveredDocumentTabId == tab.id { hoveredDocumentTabId = nil }
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
    let path = selectedTab?.fullPath ?? standardizedRoot
    let items = breadcrumbItems(forFilePath: path)
    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          if index > 0 {
            Image(systemName: "chevron.right")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(EditorIDEChrome.breadcrumbChevron)
              .padding(.horizontal, 6)
              .fixedSize()
          }
          breadcrumbSegment(item: item, index: index, total: items.count)
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
      onFocus()
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
      if inside { hoveredBreadcrumbId = item.id }
      else if hoveredBreadcrumbId == item.id { hoveredBreadcrumbId = nil }
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
        ForEach(1 ..< 8, id: \.self) { line in
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
              _ = fileTreeIndex?.children(for: node.path)
            }
          } label: {
            HStack(alignment: .center, spacing: 6) {
              SidebarDisclosureTriangle(
                expanded: isExpanded,
                tint: treeDisclosureTint(isHovered: isHovered)
              )
              Text(node.name)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(treeRowLabelColor(isSelected: false, isHovered: isHovered, dimmed: false))
            }
            .padding(.leading, EditorIDEChrome.treeEdgeInset + CGFloat(level) * EditorIDEChrome.treeIndentStep)
            .padding(.vertical, 4)
            .padding(.trailing, EditorIDEChrome.treeEdgeInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sidebarRowBackground(isSelected: false, isHovered: isHovered))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .id(node.path)
          .onHover { isHovering in
            if isHovering { hoveredPath = node.path }
            else if hoveredPath == node.path { hoveredPath = nil }
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
              .foregroundStyle(treeRowIconColor(isSelected: isSelected, isHovered: isHovered, dimmed: isDotfile))
              .frame(width: EditorIDEChrome.treeIconColumn, alignment: .center)
            Text(node.name)
              .font(.system(size: 11, weight: .regular, design: .monospaced))
              .foregroundStyle(treeRowLabelColor(isSelected: isSelected, isHovered: isHovered, dimmed: isDotfile))
          }
          .padding(.leading, EditorIDEChrome.treeEdgeInset + CGFloat(level) * EditorIDEChrome.treeIndentStep)
          .padding(.vertical, 4)
          .padding(.trailing, EditorIDEChrome.treeEdgeInset)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(sidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(node.path)
        .onHover { isHovering in
          if isHovering { hoveredPath = node.path }
          else if hoveredPath == node.path { hoveredPath = nil }
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
    return fileTreeIndex?.children(for: node.path) ?? []
  }

  // MARK: Tabs & breadcrumbs behavior

  private static func defaultDocumentTabs(rootPath: String) -> [EditorDocumentTab] {
    let nsRoot = rootPath as NSString
    let demo = EditorDocumentTab(
      id: UUID(),
      title: "Root.tsx",
      fullPath: nsRoot.appendingPathComponent("apps/axle_pay_web/assets/js/Root.tsx")
    )
    let gitignore = EditorDocumentTab(
      id: UUID(),
      title: ".gitignore",
      fullPath: nsRoot.appendingPathComponent(".gitignore")
    )
    let prettier = EditorDocumentTab(
      id: UUID(),
      title: ".prettierignore",
      fullPath: nsRoot.appendingPathComponent(".prettierignore")
    )
    return [demo, gitignore, prettier]
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

  private func breadcrumbItems(forFilePath rawPath: String) -> [EditorBreadcrumbItem] {
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
    for (i, part) in parts.enumerated() {
      acc = (acc as NSString).appendingPathComponent(part)
      let isLast = i == parts.count - 1
      let onDiskAsDir = isDirectoryPath(acc)
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
    guard target.hasPrefix(root), !target.isEmpty else { return }

    var chain: [String] = []
    var cursor = target
    while true {
      chain.append(cursor)
      if cursor == root { break }
      let parent = (cursor as NSString).deletingLastPathComponent
      if parent == cursor || parent.count < root.count { break }
      cursor = parent
    }

    for path in chain.reversed() {
      expandedPaths.insert(path)
      _ = fileTreeIndex?.children(for: path)
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
        Button("Retry", action: onRetry)
          .buttonStyle(.borderedProminent)
        Button("Open Terminal Here", action: onOpenTerminalHere)
          .buttonStyle(.bordered)
        Button("Copy Diagnostics") {
          let value = "editor_root=\(rootPath)\neditor_state=\(String(describing: state))"
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(value, forType: .string)
        }
        .buttonStyle(.bordered)
        Button("Show Diagnostics", action: onShowDiagnostics)
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
