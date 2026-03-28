import SwiftUI

struct GroupRowView: View {
    @Environment(AppState.self) var appState
    @Bindable var group: WorkspaceGroup

    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isHoveringHeader = false

    var body: some View {
        VStack(spacing: 0) {
            groupHeader
                .onHover { isHoveringHeader = $0 }
                .animation(.easeInOut(duration: 0.12), value: isHoveringHeader)

            if !group.isCollapsed {
                ForEach(group.workspaces) { workspace in
                    WorkspaceRowView(workspace: workspace, group: group)
                }
            }
        }
    }

    // MARK: - Header

    private var groupHeader: some View {
        HStack(spacing: 6) {
            // Collapse chevron
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
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

            // Group name
            if isRenaming {
                TextField("Group name", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.muxTextMuted)
                    .onSubmit {
                        group.name = newName.isEmpty ? group.name : newName
                        isRenaming = false
                    }
                    .onExitCommand { isRenaming = false }
            } else {
                Text(group.name.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.muxTextFaint)
                    .tracking(0.5)
                    .lineLimit(1)
            }

            Spacer()

            // Add workspace button — always in layout, visible on hover only (avoids layout shift)
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
            Button("Rename Group") {
                newName = group.name
                isRenaming = true
            }
            Divider()
            Button("Delete Group", role: .destructive) {
                appState.groups.removeAll { $0.id == group.id }
            }
        }
    }
}
