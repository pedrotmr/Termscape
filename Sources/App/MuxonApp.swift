import SwiftUI

@main
struct MuxonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Terminal") {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

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
            }
        }
    }
}

extension Notification.Name {
    static let newTab = Notification.Name("muxon.newTab")
    static let closeTab = Notification.Name("muxon.closeTab")
    static let splitRight = Notification.Name("muxon.splitRight")
    static let splitDown = Notification.Name("muxon.splitDown")
    static let newWorkspace = Notification.Name("muxon.newWorkspace")
    static let ghosttyConfigDidReload = Notification.Name("muxon.ghosttyConfigDidReload")
    /// Posted by the context menu to move the focused pane's terminal into a new workspace tab.
    /// userInfo keys: "surface" (TerminalSurface), "sourceTab" (WorkspaceTab), "closeSourceTab" (Bool)
    static let moveToNewTab = Notification.Name("muxon.moveToNewTab")
}

// MARK: - Content view

struct ContentView: View {
    @Environment(AppState.self) var appState
    @State private var sidebarWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)

            // Draggable resize handle
            SidebarDivider(sidebarWidth: $sidebarWidth)

            // Main content — starts flush with top of window (no gap)
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
        // Fill the whole window including behind the title bar.
        // Sidebar adds its own top clearance for traffic light buttons.
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar resize divider

private struct SidebarDivider: View {
    @Binding var sidebarWidth: CGFloat
    @State private var isHovered = false

    private let minWidth: CGFloat = 180
    private let maxWidth: CGFloat = 380

    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.muxAccent.opacity(0.5) : Color.muxBorder)
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -4))  // wider hit area
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = sidebarWidth + value.translation.width
                        sidebarWidth = proposed.clamped(to: minWidth...maxWidth)
                    }
            )
            .cursor(.resizeLeftRight)
    }
}

// MARK: - Empty state

struct EmptyWorkspaceView: View {
    @Environment(AppState.self) var appState

    @State private var isHoveringOpen = false
    @State private var isHoveringClone = false

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.043, blue: 0.051)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        .frame(width: 72, height: 72)
                    Image(systemName: "terminal")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .padding(.bottom, 20)

                Text("No workspace open")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.bottom, 6)

                Text("Open a folder or clone a repository to get started")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 28)

                HStack(spacing: 10) {
                    emptyStateButton(label: "Open Folder", icon: "folder", isHovered: isHoveringOpen) {
                        appState.openFolder()
                    }
                    .onHover { isHoveringOpen = $0 }

                    emptyStateButton(label: "Clone Repository", icon: "arrow.down.to.line", isHovered: isHoveringClone) {
                        appState.showCloneSheet = true
                    }
                    .onHover { isHoveringClone = $0 }
                }

                Spacer()

                Text("Use the sidebar to manage workspaces")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.18))
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyStateButton(label: String, icon: String, isHovered: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 13))
            }
            .foregroundStyle(isHovered ? Color.muxText : Color.white.opacity(0.55))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.09) : Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                        isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.07), lineWidth: 1
                    ))
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
    /// Sets the mouse cursor for a view.
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
