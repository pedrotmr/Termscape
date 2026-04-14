import Bonsplit
import SwiftUI

struct WorkspaceContainerView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            if let tab = workspace.selectedTab {
                TabBarView(workspace: workspace)

                CanvasHostingView(tab: tab)
                    .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                        _ = workspace.addTab()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                        // If this tab has multiple panes, Cmd+W closes the focused pane.
                        // Only close the whole tab when it's down to a single pane.
                        if tab.bonsplitController.allPaneIds.count > 1,
                           let focusedPaneId = tab.bonsplitController.focusedPaneId {
                            tab.bonsplitController.closePane(focusedPaneId)
                        } else if let tabId = workspace.selectedTabId,
                                  !(workspace.selectedTab?.isPinned ?? false) {
                            workspace.closeTab(tabId)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitRight)) { _ in
                        splitPane(tab: tab, orientation: .horizontal)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitDown)) { _ in
                        splitPane(tab: tab, orientation: .vertical)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .moveToNewTab)) { notif in
                        movePaneToNewTab(notif: notif)
                    }
            } else {
                Color.clear
                    .onAppear { workspace.ensureHasTab() }
            }
        }
        .onAppear {
            workspace.ensureHasTab()
        }
    }

    /// Move a pane's terminal surface into a brand-new workspace tab, preserving the live session.
    /// The surface is extracted from the source tab before Bonsplit can tear it down, then injected
    /// into the initial pane of the newly created workspace tab.
    private func movePaneToNewTab(notif: NotificationCenter.Publisher.Output) {
        let key = Notification.Name.MoveToNewTabKey.self
        guard let surface = notif.userInfo?[key.surface] as? TerminalSurface,
              let sourceTab = notif.userInfo?[key.sourceTab] as? WorkspaceTab
        else { return }

        let shouldCloseSource = notif.userInfo?[key.closeSourceTab] as? Bool ?? false
        if shouldCloseSource {
            workspace.closeTab(sourceTab.id)
        }

        let newTab = workspace.addTab()

        // Bonsplit auto-creates an initial pane+tab on init. Inject our surface under that tab's
        // UUID so the canvas reuses the live hostedView instead of spawning a fresh terminal.
        let initialSnapshot = newTab.bonsplitController.layoutSnapshot()
        if let firstPane = initialSnapshot.panes.first,
           let tabIdStr = firstPane.selectedTabId,
           let tabUUID = UUID(uuidString: tabIdStr) {
            newTab.surfaces[tabUUID] = surface
        }
    }

    /// Split the current pane and immediately create a terminal tab in the new empty pane.
    /// Bonsplit creates new panes with no tabs — we must add one so the canvas can
    /// attach a TerminalSurface to it.
    private func splitPane(tab: WorkspaceTab, orientation: SplitOrientation) {
        let beforeSnapshot = tab.bonsplitController.layoutSnapshot()
        let beforeTree = tab.bonsplitController.treeSnapshot()
        let targetPaneId = tab.bonsplitController.focusedPaneId
        let sourceWorkingDirectory = focusedSurfaceWorkingDirectory(
            tab: tab,
            targetPaneId: targetPaneId,
            snapshot: beforeSnapshot
        )

        guard let newPaneId = tab.bonsplitController.splitPane(nil, orientation: orientation) else { return }

        if orientation == .horizontal {
            if beforeSnapshot.panes.count == 2 {
                let isTargetInsideHorizontalContext: Bool
                if let targetPaneId {
                    isTargetInsideHorizontalContext = HorizontalPaneSizingEngine.targetPaneHasHorizontalAncestor(
                        in: beforeTree,
                        paneId: targetPaneId.id.uuidString
                    )
                } else {
                    isTargetInsideHorizontalContext = HorizontalPaneSizingEngine.containsHorizontalSplit(in: beforeTree)
                }

                if !isTargetInsideHorizontalContext {
                    applyFirstHorizontalSplitSizing(
                        tab: tab,
                        targetPaneId: targetPaneId,
                        newPaneId: newPaneId
                    )
                } else {
                    let viewportWidth = estimatedViewportWidth(from: beforeSnapshot)
                    if viewportWidth >= WorkspaceTab.minimumViewportWidthForThreePaneEqualization {
                        tab.invalidateThreePaneStretchCache()
                        tab.rebalanceThreePaneHorizontalWidthsForStretchMode(viewportWidth: viewportWidth)
                    } else if let targetPaneId {
                        tab.invalidateThreePaneStretchCache()
                        applyHorizontalSplitCreationSizing(
                            tab: tab,
                            targetPaneId: targetPaneId,
                            newPaneId: newPaneId,
                            beforeSnapshot: beforeSnapshot
                        )
                    }
                }
            } else {
                let shouldUseLocalFirstHorizontalBehavior: Bool
                if let targetPaneId {
                    shouldUseLocalFirstHorizontalBehavior = !HorizontalPaneSizingEngine.targetPaneHasHorizontalAncestor(
                        in: beforeTree,
                        paneId: targetPaneId.id.uuidString
                    )
                } else {
                    shouldUseLocalFirstHorizontalBehavior = !HorizontalPaneSizingEngine.containsHorizontalSplit(in: beforeTree)
                }

                if shouldUseLocalFirstHorizontalBehavior {
                    applyFirstHorizontalSplitSizing(
                        tab: tab,
                        targetPaneId: targetPaneId,
                        newPaneId: newPaneId
                    )
                } else if let targetPaneId {
                    applyHorizontalSplitCreationSizing(
                        tab: tab,
                        targetPaneId: targetPaneId,
                        newPaneId: newPaneId,
                        beforeSnapshot: beforeSnapshot
                    )
                }
            }
        }

        // Create a Bonsplit tab in the new pane. This fires didCreateTab → notifyLayoutChanged
        // → CanvasDocumentView creates a TerminalSurface for the new pane.
        tab.queueWorkingDirectoryForNextTab(sourceWorkingDirectory, inPane: newPaneId)
        tab.bonsplitController.createTab(
            title: "Terminal",
            icon: "terminal",
            kind: "terminal",
            inPane: newPaneId
        )
    }

    /// Keeps existing pane widths fixed and inserts the new pane with the default creation width.
    private func applyHorizontalSplitCreationSizing(
        tab: WorkspaceTab,
        targetPaneId: PaneID,
        newPaneId: PaneID,
        beforeSnapshot: LayoutSnapshot
    ) {
        let tree = tab.bonsplitController.treeSnapshot()
        var desiredPaneWidths = HorizontalPaneSizingEngine.paneWidths(from: beforeSnapshot)

        let targetPaneKey = targetPaneId.id.uuidString
        let newPaneKey = newPaneId.id.uuidString
        let targetWidth = max(
            desiredPaneWidths[targetPaneKey] ?? WorkspaceTab.splitInsertionMinimumPaneWidth,
            1
        )

        desiredPaneWidths[targetPaneKey] = targetWidth
        desiredPaneWidths[newPaneKey] = WorkspaceTab.splitInsertionMinimumPaneWidth

        let plan = HorizontalPaneSizingEngine.buildPlan(
            tree: tree,
            desiredPaneWidths: desiredPaneWidths,
            fallbackPaneWidth: WorkspaceTab.interactiveMinimumPaneWidth
        )

        for (splitId, position) in plan.splitPositions {
            _ = tab.bonsplitController.setDividerPosition(position, forSplit: splitId)
        }
        tab.canvasWidth = max(plan.rootWidth, 1)
    }

    /// First local horizontal split for a pane starts as 50/50 and fills the viewport.
    private func applyFirstHorizontalSplitSizing(tab: WorkspaceTab, targetPaneId: PaneID?, newPaneId: PaneID) {
        let tree = tab.bonsplitController.treeSnapshot()
        guard let targetPaneId else { return }
        guard let splitUUID = HorizontalPaneSizingEngine.splitIDContainingPanes(
            in: tree,
            firstPaneId: targetPaneId.id.uuidString,
            secondPaneId: newPaneId.id.uuidString,
            orientation: "horizontal"
        ) else { return }

        _ = tab.bonsplitController.setDividerPosition(0.5, forSplit: splitUUID)
        tab.canvasWidth = 0
    }

    private func estimatedViewportWidth(from snapshot: LayoutSnapshot) -> CGFloat {
        let maxX = snapshot.panes.reduce(CGFloat(0)) { partial, pane in
            max(partial, CGFloat(pane.frame.x + pane.frame.width))
        }
        return max(maxX, 1)
    }

    private func focusedSurfaceWorkingDirectory(
        tab: WorkspaceTab,
        targetPaneId: PaneID?,
        snapshot: LayoutSnapshot
    ) -> String? {
        guard let targetPaneId else { return nil }
        guard let sourcePane = snapshot.panes.first(where: { $0.paneId == targetPaneId.id.uuidString }),
              let selectedTabId = sourcePane.selectedTabId,
              let tabUUID = UUID(uuidString: selectedTabId),
              let sourceSurface = tab.surfaces[tabUUID]
        else {
            return nil
        }

        return sourceSurface.splitWorkingDirectory
    }
}
