import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GroupRowView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme
    @Bindable var group: WorkspaceGroup

    /// When true, ignore the next collapse toggle (after a group reorder drag).
    var suppressHeaderCollapse: Bool = false

    @State private var newGroupName = ""
    @State private var isHoveringHeader = false
    @State private var hoverChevron = false
    @State private var hoverAddWorkspace = false
    @State private var hoverRenameGroup = false
    @State private var hoverDeleteGroup = false
    @State private var showDeleteGroupConfirmation = false
    @State private var draggingWorkspaceId: UUID?
    @State private var dragStartIndex: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var proposedWorkspaceIndex: Int?
    @FocusState private var groupNameFocused: Bool

    private var rowH: CGFloat { WorkspaceRowView.sidebarSlotHeight }
    private let slideAnimation = Animation.spring(response: 0.25, dampingFraction: 0.82)
    private let settleAnimation = Animation.spring(response: 0.32, dampingFraction: 0.8)
    private let collapseToggleAnimation = Animation.easeInOut(duration: 0.2)

    var isRenamingGroup: Bool { appState.editingGroupId == group.id }

    private var t: AppTheme { theme.current }

    var body: some View {
        VStack(spacing: 0) {
            if !group.isImplicit {
                groupHeader
                    .animation(.easeInOut(duration: 0.12), value: isHoveringHeader)
            }

            if !group.isCollapsed {
                VStack(spacing: 0) {
                    ForEach(Array(group.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        WorkspaceRowView(workspace: workspace, group: group)
                            .zIndex(draggingWorkspaceId == workspace.id ? 1 : 0)
                            .scaleEffect(draggingWorkspaceId == workspace.id ? 1.02 : 1.0, anchor: .center)
                            .shadow(
                                color: draggingWorkspaceId == workspace.id ? .black.opacity(0.25) : .clear,
                                radius: 10, y: 4
                            )
                            .offset(y: workspaceOffset(for: workspace, at: index))
                            .animation(slideAnimation, value: proposedWorkspaceIndex)
                            .animation(slideAnimation, value: draggingWorkspaceId)
                            .simultaneousGesture(workspaceDragGesture(for: workspace, at: index))
                    }
                }
                .clipped()
                .transition(.opacity)
            }
        }
    }

    // MARK: - Workspace offset

    private func workspaceOffset(for workspace: Workspace, at index: Int) -> CGFloat {
        guard let draggedIdx = dragStartIndex,
              let proposed = proposedWorkspaceIndex
        else { return 0 }
        if workspace.id == draggingWorkspaceId { return dragTranslation }
        if draggedIdx < proposed {
            if index > draggedIdx && index <= proposed { return -rowH }
        } else if draggedIdx > proposed {
            if index >= proposed && index < draggedIdx { return rowH }
        }
        return 0
    }

    // MARK: - Workspace drag gesture

    private func workspaceDragGesture(for workspace: Workspace, at startIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if draggingWorkspaceId == nil {
                    draggingWorkspaceId = workspace.id
                    dragStartIndex = startIndex
                }
                dragTranslation = value.translation.height
                let steps = Int(round(dragTranslation / rowH))
                let clamped = max(0, min(group.workspaces.count - 1, startIndex + steps))
                withAnimation(slideAnimation) {
                    proposedWorkspaceIndex = clamped
                }
            }
            .onEnded { _ in
                if let from = dragStartIndex, let to = proposedWorkspaceIndex, from != to {
                    withAnimation(settleAnimation) {
                        group.workspaces.move(fromOffsets: IndexSet(integer: from),
                                             toOffset: to > from ? to + 1 : to)
                    }
                }
                draggingWorkspaceId = nil
                dragStartIndex = nil
                dragTranslation = 0
                proposedWorkspaceIndex = nil
            }
    }

    // MARK: - Header

    private var groupHeader: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isHoveringHeader ? t.hover : Color.clear)
                .animation(.easeInOut(duration: 0.12), value: isHoveringHeader)

            HStack(alignment: .center, spacing: 6) {
                if isRenamingGroup {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(t.textFaint)
                        .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                        .frame(width: 20, height: 20)

                    TextField("", text: Binding(
                        get: { newGroupName },
                        set: { newGroupName = $0.uppercased() }
                    ))
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
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(t.textFaint)
                                .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                                .frame(width: 20, height: 20)
                                .background(
                                    hoverChevron ? t.selected.opacity(0.35) : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .onHover { hoverChevron = $0 }

                            Text(group.name.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(t.textFaint)
                                .tracking(0.5)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)

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
                                .foregroundStyle(t.textMuted)
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
                            .foregroundStyle(t.textMuted)
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
                            .foregroundStyle(t.textMuted)
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
                .frame(height: 24)
                .frame(maxHeight: .infinity)
                .opacity(isHoveringHeader ? 1 : 0)
                .allowsHitTesting(isHoveringHeader)
            }
            .frame(minHeight: 28)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { isHoveringHeader = $0 }
        .cursor(NSCursor.openHand)
        .padding(.top, 16)
        .padding(.bottom, 0)
        .confirmationDialog(
            "Delete “\(group.name)”?",
            isPresented: $showDeleteGroupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                appState.groups.removeAll { $0.id == group.id }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the group and all workspaces inside it.")
        }
        .contextMenu {
            Button("Rename Group") { startGroupRename() }
            Divider()
            Button("Delete Group", role: .destructive) {
                showDeleteGroupConfirmation = true
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
