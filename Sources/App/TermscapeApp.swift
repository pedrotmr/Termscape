import AppKit
import SwiftUI

let workspaceWindowIdentifier = NSUserInterfaceItemIdentifier("termscape.workspace-window")

struct WorkspaceWindowIdentityMarker: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        MarkerView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let window = nsView.window else { return }
        window.identifier = workspaceWindowIdentifier
        AppDelegate.shared?.configureWorkspaceWindowDragBehaviorIfNeeded(window)
    }

    private final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = workspaceWindowIdentifier
            AppDelegate.shared?.configureWorkspaceWindowDragBehaviorIfNeeded(window)
        }
    }
}

@main
struct TermscapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appUpdater = AppUpdater()
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.appState)
                .environment(themeManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Workspace") {
                    appDelegate.appState.openWorkspace()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Terminal") {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Browser Tab") {
                    NotificationCenter.default.post(name: .newBrowserTab, object: nil)
                }

                Button("New Editor Tab") {
                    let pathKey = Notification.Name.MoveToNewTabKey.editorRootPath
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    NotificationCenter.default.post(
                        name: .newEditorTab,
                        object: nil,
                        userInfo: [pathKey: home]
                    )
                }

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Split Right") {
                    NotificationCenter.default.post(name: .splitRight, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Split Down") {
                    NotificationCenter.default.post(name: .splitDown, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Split Browser Right") {
                    NotificationCenter.default.post(name: .splitBrowserRight, object: nil)
                }

                Button("Split Browser Down") {
                    NotificationCenter.default.post(name: .splitBrowserDown, object: nil)
                }

                Divider()

                Button("Split Editor Right") {
                    NotificationCenter.default.post(name: .splitEditorRight, object: nil)
                }

                Button("Split Editor Down") {
                    NotificationCenter.default.post(name: .splitEditorDown, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let newTab = Notification.Name("termscape.newTab")
    static let newBrowserTab = Notification.Name("termscape.newBrowserTab")
    static let newEditorTab = Notification.Name("termscape.newEditorTab")
    static let closeTab = Notification.Name("termscape.closeTab")
    static let splitRight = Notification.Name("termscape.splitRight")
    static let splitDown = Notification.Name("termscape.splitDown")
    static let splitBrowserRight = Notification.Name("termscape.splitBrowserRight")
    static let splitBrowserDown = Notification.Name("termscape.splitBrowserDown")
    static let splitEditorRight = Notification.Name("termscape.splitEditorRight")
    static let splitEditorDown = Notification.Name("termscape.splitEditorDown")
    static let newWorkspace = Notification.Name("termscape.newWorkspace")
    static let ghosttyConfigDidReload = Notification.Name("termscape.ghosttyConfigDidReload")
    /// Posted by the context menu to move the focused pane content into a new workspace tab.
    static let moveToNewTab = Notification.Name("termscape.moveToNewTab")

    /// Tab/pane layout or workspace tab strip changed; `AppState` debounces persistence.
    static let workspacePersistenceNeeded = Notification.Name("termscape.workspacePersistenceNeeded")
    /// Terminal current working directory changed.
    static let terminalWorkingDirectoryDidChange = Notification.Name(
        "termscape.terminalWorkingDirectoryDidChange"
    )

    /// Typed keys for the `moveToNewTab` notification's `userInfo` dictionary.
    enum MoveToNewTabKey {
        static let surface = "surface"
        static let browserSurface = "browserSurface"
        static let editorSurface = "editorSurface"
        static let editorRootPath = "editorRootPath"
        static let contentKind = "contentKind"
        static let sourceTab = "sourceTab"
        static let closeSourceTab = "closeSourceTab"
    }

    /// Typed keys for the `terminalWorkingDirectoryDidChange` notification's `userInfo` dictionary.
    enum TerminalWorkingDirectoryDidChangeKey {
        static let workspaceId = "workspaceId"
        static let surfaceId = "surfaceId"
        static let path = "path"
    }
}

// MARK: - Content view

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme
    @State private var sidebarWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)

            SidebarDivider(sidebarWidth: $sidebarWidth)

            Group {
                if let workspace = appState.selectedWorkspace {
                    WorkspaceContainerView(workspace: workspace)
                } else {
                    EmptyWorkspaceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 400)
        .ignoresSafeArea()
        .background(
            WorkspaceWindowIdentityMarker()
                .allowsHitTesting(false)
        )
        .onReceive(NotificationCenter.default.publisher(for: .workspacePersistenceNeeded)) { _ in
            appState.schedulePersist()
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalWorkingDirectoryDidChange)) {
            notif in
            appState.maybeAutoRenameWorkspaceFromTerminalPathChange(notif)
        }
    }
}

// MARK: - Sidebar resize divider

private struct SidebarDivider: View {
    @Environment(ThemeManager.self) var theme
    @Binding var sidebarWidth: CGFloat

    private let minWidth: CGFloat = 180
    private let maxWidth: CGFloat = 520

    var body: some View {
        HorizontalResizeDivider(
            width: $sidebarWidth,
            minWidth: minWidth,
            maxWidth: maxWidth,
            idleColor: theme.current.border,
            hoverColor: theme.current.accent.opacity(0.5)
        )
    }
}

// MARK: - Empty state

struct EmptyWorkspaceView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme

    @State private var isHoveringOpen = false
    @State private var isHoveringClone = false

    private var t: AppTheme {
        theme.current
    }

    var body: some View {
        ZStack {
            t.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(t.hover)
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(t.border, lineWidth: 1)
                        .frame(width: 72, height: 72)
                    Image(systemName: "terminal")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(t.textFaint)
                }
                .padding(.bottom, 20)

                Text("No workspace open")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(t.text)
                    .padding(.bottom, 6)

                Text("Open a folder or clone a repository to get started")
                    .font(.system(size: 12))
                    .foregroundStyle(t.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 28)

                HStack(spacing: 10) {
                    emptyStateButton(label: "Open Folder", icon: "folder", isHovered: isHoveringOpen) {
                        appState.openFolder()
                    }
                    .onHover { isHoveringOpen = $0 }

                    emptyStateButton(
                        label: "Clone Repository", icon: "arrow.down.to.line", isHovered: isHoveringClone
                    ) {
                        appState.showCloneSheet = true
                    }
                    .onHover { isHoveringClone = $0 }
                }

                Spacer()

                Text("Use the sidebar to manage workspaces")
                    .font(.system(size: 11))
                    .foregroundStyle(t.textFaint)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyStateButton(
        label: String, icon: String, isHovered: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 13))
            }
            .foregroundStyle(isHovered ? t.text : t.textMuted)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? t.selected : t.hover)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Helpers

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
