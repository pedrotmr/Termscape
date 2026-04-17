import Bonsplit
import Foundation
import SwiftUI

enum WorkspacePaneContentKind: String, Codable {
  case terminal
  case browser
  case editor

  var defaultTitle: String {
    switch self {
    case .terminal:
      return "Terminal"
    case .browser:
      return "Browser"
    case .editor:
      return "Editor"
    }
  }

  var defaultIcon: String {
    switch self {
    case .terminal:
      return "terminal"
    case .browser:
      return "globe"
    case .editor:
      return "chevron.left.forwardslash.chevron.right"
    }
  }
}

@MainActor
final class WorkspaceTab: ObservableObject, Identifiable {
  static let splitInsertionMinimumPaneWidth: CGFloat = 600
  static let interactiveMinimumPaneWidth: CGFloat = 200
  static let interactiveMinimumPaneHeight: CGFloat = 200
  static let minimumViewportWidthForThreePaneEqualization: CGFloat = 1000
  let id: UUID
  @Published var title: String
  @Published var isPinned: Bool = false
  let workspaceId: UUID

  /// BonsplitController manages the split tree for this tab.
  /// Each tab has an independent layout.
  let bonsplitController: BonsplitController

  /// Terminal surfaces keyed by Bonsplit TabID's UUID.
  var surfaces: [UUID: TerminalSurface] = [:]

  /// Browser surfaces keyed by Bonsplit TabID's UUID.
  var browserSurfaces: [UUID: BrowserSurface] = [:]
  /// Editor surfaces keyed by Bonsplit TabID's UUID.
  var editorSurfaces: [UUID: EditorSurface] = [:]

  /// Text to send to the first surface once it attaches (e.g. a clone command).
  var pendingInputOnceAttached: String?

  /// Absolute canvas width in points. Preserves pane sizing when the window size changes.
  var canvasWidth: CGFloat = 0

  private let workspaceURL: URL?
  private var lastThreePaneStretchUsesThirds: Bool?
  private var paneContentKindByTabId: [UUID: WorkspacePaneContentKind] = [:]
  private var pendingWorkingDirectoryByPaneId: [UUID: String] = [:]
  private var pendingWorkingDirectoryByTabId: [UUID: String] = [:]
  private var pendingBrowserURLByPaneId: [UUID: URL] = [:]
  private var pendingBrowserURLByTabId: [UUID: URL] = [:]
  private var pendingEditorRootByPaneId: [UUID: String] = [:]
  private var pendingEditorRootByTabId: [UUID: String] = [:]
  private var pendingBrowserAddressBarFocusTabIds: Set<UUID> = []

  init(
    title: String = "Terminal",
    workspaceURL: URL?,
    workspaceId: UUID,
    initialPaneKind: WorkspacePaneContentKind = .terminal
  ) {
    id = UUID()
    self.title = title
    self.workspaceURL = workspaceURL
    self.workspaceId = workspaceId

    var config = BonsplitConfiguration()
    config.allowSplits = true
    config.autoCloseEmptyPanes = true
    config.appearance.minimumPaneWidth = Self.interactiveMinimumPaneWidth
    config.appearance.minimumPaneHeight = Self.interactiveMinimumPaneHeight
    config.appearance.enableAnimations = false
    bonsplitController = BonsplitController(configuration: config)

    // Wire delegate so canvas redraws on layout and focus changes (splits, resizes, closes, pane focus)
    // The delegate is held weakly by BonsplitController, so no retain cycle.
    bonsplitController.delegate = self

    configureInitialPaneKind(initialPaneKind)
  }

