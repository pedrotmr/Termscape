import SwiftUI
import UniformTypeIdentifiers

struct GroupRowView: View {
    @Environment(AppState.self) var appState
    @Bindable var group: WorkspaceGroup

    @State private var newGroupName = ""
    @State private var isHoveringHeader = false
    @State private var draggedWorkspaceId: UUID?
    @State private var dropTargetWorkspaceId: UUID?
    @FocusState private var groupNameFocused: Bool

    var isRenamingGroup: Bool { appState.editingGroupId == group.id }

    var body: some View {
        VStack(spacing: 0) {
            if !group.isImplicit {
                groupHeader
                    .onHover { isHoveringHeader = $0 }
                    .animation(.easeInOut(duration: 0.12), value: isHoveringHeader)
            }

            if !group.isCollapsed {
                ForEach(group.workspaces) { workspace in
                    WorkspaceRowView(workspace: workspace, group: group)
                        .opacity(draggedWorkspaceId == workspace.id ? 0.38 : 1.0)
                        .scaleEffect(draggedWorkspaceId == workspace.id ? 0.97 : 1.0, anchor: .center)
                        .overlay(alignment: .top) {
                            dropIndicator(for: workspace)
                        }
                        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: draggedWorkspaceId)
                        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: dropTargetWorkspaceId)
                        .onDrag {
                            DispatchQueue.main.async { draggedWorkspaceId = workspace.id }
                            return NSItemProvider(object: workspace.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            isTargeted: isTargetedBinding(for: workspace)
                        ) { _ in
                            reorderWorkspace(droppingOnto: workspace)
                            return true
                        }
                }
            }
        }
        // Catch-all: drop landed within the group but not on any workspace row
        // (e.g. in a gap or on the header). Resets drag state so rows don't
        // stay dimmed. Drops outside the sidebar cannot be caught by SwiftUI.
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
            resetWorkspaceDrag()
            return true
        }
    }

    // MARK: - Drop indicator

    @ViewBuilder
    private func dropIndicator(for workspace: Workspace) -> some View {
        if dropTargetWorkspaceId == workspace.id && draggedWorkspaceId != workspace.id {
            Capsule()
                .fill(Color.muxAccent)
                .frame(height: 2)
                .padding(.horizontal, 12)
                .offset(y: 1)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
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
                    .foregroundStyle(Color.muxTextFaint)
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
                    .foregroundStyle(Color.muxTextMuted)
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
                    .foregroundStyle(Color.muxTextFaint)
                    .tracking(0.5)
                    .lineLimit(1)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { startGroupRename() }
                    )
            }

            Spacer()

            Button {
                let workspace = appState.addWorkspace(in: group, url: nil)
                workspace.ensureHasTab()
                appState.selectedWorkspaceId = workspace.id
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.muxTextMuted)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.06))
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

    // MARK: - Workspace drag reorder

    private func isTargetedBinding(for workspace: Workspace) -> Binding<Bool> {
        Binding<Bool>(
            get: { dropTargetWorkspaceId == workspace.id },
            set: { isTargeted in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    if isTargeted {
                        dropTargetWorkspaceId = workspace.id
                    } else if dropTargetWorkspaceId == workspace.id {
                        dropTargetWorkspaceId = nil
                    }
                }
            }
        )
    }

    private func resetWorkspaceDrag() {
        draggedWorkspaceId = nil
        dropTargetWorkspaceId = nil
    }

    private func reorderWorkspace(droppingOnto target: Workspace) {
        guard
            let draggedId = draggedWorkspaceId,
            draggedId != target.id,
            let from = group.workspaces.firstIndex(where: { $0.id == draggedId }),
            let to = group.workspaces.firstIndex(where: { $0.id == target.id })
        else {
            draggedWorkspaceId = nil
            dropTargetWorkspaceId = nil
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            group.workspaces.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        draggedWorkspaceId = nil
        dropTargetWorkspaceId = nil
    }
}
