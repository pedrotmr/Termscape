# Plan: IDE Pane for Termscape

> Source PRD: `IDE_PANE_PRD.md`
>
> **Status snapshot (2026-04-16)**
> - Editor pane kind is wired into the workspace model and pane lifecycle.
> - Root resolution contract is implemented as `EditorRootContract` with tests in `EditorRootContractTests`.
> - `EditorSurface` provides a read-only editor chrome stub (tabs, breadcrumbs, file tree sidebar) wired to the workspace canvas.
> - `FileTreeIndex` + `FileTreeIndexPool` implement lazy tree loading, shared per-root indexes, and watcher-driven invalidation with tests in `FileTreeIndexTests`.
> - Document editing and git panel flows (Phases 3–5) are not implemented yet.

## Architectural decisions

Durable decisions that apply across all phases:

- **Pane kind model**: Extend pane content kinds to include `editor`, reusing existing pane lifecycle and split/focus orchestration patterns.
- **Session ownership**: IDE sessions are pane-local and independent.
- **Root resolution**: On IDE pane creation, seed root from focused terminal cwd; if unavailable, fallback to workspace root. Root is pinned/immutable in v1.
- **Persistence**: Persist editor session metadata (root path, open files, selected file, panel/layout visibility) while keeping heavy caches/process state out of snapshots.
- **Git behavior**: Use porcelain-v2 status with debounced/cancelable refresh. v1 git actions are stage/unstage/commit only; commit is staged-only and exposed through a secondary action flow.
- **Startup and activity model**: Heavy IDE services initialize lazily when pane first becomes visible/focused. Background activity is throttled while pane is unfocused.
- **Safety and reliability**: Focus-scoped shortcuts, explicit failure UI for unavailable roots/crashes, save conflict prompts, and memory-pressure eviction of cold caches only.
- **Delivery governance**: Default-on rollout with CI perf budgets, regression gates for terminal/browser parity, dependency acceptance rubric, and two-person sign-off for merge readiness.

---

## Phase 1: Editor Pane Skeleton and Root Contract

**User stories**: 1, 2, 3, 4, 22, 23, 30

### What to build

Introduce the editor pane as a selectable pane type and wire it into pane creation/split/move flows. Establish the root resolution contract (terminal cwd seed, workspace fallback, pin-after-create) and present recoverable error states for root unavailability and editor initialization failure.

### Acceptance criteria

- [ ] Users can create and split editor panes through the same interaction model used by other pane types.
- [ ] Editor pane root is seeded from focused terminal context and remains pinned afterward.
- [ ] If no terminal context exists, editor pane consistently falls back to workspace root.
- [ ] Unavailable root and init failure states surface a recoverable pane UI (`Retry`, terminal handoff, diagnostics).
- [ ] Existing terminal/browser pane behavior remains unchanged in the same flows.

---

## Phase 2: File Tree Vertical Slice (Lazy and Watch-Aware)

**User stories**: 5, 19, 24, 25

### What to build

Implement lazy file tree loading for editor panes with watch-driven invalidation and bounded refresh behavior. Ensure tree and indexing activity are efficient under large repositories and throttled when pane focus is lost.

### Acceptance criteria

- [ ] Tree initializes quickly with shallow initial load and lazy expansion for deeper directories.
- [ ] Tree reflects creates/deletes/renames without requiring full recursive rebuilds.
- [ ] Background tree/index work is reduced when pane is unfocused and resumes correctly on focus.
- [ ] Multiple panes targeting the same root can share backend read caches without sharing UI state.
- [ ] Restore flow does not eagerly initialize heavy tree/index activity at startup.

---

## Phase 3: Document Editing Core (Explicit Save and Conflict Safety)

**User stories**: 6, 7, 8, 9, 10, 11, 21

### What to build

Deliver end-to-end file editing: open multiple files, track dirty state, explicit save behavior, close prompts, and external-change conflict handling. Provide baseline syntax-oriented editor ergonomics while preserving data safety under memory pressure.

### Acceptance criteria

- [ ] Users can open multiple files in a pane-local editor tab model.
- [ ] Dirty indicators are accurate and close prompts prevent accidental unsaved data loss.
- [ ] Save is explicit and writes are conflict-safe when on-disk content changes externally.
- [ ] Syntax-oriented editing baseline (line-oriented affordances, bracket awareness, highlighting) is available.
- [ ] Memory-pressure eviction never drops dirty unsaved document content.

---

## Phase 4: Git Panel Read Path and Consistency Locking

**User stories**: 12, 13, 17, 26

### What to build

Add git status visibility in editor pane with staged/unstaged/untracked grouping powered by debounced, cancelable porcelain-v2 refresh. Add consistency locking behavior when external git activity is detected and instrument key local performance counters.

### Acceptance criteria

- [ ] Git panel displays staged, unstaged, and untracked sections accurately for the pinned root.
- [ ] Status refresh is debounced/cancelable and remains responsive under active repo churn.
- [ ] External git activity temporarily locks unsafe git actions until refresh completes.
- [ ] Local perf counters/events are emitted for open latency, typing p95, git refresh latency, and backlog pressure.
- [ ] No terminal/browser regressions are introduced by git status polling logic.

---

## Phase 5: Git Write Path (Stage/Unstage/Commit and Undo)

**User stories**: 14, 15, 16, 18

### What to build

Enable safe write actions from the git panel: stage/unstage and staged-only commit via a secondary commit flow. Add user-level undo for stage/unstage actions and ensure state reconciliation remains correct after each action.

### Acceptance criteria

- [ ] Users can stage and unstage files from IDE pane git panel.
- [ ] Stage/unstage actions support app-level undo semantics.
- [ ] Commit flow is secondary/explicit and commits staged content only.
- [ ] Post-action status refresh and UI reconciliation are deterministic and race-safe.
- [ ] Destructive discard actions remain out of scope in this release line.

---

## Phase 6: Persistence, Restore, and Runtime Resource Controls

**User stories**: 20, 24, 25

### What to build

Complete persistence/restore for editor pane session metadata and enforce runtime resource controls for launch and memory behavior. Ensure lazy reactivation and bounded resource use when many panes are present.

### Acceptance criteria

- [ ] Session metadata round-trips correctly across app restart.
- [ ] Startup restores editor pane metadata without eager heavy service activation.
- [ ] Cold caches/buffers are evicted under memory pressure while preserving dirty unsaved state.
- [ ] Shared backend caches per root improve efficiency without cross-pane UI coupling.
- [ ] Restored panes become fully active only on first visibility/focus.

---

## Phase 7: Release Gates, Governance, and Merge Readiness

**User stories**: 27, 28, 29

### What to build

Operationalize release controls around CI budgets, regression checks, dependency rubric enforcement, and merge governance so the default-on launch remains safe and maintainable.

### Acceptance criteria

- [ ] CI enforces IDE performance budgets for medium-repo profile (`first paint < 500ms`, `typing p95 < 16ms`, `git refresh < 700ms`).
- [ ] Terminal/browser regression suite must pass for editor-related changes.
- [ ] Dependency additions comply with measurable value and memory budget rubric.
- [ ] Merge readiness requires two-person sign-off (feature owner + independent reviewer).
- [ ] Scope expansion cannot merge if CI perf gates regress.