  /// Restore tab identity, canvas width, Bonsplit tree, and per-pane cwd from persistence (surfaces are created lazily).
  init(restoring snapshot: WorkspaceTabSnapshot, workspaceURL: URL?, workspaceId: UUID) {
    id = snapshot.id
    title = snapshot.title
    isPinned = snapshot.isPinned
    self.workspaceURL = workspaceURL
    self.workspaceId = workspaceId
    canvasWidth = snapshot.canvasWidthPts > 0 ? CGFloat(snapshot.canvasWidthPts) : 0

    var config = BonsplitConfiguration()
    config.allowSplits = true
    config.autoCloseEmptyPanes = true
    config.appearance.minimumPaneWidth = Self.interactiveMinimumPaneWidth
    config.appearance.minimumPaneHeight = Self.interactiveMinimumPaneHeight
    config.appearance.enableAnimations = false
    bonsplitController = BonsplitController(configuration: config)
    let focus = snapshot.focusedPaneId.flatMap(UUID.init(uuidString:)).map { PaneID(id: $0) }
    bonsplitController.replaceRootTree(with: snapshot.tree, focusedPaneId: focus)
    bonsplitController.delegate = self

    let allTabIDs = Set(Self.collectTabUUIDs(from: snapshot.tree))
    if let kindMap = snapshot.tabKindByTabId, !kindMap.isEmpty {
      for (idStr, rawKind) in kindMap {
        guard allTabIDs.contains(idStr),
          let uuid = UUID(uuidString: idStr),
          let kind = WorkspacePaneContentKind(rawValue: rawKind)
        else { continue }
        paneContentKindByTabId[uuid] = kind
        bonsplitController.updateTab(
          TabID(uuid: uuid),
          icon: .some(kind.defaultIcon),
          kind: .some(kind.rawValue)
        )
      }
    } else {
      // Legacy saves had no per-pane kind metadata; default all panes to terminal.
      for idStr in allTabIDs {
        guard let uuid = UUID(uuidString: idStr) else { continue }
        paneContentKindByTabId[uuid] = .terminal
        bonsplitController.updateTab(
          TabID(uuid: uuid),
          icon: .some(WorkspacePaneContentKind.terminal.defaultIcon),
          kind: .some(WorkspacePaneContentKind.terminal.rawValue)
        )
      }
    }

    if let map = snapshot.workingDirectoryByTerminalTabId {
      for (idStr, rawPath) in map {
        guard let uuid = UUID(uuidString: idStr),
          let normalized = TerminalSurface.normalizeWorkingDirectoryPath(rawPath)
        else { continue }
        pendingWorkingDirectoryByTabId[uuid] = normalized
      }
    }

    if let map = snapshot.browserURLByTabId {
      for (idStr, rawURL) in map {
        guard let uuid = UUID(uuidString: idStr),
          let url = URL(string: rawURL)
        else { continue }
        pendingBrowserURLByTabId[uuid] = url
      }
    }

    if let map = snapshot.editorRootPathByTabId {
      for (idStr, rawPath) in map {
        guard let uuid = UUID(uuidString: idStr),
          let normalized = TerminalSurface.normalizeWorkingDirectoryPath(rawPath)
        else { continue }
        pendingEditorRootByTabId[uuid] = normalized
      }
    }
  }

  func createSurface(for tabId: TabID) -> TerminalSurface {
    let defaultWorkingDirectory = TerminalSurface.normalizeWorkingDirectoryPath(workspaceURL?.path)
    let splitWorkingDirectory = pendingWorkingDirectoryByTabId.removeValue(forKey: tabId.uuid)
    let surface = TerminalSurface(
      workspaceId: workspaceId,
      workingDirectory: splitWorkingDirectory ?? defaultWorkingDirectory
    )
    surfaces[tabId.uuid] = surface
    return surface
  }

  func createBrowserSurface(for tabId: TabID) -> BrowserSurface {
    let initialURL = pendingBrowserURLByTabId.removeValue(forKey: tabId.uuid)
    let surface = BrowserSurface(workspaceId: workspaceId, initialURL: initialURL)
    browserSurfaces[tabId.uuid] = surface
    return surface
  }

  func createEditorSurface(for tabId: TabID) -> EditorSurface {
    let resolvedRoot =
      pendingEditorRootByTabId.removeValue(forKey: tabId.uuid)
      ?? resolvedFallbackEditorRootPath()
    let surface = EditorSurface(workspaceId: workspaceId, rootPath: resolvedRoot)
    editorSurfaces[tabId.uuid] = surface
    return surface
  }

