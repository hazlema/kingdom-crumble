# Selection Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the last shadow selection fact — `SceneryTool.selected_overlay` — so `ed.selection` is the ONLY truth, completing the owner's one-rule doctrine before the trigger-link UI adds a third tool.

**Architecture:** Two tasks. (1) The shadow dies: the tool field is removed, `ed.selected_overlay` becomes a derived property routed through the real setters, the per-frame gizmo pointer reads the fact, and the doc-swap shadow-clears (now redundant) come out. (2) Seam hygiene: `GridTool.reset_input_state()` replaces cross-tool pokes, and `_delete_selected`'s view-as-fact fallback dies after migrating the two tests that write the view directly.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **354 passing**) after each task: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **DEPLOY FREEZE: commit locally only. NO push/export/deploy.**
- **Test-edit charter (differs from the split):** edits are permitted ONLY at the named legacy sites — the ~5 direct `ed.selected_overlay = N` writes and the 2 direct `ed.overlay.selected_cell = ...` writes — and each migration must preserve the test's original INTENT (document old line → new line → why intent is intact, per site, in the report). No other test may change. New pins welcome.
- **Sanctioned semantic change:** writing `ed.selected_overlay` (and the tool's internal selection writes) now routes through `select_overlay()`/`deselect()` — views sync on write (inspector may open where it previously didn't). This is the doctrine, not a bug; adjudicate each affected test against it.
- The doctrine grep must hold or improve: view writers (overlay.selected_*/inspector open-close/gizmo piece-visible) confined to `_sync_views` + the two documented exceptions (per-frame gizmo POINTER — which this plan re-bases onto the fact — and the pre-capture hide).
- Zero gameplay-side changes; editor-only files.

---

### Task 1: The shadow dies

**Files:**
- Modify: `src/editor/tools/scenery_tool.gd`, `src/editor/level_editor.gd`
- Test: named-site migrations only + one new pin (`tests/unit/test_scenery_mode.gd` or interactions — implementer's placement call)

**Interfaces:**
- Produces: `ed.selected_overlay` derived — `get`: `selection["index"]` when `selection.kind == "overlay"` else `-1`; `set(v)`: `select_overlay(v)` when `v >= 0` else `deselect()`. `SceneryTool` has NO selection field; every internal read uses `ed.selected_overlay` (the getter) or `ed.selection`; every internal write uses the setters.

- [ ] **Step 1:** Inventory. Grep `selected_overlay` across src/ and tests/. List every read/write in the report (the tool's internal sites, the forwarder, the per-frame gizmo block, `_on_image_chosen`, the three doc-swap clears, the ~5 test writes).
- [ ] **Step 2:** Write the new pin FIRST: setting `ed.selected_overlay = <valid index>` on a level with a scenery piece syncs views (gizmo pointed + visible; full inspector open on that overlay's dict); setting `-1` deselects (inspector hidden, gizmo hidden). Watch it fail against the shadow-field forwarder.
- [ ] **Step 3:** Implement: remove the tool field; forwarder becomes the derived property above; per-frame gizmo block in `SceneryTool.process` reads `ed.selected_overlay` (the derived getter) so pointer and fact can never diverge; internal writes (`_scenery_press` both paths, RMB select, `_delete_selected_piece`, `exit()`, `_on_image_chosen`) route through setters; REMOVE the three now-redundant `_scenery_tool.selected_overlay = -1` doc-swap lines (the `selection` clear is the whole truth now — verify the doc-swap pin still passes).
- [ ] **Step 4:** Run the suite. Adjudicate each failing legacy write-site against the sanctioned semantics; migrate ONLY those, preserving intent (e.g. a test that wrote the field to arrange state now calls the setter and, if it asserted inspector-hidden after, that assert moves or the arrangement uses `select_overlay` + explicit close — justify per site). Any failure NOT at a named site = your change broke something: fix the code.
- [ ] **Step 5:** Full suite green (354 + 1 pin = 355, minus nothing). Commit: `git commit -m "refactor: selected_overlay shadow dies — the fact is the only selection truth"`

---

### Task 2: Seam hygiene — reset_input_state + the view-as-fact fallback dies

**Files:**
- Modify: `src/editor/tools/grid_tool.gd`, `src/editor/tools/scenery_tool.gd`
- Test: the two named `overlay.selected_cell` writer sites migrate (interactions ~249, ~298)

**Interfaces:**
- Produces: `GridTool.reset_input_state()` (clears `carrying`, `_drag_from`, `_drag_prop`, `_lmb_down` — exactly what SceneryTool.enter() pokes today); SceneryTool.enter()/exit() call it instead of reaching into `ed._grid_tool.*` fields; `GridTool._delete_selected` reads ONLY `ed.selection` (the `overlay.selected_cell` fallback is deleted).

- [ ] **Step 1:** Migrate the two tests: replace their direct `ed.overlay.selected_cell = <cell>` arrangement with `ed.select_cell(<cell>, Vector2i(1,1), ed.occupancy[<cell>])` (or `ed._press(<cell>)` where the click path IS the intent — choose per test, justify). Watch them still pass BEFORE the code change (the setter path must be equivalent already).
- [ ] **Step 2:** Add `reset_input_state()` to GridTool; SceneryTool hooks call it; delete the direct pokes.
- [ ] **Step 3:** Delete `_delete_selected`'s fallback read of `ed.overlay.selected_cell`; it consumes `ed.selection` only.
- [ ] **Step 4:** Full suite green (355). The doctrine grep re-run and reported (view-writers count must not grow).
- [ ] **Step 5:** Commit: `git commit -m "refactor: reset_input_state seam + view-as-fact fallback dies — unification complete"`
