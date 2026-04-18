import Bonsplit
import SwiftUI

struct TabBarView: View {
  @Environment(ThemeManager.self) var theme
  @ObservedObject var workspace: Workspace
  @State private var editingTabId: UUID?

  private var t: AppTheme {
    theme.current
  }

  var body: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 1) {
          ForEach(workspace.tabs) { tab in
            TabItemView(
              tab: tab,
              isSelected: workspace.selectedTabId == tab.id,
              editingTabId: $editingTabId,
              onSelect: { workspace.selectTab(tab.id) },
              onClose: { workspace.closeTab(tab.id) },
              onTogglePin: { workspace.togglePin(tab.id) }
            )
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
      }

      separator

      // New tab button
      TabBarIconButton(systemImage: "terminal", help: "New Terminal Tab (⌘T)", theme: t) {
        _ = workspace.addTab()
      }

      TabBarIconButton(systemImage: "globe", help: "New Browser Tab", theme: t) {
        NotificationCenter.default.post(name: .newBrowserTab, object: nil)
      }

      TabBarIconButton(
        systemImage: "chevron.left.forwardslash.chevron.right",
        help: "New Editor Tab",
        theme: t
      ) {
        let pathKey = Notification.Name.MoveToNewTabKey.editorRootPath
        guard let sourceTab = workspace.selectedTab else { return }
        let snapshot = sourceTab.bonsplitController.layoutSnapshot()
        let root = sourceTab.resolveEditorRootFromFocusedContext(
          targetPaneId: sourceTab.bonsplitController.focusedPaneId,
          snapshot: snapshot
        )
        NotificationCenter.default.post(
          name: .newEditorTab,
          object: nil,
          userInfo: [pathKey: root]
        )
      }

      // Split pane buttons
      TabBarIconButton(systemImage: "square.split.2x1", help: "Split Terminal Right (⌘D)", theme: t)
      {
        NotificationCenter.default.post(name: .splitRight, object: nil)
      }
      TabBarIconButton(systemImage: "square.split.1x2", help: "Split Terminal Down (⌘⇧D)", theme: t)
      {
        NotificationCenter.default.post(name: .splitDown, object: nil)
      }
      .padding(.trailing, 6)
    }
    .frame(height: 38)
    .background(t.surface)
    .zIndex(50)
    .overlay(alignment: .bottom) {
      Rectangle().fill(t.border).frame(height: 1)
    }
  }

  private var separator: some View {
    Rectangle()
      .fill(t.border)
      .frame(width: 1, height: 16)
      .padding(.horizontal, 3)
  }
}

// MARK: - Tab item

struct TabItemView: View {
  @Environment(ThemeManager.self) var theme
  @ObservedObject var tab: WorkspaceTab
  let isSelected: Bool
  @Binding var editingTabId: UUID?
  let onSelect: () -> Void
  let onClose: () -> Void
  let onTogglePin: () -> Void

  @State private var isHovered = false
  @State private var renameText = ""
  @FocusState private var isRenameFocused: Bool

  private var t: AppTheme {
    theme.current
  }

  private var isRenaming: Bool {
    editingTabId == tab.id
  }