  func queueWorkingDirectoryForNextTab(_ workingDirectory: String?, inPane paneId: PaneID) {
    guard let normalized = TerminalSurface.normalizeWorkingDirectoryPath(workingDirectory) else {
      return
    }
    pendingWorkingDirectoryByPaneId[paneId.id] = normalized
  }

  func queueBrowserURLForNextTab(_ url: URL?, inPane paneId: PaneID) {
    guard let url else { return }
    pendingBrowserURLByPaneId[paneId.id] = url
  }

  func queueEditorRootForNextTab(_ rootPath: String?, inPane paneId: PaneID) {
    guard let normalized = TerminalSurface.normalizeWorkingDirectoryPath(rootPath) else {
      return
    }
    pendingEditorRootByPaneId[paneId.id] = normalized
  }

  /// Overrides the pinned root for an editor tab before its surface is created (e.g. new editor workspace tab).
  func setPendingEditorRootIfNoSurface(_ rootPath: String, for tabId: TabID) {
    guard editorSurfaces[tabId.uuid] == nil else { return }
    guard let normalized = TerminalSurface.normalizeWorkingDirectoryPath(rootPath) else { return }
    pendingEditorRootByTabId[tabId.uuid] = normalized
  }

  func browserURL(for tabUUID: UUID) -> URL? {
    browserSurfaces[tabUUID]?.currentURL ?? pendingBrowserURLByTabId[tabUUID]
  }

  func editorRootPath(for tabUUID: UUID) -> String? {
    editorSurfaces[tabUUID]?.rootPath ?? pendingEditorRootByTabId[tabUUID]
  }

  func detachTerminalSurface(for tabUUID: UUID) -> TerminalSurface? {
    surfaces.removeValue(forKey: tabUUID)
  }

  func detachBrowserSurface(for tabUUID: UUID) -> BrowserSurface? {
    browserSurfaces.removeValue(forKey: tabUUID)
  }

  func detachEditorSurface(for tabUUID: UUID) -> EditorSurface? {
    editorSurfaces.removeValue(forKey: tabUUID)
  }

  func attachTerminalSurface(_ surface: TerminalSurface, to tabUUID: UUID) {
    surfaces[tabUUID] = surface
    paneContentKindByTabId[tabUUID] = .terminal
    bonsplitController.updateTab(
      TabID(uuid: tabUUID),
      icon: .some(WorkspacePaneContentKind.terminal.defaultIcon),
      kind: .some(WorkspacePaneContentKind.terminal.rawValue)
    )
  }

  func attachBrowserSurface(_ surface: BrowserSurface, to tabUUID: UUID) {
    browserSurfaces[tabUUID] = surface
    paneContentKindByTabId[tabUUID] = .browser
    pendingBrowserURLByTabId[tabUUID] = surface.currentURL
    bonsplitController.updateTab(
      TabID(uuid: tabUUID),
      icon: .some(WorkspacePaneContentKind.browser.defaultIcon),
      kind: .some(WorkspacePaneContentKind.browser.rawValue)
    )
  }

  func attachEditorSurface(_ surface: EditorSurface, to tabUUID: UUID) {
    editorSurfaces[tabUUID] = surface
    pendingEditorRootByTabId[tabUUID] = surface.rootPath
    paneContentKindByTabId[tabUUID] = .editor
    bonsplitController.updateTab(
      TabID(uuid: tabUUID),
      icon: .some(WorkspacePaneContentKind.editor.defaultIcon),
      kind: .some(WorkspacePaneContentKind.editor.rawValue)
    )
  }

  func consumePendingBrowserAddressBarFocus(for tabUUID: UUID) -> Bool {
    pendingBrowserAddressBarFocusTabIds.remove(tabUUID) != nil
  }

  func paneContentKind(for tabUUID: UUID, fallbackPaneId: String? = nil) -> WorkspacePaneContentKind
  {
    if let kind = paneContentKindByTabId[tabUUID] {
      return kind
    }

    let resolvedKind: WorkspacePaneContentKind
    if let fallbackPaneId,
      let paneUUID = UUID(uuidString: fallbackPaneId),
      let selected = bonsplitController.selectedTab(inPane: PaneID(id: paneUUID)),
      selected.id.uuid == tabUUID,
      let kindRaw = selected.kind,
      let parsed = WorkspacePaneContentKind(rawValue: kindRaw)
    {
      resolvedKind = parsed
    } else {
      resolvedKind = .terminal
    }

    paneContentKindByTabId[tabUUID] = resolvedKind
    return resolvedKind
  }

