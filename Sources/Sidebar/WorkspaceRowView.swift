import SwiftUI

struct WorkspaceRowView: View {
    @Environment(AppState.self) var appState
    @ObservedObject var workspace: Workspace
    let group: WorkspaceGroup

    @State private var newName = ""
    @State private var isHovered = false
    @FocusState private var renameFieldFocused: Bool

    var isSelected: Bool { appState.selectedWorkspaceId == workspace.id }
    var isRenaming: Bool { appState.editingWorkspaceId == workspace.id }

    var body: some View {
        Button {
            appState.selectWorkspace(workspace.id)
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .contextMenu { contextMenuItems }
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { startRename() }
        )
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isRenaming)
    }

    // MARK: - Row content

    private var rowContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .padding(.leading, 4)

            if isRenaming {
                TextField("", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.muxText)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(workspace.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.muxText : Color.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        // Focus the field on next runloop tick so the view is in the hierarchy
        .onChange(of: isRenaming) { _, renaming in
            if renaming {
                DispatchQueue.main.async { renameFieldFocused = true }
            }
        }
    }

    private var rowBackground: some View {
        Group {
            if isRenaming {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.muxSelected)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.muxAccent.opacity(0.45), lineWidth: 1)
                    )
            } else if isSelected {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.muxSelected)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
            } else if isHovered {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.muxHover)
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Rename") { startRename() }

        if appState.groups.count > 1 {
            Menu("Move to Group") {
                ForEach(appState.groups.filter { $0.id != group.id }) { targetGroup in
                    Button(targetGroup.name) { moveWorkspace(to: targetGroup) }
                }
            }
        }

        Divider()

        Button("Close Workspace", role: .destructive) {
            appState.removeWorkspace(workspace, from: group)
        }
    }

    // MARK: - Helpers

    private var dotColor: Color {
        let palette: [Color] = [
            Color(red: 0.40, green: 0.60, blue: 1.00),
            Color(red: 0.35, green: 0.85, blue: 0.60),
            Color(red: 1.00, green: 0.55, blue: 0.35),
            Color(red: 0.78, green: 0.47, blue: 1.00),
            Color(red: 1.00, green: 0.80, blue: 0.28),
            Color(red: 0.28, green: 0.86, blue: 1.00),
        ]
        return palette[abs(workspace.id.hashValue) % palette.count]
    }

    private func startRename() {
        newName = workspace.name
        appState.editingWorkspaceId = workspace.id
    }

    private func commitRename() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { workspace.name = trimmed }
        appState.editingWorkspaceId = nil
        renameFieldFocused = false
    }

    private func cancelRename() {
        appState.editingWorkspaceId = nil
        renameFieldFocused = false
    }

    private func moveWorkspace(to targetGroup: WorkspaceGroup) {
        group.workspaces.removeAll { $0.id == workspace.id }
        targetGroup.workspaces.append(workspace)
    }
}
