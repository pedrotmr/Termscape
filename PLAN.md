# Termscape — Product & Technical Plan

## What We're Building

A next-generation macOS terminal workspace manager with a spatial canvas concept: instead of squeezing panes when too many are open, the terminal area scrolls horizontally like a canvas. Think Figma meets terminal.

---

## Product Decisions (locked)

| Decision           | Choice                                                            |
| ------------------ | ----------------------------------------------------------------- |
| Platform           | macOS 14+ native                                                  |
| Language           | Swift + SwiftUI + AppKit                                          |
| Terminal rendering | Ghostty (libghostty), GPU-accelerated via Metal                   |
| Split system       | Bonsplit (vendor submodule)                                       |
| Canvas behavior    | Custom NSScrollView, horizontal scroll when panes exceed viewport |
| Sidebar groups     | Named collapsible sections, drag to reorder                       |
| Workspace opening  | Folder picker (NSOpenPanel) or git clone URL                      |

---

## V1 Scope ✅ (build this)

- Sidebar with named collapsible groups + workspaces
- Drag to reorder workspaces and groups
- Open workspace via folder picker or git clone URL
- Multiple tabs per workspace (each tab = fresh terminal, no state shared)
- Split panes per tab (horizontal + vertical)
- Spatial canvas: min pane width ~400pt, horizontal scroll instead of squeeze
- Ghostty-powered terminal rendering in every pane
- Keyboard shortcuts: Cmd+T new tab, Cmd+W close, Cmd+D split right, Cmd+Shift+D split down
- Workspace list persisted to JSON in Application Support

---

## V2+ Backlog 🔮 (do NOT build yet)

- Session persistence (restore all workspaces/tabs/panes on relaunch)
- Git branch display in sidebar per workspace
- Workspace color labels
- Remote/SSH workspaces
- AI/agent integration (Unix socket control API for Claude Code etc.)
- Built-in browser panel
- Themes / appearance customization UI
- Tab title tracks terminal process title
- Workspace-level environment variable overrides
- Multiple windows

---

## Architecture

### Data Model

```
AppState
  └── groups: [Group]
        └── workspaces: [Workspace]
              ├── rootURL: URL?
              └── tabs: [WorkspaceTab]
                    ├── bonsplitController: BonsplitController  ← one per tab
                    └── surfaces: [UUID: TerminalSurface]
```

Key: `BonsplitController` lives on **WorkspaceTab** (not Workspace). Each tab has its own independent split layout.

### UI Stack

```
NSWindow.contentView
├── NSHostingView (SwiftUI)
│   └── HSplitView
│       ├── SidebarView (pure SwiftUI)
│       └── WorkspaceContainerView
│             ├── TabBarView (pure SwiftUI)
│             └── CanvasHostingView (NSViewRepresentable)
│                   └── CanvasScrollView (NSScrollView)
│                         └── CanvasDocumentView (NSView)
│                               └── [GhosttySurfaceScrollView × N] — absolutely positioned
```

Terminal surfaces (Metal-backed NSViews) live in `CanvasDocumentView`, outside SwiftUI's layout system.

### Spatial Canvas Logic

- `PaneLayoutEngine` computes total canvas width from the split tree
- Horizontal splits: widths add (panes side by side)
- Vertical splits: width = max of children
- Min pane width: 400pt — never goes below this
- `CanvasDocumentView` width = max(computedWidth, viewportWidth)
- Horizontal scroll activates automatically when panes overflow viewport

---

## Project Structure

```
Termscape/
├── project.yml                          # XcodeGen spec
├── PLAN.md                              # This file
├── Sources/
│   ├── App/
│   │   ├── TermscapeApp.swift
│   │   └── AppDelegate.swift
│   ├── Ghostty/
│   │   ├── GhosttyApp.swift             # ghostty_app_t singleton
│   │   ├── TerminalSurface.swift        # owns ghostty_surface_t
│   │   ├── GhosttyNSView.swift          # Metal NSView + input handling
│   │   └── GhosttySurfaceScrollView.swift
│   ├── Model/
│   │   ├── AppState.swift
│   │   ├── Group.swift
│   │   ├── Workspace.swift
│   │   └── WorkspaceTab.swift
│   ├── Canvas/
│   │   ├── CanvasScrollView.swift
│   │   ├── CanvasDocumentView.swift
│   │   ├── CanvasHostingView.swift
│   │   └── PaneLayoutEngine.swift
│   ├── Sidebar/
│   │   ├── SidebarView.swift
│   │   ├── GroupRowView.swift
│   │   └── WorkspaceRowView.swift
│   ├── Workspace/
│   │   ├── WorkspaceContainerView.swift
│   │   └── TabBarView.swift
│   └── Shared/
│       └── Extensions.swift
├── vendor/
│   └── bonsplit/                        # Git submodule
└── Resources/
    ├── GhosttyKit.xcframework
    ├── termscape-Bridging-Header.h
    └── shell-integration/
```

---

## Build Phases

### Phase 1 — Single working terminal

Goal: App launches, sidebar shows, click workspace → working shell

1. Xcode project setup (XcodeGen)
2. GhosttyApp singleton + tick loop
3. GhosttyNSView + TerminalSurface (minimal Ghostty integration)
4. AppState + Group + Workspace models (hardcoded for now)
5. SidebarView + HSplitView layout
6. WorkspaceContainerView with one full-size terminal
   **Milestone: working shell appears**

### Phase 2 — Tabs

1. WorkspaceTab + BonsplitController (one pane)
2. TabBarView wired to tab creation/switching/closing
3. Each tab = independent TerminalSurface
   **Milestone: multiple independent tabs**

### Phase 3 — Spatial canvas + splits

1. PaneLayoutEngine (canvas width computation)
2. CanvasScrollView + CanvasDocumentView
3. Wire Cmd+D / Cmd+Shift+D → splitPane()
4. Divider drag → divider position update
5. BonsplitDelegate → canvas relayout
   **Milestone: splits work + horizontal scroll when overflow**

### Phase 4 — Workspace management

1. openFolder() via NSOpenPanel
2. cloneRepo() via git clone terminal
3. Group collapsing + drag reorder
4. Workspace context menu (rename, close, move to group)
5. Persist workspace list to JSON
   **Milestone: full sidebar workflow**

### Phase 5 — Polish

- Keyboard shortcuts, window title, app icon, error handling

---

## Reference Codebase

`/Users/pedrotmr/Developer/_temp_/cmux` — use as reference, not a port.

Key files to adapt:

- `Sources/GhosttyTerminalView.swift` → GhosttyApp + TerminalSurface + GhosttyNSView
- `Sources/Panels/TerminalPanel.swift` → TerminalSurface lifecycle
- `vendor/bonsplit/Sources/Bonsplit/Public/BonsplitController.swift` → split API
- `Sources/WorkspaceContentView.swift` → BonsplitView wiring pattern

GhosttyKit.xcframework: `/Users/pedrotmr/Developer/_temp_/cmux/ghostty/macos/GhosttyKit.xcframework`
