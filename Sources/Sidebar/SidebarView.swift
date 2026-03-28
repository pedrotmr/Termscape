import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @State private var isAddHovered = false

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Title bar clearance — pushes content below macOS traffic light buttons.
            // Standard hidden-title-bar height on macOS is 28pt.
            Color.clear.frame(height: 28)

            // Workspace list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(appState.groups) { group in
                        GroupRowView(group: group)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)

            // Footer
            Rectangle()
                .fill(Color.muxBorder)
                .frame(height: 1)

            HStack(spacing: 2) {
                Spacer()

                Menu {
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
                        let group = WorkspaceGroup(name: "New Group")
                        appState.groups.append(group)
                    } label: {
                        Label("New Group", systemImage: "rectangle.3.group")
                    }
                } label: {
                    SidebarMenuButton(isHovered: isAddHovered)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .onHover { isAddHovered = $0 }
                .animation(.easeInOut(duration: 0.12), value: isAddHovered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color.muxSidebar)
        .contextMenu {
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
                let group = WorkspaceGroup(name: "New Group")
                appState.groups.append(group)
            } label: {
                Label("New Group", systemImage: "rectangle.3.group")
            }
        }
        .sheet(isPresented: $appState.showCloneSheet) {
            CloneSheetView()
        }
    }
}

// MARK: - Footer menu button

private struct SidebarMenuButton: View {
    let isHovered: Bool

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(isHovered ? Color.white.opacity(0.75) : Color.muxTextMuted)
            .frame(width: 30, height: 30)
            .background(isHovered ? Color.white.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .help("Open project, clone from URL, or create group")
    }
}

// MARK: - Clone sheet

struct CloneSheetView: View {
    @Environment(AppState.self) var appState
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 5) {
                Text("Clone Repository")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.muxText)
                Text("Paste a git URL to clone into a new workspace")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muxTextMuted)
            }
            .padding(.bottom, 20)

            // URL field
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.muxTextFaint)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isFocused ? Color.muxAccent.opacity(0.55) : Color.muxBorder,
                            lineWidth: 1
                        )

                    TextField("https://github.com/owner/repo.git", text: $appState.cloneURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.muxText)
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
        .background(Color.muxElevated)
        .onAppear { isFocused = true }
    }

    private func clone() {
        appState.cloneRepository(urlString: appState.cloneURL)
    }
}
