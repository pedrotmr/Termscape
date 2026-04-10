import SwiftUI
import UniformTypeIdentifiers

private struct GroupFrameKey: PreferenceKey {
  static var defaultValue: [UUID: CGRect] = [:]
  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

struct SidebarView: View {
  @Environment(AppState.self) var appState
  @Environment(ThemeManager.self) var theme
  @State private var isAppearanceHovered = false
  @State private var isAddHovered = false
  @State private var showAddPopover = false
  @State private var showSettings = false
  @State private var draggingGroupId: UUID?
  @State private var groupDragStartIndex: Int?
  @State private var groupDragTranslation: CGFloat = 0
  @State private var proposedGroupIndex: Int?
  @State private var groupFrames: [UUID: CGRect] = [:]
  @State private var groupHeaderFrames: [UUID: CGRect] = [:]
  @State private var workspaceRowFrames: [UUID: CGRect] = [:]
  /// When set, the matching group's header collapse action is skipped (e.g. after a reorder drag).
  @State private var groupIdToSuppressHeaderCollapse: UUID?

  @State private var draggingWorkspaceId: UUID?
  @State private var workspaceDragSourceGroupId: UUID?
  @State private var workspaceDragFromIndex: Int?
  @State private var workspaceDragTranslation: CGFloat = 0
  @State private var workspaceDragStartMidY: CGFloat = 0
  @State private var proposedWorkspaceDrop: WorkspaceDropTarget?
  @State private var workspaceDragStartFlatIndex: Int?
  @State private var proposedWorkspaceFlatInsert: Int?
  @State private var hoverExpandWorkItem: DispatchWorkItem?
  @State private var hoverExpandTargetGroupId: UUID?

  private static let newGroupName = "NEW GROUP"
  private static let collapsedGroupHoverExpandDelay: TimeInterval = 0.3
  private static let groupDragCollapseSuppressionThreshold: CGFloat = 5
  private var t: AppTheme { theme.current }
  private let slideAnimation = Animation.spring(response: 0.25, dampingFraction: 0.82)
  private let settleAnimation = Animation.spring(response: 0.32, dampingFraction: 0.8)

  var body: some View {
    @Bindable var appState = appState

    VStack(spacing: 0) {
      Color.clear.frame(height: 46)

      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(appState.groups.enumerated()), id: \.element.id) { index, group in
            sidebarGroupRow(group: group, index: index)
          }
        }
        .padding(.bottom, 8)
        .coordinateSpace(name: "sidebarList")
        .onPreferenceChange(GroupFrameKey.self) { groupFrames = $0 }
        .onPreferenceChange(GroupHeaderFrameKey.self) { groupHeaderFrames = $0 }
        .onPreferenceChange(WorkspaceRowFrameKey.self) { workspaceRowFrames = $0 }
      }
      .scrollIndicators(.never)
      .scrollClipDisabled(true)

      // Footer
      Rectangle()
        .fill(t.border)
        .frame(height: 1)

