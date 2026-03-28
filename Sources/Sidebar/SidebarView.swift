import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @State private var isAddHovered = false
    @State private var draggedGroupId: UUID?
    @State private var dropTargetGroupId: UUID?

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            Color.clear.frame(height: 46)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(appState.groups) { group in
                        GroupRowView(group: group)
                            .opacity(draggedGroupId == group.id ? 0.38 : 1.0)
                            .scaleEffect(draggedGroupId == group.id ? 0.97 : 1.0, anchor: .center)
                            .overlay(alignment: .top) {
                                groupDropIndicator(for: group)
                            }
                            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: draggedGroupId)
                            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: dropTargetGroupId)
                            .onDrag {
                                guard !group.isImplicit else { return NSItemProvider() }
                                DispatchQueue.main.async { draggedGroupId = group.id }
                                return NSItemProvider(object: group.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                isTargeted: groupIsTargetedBinding(for: group)
                            ) { _ in
                                reorderGroup(droppingOnto: group)
                                return true
                            }
                    }
                }
                .padding(.bottom, 8)
                // Catch-all: drop landed in the scroll area but not on any group row.
                // Resets drag state so groups don't stay dimmed after a missed drop.
                .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                    resetGroupDrag()
                    return true
                }
            }
            .scrollIndicators(.never)

            // Footer
            Rectangle()
                .fill(Color.muxBorder)
                .frame(height: 1)

            HStack(spacing: 2) {
                Spacer()

                Menu {
                    addMenuItems
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
        .contextMenu { addMenuItems }
        .sheet(isPresented: $appState.showCloneSheet) {
            CloneSheetView()
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

    // MARK: - Group drop indicator

    @ViewBuilder
    private func groupDropIndicator(for group: WorkspaceGroup) -> some View {
        if dropTargetGroupId == group.id && draggedGroupId != group.id && !group.isImplicit {
            Capsule()
                .fill(Color.muxAccent)
                .frame(height: 2)
                .padding(.horizontal, 12)
                .offset(y: 1)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
        }
    }

    // MARK: - Group drag reorder

    private func groupIsTargetedBinding(for group: WorkspaceGroup) -> Binding<Bool> {
        Binding<Bool>(
            get: { dropTargetGroupId == group.id },
            set: { isTargeted in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    if isTargeted && !group.isImplicit {
                        dropTargetGroupId = group.id
                    } else if dropTargetGroupId == group.id {
                        dropTargetGroupId = nil
                    }
                }
            }
        )
    }

    private func resetGroupDrag() {
        draggedGroupId = nil
        dropTargetGroupId = nil
    }

    private func reorderGroup(droppingOnto target: WorkspaceGroup) {
        guard
            !target.isImplicit,
            let draggedId = draggedGroupId,
            draggedId != target.id,
            let from = appState.groups.firstIndex(where: { $0.id == draggedId }),
            let to = appState.groups.firstIndex(where: { $0.id == target.id })
        else {
            draggedGroupId = nil
            dropTargetGroupId = nil
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            appState.groups.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        draggedGroupId = nil
        dropTargetGroupId = nil
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
