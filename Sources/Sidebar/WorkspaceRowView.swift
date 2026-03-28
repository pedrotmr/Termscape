import SwiftUI

struct WorkspaceRowView: View {
    @Environment(AppState.self) var appState
    @ObservedObject var workspace: Workspace
    let group: WorkspaceGroup

    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isHovered = false

    var isSelected: Bool { appState.selectedWorkspaceId == workspace.id }

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
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    // MARK: - Row content

    private var rowContent: some View {
        HStack(spacing: 8) {
            // Color dot indicator
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .padding(.leading, 4)

            if isRenaming {
                TextField("Workspace name", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.muxText)
                    .onSubmit { commitRename() }
                    .onExitCommand { isRenaming = false }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.muxText : Color.white.opacity(0.65))
                        .lineLimit(1)

                    if let url = workspace.rootURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.muxTextFaint)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
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
        Button("Rename") {
            newName = workspace.name
            isRenaming = true
        }

        if appState.groups.count > 1 {
            Menu("Move to Group") {
                ForEach(appState.groups.filter { $0.id != group.id }) { targetGroup in
                    Button(targetGroup.name) {
                        moveWorkspace(to: targetGroup)
                    }
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
            Color(red: 0.40, green: 0.60, blue: 1.00),  // blue
            Color(red: 0.35, green: 0.85, blue: 0.60),  // green
            Color(red: 1.00, green: 0.55, blue: 0.35),  // orange
            Color(red: 0.78, green: 0.47, blue: 1.00),  // purple
            Color(red: 1.00, green: 0.80, blue: 0.28),  // yellow
            Color(red: 0.28, green: 0.86, blue: 1.00),  // cyan
        ]
        let index = abs(workspace.id.hashValue) % palette.count
        return palette[index]
    }

    private func commitRename() {
        if !newName.isEmpty { workspace.name = newName }
        isRenaming = false
    }

    private func moveWorkspace(to targetGroup: WorkspaceGroup) {
        group.workspaces.removeAll { $0.id == workspace.id }
        targetGroup.workspaces.append(workspace)
    }
}
