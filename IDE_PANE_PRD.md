## Problem Statement

Termscape users can currently open terminal and browser pane content, but there is no native IDE-style pane for code-centric workflows. This forces users to context-switch to external editors for file navigation, editing, and repository status tasks, reducing flow and making split-based workspace composition less useful for development-heavy sessions.

The app needs an IDE pane that feels integrated with existing pane semantics (split, focus, move-to-new-tab, persistence), without degrading performance or reliability for terminal/browser users. The biggest challenge is adding editor and git capabilities while preserving predictable behavior under load and maintaining strong safety guarantees.

## Solution

Add a third pane content kind, `editor`, implemented as a native-first IDE pane with:

- Left file tree (lazy expansion),
- Main editor area with multiple open files,
- Simplified git panel (status sections + stage/unstage/commit),
- Explicit save workflow and conflict-safe file writes.

Behavioral contract:

- IDE pane root is seeded from focused terminal cwd at creation time, then pinned and immutable in v1.
- If no terminal cwd is available, fallback to workspace root.
- IDE pane sessions are pane-local and independent.
- Heavy services initialize lazily on first visibility/focus.
- Background work throttles when pane is unfocused.
- Default-on rollout with strict CI gates for performance and regression safety.

## User Stories

1. As a developer, I want to open a new IDE pane from my current terminal context, so that file navigation starts in the repo I am actively using.
2. As a developer, I want IDE pane root selection to be deterministic, so that pane contents do not unexpectedly jump as terminal cwd changes.
3. As a developer, I want IDE panes to be independent per pane, so that each pane can represent a separate coding context.
4. As a developer, I want IDE panes split from an IDE pane to start as fresh sessions with the same root, so that I can compare or edit independently without hidden coupling.
5. As a developer, I want a lazy file tree, so that large repositories do not block initial interaction.
6. As a developer, I want to open multiple files in editor tabs, so that I can move between related files quickly.
7. As a developer, I want dirty-state indicators, so that unsaved changes are always visible.
8. As a developer, I want save on explicit command rather than automatic writes, so that file mutations are intentional.
9. As a developer, I want a close prompt for dirty files/panes, so that I do not accidentally lose unsaved edits.
10. As a developer, I want save conflict handling when files changed externally, so that I do not overwrite changes unknowingly.
11. As a developer, I want syntax-oriented editing features (line numbers, bracket matching, syntax highlighting), so that editing is efficient.
12. As a developer, I want a git panel showing staged, unstaged, and untracked files, so that I can track repository state without leaving the pane.
13. As a developer, I want git status refresh to stay responsive even in active repos, so that status is useful instead of laggy.
14. As a developer, I want stage and unstage actions in-pane, so that I can prepare commits quickly.
15. As a developer, I want commit from the IDE pane using staged-only semantics, so that behavior matches core git expectations.
16. As a developer, I want commit action presented as a secondary flow, so that accidental commits are less likely.
17. As a developer, I want temporary lockouts of IDE git actions during external git activity refresh, so that state remains consistent.
18. As a developer, I want undo for stage/unstage actions, so that common mistakes are recoverable.
19. As a developer, I want IDE services to throttle when pane is not focused, so that terminal/browser performance stays stable.
20. As a developer, I want cold cache eviction under memory pressure, so that the app remains stable with multiple IDE panes.
21. As a developer, I want unsaved dirty content preserved even when caches are evicted, so that memory controls do not lose work.
22. As a developer, I want explicit error UI when pane root becomes unavailable, so that failure is understandable and recoverable.
23. As a developer, I want crash-safe fallback controls (`Retry`, `Open Terminal Here`, diagnostics), so that the app remains usable under IDE failures.
24. As a developer, I want restored IDE panes to initialize lazily at startup, so that app launch remains fast for all users.
25. As a maintainer, I want shared backend read caches per root (while keeping pane-local UI state), so that duplicate roots do not duplicate heavy work.
26. As a maintainer, I want local perf counters for open latency, typing latency, git refresh latency, and watcher backlog, so that regressions are visible quickly.
27. As a maintainer, I want hard CI performance budgets enforced, so that scope expansion cannot silently degrade UX.
28. As a maintainer, I want two-person sign-off for merge readiness, so that big-bang delivery risk is checked independently.
29. As a maintainer, I want feature-level dependency admission tied to measurable complexity/perf gain and memory ceiling, so that dependency drift stays controlled.
30. As a user, I want terminal and browser flows unchanged by default when not using IDE panes, so that existing workflows stay reliable.

## Implementation Decisions

- **Pane content expansion**
  - Introduce `editor` as a first-class pane content kind alongside terminal and browser.
  - Reuse existing pane orchestration patterns (split/focus/persistence lifecycle) instead of creating a separate layout pipeline.