  func setPaneContentKind(_ kind: WorkspacePaneContentKind, for tabId: TabID) {
    paneContentKindByTabId[tabId.uuid] = kind
    bonsplitController.updateTab(
      tabId,
      icon: .some(kind.defaultIcon),
      kind: .some(kind.rawValue)
    )
  }

  func removeSurface(for tabId: TabID) {
    surfaces[tabId.uuid]?.teardown()
    surfaces.removeValue(forKey: tabId.uuid)
  }

  func removeBrowserSurface(for tabId: TabID) {
    browserSurfaces[tabId.uuid]?.teardown()
    browserSurfaces.removeValue(forKey: tabId.uuid)
  }

  func removeEditorSurface(for tabId: TabID) {
    editorSurfaces[tabId.uuid]?.teardown()
    editorSurfaces.removeValue(forKey: tabId.uuid)
  }

  func removePaneContent(for tabId: TabID) {
    removeSurface(for: tabId)
    removeBrowserSurface(for: tabId)
    removeEditorSurface(for: tabId)
    paneContentKindByTabId.removeValue(forKey: tabId.uuid)
    pendingWorkingDirectoryByTabId.removeValue(forKey: tabId.uuid)
    pendingBrowserURLByTabId.removeValue(forKey: tabId.uuid)
    pendingEditorRootByTabId.removeValue(forKey: tabId.uuid)
  }

  func invalidateThreePaneStretchCache() {
    lastThreePaneStretchUsesThirds = nil
  }

  /// In stretch mode with three panes, rebalance horizontal splits to equal thirds.
  func rebalanceThreePaneHorizontalWidthsForStretchMode(viewportWidth: CGFloat? = nil) {
    guard canvasWidth <= 0 else {
      lastThreePaneStretchUsesThirds = nil
      return
    }

    let tree = bonsplitController.treeSnapshot()
    let paneIDs = HorizontalPaneSizingEngine.paneIDs(in: tree)
    guard paneIDs.count == 3 else {
      lastThreePaneStretchUsesThirds = nil
      return
    }

    let effectiveViewportWidth = max(viewportWidth ?? estimatedViewportWidthForStretchMode(), 1)
    let shouldUseEqualThirds =
      effectiveViewportWidth >= Self.minimumViewportWidthForThreePaneEqualization
    guard lastThreePaneStretchUsesThirds != shouldUseEqualThirds else { return }

    if shouldUseEqualThirds {
      var desiredPaneWidths: [String: CGFloat] = [:]
      desiredPaneWidths.reserveCapacity(3)
      for paneID in paneIDs {
        desiredPaneWidths[paneID] = 1
      }

      let plan = HorizontalPaneSizingEngine.buildPlan(
        tree: tree,
        desiredPaneWidths: desiredPaneWidths,
        fallbackPaneWidth: Self.interactiveMinimumPaneWidth
      )

      for (splitId, position) in plan.splitPositions {
        _ = bonsplitController.setDividerPosition(position, forSplit: splitId)
      }
    } else {
      for splitId in HorizontalPaneSizingEngine.splitIDs(in: tree, orientation: "horizontal") {
        _ = bonsplitController.setDividerPosition(0.5, forSplit: splitId)
      }
    }
    canvasWidth = 0
    lastThreePaneStretchUsesThirds = shouldUseEqualThirds
  }

  func teardown() {
    for surface in surfaces.values {
      surface.teardown()
    }
    surfaces.removeAll()
    for surface in browserSurfaces.values {
      surface.teardown()
    }
    browserSurfaces.removeAll()
    for surface in editorSurfaces.values {
      surface.teardown()
    }
    editorSurfaces.removeAll()
  }

