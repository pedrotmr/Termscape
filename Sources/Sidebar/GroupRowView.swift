import AppKit
import SwiftUI

struct WorkspaceRowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct GroupHeaderFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Insert-before index in `groupId` for workspace drag preview/commit.
struct WorkspaceDropTarget: Equatable {
    var groupId: UUID
    var index: Int
}

struct GroupRowView: View {
    private enum GroupChrome {
        static let edgeInset: CGFloat = 10
        static let separatorInset: CGFloat = 0
        static let headerTopPadding: CGFloat = 8
        static let headerBottomPadding: CGFloat = 6
        static let expandedBottomPadding: CGFloat = 10
    }

    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme
    @Bindable var group: WorkspaceGroup

    /// Whole-section lift (header + workspaces) while reordering this group in the sidebar.
    var isGroupReorderDragging: Bool = false
    /// When true, ignore the next collapse toggle (after a group reorder drag).
    var suppressHeaderCollapse: Bool = false
    /// Group reorder drag — header only; nil for implicit groups.
    var groupReorderGesture: AnyGesture<DragGesture.Value>?
    /// Per-row workspace drag from sidebar coordinator.
    var workspaceDragGesture: (Workspace, Int) -> AnyGesture<DragGesture.Value>
    /// Vertical preview offset for a workspace row while dragging (sidebar-owned).
    var workspaceRowYOffset: (UUID) -> CGFloat
    /// Lifted drag indicator for row highlight (nil when idle).
    var draggingWorkspaceId: UUID?
    /// Drives sibling offset animation while a workspace drag is active.
    var proposedWorkspaceDropTarget: WorkspaceDropTarget?
    /// Live insert index among visible rows (excluding drag); animates sibling shifts.
    var proposedWorkspaceFlatInsert: Int?
    /// Draw the section's top divider.
    var showsTopDivider: Bool = false
    /// Draw the section's bottom divider.
    var showsBottomDivider: Bool = false
    /// Extra spacing before the top divider for the first explicit group after loose workspaces.
    var topDividerSpacing: CGFloat = 0

    @State private var newGroupName = ""
    @State private var isHoveringHeader = false
    @State private var hoverChevron = false
    @State private var hoverAddWorkspace = false
    @State private var hoverRenameGroup = false
    @State private var hoverDeleteGroup = false
    @State private var showDeleteGroupConfirmation = false
    @FocusState private var groupNameFocused: Bool

    private let slideAnimation = Animation.spring(response: 0.25, dampingFraction: 0.82)
    private let collapseToggleAnimation = Animation.easeInOut(duration: 0.2)

    var isRenamingGroup: Bool {
        appState.editingGroupId == group.id
    }

    private var t: AppTheme {
        theme.current
    }

    var body: some View {
        VStack(spacing: 0) {
            if !group.isImplicit, showsTopDivider {
                Rectangle()
                    .fill(t.border.opacity(0.95))
                    .frame(height: 1)
                    .padding(.top, topDividerSpacing)
            }

            if !group.isImplicit {
                headerWithOptionalGroupDrag
                    .animation(.easeInOut(duration: 0.12), value: isHoveringHeader)
            }

            if !group.isCollapsed {
                VStack(spacing: 0) {
                    ForEach(Array(group.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        let isDraggingRow = draggingWorkspaceId == workspace.id
                        WorkspaceRowView(workspace: workspace, group: group)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: WorkspaceRowFrameKey.self,
                                        value: [workspace.id: geo.frame(in: .named("sidebarList"))]
                                    )
                                }
                            )
                            .zIndex(isDraggingRow ? 50 : 0)
                            .scaleEffect(isDraggingRow ? 1.02 : 1.0, anchor: .center)
                            .shadow(
                                color: isDraggingRow ? .black.opacity(0.25) : .clear,
                                radius: 10, y: 4
                            )
                            .offset(y: workspaceRowYOffset(workspace.id))
                            .animation(slideAnimation, value: draggingWorkspaceId)
                            .animation(slideAnimation, value: proposedWorkspaceFlatInsert)
                            .simultaneousGesture(workspaceDragGesture(workspace, index))
                    }
                }
                .padding(.bottom, group.isImplicit ? 0 : GroupChrome.expandedBottomPadding)
                .transition(.opacity)
            }

