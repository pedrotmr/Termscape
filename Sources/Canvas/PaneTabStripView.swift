import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PaneTabStripItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String?
    let isPinned: Bool
}

struct PaneTabStripView: View {
    let paneId: UUID
    let tabs: [PaneTabStripItem]
    let selectedTabId: UUID?
    let backgroundColor: NSColor
    let accentColor: NSColor
    let onSelect: (UUID) -> Void
    let onMoveTab: (_ tabId: UUID, _ targetPaneId: UUID, _ targetIndex: Int?) -> Void
    @ObservedObject private var dragState = PaneTabDragState.shared

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { entry in
                tabView(tab: entry.element, index: entry.offset)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: backgroundColor).opacity(0.92))
        .overlay {
            if dragState.hoverPaneId == paneId {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: accentColor).opacity(0.65), lineWidth: 1.5)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: tabs.map(\.id))
        .onDrop(
            of: [UTType.termscapePaneTab],
            delegate: PaneTabDropDelegate(
                dragState: dragState,
                targetPaneId: paneId,
                targetIndex: tabs.count,
                onMoveTab: onMoveTab
            )
        )
    }

    private func tabView(tab: PaneTabStripItem, index: Int) -> some View {
        HStack(spacing: 4) {
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color(nsColor: accentColor).opacity(0.85))
            } else if let icon = tab.icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(textColor(for: tab.id).opacity(0.75))
            }

            Text(tab.title)
                .font(.system(size: 11, weight: selectedTabId == tab.id ? .semibold : .regular))
                .foregroundStyle(textColor(for: tab.id))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tabBackground(for: tab.id))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .opacity(dragState.draggedTabId == tab.id ? 0.38 : 1)
        .scaleEffect(dragState.draggedTabId == tab.id ? 0.97 : 1)
        .overlay(alignment: .leading) {
            if dragState.hoverPaneId == paneId, dragState.hoverIndex == index {
                Rectangle()
                    .fill(Color(nsColor: accentColor))
                    .frame(width: 2)
                    .padding(.vertical, 2)
            }
        }
        .overlay(alignment: .trailing) {
            if dragState.hoverPaneId == paneId, dragState.hoverIndex == tabs.count, index == tabs.count - 1 {
                Rectangle()
                    .fill(Color(nsColor: accentColor))
                    .frame(width: 2)
                    .padding(.vertical, 2)
            }
        }
        .onTapGesture {
            onSelect(tab.id)
        }
        .onDrag {
            dragState.begin(tabId: tab.id, sourcePaneId: paneId)
            return makeItemProvider(for: tab.id)
        }
        .onDrop(
            of: [UTType.termscapePaneTab],
            delegate: PaneTabDropDelegate(
                dragState: dragState,
                targetPaneId: paneId,
                targetIndex: index,
                onMoveTab: onMoveTab
            )
        )
    }

    private func tabBackground(for tabId: UUID) -> Color {
        if selectedTabId == tabId {
            return Color(nsColor: accentColor).opacity(0.24)
        }
        return Color.white.opacity(0.06)
    }

    private func textColor(for tabId: UUID) -> Color {
        selectedTabId == tabId ? .white : .white.opacity(0.76)
    }

    private func makeItemProvider(for tabId: UUID) -> NSItemProvider {
        let payload = PaneTabDragPayload(tabId: tabId.uuidString)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.termscapePaneTab.identifier,
            visibility: .all
        ) { completion in
            let data = try? JSONEncoder().encode(payload)
            completion(data, nil)
            return nil
        }
        return provider
    }
}

private struct PaneTabDragPayload: Codable {
    let tabId: String
}

private final class PaneTabDragState: ObservableObject {
    static let shared = PaneTabDragState()

    @Published var draggedTabId: UUID?
    @Published var sourcePaneId: UUID?
    @Published var hoverPaneId: UUID?
    @Published var hoverIndex: Int?

    private var lastMoveSignature: String?

    private init() {}

    func begin(tabId: UUID, sourcePaneId: UUID) {
        draggedTabId = tabId
        self.sourcePaneId = sourcePaneId
        hoverPaneId = sourcePaneId
        hoverIndex = nil
        lastMoveSignature = nil
    }

    func setHover(targetPaneId: UUID, targetIndex: Int?) {
        hoverPaneId = targetPaneId
        hoverIndex = targetIndex
    }

    func shouldIssueMove(tabId: UUID, targetPaneId: UUID, targetIndex: Int?) -> Bool {
        let signature = "\(tabId.uuidString)|\(targetPaneId.uuidString)|\(targetIndex.map(String.init) ?? "nil")"
        guard signature != lastMoveSignature else { return false }
        lastMoveSignature = signature
        return true
    }

    func clearHover(for targetPaneId: UUID, targetIndex: Int?) {
        guard hoverPaneId == targetPaneId, hoverIndex == targetIndex else { return }
        hoverPaneId = nil
        hoverIndex = nil
    }

    func end() {
        draggedTabId = nil
        sourcePaneId = nil
        hoverPaneId = nil
        hoverIndex = nil
        lastMoveSignature = nil
    }
}

private struct PaneTabDropDelegate: DropDelegate {
    let dragState: PaneTabDragState
    let targetPaneId: UUID
    let targetIndex: Int?
    let onMoveTab: (_ tabId: UUID, _ targetPaneId: UUID, _ targetIndex: Int?) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggedTabId = dragState.draggedTabId else { return }
        dragState.setHover(targetPaneId: targetPaneId, targetIndex: targetIndex)
        guard dragState.shouldIssueMove(tabId: draggedTabId, targetPaneId: targetPaneId, targetIndex: targetIndex) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            onMoveTab(draggedTabId, targetPaneId, targetIndex)
        }
    }

    func dropExited(info _: DropInfo) {
        dragState.clearHover(for: targetPaneId, targetIndex: targetIndex)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        dragState.draggedTabId != nil || info.hasItemsConforming(to: [UTType.termscapePaneTab])
    }

    func performDrop(info: DropInfo) -> Bool {
        if let draggedTabId = dragState.draggedTabId {
            if dragState.shouldIssueMove(tabId: draggedTabId, targetPaneId: targetPaneId, targetIndex: targetIndex) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    onMoveTab(draggedTabId, targetPaneId, targetIndex)
                }
            }
            dragState.end()
            return true
        }

        guard let provider = info.itemProviders(for: [UTType.termscapePaneTab]).first else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.termscapePaneTab.identifier) {
            data, _ in
            guard let data,
                  let payload = try? JSONDecoder().decode(PaneTabDragPayload.self, from: data),
                  let tabId = UUID(uuidString: payload.tabId)
            else { return }

            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.15)) {
                    onMoveTab(tabId, targetPaneId, targetIndex)
                }
                dragState.end()
            }
        }

        return true
    }
}

private extension UTType {
    static let termscapePaneTab = UTType(importedAs: "com.termscape.pane-tab")
}