  private func configureInitialPaneKind(_ kind: WorkspacePaneContentKind) {
    let snapshot = bonsplitController.layoutSnapshot()
    guard let firstPane = snapshot.panes.first,
      let selectedTabId = firstPane.selectedTabId,
      let tabUUID = UUID(uuidString: selectedTabId)
    else {
      return
    }

    let tabId = TabID(uuid: tabUUID)
    paneContentKindByTabId[tabUUID] = kind
    switch kind {
    case .terminal:
      bonsplitController.updateTab(
        tabId,
        icon: .some(kind.defaultIcon),
        kind: .some(kind.rawValue)
      )
    case .browser:
      bonsplitController.updateTab(
        tabId,
        title: kind.defaultTitle,
        icon: .some(kind.defaultIcon),
        kind: .some(kind.rawValue)
      )
      pendingBrowserAddressBarFocusTabIds.insert(tabUUID)
    case .editor:
      let root = resolvedFallbackEditorRootPath()
      pendingEditorRootByTabId[tabUUID] = root
      bonsplitController.updateTab(
        tabId,
        title: kind.defaultTitle,
        icon: .some(kind.defaultIcon),
        kind: .some(kind.rawValue)
      )
    }
  }

  func resolvedFallbackEditorRootPath() -> String {
    EditorRootContract.resolvePinnedRoot(
      focusedKind: nil,
      terminalWorkingDirectory: nil,
      editorRootPath: nil,
      workspaceRootPath: workspaceURL?.path,
      fallbackHomePath: FileManager.default.homeDirectoryForCurrentUser.path,
      normalizePath: TerminalSurface.normalizeWorkingDirectoryPath
    )
  }

  func resolveEditorRootFromFocusedContext(
    targetPaneId: PaneID?,
    snapshot: LayoutSnapshot
  ) -> String {
    guard let targetPaneId,
      let sourcePane = snapshot.panes.first(where: { $0.paneId == targetPaneId.id.uuidString }),
      let selectedTabId = sourcePane.selectedTabId,
      let tabUUID = UUID(uuidString: selectedTabId)
    else {
      return resolvedFallbackEditorRootPath()
    }

    let focusedKind = paneContentKind(for: tabUUID, fallbackPaneId: sourcePane.paneId)
    return EditorRootContract.resolvePinnedRoot(
      focusedKind: focusedKind,
      terminalWorkingDirectory: surfaces[tabUUID]?.splitWorkingDirectory,
      editorRootPath: editorRootPath(for: tabUUID),
      workspaceRootPath: workspaceURL?.path,
      fallbackHomePath: FileManager.default.homeDirectoryForCurrentUser.path,
      normalizePath: TerminalSurface.normalizeWorkingDirectoryPath
    )
  }

  func replaceEditorPaneWithTerminal(tabUUID: UUID, preferredRootPath: String?) {
    removeEditorSurface(for: TabID(uuid: tabUUID))
    if let normalized = TerminalSurface.normalizeWorkingDirectoryPath(preferredRootPath) {
      pendingWorkingDirectoryByTabId[tabUUID] = normalized
    }
    setPaneContentKind(.terminal, for: TabID(uuid: tabUUID))
    NotificationCenter.default.post(name: .workspacePersistenceNeeded, object: nil)
  }

  func focusedPaneContentKind(snapshot: LayoutSnapshot) -> WorkspacePaneContentKind {
    guard let focusedPaneId = snapshot.focusedPaneId,
      let pane = snapshot.panes.first(where: { $0.paneId == focusedPaneId }),
      let selectedTabId = pane.selectedTabId,
      let tabUUID = UUID(uuidString: selectedTabId)
    else {
      return .terminal
    }
    return paneContentKind(for: tabUUID, fallbackPaneId: pane.paneId)
  }

  private static func collectTabUUIDs(from node: ExternalTreeNode) -> [String] {
    switch node {
    case .pane(let pane):
      return pane.tabs.map(\.id)
    case .split(let split):
      return collectTabUUIDs(from: split.first) + collectTabUUIDs(from: split.second)
    }
  }
}

// MARK: - BonsplitDelegate

