import AppKit
import SwiftUI

struct WorkspaceDotColor: Identifiable {
    var id: String { hex }
    let name: String
    let hex: String

    static let palette: [WorkspaceDotColor] = [
        // Pinks & Purples
        .init(name: "Acai",               hex: "#70445d"),
        .init(name: "Fuchsia",            hex: "#e45da7"),
        .init(name: "Mauve",              hex: "#b86c7c"),
        // Reds
        .init(name: "Angular Red",        hex: "#dd0531"),
        .init(name: "Burgundy",           hex: "#a3323b"),
        // Browns
        .init(name: "Coffee",             hex: "#49312e"),
        .init(name: "Tobacco",            hex: "#8d5449"),
        .init(name: "Brick",              hex: "#c25537"),
        .init(name: "Svelte Orange",      hex: "#ff3d00"),
        .init(name: "Leopard",            hex: "#8a6c50"),
        // Warm Neutrals & Ambers
        .init(name: "Nude",               hex: "#c6b9ab"),
        .init(name: "Sand",               hex: "#bca386"),
        .init(name: "Caramel",            hex: "#e5b575"),
        .init(name: "Honey",              hex: "#e2b36f"),
        .init(name: "Ipanema Beige",      hex: "#f2eadc"),
        .init(name: "Moss",               hex: "#82724d"),
        // Yellows & Greens
        .init(name: "JavaScript Yellow",  hex: "#f9e64f"),
        .init(name: "Mint",               hex: "#8d9c81"),
        .init(name: "Forest",             hex: "#465243"),
        .init(name: "Node Green",         hex: "#215732"),
        .init(name: "Vue Green",          hex: "#42b883"),
        // Blues & Teals
        .init(name: "React Blue",         hex: "#61dafb"),
        .init(name: "Peacock",            hex: "#337295"),
        .init(name: "Azure Blue",         hex: "#007fff"),
        .init(name: "Mandalorian Blue",   hex: "#1857a4"),
    ]
}

struct WorkspaceRowView: View {
    /// Vertical extent of one workspace row in the sidebar list (including outer padding). Kept in sync with `GroupRowView` drag offsets.
    static let sidebarSlotHeight: CGFloat = 38

    private static let closeButtonWidth: CGFloat = 20
    private static let closeButtonLeadingGap: CGFloat = 6
    /// Extra trailing inset when the hover close control is visible (`closeButtonWidth` + gap to the label).
    private static var hoveredCloseReserveWidth: CGFloat { closeButtonWidth + closeButtonLeadingGap }
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme
    @ObservedObject var workspace: Workspace
    let group: WorkspaceGroup

    @State private var newName = ""
    @State private var isHovered = false
    @State private var hoverCloseWorkspace = false
    @FocusState private var renameFieldFocused: Bool

    private var t: AppTheme { theme.current }
    var isSelected: Bool { appState.selectedWorkspaceId == workspace.id }
    var isRenaming: Bool { appState.editingWorkspaceId == workspace.id }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                appState.selectWorkspace(workspace.id)
            } label: {
                rowContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovered && !isRenaming {
                Button {
                    appState.removeWorkspace(workspace, from: group)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(t.textMuted)
                        .frame(width: 20, height: 20)
                        .background(hoverCloseWorkspace ? t.selected.opacity(0.42) : t.hover)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .onHover { hoverCloseWorkspace = $0 }
                .sidebarHoverTooltip(
                    "Close workspace",
                    theme: t,
                    isPresented: $hoverCloseWorkspace,
                    horizontalAnchor: .trailing
                )
                .padding(.trailing, 10)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
                    .foregroundStyle(t.text)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .onChange(of: renameFieldFocused) { _, focused in
                        guard !focused else { return }
                        DispatchQueue.main.async {
                            guard appState.editingWorkspaceId == workspace.id else { return }
                            commitRename()
                        }
                    }
            } else {
                Text(workspace.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? t.text : t.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 10 + ((isHovered && !isRenaming) ? Self.hoveredCloseReserveWidth : 0))
        .padding(.trailing, 10 + ((isHovered && !isRenaming) ? Self.hoveredCloseReserveWidth : 0))
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
                    .fill(t.selected)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(t.accent.opacity(0.45), lineWidth: 1)
                    )
            } else if isSelected {
                RoundedRectangle(cornerRadius: 7)
                    .fill(t.selected)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(t.border, lineWidth: 1)
                    )
            } else if isHovered {
                RoundedRectangle(cornerRadius: 7)
                    .fill(t.hover)
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Rename") { startRename() }

        Menu("Change Color") {
            ForEach(WorkspaceDotColor.palette) { dotColor in
                Button {
                    workspace.color = dotColor.hex
                    appState.persist()
                } label: {
                    Label {
                        Text(dotColor.name)
                    } icon: {
                        Image(nsImage: colorDotNSImage(hex: dotColor.hex))
                    }
                }
            }
        }

        Divider()

        let currentIndex = group.workspaces.firstIndex(where: { $0.id == workspace.id })
        let isFirstWorkspace = currentIndex.map { $0 == 0 } ?? true
        let isLastWorkspace = currentIndex.map { $0 == group.workspaces.count - 1 } ?? true

        Button("Move Up") {
            if let idx = currentIndex, idx > 0 {
                group.workspaces.swapAt(idx, idx - 1)
                appState.persist()
            }
        }
        .disabled(isFirstWorkspace)

        Button("Move Down") {
            if let idx = currentIndex, idx < group.workspaces.count - 1 {
                group.workspaces.swapAt(idx, idx + 1)
                appState.persist()
            }
        }
        .disabled(isLastWorkspace)

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
        if let hex = workspace.color {
            return Color(hex: hex)
        }
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
        guard appState.editingWorkspaceId == workspace.id else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { workspace.name = trimmed }
        appState.editingWorkspaceId = nil
        renameFieldFocused = false
    }

    private func cancelRename() {
        appState.editingWorkspaceId = nil
        renameFieldFocused = false
    }

    private static var colorDotCache: [String: NSImage] = [:]

    private func colorDotNSImage(hex: String) -> NSImage {
        if let cached = Self.colorDotCache[hex] { return cached }
        let nsColor = NSColor(Color(hex: hex))
        let size = CGSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        Self.colorDotCache[hex] = image
        return image
    }

    private func moveWorkspace(to targetGroup: WorkspaceGroup) {
        group.workspaces.removeAll { $0.id == workspace.id }
        targetGroup.workspaces.append(workspace)
        appState.persist()
    }
}