            if !group.isImplicit, showsBottomDivider {
                Rectangle()
                    .fill(t.border.opacity(0.95))
                    .frame(height: 1)
            }
        }
        .background {
            if isGroupReorderDragging {
                Rectangle()
                    .fill(t.surface.opacity(0.72))
                    .overlay(
                        Rectangle()
                            .strokeBorder(t.border.opacity(0.45), lineWidth: 1)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isGroupReorderDragging)
    }

    @ViewBuilder
    private var headerWithOptionalGroupDrag: some View {
        if let groupReorderGesture {
            groupHeader.simultaneousGesture(groupReorderGesture)
        } else {
            groupHeader
        }
    }

    // MARK: - Header

    private var groupHeader: some View {
        HStack(alignment: .center, spacing: 6) {
            if isRenamingGroup {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(t.textFaint)
                    .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                    .frame(width: 14, height: 14)

                TextField(
                    "",
                    text: Binding(
                        get: { newGroupName },
                        set: { newGroupName = $0.uppercased() }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(t.textMuted)
                .tracking(0.5)
                .focused($groupNameFocused)
                .onSubmit { commitGroupRename() }
                .onExitCommand { cancelGroupRename() }
                .onChange(of: groupNameFocused) { _, focused in
                    guard !focused else { return }
                    DispatchQueue.main.async {
                        guard appState.editingGroupId == group.id else { return }
                        commitGroupRename()
                    }
                }

                Spacer(minLength: 0)
            } else {
                Button {
                    guard !suppressHeaderCollapse else { return }
                    withAnimation(collapseToggleAnimation) {
                        group.isCollapsed.toggle()
                        appState.schedulePersist()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(hoverChevron ? t.textMuted : t.textFaint)
                            .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                            .frame(width: 18, height: 18)
                            .background(hoverChevron ? t.selected.opacity(0.35) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onHover { hoverChevron = $0 }

                        Text(group.name.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isHoveringHeader ? t.textMuted : t.textFaint)
                            .tracking(0.6)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity)
            }

            HStack(spacing: 4) {
                if !isRenamingGroup {
                    Button {
                        startGroupRename()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(hoverRenameGroup ? t.text : t.textFaint)
                            .frame(width: 20, height: 20)
                            .background(
                                (hoverRenameGroup && isHoveringHeader) ? t.selected.opacity(0.42) : t.hover
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .cursor(NSCursor.arrow)
                    .onHover { hoverRenameGroup = $0 }
                    .sidebarHoverTooltip(
                        "Rename group",
                        theme: t,
                        isPresented: $hoverRenameGroup,
                        horizontalAnchor: .trailing
                    )
                }

                Button {
                    let workspace = appState.addWorkspace(in: group, url: nil)
                    workspace.ensureHasTab()
                    appState.selectedWorkspaceId = workspace.id
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hoverAddWorkspace ? t.text : t.textFaint)
                        .frame(width: 20, height: 20)
                        .background(
                            (hoverAddWorkspace && isHoveringHeader) ? t.selected.opacity(0.42) : t.hover
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .cursor(NSCursor.arrow)
                .onHover { hoverAddWorkspace = $0 }
                .sidebarHoverTooltip(
                    "New workspace",
                    theme: t,
                    isPresented: $hoverAddWorkspace,
                    horizontalAnchor: .trailing
                )

                Button {
                    showDeleteGroupConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(hoverDeleteGroup ? t.text : t.textFaint)
                        .frame(width: 20, height: 20)
                        .background(
                            (hoverDeleteGroup && isHoveringHeader) ? t.selected.opacity(0.42) : t.hover
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .cursor(NSCursor.arrow)
                .onHover { hoverDeleteGroup = $0 }
                .sidebarHoverTooltip(
                    "Delete group",
                    theme: t,
                    isPresented: $hoverDeleteGroup,
                    horizontalAnchor: .trailing
                )
            }
            .opacity(isHoveringHeader ? 1 : 0.18)
            .allowsHitTesting(isHoveringHeader)
        }
        .frame(minHeight: 23)
        .padding(.leading, GroupChrome.edgeInset)
        .padding(.trailing, GroupChrome.edgeInset)
        .padding(.top, GroupChrome.headerTopPadding)
        .padding(.bottom, GroupChrome.headerBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: GroupHeaderFrameKey.self,
                    value: [group.id: geo.frame(in: .named("sidebarList"))]
                )
            }
        )
        .contentShape(Rectangle())
        .onHover { isHoveringHeader = $0 }
        .cursor(NSCursor.openHand)
        .confirmationDialog(
            "Delete “\(group.name)”?",
            isPresented: $showDeleteGroupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                for workspace in group.workspaces {
                    workspace.teardown()
                }
                appState.groups.removeAll { $0.id == group.id }
                appState.schedulePersist()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the group and all workspaces inside it.")
        }
        .releaseSafeContextMenu {
            Button {
                startGroupRename()
            } label: {
                Label("Rename Group", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteGroupConfirmation = true
            } label: {
                Label("Delete Group", systemImage: "trash")
            }
        }
        .onChange(of: isRenamingGroup) { _, renaming in
            if renaming {
                DispatchQueue.main.async { groupNameFocused = true }
            }
        }
    }

    // MARK: - Group rename

    private func startGroupRename() {
        newGroupName = group.name.uppercased()
        appState.editingGroupId = group.id
    }

    private func commitGroupRename() {
        guard appState.editingGroupId == group.id else { return }
        let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { group.name = trimmed.uppercased() }
        appState.editingGroupId = nil
        groupNameFocused = false
    }

    private func cancelGroupRename() {
        appState.editingGroupId = nil
        groupNameFocused = false
    }
}
