import SwiftUI
import UniformTypeIdentifiers

private struct GroupFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme
    @State private var showSettings = false
    @State private var draggingGroupId: UUID?
    @State private var groupDragTranslation: CGFloat = 0
    @State private var proposedGroupIndex: Int?
    @State private var groupFrames: [UUID: CGRect] = [:]

    private var t: AppTheme { theme.current }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Title bar clearance — pushes content below macOS traffic light buttons.
            Color.clear.frame(height: 28)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(appState.groups.enumerated()), id: \.element.id) { index, group in
                        GroupRowView(group: group)
                            .background(GeometryReader { geo in
                                Color.clear.preference(
                                    key: GroupFrameKey.self,
                                    value: [group.id: geo.frame(in: .named("sidebarList"))]
                                )
                            })
                            .zIndex(draggingGroupId == group.id ? 1 : 0)
                            .scaleEffect(draggingGroupId == group.id ? 1.01 : 1.0, anchor: .center)
                            .shadow(
                                color: draggingGroupId == group.id ? .black.opacity(0.2) : .clear,
                                radius: 8, y: 3
                            )
                            .offset(y: groupOffset(for: group, at: index))
                            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: proposedGroupIndex)
                            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: draggingGroupId)
                            .simultaneousGesture(group.isImplicit ? nil : groupDragGesture(for: group, at: index))
                    }
                }
                .padding(.bottom, 8)
                .coordinateSpace(name: "sidebarList")
                .onPreferenceChange(GroupFrameKey.self) { groupFrames = $0 }
            }
            .scrollIndicators(.never)

            // Footer
            Rectangle()
                .fill(t.border)
                .frame(height: 1)

            HStack(spacing: 2) {
                SidebarIconButton(systemImage: "folder.badge.plus", help: "Open Folder as Workspace", theme: t) {
                    appState.openFolder()
                }
                SidebarIconButton(systemImage: "arrow.down.to.line", help: "Clone Git Repository", theme: t) {
                    appState.showCloneSheet = true
                }

                Spacer()

                SidebarIconButton(systemImage: "slider.horizontal.3", help: "Settings", theme: t) {
                    showSettings = true
                }
                SidebarIconButton(systemImage: "plus", help: "New Group", theme: t) {
                    let group = WorkspaceGroup(name: "NEW GROUP", isImplicit: false)
                    appState.groups.append(group)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .contextMenu { addMenuItems }
        .background(t.sidebar)
        .sheet(isPresented: $appState.showCloneSheet) {
            CloneSheetView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private var addMenuItems: some View {
        Button {
            appState.openFolder()
        } label: {
            Label("Open Project", systemImage: "folder.badge.plus")
        }
        Button {
            appState.showCloneSheet = true
        } label: {
            Label("Clone from URL", systemImage: "arrow.down.to.line")
        }
        Divider()
        Button {
            let group = WorkspaceGroup(name: "NEW GROUP", isImplicit: false)
            appState.groups.append(group)
        } label: {
            Label("New Group", systemImage: "rectangle.3.group")
        }
    }

    // MARK: - Group offset

    private func groupOffset(for group: WorkspaceGroup, at index: Int) -> CGFloat {
        guard let draggingId = draggingGroupId,
              let proposed = proposedGroupIndex,
              let draggedIdx = appState.groups.firstIndex(where: { $0.id == draggingId })
        else { return 0 }
        if group.id == draggingId { return groupDragTranslation }
        let draggedH = groupFrames[draggingId]?.height ?? 44
        if draggedIdx < proposed {
            if index > draggedIdx && index <= proposed { return -draggedH }
        } else if draggedIdx > proposed {
            if index >= proposed && index < draggedIdx { return draggedH }
        }
        return 0
    }

    // MARK: - Group drag gesture

    private func groupDragGesture(for group: WorkspaceGroup, at startIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if draggingGroupId == nil { draggingGroupId = group.id }
                groupDragTranslation = value.translation.height
                guard let draggedFrame = groupFrames[group.id] else { return }
                let cursorY = draggedFrame.midY + groupDragTranslation
                var best = startIndex
                var bestDist = CGFloat.infinity
                for (idx, g) in appState.groups.enumerated() {
                    guard g.id != group.id, let f = groupFrames[g.id] else { continue }
                    let d = abs(cursorY - f.midY)
                    if d < bestDist { bestDist = d; best = idx }
                }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    proposedGroupIndex = best
                }
            }
            .onEnded { _ in
                if let from = appState.groups.firstIndex(where: { $0.id == draggingGroupId }),
                   let to = proposedGroupIndex, from != to {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        appState.groups.move(fromOffsets: IndexSet(integer: from),
                                            toOffset: to > from ? to + 1 : to)
                    }
                }
                draggingGroupId = nil
                groupDragTranslation = 0
                proposedGroupIndex = nil
            }
    }
}

// MARK: - Footer icon button

private struct SidebarIconButton: View {
    let systemImage: String
    let help: String
    let theme: AppTheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isHovered ? theme.text : theme.textMuted)
                .frame(width: 30, height: 30)
                .background(isHovered ? theme.hover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Clone sheet

struct CloneSheetView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme
    @FocusState private var isFocused: Bool

    private var t: AppTheme { theme.current }

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 5) {
                Text("Clone Repository")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.text)
                Text("Paste a git URL to clone into a new workspace")
                    .font(.system(size: 12))
                    .foregroundStyle(t.textMuted)
            }
            .padding(.bottom, 20)

            // URL field
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.textFaint)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(t.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isFocused ? t.accent.opacity(0.55) : t.border,
                            lineWidth: 1
                        )

                    TextField("https://github.com/owner/repo.git", text: $appState.cloneURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(t.text)
                        .focused($isFocused)
                        .onSubmit { clone() }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                }
                .frame(height: 36)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            .padding(.bottom, 20)

            // Actions
            HStack {
                Button("Cancel") {
                    appState.showCloneSheet = false
                    appState.cloneURL = ""
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(MuxonSecondaryButtonStyle())

                Spacer()

                Button("Clone") { clone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.cloneURL.isEmpty)
                    .buttonStyle(MuxonPrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(t.elevated)
        .onAppear { isFocused = true }
    }

    private func clone() {
        appState.cloneRepository(urlString: appState.cloneURL)
    }
}