- **Primary modules (deep-module set)**
  - `EditorPaneCoordinator`
    - Single façade that orchestrates pane lifecycle, focus, service wiring, and error fallback behavior.
    - Owns integration between UI layer and backend services.
  - `EditorSessionStore`
    - Pane-local UI/session state: open files, selected file, tab ordering, panel visibility, and transient UI flags.
    - No cross-pane mutation coupling.
  - `RepositoryContextResolver`
    - Resolves root at create time from focused terminal cwd, with workspace root fallback.
    - Enforces root pinning and immutability in v1.
  - `FileTreeIndex`
    - Lazy hierarchical tree loading, path metadata cache, watch-driven invalidation strategy, and bounded refresh.
  - `DocumentStore`
    - Open buffers, dirty state, load/save pipeline, external change detection, and conflict-safe write semantics.
  - `GitWorkflowService`
    - Debounced/cancelable status refresh using porcelain v2.
    - Stage/unstage/commit actions, staged-only commit semantics, temporary lock during external activity refresh, and undo support for stage/unstage.
  - `EditorPersistenceCodec`
    - Encode/decode/versioning for editor pane snapshot fields:
      - root path,
      - open file list,
      - selected file,
      - panel/layout visibility.
  - `EditorPerfMonitor`
    - Local-only counters and structured events for open latency, typing p95, git refresh latency, watcher backlog, and pressure signals.

- **Editor engine strategy**
  - Use an `EditorEngine` abstraction boundary now, with native-first implementation path.
  - Keep a future engine swap possible (for advanced implementations) without rewriting pane orchestration.

- **Git UX and safety**
  - v1 supports stage/unstage/commit.
  - v1 excludes destructive discard actions.
  - Commit entry is a secondary action flow with explicit message entry and staged context.

- **Persistence and startup**
  - Persist pane-local IDE session metadata only (not heavy caches).
  - Restore metadata at startup, but initialize heavy services lazily on first visibility/focus.

- **Performance and reliability**
  - Shared read caches allowed per root for expensive backend reads.
  - UI/session remains pane-local even when caches are shared.
  - Throttle background work for unfocused panes.
  - Evict cold caches/buffers under memory pressure, never evict unsaved dirty content.

- **Failure behavior**
  - Root unavailable state is explicit and recoverable.
  - Editor crash/init failure degrades to pane-level error view with retry and diagnostics actions.

- **Delivery and governance**
  - Big-bang implementation is accepted, but merge is gated by:
    - regression checks for existing terminal/browser behavior,
    - IDE performance budget checks,
    - two-person sign-off (owner + independent reviewer).
  - Scope can expand with broad contributor involvement only when CI perf budgets remain green.
  - New dependencies must satisfy measurable value criteria and memory budget constraints.

## Testing Decisions

- **Good test definition**
  - Test externally observable behavior and contracts, not implementation details.
  - Prefer deterministic tests with explicit inputs/outputs and bounded timing.
  - Include both happy paths and failure/recovery paths for all stateful services.

- **Modules to test (required)**
  - `RepositoryContextResolver`
    - Root resolution precedence (focused terminal cwd vs fallback).
    - Root pinning immutability contract.
  - `FileTreeIndex`
    - Lazy expansion correctness.
    - Watch invalidation correctness under create/delete/rename events.
    - Large-tree behavior without eager recursion.
  - `DocumentStore`
    - Dirty tracking.
    - Explicit save behavior.
    - External-change conflict path behavior.
  - `GitWorkflowService`
    - Porcelain parsing correctness.
    - Debounce and cancellation behavior.
    - External-activity temporary lock behavior.
    - Stage/unstage/commit semantics and undo for stage/unstage.
  - `EditorPersistenceCodec`
    - Snapshot round-trip.
    - Backward-compatible decode for future evolution.
  - `EditorPaneCoordinator`
    - High-level lifecycle and fallback error transitions.
  - `EditorPerfMonitor`
    - Counter/event emission for defined metrics.

- **Integration/regression coverage**
  - Pane creation and split flows with editor kind.
  - IDE/terminal/browser focus and shortcut scoping.
  - Startup restore with lazy service init.
  - Memory pressure eviction policy behavior.
  - Existing terminal/browser regression suite must remain green.

- **Performance gates**
  - Required CI thresholds for medium repo profile:
    - first paint < 500ms,
    - typing p95 < 16ms,
    - git refresh < 700ms.
  - Any scope expansion must continue to pass these budgets.

## Out of Scope

- LSP-powered language intelligence (diagnostics, go-to-definition, rename, hover) in v1.
- Root rebind/re-root workflow in v1.
- Destructive git discard actions in first ship.
- Auto-save as default save behavior.
- Full app-level undo for commit actions.
- Remote analytics/telemetry pipeline (local observability only).
- Full minimap/multi-cursor/folding parity guarantees in first milestone (can be staged after core reliability).

## Further Notes

- This PRD intentionally prioritizes reliability and predictability over maximal initial feature density.
- The architecture favors deep, testable modules with explicit interfaces so that future expansions (LSP, richer editor engine, advanced git UX) can be added without destabilizing core pane orchestration.
- Even with default-on rollout, launch-time and non-IDE workflows are protected by lazy initialization, throttling, memory controls, and strict CI budget gates.
