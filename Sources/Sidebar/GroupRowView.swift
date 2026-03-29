import SwiftUI
import UniformTypeIdentifiers

struct GroupRowView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme
    @Bindable var group: WorkspaceGroup

    @State private var newGroupName = ""
    @State private var isHoveringHeader = false
    @State private var draggingWorkspaceId: UUID?
    @State private var dragStartIndex: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var proposedWorkspaceIndex: Int?
    @FocusState private var groupNameFocused: Bool

    private let rowH: CGFloat = 32
    private let slideAnimation = Animation.spring(response: 0.25, dampingFraction: 0.82)
    private let settleAnimation = Animation.spring(response: 0.32, dampingFraction: 0.8)

    var isRenamingGroup: Bool { appState.editingGroupId == group.id }

    private var t: AppTheme { theme.current }

    var body: some View {
        VStack(spacing: 0) {
            if !group.isImplicit {
                groupHeader
                    .onHover { isHoveringHeader = $0 }
                    .animation(.easeInOut(duration: 0.12), value: isHoveringHeader)
            }

            if !group.isCollapsed {
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
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    group.isCollapsed.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(t.textFaint)
                    .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)

            if isRenamingGroup {
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
                        if !focused { commitGroupRename() }
                    }
            } else {
                Text(group.name.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(t.textFaint)
                    .tracking(0.5)
                    .lineLimit(1)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { startGroupRename() }
                    )
            }

            Spacer()

            // Add workspace button
            Button {
                let workspace = appState.addWorkspace(in: group, url: nil)
                workspace.ensureHasTab()
                appState.selectedWorkspaceId = workspace.id
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.textMuted)
                    .frame(width: 20, height: 20)
                    .background(t.hover)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Add Workspace")
            .opacity(isHoveringHeader ? 1 : 0)
            .allowsHitTesting(isHoveringHeader)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename Group") { startGroupRename() }
            Divider()
            Button("Delete Group", role: .destructive) {
                appState.groups.removeAll { $0.id == group.id }
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
