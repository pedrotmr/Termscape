# Ultra Review — working tree vs `main`

**Verdict:** COMMENT  
**Generated:** 2026-04-17T22:30:00Z (assistant run)  
**Scope:** `git diff main` on worktree `wi4t` (~18 files, +4985 / −2584 LOC)  
**Lenses run:** Correctness, Security, Architecture, Performance, Readability, Convention (AGENTS.md)  
**Findings:** 0 critical, 3 important, 3 suggestions  
**Threshold:** 80 (findings below dropped)

## Summary

The branch lands a large **IDE-style editor pane** (SwiftUI chrome, `FileTreeIndex` with pooling and invalidation, `EditorRootContract`, canvas integration for editor/browser/terminal, persistence hooks, and tests). Recent fixes address **SwiftUI tree remounting**, **failed directory scan caching**, **`revealDirectoryChain` path boundaries**, **debounced expanded-folder reloads**, and **editor move-to-new-tab detach parity**. Remaining issues are mostly **product consistency** (editor root from the app menu vs tab bar) and **defense-in-depth** on tree loads, not hard crashes in normal Bonsplit flows.

## Critical (0)

## Important (3)

### 1. “New Editor Tab” from the app menu always roots at `~/`, unlike the tab bar
- **Location:** `Sources/App/TermscapeApp.swift` (CommandMenu “Terminal” → “New Editor Tab”) vs `Sources/Workspace/TabBarView.swift` (toolbar editor button)  
- **Lens:** correctness (also flagged by: architecture)  
- **Confidence:** 88/100  
- **Impact:** Users opening an editor from the **menu** get **home** as the pinned root while the **tab bar** path uses `resolveEditorRootFromFocusedContext` (workspace / terminal cwd / existing editor). That is confusing and can violate the expectation that “new editor” matches the current workspace story.  
- **Evidence:**
  ```swift
  Button("New Editor Tab") {
    let pathKey = Notification.Name.MoveToNewTabKey.editorRootPath
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    NotificationCenter.default.post(
      name: .newEditorTab,
      object: nil,
      userInfo: [pathKey: home]
    )
  }
  ```
- **Fix:** Reuse the same resolution path as `TabBarView` (post through a small helper on `Workspace` / duplicate the `resolveEditorRootFromFocusedContext` call against `workspace.selectedTab`), or post a dedicated notification handled on the main workspace with access to `WorkspaceTab`.

### 2. `FileTreeIndex.scheduleLoadChildren` does not enforce paths under the index `rootPath`
- **Location:** `Sources/Editor/FileTreeIndex.swift` — `scheduleLoadChildren(for:)`  
- **Lens:** security (also flagged by: correctness)  
- **Confidence:** 83/100  
- **Impact:** Any caller bug or corrupted `expandedPaths` could trigger **directory enumeration outside the editor root** (same process, but violates the trust boundary the UI assumes). `EditorSurfaceRootView.rescheduleTreeLoadsForExpandedFolders` forwards `expandedPaths` without re-checking the root prefix.  
- **Evidence:**
  ```swift
  func scheduleLoadChildren(for path: String) {
    if childCache[path] != nil { return }
    if loadingPaths.contains(path) { return }
    loadingPaths.insert(path)
    // ... scan(path: capturedPath, ...) — no guard path.hasPrefix(rootPath)
  }
  ```
- **Fix:** Early-return unless `path == rootPath || path.hasPrefix(rootPath + "/")` (after normalizing both sides the same way as `EditorSurface`).

### 3. Very large surface modules vs maintainability goals
- **Location:** `Sources/Editor/EditorSurface.swift` (~940 LOC), `Sources/Canvas/CanvasDocumentView.swift` (large churn)  
- **Lens:** architecture  
- **Confidence:** 81/100  
- **Impact:** Harder to review, test in isolation, and reuse; increases merge-conflict cost. AGENTS.md emphasizes **deduplication** and checking for **shared extraction** before adding functionality — the editor tree, chrome, and tab model are tightly packed into few files.  
- **Evidence:** `git diff main --stat` shows `EditorSurface.swift` +942 and `CanvasDocumentView.swift` +1199/−1073 lines of movement.  
- **Fix:** Incremental extraction (e.g. sidebar/tree row views, move-to-tab payload builder, editor chrome colors) without a big-bang rewrite.