@MainActor
extension WorkspaceTab: BonsplitDelegate {
  /// Post the notification that CanvasHostingView listens for, triggering a canvas relayout.
  func notifyLayoutChanged() {
    NotificationCenter.default.post(name: .bonsplitLayoutDidChange, object: bonsplitController)
    NotificationCenter.default.post(name: .workspacePersistenceNeeded, object: nil)
  }

  /// Canvas needs to redraw whenever a tab is created (new pane tab → needs a surface)
  func splitTabBar(
    _: BonsplitController, didCreateTab tab: Bonsplit.Tab, inPane pane: PaneID
  ) {
    let kind = WorkspacePaneContentKind(rawValue: tab.kind ?? "") ?? .terminal
    paneContentKindByTabId[tab.id.uuid] = kind

    switch kind {
    case .terminal:
      if let pendingWorkingDirectory = pendingWorkingDirectoryByPaneId.removeValue(forKey: pane.id)
      {
        pendingWorkingDirectoryByTabId[tab.id.uuid] = pendingWorkingDirectory
      }
    case .browser:
      if let pendingURL = pendingBrowserURLByPaneId.removeValue(forKey: pane.id) {
        pendingBrowserURLByTabId[tab.id.uuid] = pendingURL
      }
      pendingBrowserAddressBarFocusTabIds.insert(tab.id.uuid)
    case .editor:
      if let pendingRoot = pendingEditorRootByPaneId.removeValue(forKey: pane.id) {
        pendingEditorRootByTabId[tab.id.uuid] = pendingRoot
      } else {
        pendingEditorRootByTabId[tab.id.uuid] = resolvedFallbackEditorRootPath()
      }
    }
    notifyLayoutChanged()
  }

  func splitTabBar(
    _: BonsplitController, didSplitPane _: PaneID, newPane _: PaneID,
    orientation _: SplitOrientation
  ) {
    // Note: new pane is empty (no tabs yet). WorkspaceContainerView calls createTab
    // immediately after, which fires didCreateTab → notifyLayoutChanged.
    // We don't notify here to avoid a redundant update with an empty pane.
  }

  /// Teardown the TerminalSurface for the closed tab so Ghostty frees its resources.
  func splitTabBar(
    _: BonsplitController, didCloseTab tabId: TabID, fromPane _: PaneID
  ) {
    removePaneContent(for: tabId)
  }

  func splitTabBar(_: BonsplitController, didClosePane _: PaneID) {
    normalizeLayoutForSmallPaneCount()
    notifyLayoutChanged()
  }

  func splitTabBar(_: BonsplitController, didFocusPane _: PaneID) {
    notifyLayoutChanged()
  }

  func splitTabBar(_: BonsplitController, didChangeGeometry _: LayoutSnapshot) {
    notifyLayoutChanged()
  }

  /// When the tree collapses to three panes or fewer, switch from strict-width mode
  /// back to viewport-filling behavior with small-pane normalization.
  private func normalizeLayoutForSmallPaneCount() {
    let paneCount = bonsplitController.allPaneIds.count
    guard paneCount <= 3 else {
      lastThreePaneStretchUsesThirds = nil
      return
    }

    // Let CanvasDocumentView derive width from the current viewport.
    canvasWidth = 0

    if paneCount == 3 {
      invalidateThreePaneStretchCache()
      rebalanceThreePaneHorizontalWidthsForStretchMode()
      return
    }

    lastThreePaneStretchUsesThirds = nil
    guard paneCount == 2 else { return }
    let tree = bonsplitController.treeSnapshot()
    guard case .split(let split) = tree,
      let splitUUID = UUID(uuidString: split.id)
    else { return }

    _ = bonsplitController.setDividerPosition(0.5, forSplit: splitUUID)
  }

  private func estimatedViewportWidthForStretchMode() -> CGFloat {
    let snapshot = bonsplitController.layoutSnapshot()
    let maxX = snapshot.panes.reduce(CGFloat(0)) { partial, pane in
      max(partial, CGFloat(pane.frame.x + pane.frame.width))
    }
    return max(maxX, 1)
  }
}
