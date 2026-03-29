import Foundation
import SwiftUI

@MainActor
final class Workspace: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var rootURL: URL?
    @Published var color: String?
    @Published var tabs: [WorkspaceTab] = []
    @Published var selectedTabId: UUID?

    var selectedTab: WorkspaceTab? {
        tabs.first { $0.id == selectedTabId }
    }

    init(id: UUID = UUID(), name: String, rootURL: URL? = nil, color: String? = nil) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.color = color
    }

    convenience init(snapshot: WorkspaceSnapshot) {
        self.init(id: snapshot.id, name: snapshot.name, rootURL: snapshot.rootURL, color: snapshot.color)
    }

    func addTab(title: String = "Terminal") -> WorkspaceTab {
        let tab = WorkspaceTab(
            title: title,
            workspaceURL: rootURL,
            workspaceId: id
        )
        tabs.append(tab)
        selectedTabId = tab.id
        return tab
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
    }

    func togglePin(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let tab = tabs[index]
        tab.isPinned.toggle()

        if tab.isPinned {
            tabs.remove(at: index)
            let insertAt = tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.count
            tabs.insert(tab, at: insertAt)
        }
    }

    func moveTab(from sourceId: UUID, to destinationId: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == sourceId }),
              let to   = tabs.firstIndex(where: { $0.id == destinationId }),
              from != to
        else { return }

        let movingTab = tabs[from]
        let destTab = tabs[to]
        guard movingTab.isPinned == destTab.isPinned else { return }

        tabs.move(fromOffsets: IndexSet(integer: from),
                  toOffset: to < from ? to : to + 1)
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
