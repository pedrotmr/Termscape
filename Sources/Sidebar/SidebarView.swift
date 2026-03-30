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
    @State private var isAppearanceHovered = false
    @State private var isAddHovered = false
    @State private var showAddPopover = false
    @State private var showSettings = false
    @State private var draggingGroupId: UUID?
    @State private var groupDragStartIndex: Int?
    @State private var groupDragTranslation: CGFloat = 0
    @State private var proposedGroupIndex: Int?
    @State private var groupFrames: [UUID: CGRect] = [:]
    /// When set, the matching group's header collapse action is skipped (e.g. after a reorder drag).
    @State private var groupIdToSuppressHeaderCollapse: UUID?

    private static let newGroupName = "NEW GROUP"
    private static let groupDragCollapseSuppressionThreshold: CGFloat = 5
    private var t: AppTheme { theme.current }
    private let slideAnimation = Animation.spring(response: 0.25, dampingFraction: 0.82)
    private let settleAnimation = Animation.spring(response: 0.32, dampingFraction: 0.8)

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            Color.clear.frame(height: 46)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(appState.groups.enumerated()), id: \.element.id) { index, group in
                        GroupRowView(
                            group: group,
                            suppressHeaderCollapse: groupIdToSuppressHeaderCollapse == group.id
                        )
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
                            .animation(slideAnimation, value: proposedGroupIndex)
                            .animation(slideAnimation, value: draggingGroupId)
                            .simultaneousGesture(group.isImplicit ? nil : groupDragGesture(for: group, at: index))
                    }
                }
                .padding(.bottom, 8)
                .coordinateSpace(name: "sidebarList")
                .onPreferenceChange(GroupFrameKey.self) { groupFrames = $0 }
            }
            .scrollIndicators(.never)
            .scrollClipDisabled(true)

            // Footer
            Rectangle()
                .fill(t.border)
                .frame(height: 1)

            HStack(spacing: 2) {
                Spacer()

                Button {
                    showSettings = true
                } label: {
                    SidebarIconGlyph(systemImage: "slider.horizontal.3", theme: t, isHovered: isAppearanceHovered)
                }
                .buttonStyle(.plain)
                .help("Appearance")
                .onHover { isAppearanceHovered = $0 }
                .animation(.easeInOut(duration: 0.12), value: isAppearanceHovered)

                Button {
                    showAddPopover.toggle()
                } label: {
                    SidebarIconGlyph(systemImage: "plus", theme: t, isHovered: isAddHovered)
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .help("Add")
                .onHover { isAddHovered = $0 }
                .animation(.easeInOut(duration: 0.12), value: isAddHovered)
                .popover(isPresented: $showAddPopover) {
                    AddActionsPopover(
                        theme: t,
                        isPresented: $showAddPopover,
                        onOpenProject: openProjectAction,
                        onCloneFromURL: cloneFromURLAction,
                        onNewGroup: createGroupAction
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
            openProjectAction()
        } label: {
            Label("Open Project", systemImage: "folder.badge.plus")
        }
        Button {
            cloneFromURLAction()
        } label: {
            Label("Clone from URL", systemImage: "arrow.down.to.line")
        }
        Divider()
        Button {
            createGroupAction()
        } label: {
            Label("New Group", systemImage: "rectangle.3.group")
        }
    }

    // MARK: - Group offset

    private func groupOffset(for group: WorkspaceGroup, at index: Int) -> CGFloat {
        guard let draggingId = draggingGroupId,
              let draggedIdx = groupDragStartIndex,
              let proposed = proposedGroupIndex
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
                if draggingGroupId == nil {
                    draggingGroupId = group.id
                    groupDragStartIndex = startIndex
                }
                groupDragTranslation = value.translation.height
                if abs(value.translation.height) > Self.groupDragCollapseSuppressionThreshold {
                    groupIdToSuppressHeaderCollapse = group.id
                }
                guard let draggedFrame = groupFrames[group.id] else { return }
                let cursorY = draggedFrame.midY + groupDragTranslation
                var best = startIndex
                var bestDist = CGFloat.infinity
                for (idx, g) in appState.groups.enumerated() {
                    guard g.id != group.id, let f = groupFrames[g.id] else { continue }
                    let d = abs(cursorY - f.midY)
                    if d < bestDist { bestDist = d; best = idx }
                }
                withAnimation(slideAnimation) {
                    proposedGroupIndex = best
                }
            }
            .onEnded { _ in
                if let from = groupDragStartIndex, let to = proposedGroupIndex, from != to {
                    withAnimation(settleAnimation) {
                        appState.groups.move(fromOffsets: IndexSet(integer: from),
                                            toOffset: to > from ? to + 1 : to)
                    }
                }
                draggingGroupId = nil
                groupDragStartIndex = nil
                groupDragTranslation = 0
                proposedGroupIndex = nil
                DispatchQueue.main.async {
                    groupIdToSuppressHeaderCollapse = nil
                }
            }
    }

    private func openProjectAction() {
        appState.openFolder()
    }

    private func cloneFromURLAction() {
        appState.showCloneSheet = true
    }

    private func createGroupAction() {
        let group = WorkspaceGroup(name: Self.newGroupName, isImplicit: false)
        appState.groups.append(group)
    }
}

// MARK: - Footer menu button

private struct SidebarIconGlyph: View {
    let systemImage: String
    let theme: AppTheme
    let isHovered: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(isHovered ? theme.text : theme.textMuted)
            .frame(width: 30, height: 30)
            .background(isHovered ? theme.hover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct AddActionsPopover: View {
    let theme: AppTheme
    @Binding var isPresented: Bool
    let onOpenProject: () -> Void
    let onCloneFromURL: () -> Void
    let onNewGroup: () -> Void

    private func actionWrapper(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            isPresented = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AddActionsRow(systemImage: "folder.badge.plus", title: "Open Project", theme: theme, action: actionWrapper(onOpenProject))
            divider
            AddActionsRow(systemImage: "arrow.down.to.line", title: "Clone from URL", theme: theme, action: actionWrapper(onCloneFromURL))
            divider
            AddActionsRow(systemImage: "rectangle.3.group", title: "New Group", theme: theme, action: actionWrapper(onNewGroup))
        }
        .padding(8)
        .frame(width: 220)
        .background(theme.elevated)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: 1)
            .padding(.vertical, 3)
    }
}

private struct AddActionsRow: View {
    let systemImage: String
    let title: String
    let theme: AppTheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? theme.hover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
