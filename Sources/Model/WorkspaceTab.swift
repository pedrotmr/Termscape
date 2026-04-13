import Bonsplit
import Foundation
import SwiftUI

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

  /// Text to send to the first surface once it attaches (e.g. a clone command).
  var pendingInputOnceAttached: String?

  /// Absolute canvas width in points. Preserves pane sizing when the window size changes.
  var canvasWidth: CGFloat = 0

  private let workspaceURL: URL?
  private var lastThreePaneStretchUsesThirds: Bool?
  private var pendingWorkingDirectoryByPaneId: [UUID: String] = [:]
  private var pendingWorkingDirectoryByTabId: [UUID: String] = [:]

  init(title: String = "Terminal", workspaceURL: URL?, workspaceId: UUID) {
    self.id = UUID()
    self.title = title
    self.workspaceURL = workspaceURL
    self.workspaceId = workspaceId

    var config = BonsplitConfiguration()
    config.allowSplits = true
    config.autoCloseEmptyPanes = true
    config.appearance.minimumPaneWidth = Self.interactiveMinimumPaneWidth
    config.appearance.minimumPaneHeight = Self.interactiveMinimumPaneHeight
    config.appearance.enableAnimations = false
    self.bonsplitController = BonsplitController(configuration: config)

    // Wire delegate so canvas redraws on layout and focus changes (splits, resizes, closes, pane focus)
    // The delegate is held weakly by BonsplitController, so no retain cycle.
    self.bonsplitController.delegate = self
  }

  /// Restore tab identity, canvas width, Bonsplit tree, and per-pane cwd from persistence (surfaces are created lazily).
  init(restoring snapshot: WorkspaceTabSnapshot, workspaceURL: URL?, workspaceId: UUID) {
    self.id = snapshot.id
    self.title = snapshot.title
    self.isPinned = snapshot.isPinned
    self.workspaceURL = workspaceURL
    self.workspaceId = workspaceId
    self.canvasWidth = snapshot.canvasWidthPts > 0 ? CGFloat(snapshot.canvasWidthPts) : 0

    var config = BonsplitConfiguration()
    config.allowSplits = true
    config.autoCloseEmptyPanes = true
    config.appearance.minimumPaneWidth = Self.interactiveMinimumPaneWidth
    config.appearance.minimumPaneHeight = Self.interactiveMinimumPaneHeight
    config.appearance.enableAnimations = false
    self.bonsplitController = BonsplitController(configuration: config)
    let focus = snapshot.focusedPaneId.flatMap(UUID.init(uuidString:)).map { PaneID(id: $0) }
    self.bonsplitController.replaceRootTree(with: snapshot.tree, focusedPaneId: focus)
    self.bonsplitController.delegate = self

    if let map = snapshot.workingDirectoryByTerminalTabId {
      for (idStr, rawPath) in map {
        guard let uuid = UUID(uuidString: idStr),
          let normalized = TerminalSurface.normalizeWorkingDirectoryPath(rawPath)
        else { continue }
        pendingWorkingDirectoryByTabId[uuid] = normalized
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

  func queueWorkingDirectoryForNextTab(_ workingDirectory: String?, inPane paneId: PaneID) {
    guard let normalized = TerminalSurface.normalizeWorkingDirectoryPath(workingDirectory) else {
      return
    }
    pendingWorkingDirectoryByPaneId[paneId.id] = normalized
  }

  func removeSurface(for tabId: TabID) {
    surfaces[tabId.uuid]?.teardown()
    surfaces.removeValue(forKey: tabId.uuid)
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
  }
}

// MARK: - BonsplitDelegate

extension WorkspaceTab: BonsplitDelegate {
  private static var layoutPersistenceWorkItem: DispatchWorkItem?

  /// Post the notification that CanvasHostingView listens for, triggering a canvas relayout.
  func notifyLayoutChanged() {
    NotificationCenter.default.post(name: .bonsplitLayoutDidChange, object: bonsplitController)
    Self.layoutPersistenceWorkItem?.cancel()
    let item = DispatchWorkItem {
      NotificationCenter.default.post(name: .workspacePersistenceNeeded, object: nil)
    }
    Self.layoutPersistenceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
  }

  // Canvas needs to redraw whenever a tab is created (new pane tab → needs a surface)
  func splitTabBar(
    _ controller: BonsplitController, didCreateTab tab: Bonsplit.Tab, inPane pane: PaneID
  ) {
    if let pendingWorkingDirectory = pendingWorkingDirectoryByPaneId.removeValue(forKey: pane.id) {
      pendingWorkingDirectoryByTabId[tab.id.uuid] = pendingWorkingDirectory
    }
    notifyLayoutChanged()
  }

  func splitTabBar(
    _ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID,
    orientation: SplitOrientation
  ) {
    // Note: new pane is empty (no tabs yet). WorkspaceContainerView calls createTab
    // immediately after, which fires didCreateTab → notifyLayoutChanged.
    // We don't notify here to avoid a redundant update with an empty pane.
  }

  /// Teardown the TerminalSurface for the closed tab so Ghostty frees its resources.
  func splitTabBar(
    _ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID
  ) {
    removeSurface(for: tabId)
  }

  func splitTabBar(_ controller: BonsplitController, didClosePane paneId: PaneID) {
    normalizeLayoutForSmallPaneCount()
    notifyLayoutChanged()
  }

  func splitTabBar(_ controller: BonsplitController, didFocusPane pane: PaneID) {
    notifyLayoutChanged()
  }

  func splitTabBar(_ controller: BonsplitController, didChangeGeometry snapshot: LayoutSnapshot) {
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
