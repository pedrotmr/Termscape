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
                    .onReceive(NotificationCenter.default.publisher(for: .newBrowserTab)) { _ in
                        _ = workspace.addBrowserTab()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .newEditorTab)) { notif in
                        let key = Notification.Name.MoveToNewTabKey.editorRootPath
                        guard let rawRoot = notif.userInfo?[key] as? String,
                              let root = TerminalSurface.normalizeWorkingDirectoryPath(rawRoot)
                        else { return }

                        let newTab = workspace.addEditorTab()
                        let initialSnapshot = newTab.bonsplitController.layoutSnapshot()
                        guard let firstPane = initialSnapshot.panes.first,
                              let selectedTabId = firstPane.selectedTabId,
                              let firstTabUUID = UUID(uuidString: selectedTabId)
                        else { return }

                        // Initial Bonsplit tab already exists; pane-queue only applies to tabs created later in that pane.
                        newTab.setPendingEditorRootIfNoSurface(root, for: TabID(uuid: firstTabUUID))
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                        let snapshot = tab.bonsplitController.layoutSnapshot()
                        if tab.focusedPaneContentKind(snapshot: snapshot) == .editor,
                           let focusedPaneId = snapshot.focusedPaneId,
                           let pane = snapshot.panes.first(where: { $0.paneId == focusedPaneId }),
                           let selectedTabIdStr = pane.selectedTabId,
                           let bonsplitTabUUID = UUID(uuidString: selectedTabIdStr),
                           let editor = tab.editorSurfaces[bonsplitTabUUID],
                           editor.requestSmartCloseRightmostDocumentTab()
                        {
                            return
                        }

                        // If this tab has multiple panes, Cmd+W closes the focused pane.
                        // Only close the whole tab when it's down to a single pane.
                        if tab.bonsplitController.allPaneIds.count > 1,
                           let focusedPaneId = tab.bonsplitController.focusedPaneId
                        {
                            tab.bonsplitController.closePane(focusedPaneId)
                        } else if let tabId = workspace.selectedTabId,
                                  !(workspace.selectedTab?.isPinned ?? false)
                        {
                            workspace.closeTab(tabId)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitRight)) { _ in
                        let snapshot = tab.bonsplitController.layoutSnapshot()
                        splitPane(
                            tab: tab,
                            orientation: .horizontal,
                            contentKind: tab.focusedPaneContentKind(snapshot: snapshot)
                        )
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitDown)) { _ in
                        let snapshot = tab.bonsplitController.layoutSnapshot()
                        splitPane(
                            tab: tab,
                            orientation: .vertical,
                            contentKind: tab.focusedPaneContentKind(snapshot: snapshot)
                        )
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitBrowserRight)) { _ in
                        splitPane(tab: tab, orientation: .horizontal, contentKind: .browser)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitBrowserDown)) { _ in
                        splitPane(tab: tab, orientation: .vertical, contentKind: .browser)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitEditorRight)) { _ in
                        splitPane(tab: tab, orientation: .horizontal, contentKind: .editor)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitEditorDown)) { _ in
                        splitPane(tab: tab, orientation: .vertical, contentKind: .editor)
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

    /// Move a pane's focused content surface into a brand-new workspace tab, preserving live state.
    /// The surface is extracted from the source tab before Bonsplit can tear it down, then injected
    /// into the initial pane of the newly created workspace tab.
    private func movePaneToNewTab(notif: NotificationCenter.Publisher.Output) {
        let key = Notification.Name.MoveToNewTabKey.self
        guard let sourceTab = notif.userInfo?[key.sourceTab] as? WorkspaceTab
        else { return }

        let contentKind =
            WorkspacePaneContentKind(
                rawValue: (notif.userInfo?[key.contentKind] as? String) ?? ""
            ) ?? .terminal

        let shouldCloseSource = notif.userInfo?[key.closeSourceTab] as? Bool ?? false
        if shouldCloseSource {
            workspace.closeTab(sourceTab.id)
        }

        switch contentKind {
        case .terminal:
            guard let surface = notif.userInfo?[key.surface] as? TerminalSurface else { return }
            let newTab = workspace.addTab(
                title: WorkspacePaneContentKind.terminal.defaultTitle,
                initialPaneKind: .terminal
            )
            let initialSnapshot = newTab.bonsplitController.layoutSnapshot()
            if let firstPane = initialSnapshot.panes.first,
               let tabIdStr = firstPane.selectedTabId,
               let tabUUID = UUID(uuidString: tabIdStr)
            {
                newTab.attachTerminalSurface(surface, to: tabUUID)
            }
        case .browser:
            guard let surface = notif.userInfo?[key.browserSurface] as? BrowserSurface else { return }
            let newTab = workspace.addTab(
                title: WorkspacePaneContentKind.browser.defaultTitle,
                initialPaneKind: .browser
            )
            newTab.title = WorkspacePaneContentKind.browser.defaultTitle
            let initialSnapshot = newTab.bonsplitController.layoutSnapshot()
            if let firstPane = initialSnapshot.panes.first,
               let tabIdStr = firstPane.selectedTabId,
               let tabUUID = UUID(uuidString: tabIdStr)
            {
                newTab.attachBrowserSurface(surface, to: tabUUID)
            }
        case .editor:
            let newTab = workspace.addTab(
                title: WorkspacePaneContentKind.editor.defaultTitle,
                initialPaneKind: .editor
            )
            let initialSnapshot = newTab.bonsplitController.layoutSnapshot()
            guard let firstPane = initialSnapshot.panes.first,
                  let selectedTabId = firstPane.selectedTabId,
                  let firstTabUUID = UUID(uuidString: selectedTabId)
            else { return }
            if let surface = notif.userInfo?[key.editorSurface] as? EditorSurface {
                newTab.attachEditorSurface(surface, to: firstTabUUID)
            } else if let rootPath = notif.userInfo?[key.editorRootPath] as? String {
                newTab.setPendingEditorRootIfNoSurface(rootPath, for: TabID(uuid: firstTabUUID))
            } else {
                return
            }
        }
    }

    /// Split the current pane and immediately create content in the new empty pane.
    /// Bonsplit creates new panes with no tabs — we must add one so the canvas can
    /// attach the correct surface type to it.
    private func splitPane(
        tab: WorkspaceTab,
        orientation: SplitOrientation,
        contentKind: WorkspacePaneContentKind
    ) {
        let beforeSnapshot = tab.bonsplitController.layoutSnapshot()
        let beforeTree = tab.bonsplitController.treeSnapshot()
        let targetPaneId = tab.bonsplitController.focusedPaneId
        let sourceWorkingDirectory = focusedSurfaceWorkingDirectory(
            tab: tab,
            targetPaneId: targetPaneId,
            snapshot: beforeSnapshot
        )
        let sourceBrowserURL = focusedBrowserURL(
            tab: tab,
            targetPaneId: targetPaneId,
            snapshot: beforeSnapshot
        )
        let sourceEditorRoot = tab.resolveEditorRootFromFocusedContext(
            targetPaneId: targetPaneId,
            snapshot: beforeSnapshot
        )

        guard let newPaneId = tab.bonsplitController.splitPane(nil, orientation: orientation) else {
            return
        }

        if orientation == .horizontal {
            if beforeSnapshot.panes.count == 2 {
                let isTargetInsideHorizontalContext: Bool = if let targetPaneId {
                    HorizontalPaneSizingEngine.targetPaneHasHorizontalAncestor(
                        in: beforeTree,
                        paneId: targetPaneId.id.uuidString
                    )
                } else {
                    HorizontalPaneSizingEngine.containsHorizontalSplit(
                        in: beforeTree
                    )
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
                let shouldUseLocalFirstHorizontalBehavior: Bool = if let targetPaneId {
                    !HorizontalPaneSizingEngine.targetPaneHasHorizontalAncestor(
                        in: beforeTree,
                        paneId: targetPaneId.id.uuidString
                    )
                } else {
                    !HorizontalPaneSizingEngine.containsHorizontalSplit(in: beforeTree)
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

        switch contentKind {
        case .terminal:
            tab.queueWorkingDirectoryForNextTab(sourceWorkingDirectory, inPane: newPaneId)
        case .browser:
            tab.queueBrowserURLForNextTab(sourceBrowserURL, inPane: newPaneId)
        case .editor:
            tab.queueEditorRootForNextTab(sourceEditorRoot, inPane: newPaneId)
        }

        // Create a Bonsplit tab in the new pane. This fires didCreateTab → notifyLayoutChanged.
        tab.bonsplitController.createTab(
            title: contentKind.defaultTitle,
            icon: contentKind.defaultIcon,
            kind: contentKind.rawValue,
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
    private func applyFirstHorizontalSplitSizing(
        tab: WorkspaceTab, targetPaneId: PaneID?, newPaneId: PaneID
    ) {
        let tree = tab.bonsplitController.treeSnapshot()
        guard let targetPaneId else { return }
        guard
            let splitUUID = HorizontalPaneSizingEngine.splitIDContainingPanes(
                in: tree,
                firstPaneId: targetPaneId.id.uuidString,
                secondPaneId: newPaneId.id.uuidString,
                orientation: "horizontal"
            )
        else { return }

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

    private func focusedBrowserURL(
        tab: WorkspaceTab,
        targetPaneId: PaneID?,
        snapshot: LayoutSnapshot
    ) -> URL? {
        guard let targetPaneId else { return nil }
        guard let sourcePane = snapshot.panes.first(where: { $0.paneId == targetPaneId.id.uuidString }),
              let selectedTabId = sourcePane.selectedTabId,
              let tabUUID = UUID(uuidString: selectedTabId)
        else {
            return nil
        }

        return tab.browserURL(for: tabUUID)
    }
}