## Suggestions (3)

### 1. Sidebar search does not filter the file tree
- **Location:** `Sources/Editor/EditorSurface.swift` — `sidebarSearchText` / `TextField("Search files"…)`  
- **Lens:** readability  
- **Confidence:** 85/100  
- **Benefit:** Avoids misleading UX (“search” that does nothing).  
- **Suggestion:** Filter `childrenForNode` / visible rows, or change placeholder to “Search (coming soon)” until wired.

### 2. `movePaneToNewTab` closes the source tab before attaching to the new tab
- **Location:** `Sources/Workspace/WorkspaceContainerView.swift` — `movePaneToNewTab(notif:)`  
- **Lens:** correctness  
- **Confidence:** 78/100  
- **Benefit:** If a future Bonsplit regression made `layoutSnapshot()` empty for a new tab, a detached surface could be left unattached after `closeTab` already ran.  
- **Suggestion:** After validation, prefer **attach surface → then `closeTab`** (or split: validate new tab snapshot before closing source). Low priority if invariants are stable.

### 3. Update AGENTS.md architecture snippet for multi-surface tabs
- **Location:** `AGENTS.md` — “Model (rough)” tree (`surfaces[UUID: TerminalSurface]` only)  
- **Lens:** convention  
- **Confidence:** 79/100  
- **Benefit:** Onboarding and agent context match reality (`browserSurfaces`, `editorSurfaces`).  
- **Suggestion:** Extend the diagram one level to list editor/browser maps or say “per-kind surface dictionaries”.

## Strengths

- **Editor root contract** is explicit and covered by `EditorRootContractTests`; path-sensitive UI (`revealDirectoryChain`, breadcrumbs) uses **`root` / `root + "/"`** style guards in several places.  
- **File tree** uses off-main scans, pooled indexes, debounced invalidation, and **does not cache failed reads as empty** (with a regression test).  
- **Move to new tab** for editors now follows **detach/attach** like terminal/browser, preserving live `EditorSurface` state when a surface exists.

## Verification Notes

- Tests reviewed: **partial** — `FileTreeIndexTests` and `EditorRootContractTests` were green in a recent `xcodebuild` slice; this pipeline did not re-run the full test target matrix.  
- Security-sensitive paths touched: **yes** (filesystem enumeration, path prefix handling, `NotificationCenter` payloads for surface moves).  
- Plan alignment checked: **no** — `--plan` not provided (`IDE_PANE_PRD.md` exists in tree but not used as a gate).

## Process Log

- Context agents: **3** (summary, conventions, history) — executed inline via `git diff` / file reads / short `git log` samples  
- Specialist agents: **6** lenses — executed inline by primary assistant (single consolidated pass)  
- Candidate findings: **~12** raw (incl. overlaps)  
- Dropped (score <80): e.g. speculative `movePaneToNewTab` ordering severity, AGENTS diagram-only nits below threshold, hypothetical unbounded parallel scan storms (mitigated by `loadingPaths`)  
- Deduplicated: **2** clusters merged (menu vs tab bar editor root; path-boundary class)  
- Final findings: **6** pre-cap → **3 Important + 3 Suggestions** after severity cap for Suggestions  

### Pipeline fidelity

- **Phase 3 (per-finding Haiku scoring)** was **approximated** by deterministic primary-assistant scoring with the published rubric (same 0–100 scale, **≥80 kept**). For strict adherence, re-run with one scoring agent per retained finding.  
- `gh pr list --search` per file (Phase 1C) was **not** fully executed to save noise; history uses `git log --oneline -5` on representative paths only.
