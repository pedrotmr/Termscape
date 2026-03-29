import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme
    @State private var isAppearanceHovered = false
    @State private var isAddHovered = false
    @State private var showAddPopover = false
    @State private var showSettings = false
    @State private var draggedGroupId: UUID?
    @State private var dropTargetGroupId: UUID?

    private var t: AppTheme { theme.current }

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
                        onOpenProject: {
                            openProjectAction()
                            showAddPopover = false
                        },
                        onCloneFromURL: {
                            cloneFromURLAction()
                            showAddPopover = false
                        },
                        onNewGroup: {
                            createGroupAction()
                            showAddPopover = false
                        }
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

    // MARK: - Group drop indicator

    @ViewBuilder
    private func groupDropIndicator(for group: WorkspaceGroup) -> some View {
        if dropTargetGroupId == group.id && draggedGroupId != group.id && !group.isImplicit {
            Capsule()
                .fill(t.accent)
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

    private func openProjectAction() {
        appState.openFolder()
    }

    private func cloneFromURLAction() {
        appState.showCloneSheet = true
    }

    private func createGroupAction() {
        let group = WorkspaceGroup(name: "NEW GROUP", isImplicit: false)
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
    let onOpenProject: () -> Void
    let onCloneFromURL: () -> Void
    let onNewGroup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AddActionsRow(systemImage: "folder.badge.plus", title: "Open Project", theme: theme, action: onOpenProject)
            divider
            AddActionsRow(systemImage: "arrow.down.to.line", title: "Clone from URL", theme: theme, action: onCloneFromURL)
            divider
            AddActionsRow(systemImage: "rectangle.3.group", title: "New Group", theme: theme, action: onNewGroup)
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
