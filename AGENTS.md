# AGENTS.md

## Project Snapshot

Termscape is a terminal workspace app.

This repository is a VERY EARLY WIP. Proposing sweeping changes that improve long-term maintainability is encouraged.

## Core Feature

- Panes scroll horizontally instead of shrinking (canvas-Figma-like).
- Terminals render via **Ghostty** (`GhosttyKit.xcframework`, Metal).

## Core Priorities

1. Performance first.
2. Reliability first.
3. Keep behavior predictable under load, resize, focus, tab/split churn, teardown, failures.

If a tradeoff is required, choose correctness and robustness over short-term convenience.

## Maintainability

Long term maintainability is a core priority. If you add new functionality, first check if there is shared logic that can be extracted to a separate module. Duplicate logic across multiple files is a code smell and should be avoided. Don't be afraid to change existing code. Don't take shortcuts by just adding local logic to solve a problem.

## Practices

- Match existing **naming**, **feature folders** (`Sources/<Feature>`, shared in `Shared`), and **concurrency** (`@MainActor` for model/UI; Ghostty C API on main thread; `GhosttyCallbackContext` safe for cross-thread C callbacks).
- **Deduplicate** — extract shared rules; avoid one-off forks.
- **Fix causes**, not symptoms; comments **brief and intent-only**.
- **Verify** — Debug build passes; smoke the flows you touched. Add focused tests for non-trivial logic when practical.

Treat **`vendor/bonsplit/`** and **GhosttyKit** as external unless upgrading them.

## Stack conventions

- Swift 5.10, arm64, deployment **macOS 14.0**
- `@Observable` — `AppState`, `WorkspaceGroup`, `ThemeManager`; `@ObservableObject` + `@Published` — `Workspace`, `WorkspaceTab`
- Bridging: `Resources/termscape-Bridging-Header.h` → `ghostty.h` (`-lc++ -lz`)

## Model (rough)

```
AppState (@Observable)
  └── groups → workspaces → tabs
        └── per tab: BonsplitController + surfaces[UUID: TerminalSurface]
```

Workspaces persist under `~/Library/Application Support/termscape/workspaces.json` (`WorkspaceSnapshot` / `[WorkspaceGroup]`).

## UI / layout

SwiftUI: sidebar + tabs. Canvas: **AppKit** (`NSViewRepresentable` → scroll view → **`CanvasDocumentView`**), panes as absolutely positioned Metal-backed views — **outside SwiftUI layout**. Main layout hook: `CanvasDocumentView.update(tab:viewportSize:)`.

**Canvas** — `PaneLayoutEngine` (Bonsplit tree → columns, ~600pt min width); `CanvasHostingView` listens for `.bonsplitLayoutDidChange`.

**Ghostty** — `GhosttyApp` owns `ghostty_app_t`; `TerminalSurface` owns surface lifecycle; `GhosttyNSView` is the Metal view.

**Notifications** (orchestration): e.g. `.newTab`, `.closeTab`, `.splitRight`, `.splitDown`, `.moveToNewTab`, `.bonsplitLayoutDidChange`, `.ghosttyConfigDidReload` — `WorkspaceContainerView` coordinates lifecycle.

## Build

```bash
xcodegen generate   # after editing project.yml
xcodebuild -project Termscape.xcodeproj -scheme Termscape -configuration Debug build
```

Release: `Scripts/release/` (ZIP/DMG, notarize, Sparkle); CI on tag `v*` via `.github/workflows/release.yml`.
