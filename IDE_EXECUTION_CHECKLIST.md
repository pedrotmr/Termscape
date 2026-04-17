# IDE Pane Execution Checklist

> Companion to `IDE_IMPLEMENTATION_PLAN.md`
> Source PRD: `IDE_PANE_PRD.md`

Use this as the day-to-day tracker for delivery sequencing, ownership, and risk management.

## Status legend

- `todo` = not started
- `in_progress` = actively being implemented
- `blocked` = waiting on dependency/decision
- `done` = merged and verified

## Phase tracker

**Phase Tracker**

1. **Editor Pane Skeleton and Root Contract**
   - **Owner:** Codex
   - **Status:** `done`
   - **Risk:** High
   - **Exit check:**
     - Editor pane create/split/move works
     - Root pinning contract enforced
     - Fallback error view works
   - **Notes (2026-04-16):**
     - `EditorRootContract` implements the root resolution rules with coverage in `EditorRootContractTests`.
     - `EditorSurface` is created and torn down by the workspace container and respects the pinned root.

2. **File Tree Vertical Slice (Lazy and Watch-Aware)**
   - **Owner:** Codex
   - **Status:** `in_progress`
   - **Risk:** Medium
   - **Exit check:**
     - Lazy expansion
     - Watch invalidation
     - Unfocused throttling validated on large repo
   - **Notes (2026-04-16):**
     - `FileTreeIndex` + `FileTreeIndexPool` implement lazy per-directory loading, sorted children, and shared indexes per root.
     - Watcher-driven invalidation is wired with debounce; sidebar uses it for the read-only file tree.
     - Still missing: explicit throttling policy when panes are unfocused and perf validation on large repos.

3. **Document Editing Core (Explicit Save and Conflict Safety)**
   - **Owner:** TBD
   - **Status:** `todo`
   - **Risk:** High
   - **Exit check:**
     - Multi-file editing
     - Dirty prompts
     - Explicit save
     - External-change conflict path validated

4. **Git Panel Read Path and Consistency Locking**
   - **Owner:** TBD
   - **Status:** `todo`
   - **Risk:** Medium
   - **Exit check:**
     - Porcelain-v2 status is accurate
     - Debounce/cancel works
     - External-activity lock behaves correctly

5. **Git Write Path (Stage/Unstage/Commit and Undo)**
   - **Owner:** TBD
   - **Status:** `todo`
   - **Risk:** High
   - **Exit check:**
     - Stage/unstage/undo
     - Staged-only commit flow is deterministic and race-safe

6. **Persistence, Restore, and Runtime Resource Controls**
   - **Owner:** TBD
   - **Status:** `todo`
   - **Risk:** High
   - **Exit check:**
     - Snapshot restore works
     - Lazy activation preserved
     - Memory-pressure eviction protects dirty content

7. **Release Gates, Governance, and Merge Readiness**
   - **Owner:** TBD
   - **Status:** `todo`
   - **Risk:** High
   - **Exit check:**
     - CI perf budgets + regression gates green
     - Dependency rubric checks pass
     - Two-person sign-off complete

## Dependency chain (must remain true)

- Phase 1 must complete before all other phases.
- Phase 2 should complete before Phase 3 (tree and path contract stabilize editor navigation).
- Phase 4 should complete before Phase 5 (read path and lock semantics are foundation for write path).
- Phase 6 should start after Phases 1-5 contracts are stable enough to persist.
- Phase 7 runs continuously, but final sign-off happens after all prior phases are done.

## Global merge gates (non-negotiable)

- [ ] Existing terminal/browser regression checks pass.
- [ ] IDE performance budgets pass:
  - [ ] first paint < 500ms
  - [ ] typing p95 < 16ms
  - [ ] git refresh < 700ms
- [ ] Save conflict and root-unavailable recovery paths are tested.
- [ ] No destructive discard action is present in this release line.
- [ ] Two-person sign-off recorded (feature owner + independent reviewer).

## Per-phase handoff checklist template

Copy this block under each phase while executing:

- [ ] Scope for phase re-confirmed against PRD and plan
- [ ] Core behavior demoed end-to-end
- [ ] Failure/recovery behavior verified
- [ ] Tests added/updated for external behavior
- [ ] Performance impact measured and within budget
- [ ] Notes captured for next phase dependencies