  var body: some View {
    HStack(spacing: 5) {
      if tab.isPinned {
        Image(systemName: "pin.fill")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(t.accent.opacity(0.8))
      } else {
        let kind = tab.focusedPaneContentKind(snapshot: tab.bonsplitController.layoutSnapshot())
        Image(systemName: kind.defaultIcon)
          .font(.system(size: 10))
          .foregroundStyle(isSelected ? t.text.opacity(0.7) : t.textFaint)
      }

      if isRenaming {
        TextField("", text: $renameText)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(t.text)
          .frame(maxWidth: 110)
          .textFieldStyle(.plain)
          .focused($isRenameFocused)
          .onSubmit { commitRename() }
          .onExitCommand { cancelRename() }
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(t.accent.opacity(0.6), lineWidth: 1)
              .padding(.horizontal, -4)
          )
      } else {
        Text(tab.title)
          .font(.system(size: 12, weight: isSelected ? .medium : .regular))
          .foregroundStyle(isSelected ? t.text : t.textMuted)
          .lineLimit(1)
          .frame(maxWidth: 110, alignment: .leading)
      }

      if tab.isPinned {
        // Pinned tabs: no close button, pin icon already shown on left
        // Show unpin affordance on hover
        if isHovered {
          Button(action: onTogglePin) {
            Image(systemName: "pin.slash")
              .font(.system(size: 8.5, weight: .semibold))
              .foregroundStyle(Color.white.opacity(0.45))
              .frame(width: 14, height: 14)
              .background(Color.white.opacity(0.07))
              .clipShape(RoundedRectangle(cornerRadius: 3))
          }
          .buttonStyle(.plain)
          .help("Unpin Tab")
        } else {
          Color.clear.frame(width: 14, height: 14)
        }
      } else {
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(t.textMuted)
            .frame(width: 14, height: 14)
            .background(isHovered ? t.hover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .opacity((isHovered || isSelected) ? 1 : 0)
        .help("Close Tab")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(tabBackground)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .contentShape(Rectangle())
    .onTapGesture { onSelect() }
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        beginRename()
      }
    )
    .onHover { isHovered = $0 }
    .animation(.easeInOut(duration: 0.12), value: isHovered)
    .overlay(alignment: .bottom) {
      if isSelected {
        RoundedRectangle(cornerRadius: 1)
          .fill(t.accent)
          .frame(height: 2)
          .padding(.horizontal, 8)
      }
    }
    .onChange(of: isRenaming) { renaming in
      if renaming {
        isRenameFocused = true
        DispatchQueue.main.async {
          NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSResponder.selectAll(_:)), with: nil
          )
        }
      }
    }
    .onChange(of: isRenameFocused) { focused in
      if !focused { commitRename() }
    }
    .contextMenu {
      Button {
        beginRename()
      } label: {
        Label("Rename", systemImage: "pencil")
      }
      Button {
        onTogglePin()
      } label: {
        Label(
          tab.isPinned ? "Unpin Tab" : "Pin Tab",
          systemImage: tab.isPinned ? "pin.slash" : "pin"
        )
      }
      Divider()
      Button(role: .destructive) {
        onClose()
      } label: {
        Label("Close Tab", systemImage: "xmark")
      }
      .disabled(tab.isPinned)
    }
  }

  @ViewBuilder
  private var tabBackground: some View {
    if isSelected {
      t.selected
    } else if isHovered {
      t.hover
    } else {
      Color.clear
    }
  }

  private func commitRename() {
    guard isRenaming else { return }
    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty {
      tab.title = trimmed
      NotificationCenter.default.post(name: .workspacePersistenceNeeded, object: nil)
    }
    editingTabId = nil
  }

  private func cancelRename() {
    editingTabId = nil
  }

  private func beginRename() {
    renameText = tab.title
    editingTabId = tab.id
  }
}

// MARK: - Icon button

private struct TabBarIconButton: View {
  let systemImage: String
  let help: String
  let theme: AppTheme
  let action: () -> Void

  @State private var isHovered = false
  @State private var tooltipVisible = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(isHovered ? theme.text : theme.textMuted)
        .frame(width: 28, height: 28)
        .background(isHovered ? theme.hover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
    .buttonStyle(.plain)
    .help(help)
    .overlay(alignment: .bottomTrailing) {
      if tooltipVisible {
        Text(help)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(theme.text)
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(theme.elevated)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(theme.border, lineWidth: 1)
          )
          .fixedSize(horizontal: true, vertical: true)
          .lineLimit(1)
          .offset(y: 30)
          .allowsHitTesting(false)
          .zIndex(1000)
      }
    }
    .zIndex(tooltipVisible ? 1000 : 0)
    .onHover { hovering in
      isHovered = hovering
      if hovering {
        tooltipVisible = true
      } else {
        tooltipVisible = false
      }
    }
    .animation(.easeInOut(duration: 0.12), value: isHovered)
  }
}