      HStack(spacing: 2) {
        Spacer()

        Button {
          showSettings = true
        } label: {
          SidebarIconGlyph(
            systemImage: "slider.horizontal.3", theme: t, isHovered: isAppearanceHovered)
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
            isPresented: $showAddPopover,
            onOpenWorkspace: openWorkspaceAction,
            onOpenProject: openProjectAction,
            onCloneFromURL: cloneFromURLAction,
            onNewGroup: createGroupAction
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

  private func sidebarGroupRow(group: WorkspaceGroup, index: Int) -> AnyView {
    let reorder: AnyGesture<DragGesture.Value>? =
      group.isImplicit
      ? nil
      : groupDragGesture(for: group, at: index)
    let row = GroupRowView(
      group: group,
      isGroupReorderDragging: draggingGroupId == group.id,
      suppressHeaderCollapse: groupIdToSuppressHeaderCollapse == group.id,
      groupReorderGesture: reorder,
      workspaceDragGesture: { w, rowIdx in
        workspaceDragGesture(group: group, workspace: w, rowIndex: rowIdx)
      },
      workspaceRowYOffset: { wid in
        workspaceRowYOffset(workspaceId: wid, group)
      },
      draggingWorkspaceId: draggingWorkspaceId,
      proposedWorkspaceDropTarget: proposedWorkspaceDrop,
      proposedWorkspaceFlatInsert: proposedWorkspaceFlatInsert
    )
    .background(
      GeometryReader { geo in
        Color.clear.preference(
          key: GroupFrameKey.self,
          value: [group.id: geo.frame(in: .named("sidebarList"))]
        )
      }
    )
    .zIndex(sidebarGroupRowZIndex(group: group))
    .scaleEffect(draggingGroupId == group.id ? 1.01 : 1.0, anchor: .center)
    .shadow(
      color: draggingGroupId == group.id ? .black.opacity(0.2) : .clear,
      radius: 8, y: 3
    )
    .offset(y: groupOffset(for: group, at: index))
    // Dragged row follows finger 1:1; spring here lags behind `groupDragTranslation`.
    .animation(
      draggingGroupId == group.id ? nil : slideAnimation, value: proposedGroupIndex
    )
    .animation(
      draggingGroupId == group.id ? nil : slideAnimation, value: draggingGroupId
    )
    .animation(
      draggingGroupId == group.id ? nil : slideAnimation, value: groupDragTranslation)
    return AnyView(row)
  }

  @ViewBuilder
  private var addMenuItems: some View {
    Button {
      openWorkspaceAction()
    } label: {
      Label("Open Workspace", systemImage: "plus.square.on.square")
    }
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

  private func sidebarGroupRowZIndex(group: WorkspaceGroup) -> Double {
    if let wid = draggingWorkspaceId, group.workspaces.contains(where: { $0.id == wid }) {
      return 2
    }
    if draggingGroupId == group.id { return 1 }
    return 0
  }

  // MARK: - Group offset

  private func groupOffset(for group: WorkspaceGroup, at index: Int) -> CGFloat {
    guard let draggingId = draggingGroupId,
      let draggedIdx = groupDragStartIndex,
      let proposed = proposedGroupIndex
    else { return 0 }
    if group.id == draggingId { return groupDragTranslation }
    let draggedH = groupFrames[draggingId]?.height ?? 44
    if draggedIdx < proposed {
      if index > draggedIdx && index <= proposed { return -draggedH }
    } else if draggedIdx > proposed {
      if index >= proposed && index < draggedIdx { return draggedH }
    }
    return 0
  }

  // MARK: - Group drag gesture

  private func groupDragGesture(for group: WorkspaceGroup, at startIndex: Int) -> AnyGesture<
    DragGesture.Value
  > {
    AnyGesture(
      // List coordinate space: local space moves with `.offset`, which would under-report translation.
      DragGesture(minimumDistance: 3, coordinateSpace: .named("sidebarList"))
        .onChanged { value in
          if draggingGroupId == nil {
            draggingGroupId = group.id
            groupDragStartIndex = startIndex
          }
          groupDragTranslation = value.translation.height
          if abs(value.translation.height) > Self.groupDragCollapseSuppressionThreshold {
            groupIdToSuppressHeaderCollapse = group.id
          }
          // Same coordinate space as the drag gesture — pointer Y, not row midY (avoids stale frame reads).
          let cursorY = value.location.y
          guard let dragIdx = appState.groups.firstIndex(where: { $0.id == group.id }) else {
            return
          }
          let target = proposedGroupArrayIndex(cursorY: cursorY, draggingArrayIndex: dragIdx)
          proposedGroupIndex = target
        }
        .onEnded { _ in
          if let from = groupDragStartIndex, var to = proposedGroupIndex, from != to {
            if let imp = appState.groups.firstIndex(where: { $0.isImplicit }) {
              to = max(to, imp + 1)
            }
            to = min(to, max(0, appState.groups.count - 1))
            guard from != to else {
              draggingGroupId = nil
              groupDragStartIndex = nil
              groupDragTranslation = 0
              proposedGroupIndex = nil
              DispatchQueue.main.async {
                groupIdToSuppressHeaderCollapse = nil
              }
              return
            }
            withAnimation(settleAnimation) {
              appState.groups.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to)
            }
          }
          draggingGroupId = nil
          groupDragStartIndex = nil
          groupDragTranslation = 0
          proposedGroupIndex = nil
          DispatchQueue.main.async {
            groupIdToSuppressHeaderCollapse = nil
          }
        }
    )
  }

  /// Target `groups` index from vertical position — uses gaps between group frames, not “nearest midY” (fixes last-group nudge-down reordering the stack).
  private func proposedGroupArrayIndex(cursorY: CGFloat, draggingArrayIndex: Int) -> Int {
    var entries: [(arrIdx: Int, frame: CGRect)] = []
    for (i, g) in appState.groups.enumerated() {
      guard let f = groupFrames[g.id] else { continue }
      entries.append((i, f))
    }
    entries.sort { $0.frame.minY < $1.frame.minY }
    let rest = entries.filter { $0.arrIdx != draggingArrayIndex }
    if rest.isEmpty { return draggingArrayIndex }

    let k: Int
    if cursorY < rest[0].frame.minY {
      k = 0
    } else {
      var insert = rest.count
      for i in 1..<rest.count {
        let midY = (rest[i - 1].frame.maxY + rest[i].frame.minY) / 2
        if cursorY < midY {
          insert = i
          break
        }
      }
      k = insert
    }

    var seq = rest.map(\.arrIdx)
    seq.insert(draggingArrayIndex, at: min(k, seq.count))
    guard let pos = seq.firstIndex(of: draggingArrayIndex) else { return draggingArrayIndex }
    var target = pos
    if let imp = appState.groups.firstIndex(where: { $0.isImplicit }),
      draggingArrayIndex < appState.groups.count,
      !appState.groups[draggingArrayIndex].isImplicit
    {
      target = max(target, imp + 1)
    }
    return min(max(0, target), appState.groups.count - 1)
  }

  // MARK: - Workspace drag (sidebar-wide)

  private func workspaceRowYOffset(workspaceId: UUID, _: WorkspaceGroup) -> CGFloat {
    let rowH = WorkspaceRowView.sidebarSlotHeight
    guard draggingWorkspaceId != workspaceId else {
      return workspaceDragTranslation
    }
    guard let dragId = draggingWorkspaceId,
      let fromFlat = workspaceDragStartFlatIndex,
      let toFlat = proposedWorkspaceFlatInsert
    else { return 0 }
    let rem = orderedWorkspaceSlots(excluding: dragId)
    guard let remIndex = rem.firstIndex(where: { $0.workspaceId == workspaceId }) else { return 0 }
    if fromFlat < toFlat {
      if remIndex >= fromFlat && remIndex < toFlat { return -rowH }
    } else if fromFlat > toFlat {
      if remIndex >= toFlat && remIndex < fromFlat { return rowH }
    }
    return 0
  }

  private func workspaceDragGesture(group: WorkspaceGroup, workspace: Workspace, rowIndex: Int)
    -> AnyGesture<DragGesture.Value>
  {
    AnyGesture(
      DragGesture(minimumDistance: 3)
        .onChanged { value in
          if draggingWorkspaceId == nil {
            draggingWorkspaceId = workspace.id
            workspaceDragSourceGroupId = group.id
            workspaceDragFromIndex = rowIndex
            workspaceDragStartMidY = workspaceRowFrames[workspace.id]?.midY ?? 0
            let full = fullOrderedWorkspaceSlots()
            workspaceDragStartFlatIndex =
              full.firstIndex(where: { $0.workspaceId == workspace.id })
              ?? modelFallbackFlatIndex(workspaceId: workspace.id)
          }
          workspaceDragTranslation = value.translation.height
          let cursorY =
            workspaceRowFrames[workspace.id].map { $0.midY }
            ?? (workspaceDragStartMidY + workspaceDragTranslation)
          updateProposedWorkspaceDrop(cursorY: cursorY)
          updateCollapsedGroupHoverExpand(cursorY: cursorY)
        }
        .onEnded { _ in
          resetCollapsedGroupHoverExpand()
          commitWorkspaceRelocateIfNeeded(workspaceId: workspace.id)
          clearWorkspaceDragState()
        }
    )
  }

  /// Visible workspace rows with layout frames, top-to-bottom (optionally excluding one id).
  private func orderedWorkspaceSlots(excluding excludeId: UUID?) -> [(
    groupId: UUID, indexInGroup: Int, workspaceId: UUID
  )] {
    var slots: [(groupId: UUID, indexInGroup: Int, workspaceId: UUID)] = []
    for g in appState.groups {
      guard !g.isCollapsed else { continue }
      for (i, ws) in g.workspaces.enumerated() {
        if ws.id == excludeId { continue }
        guard workspaceRowFrames[ws.id] != nil else { continue }
        slots.append((g.id, i, ws.id))
      }
    }
    return slots.sorted {
      (workspaceRowFrames[$0.workspaceId]?.minY ?? 0)
        < (workspaceRowFrames[$1.workspaceId]?.minY ?? 0)
    }
  }

  private func fullOrderedWorkspaceSlots() -> [(
    groupId: UUID, indexInGroup: Int, workspaceId: UUID
  )] {
    var slots: [(groupId: UUID, indexInGroup: Int, workspaceId: UUID)] = []
    for g in appState.groups {
      guard !g.isCollapsed else { continue }
      for (i, ws) in g.workspaces.enumerated() {
        guard workspaceRowFrames[ws.id] != nil else { continue }
        slots.append((g.id, i, ws.id))
      }
    }
    return slots.sorted {
      (workspaceRowFrames[$0.workspaceId]?.minY ?? 0)
        < (workspaceRowFrames[$1.workspaceId]?.minY ?? 0)
    }
  }

  private func modelFallbackFlatIndex(workspaceId: UUID) -> Int {
    var n = 0
    for g in appState.groups {
      guard !g.isCollapsed else { continue }
      for ws in g.workspaces {
        if ws.id == workspaceId { return n }
        n += 1
      }
    }
    return 0
  }

  /// `toFlat` from row midYs keeps sibling shifts responsive; drop target is refined at group boundaries so “after last in A” doesn’t become `(nextGroup, 0)`.
  private func updateProposedWorkspaceDrop(cursorY: CGFloat) {
    guard let draggingId = draggingWorkspaceId else { return }
    let rem = orderedWorkspaceSlots(excluding: draggingId)

    if rem.isEmpty {
      guard let sourceGid = workspaceDragSourceGroupId else { return }
      proposedWorkspaceFlatInsert = 0
      proposedWorkspaceDrop = WorkspaceDropTarget(groupId: sourceGid, index: 0)
      return
    }

    var toFlat = rem.count
    for i in 0..<rem.count {
      let rowMid = workspaceRowFrames[rem[i].workspaceId]?.midY ?? 0
      if cursorY < rowMid {
        toFlat = i
        break
      }
    }
    proposedWorkspaceFlatInsert = toFlat
    proposedWorkspaceDrop = workspaceDropTargetRefined(cursorY: cursorY, toFlat: toFlat, rem: rem)
  }

  private func workspaceDropTargetRefined(
    cursorY: CGFloat,
    toFlat: Int,
    rem: [(groupId: UUID, indexInGroup: Int, workspaceId: UUID)]
  ) -> WorkspaceDropTarget? {
    if rem.isEmpty {
      guard let sourceGid = workspaceDragSourceGroupId else { return nil }
      return WorkspaceDropTarget(groupId: sourceGid, index: 0)
    }
    if toFlat == 0 {
      return WorkspaceDropTarget(groupId: rem[0].groupId, index: rem[0].indexInGroup)
    }
    if toFlat >= rem.count {
      let last = rem[rem.count - 1]
      return WorkspaceDropTarget(groupId: last.groupId, index: last.indexInGroup + 1)
    }
    let prev = rem[toFlat - 1]
    let curr = rem[toFlat]
    if prev.groupId != curr.groupId {
      let pF = workspaceRowFrames[prev.workspaceId] ?? .zero
      let cF = workspaceRowFrames[curr.workspaceId] ?? .zero
      let gapMid = (pF.maxY + cF.minY) / 2
      if cursorY < gapMid {
        return WorkspaceDropTarget(groupId: prev.groupId, index: prev.indexInGroup + 1)
      }
    }
    return WorkspaceDropTarget(groupId: curr.groupId, index: curr.indexInGroup)
  }

  private func commitWorkspaceRelocateIfNeeded(workspaceId: UUID) {
    guard let sourceGid = workspaceDragSourceGroupId,
      let sourceGroup = appState.groups.first(where: { $0.id == sourceGid }),
      let freshFrom = sourceGroup.workspaces.firstIndex(where: { $0.id == workspaceId })
    else { return }

    // Match live preview (midY / flat insert). Gap-only commit was snapping “before first row” to “after first”.
    guard let drop = proposedWorkspaceDrop else { return }

    if drop.groupId == sourceGid, drop.index == freshFrom {
      return
    }

    withAnimation(settleAnimation) {
      appState.relocateWorkspace(
        workspaceId: workspaceId,
        fromGroupId: sourceGid,
        fromIndex: freshFrom,
        toGroupId: drop.groupId,
        toIndex: drop.index
      )
    }
  }

  private func clearWorkspaceDragState() {
    draggingWorkspaceId = nil
    workspaceDragSourceGroupId = nil
    workspaceDragFromIndex = nil
    workspaceDragTranslation = 0
    workspaceDragStartMidY = 0
    workspaceDragStartFlatIndex = nil
    proposedWorkspaceFlatInsert = nil
    proposedWorkspaceDrop = nil
  }

  private func updateCollapsedGroupHoverExpand(cursorY: CGFloat) {
    guard draggingWorkspaceId != nil else {
      resetCollapsedGroupHoverExpand()
      return
    }
    var hitCollapsed: UUID?
    for g in appState.groups {
      guard g.isCollapsed, !g.isImplicit else { continue }
      guard let rect = groupHeaderFrames[g.id] ?? groupFrames[g.id] else { continue }
      if cursorY >= rect.minY, cursorY <= rect.maxY {
        hitCollapsed = g.id
        break
      }
    }
    guard let gid = hitCollapsed else {
      resetCollapsedGroupHoverExpand()
      return
    }
    if hoverExpandTargetGroupId == gid { return }

    resetCollapsedGroupHoverExpand()
    hoverExpandTargetGroupId = gid
    let capturedId = gid
    let work = DispatchWorkItem { [appState] in
      guard let g = appState.groups.first(where: { $0.id == capturedId }) else { return }
      guard g.isCollapsed else { return }
      g.isCollapsed = false
    }
    hoverExpandWorkItem = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.collapsedGroupHoverExpandDelay, execute: work)
  }

  private func resetCollapsedGroupHoverExpand() {
    hoverExpandWorkItem?.cancel()
    hoverExpandWorkItem = nil
    hoverExpandTargetGroupId = nil
  }

  private func openWorkspaceAction() {
    appState.openWorkspace()
  }

  private func openProjectAction() {
    appState.openFolder()
  }

  private func cloneFromURLAction() {
    appState.showCloneSheet = true
  }

  private func createGroupAction() {
    let group = WorkspaceGroup(name: Self.newGroupName, isImplicit: false)
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
  @Binding var isPresented: Bool
  let onOpenWorkspace: () -> Void
  let onOpenProject: () -> Void
  let onCloneFromURL: () -> Void
  let onNewGroup: () -> Void

  private func actionWrapper(_ action: @escaping () -> Void) -> () -> Void {
    {
      action()
      isPresented = false
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      AddActionsRow(
        systemImage: "plus.square.on.square", title: "Open Workspace", theme: theme,
        action: actionWrapper(onOpenWorkspace))
      divider
      AddActionsRow(
        systemImage: "folder.badge.plus", title: "Open Project", theme: theme,
        action: actionWrapper(onOpenProject))
      divider
      AddActionsRow(
        systemImage: "arrow.down.to.line", title: "Clone from URL", theme: theme,
        action: actionWrapper(onCloneFromURL))
      divider
      AddActionsRow(
        systemImage: "rectangle.3.group", title: "New Group", theme: theme,
        action: actionWrapper(onNewGroup))
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
        .buttonStyle(TermscapeSecondaryButtonStyle())

        Spacer()

        Button("Clone") { clone() }
          .keyboardShortcut(.defaultAction)
          .disabled(appState.cloneURL.isEmpty)
          .buttonStyle(TermscapePrimaryButtonStyle())
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
