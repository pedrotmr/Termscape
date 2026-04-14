import Foundation
import SwiftUI

@MainActor
final class Workspace: ObservableObject, Identifiable {
  let id: UUID
  @Published var name: String
  @Published var isNameManuallyCustomized: Bool
  @Published var rootURL: URL?
  @Published var color: String?
  @Published var tabs: [WorkspaceTab] = []
  @Published var selectedTabId: UUID?

  var selectedTab: WorkspaceTab? {
    tabs.first { $0.id == selectedTabId }
  }

  init(
    id: UUID = UUID(),
    name: String,
    rootURL: URL? = nil,
    color: String? = nil,
    isNameManuallyCustomized: Bool = false
  ) {
    self.id = id
    self.name = name
    self.isNameManuallyCustomized = isNameManuallyCustomized
    self.rootURL = rootURL
    self.color = color
  }

    convenience init(snapshot: WorkspaceSnapshot) {
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            rootURL: snapshot.rootURL,
            color: snapshot.color,
            isNameManuallyCustomized: snapshot.isNameManuallyCustomized ?? false
        )
        if let snapshots = snapshot.tabSnapshots, !snapshots.isEmpty {
            for snap in snapshots {
                let tab = WorkspaceTab(restoring: snap, workspaceURL: rootURL, workspaceId: id)
                tabs.append(tab)
            }
            if let sel = snapshot.selectedTabId, tabs.contains(where: { $0.id == sel }) {
                selectedTabId = sel
            } else {
                selectedTabId = tabs.first?.id
            }
        } else {
            _ = addTab()
        }
    }

  func selectTab(_ id: UUID) {
    selectedTabId = id
    Self.notifyPersistenceNeeded()
  }

  private static func notifyPersistenceNeeded() {
    NotificationCenter.default.post(name: .workspacePersistenceNeeded, object: nil)
  }

  func addTab(
    title: String = WorkspacePaneContentKind.terminal.defaultTitle,
    initialPaneKind: WorkspacePaneContentKind = .terminal
  ) -> WorkspaceTab {
    let tab = WorkspaceTab(
      title: title,
      workspaceURL: rootURL,
      workspaceId: id,
      initialPaneKind: initialPaneKind
    )
    tabs.append(tab)
    selectedTabId = tab.id
    Self.notifyPersistenceNeeded()
    return tab
  }

  func addBrowserTab() -> WorkspaceTab {
    addTab(title: WorkspacePaneContentKind.browser.defaultTitle, initialPaneKind: .browser)
  }

  func closeTab(_ tabId: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabId }),
      !tabs[index].isPinned
    else { return }
    tabs[index].teardown()
    tabs.remove(at: index)

    if selectedTabId == tabId {
      selectedTabId = tabs.last?.id
    }
    Self.notifyPersistenceNeeded()
  }

  func togglePin(_ tabId: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
    let tab = tabs[index]
    tab.isPinned.toggle()

    tabs.remove(at: index)
    let insertAt = tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.count
    tabs.insert(tab, at: insertAt)
    Self.notifyPersistenceNeeded()
  }

  func moveTab(from sourceId: UUID, to destinationId: UUID) {
    guard let from = tabs.firstIndex(where: { $0.id == sourceId }),
      let to = tabs.firstIndex(where: { $0.id == destinationId }),
      from != to
    else { return }

    let movingTab = tabs[from]
    let destTab = tabs[to]
    guard movingTab.isPinned == destTab.isPinned else { return }

    let tab = tabs.remove(at: from)
    tabs.insert(tab, at: to)
    Self.notifyPersistenceNeeded()
  }

  func ensureHasTab() {
    if tabs.isEmpty {
      _ = addTab()
    }
  }

  func teardown() {
    for tab in tabs {
      tab.teardown()
    }
    tabs.removeAll()
  }
}
