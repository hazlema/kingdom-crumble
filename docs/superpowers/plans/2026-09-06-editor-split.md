# Editor Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the editor's 18 hand-maintained sync sites to ONE selection rule, per the audit (docs/audits/2026-09-06-editor-architecture.md) and the owner's doctrine: *the editor loads the JSON, renders it, everything is selectable — selection is one fact, views render it.*

**Architecture:** Five refactor tasks. (1) The bake/image pipeline moves out. (2-3) Two tools — GridTool (crates + props, the "game layer"; they share the grid model, do NOT split them) and SceneryTool (the "scenery layer") — own their interaction state behind enter/exit hooks; the shared RMB pan-vs-menu disambiguator is written once. (4) A single `_sync_views()` choke point owns inspector/overlay/gizmo agreement. (5) Registry hygiene. **NO behavior or visual changes** — the 348-test suite is the contract and must be green after every task.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **348 passing**) after EVERY task: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **DEPLOY FREEZE: commit locally only. NO push/export/deploy.**
- **REFACTOR ONLY: zero behavior change, zero visual change, zero test edits.** If a test fails, the move broke something — fix the move, never the test. If a move genuinely cannot preserve behavior, report BLOCKED.
- **Forwarder contract** — these editor symbols are referenced by tests and MUST keep working exactly (property or method forwarders where the owner moves into a tool): `carrying`, `mode`, `occupancy`, `overlay`, `palette`, `menu`, `current`, `save_path`, `selected_overlay`, `_scenery_pieces`, `_spawned_props`, `_press(cell)`, `_release(cell, over_ui)`, `_rebuild()`, `_rebuild_scenery()`, `_bake_scenery()`, `_delete_selected()`, `_delete_selected_piece()`, `_drop_background()`, `_enter_scenery()`, `_exit_scenery()`, `_mouse_over_ui(p)`, `_on_clear()`, `_on_save_as(stem)`, `_pick_piece(world)`, `_show_crate_info(cell)`, `_crate_info`, `_info_key`, `import_scenery_image(path)`, `_unhandled_input(ev)`.
- Healthy layers are OFF LIMITS (audit-verified): Pieces, PropBuilder, SceneryBuilder, LevelJson/LevelStore/LevelLayout, EditorGrid, GridOverlay + SceneryGizmo internals, the polled-`_process` input model.
- Move code VERBATIM wherever the task says verbatim — refactor structure, not implementations.
- GDScript traps: `%Node` unique-name lookups only resolve inside the owning scene — moved code running in a RefCounted/Node tool must reach UI via `ed` (the editor reference); GUT counts engine errors as failures.

---

### Task 1: Extract the darkroom (`SceneryBake`)

**Files:**
- Create: `src/editor/scenery_bake.gd`
- Modify: `src/editor/level_editor.gd` (remove moved functions; add forwarder + delegate call sites)

**Interfaces:**
- Produces: `class_name SceneryBake extends RefCounted` with `static func bake(layout: LevelLayout) -> int` (returns skipped count, exactly `_bake_scenery`'s contract) and the moved helpers as statics.

- [ ] **Step 1:** Read `src/editor/level_editor.gd` and locate this exact function inventory: `_bake_scenery`, `_rotate_image`, `_bilinear_sample`, `_strip_background`, `_cap_image_to_max`, `_strip_edit_keys`, plus any private const used ONLY by them (search each const's other references before moving it).
- [ ] **Step 2:** Create `src/editor/scenery_bake.gd` (`class_name SceneryBake extends RefCounted`; header comment: "Save-time scenery baking + image processing. Moved verbatim from level_editor.gd (editor-split task 1) — pure functions of the layout, no editor state."). Move the inventory VERBATIM as `static func`s; `_bake_scenery(current-references)` becomes `static func bake(layout: LevelLayout) -> int` with `current` → `layout` renamed inside (the ONLY permitted edit besides `static` keywords and helper-call prefixes).
- [ ] **Step 3:** In level_editor.gd: delete the moved bodies; add the test-contract forwarder `func _bake_scenery() -> int: return SceneryBake.bake(current)`; repoint internal callers (`_bake_and_capture` etc. — grep `_bake_scenery\|_strip_edit_keys` etc. for every call site).
- [ ] **Step 4:** Focused runs: `-gtest=res://tests/unit/test_scenery_mode.gd` and `-gtest=res://tests/unit/test_audit_fixes.gd` (both call `ed._bake_scenery`). Then FULL suite: **348 passing**, zero test edits.
- [ ] **Step 5:** Commit: `git commit -m "refactor: bake pipeline moves to SceneryBake — pure move, editor sheds ~450 lines"`

---

### Task 2: EditorTool base + GridTool (crates + props together)

**Files:**
- Create: `src/editor/tools/editor_tool.gd`, `src/editor/tools/grid_tool.gd`
- Modify: `src/editor/level_editor.gd`

**Interfaces:**
- Produces:

```gdscript
# src/editor/tools/editor_tool.gd
class_name EditorTool
extends RefCounted

# One interaction model. The editor owns the document, camera, and
# shared services; a tool owns ITS input state and nothing else.
# enter()/exit() are the ONLY places cross-mode state may be touched.

var ed: LevelEditor


func _init(editor: LevelEditor) -> void:
	ed = editor


func enter() -> void:
	pass


func exit() -> void:
	pass


# Called every frame from the editor's _process while active.
func process(_mouse: Vector2, _over_ui: bool) -> void:
	pass
```

- `GridTool` (extends EditorTool) owns and moves VERBATIM from level_editor.gd: `carrying`, `_drag_from`, `_drag_prop`, `_lmb_down` (its own copy — this kills shared-edge-detector resets), `_crate_context`, `_crate_info`, `_info_cell`, `_info_key`, and the functions `_press`, `_release`, `_try_place`, `_place`, `_move`, `_move_prop`, `_delete_prop`, `_prop_entry_for`, `_delete_selected` (crate/prop dispatch), `_update_ghost`, `_show_crate_context`, `_on_crate_context_item`, `_show_crate_info`, `_on_crate_info_action` — bodies unchanged except: `%PieceInspector`/`overlay`/`menu`/`occupancy`/`current`/`footprint`/`Pieces`-static references become `ed.`-qualified where they touch editor-owned things (`overlay` → `ed.overlay`, `current` → `ed.current`, `occupancy` → `ed.occupancy`, `%PieceInspector` → `ed.inspector()` — add `func inspector() -> PieceInspector: return %PieceInspector` on the editor).
- `GridTool.process(mouse, over_ui)` = the current crates-mode block of `_process` (LMB edge detection + press/release + `_update_ghost` + the RMB menu block) moved verbatim, using the shared disambiguator below.
- Editor gains ONE shared RMB disambiguator (replaces the two verbatim copies): 

```gdscript
# Shared by all tools: true exactly when this frame is an RMB release
# without significant motion (a moving RMB is a camera pan).
func rmb_menu_release(mouse: Vector2, over_ui: bool) -> bool:
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if rmb and not _rmb_down:
		_rmb_press_pos = mouse
		_rmb_down = true
	elif not rmb and _rmb_down:
		_rmb_down = false
		return not over_ui and mouse.distance_to(_rmb_press_pos) < _CONTEXT_MENU_MOTION_THRESHOLD
	return false
```

- Editor `_process` becomes: camera pan + `over_ui` computation + `_tool.process(mouse, over_ui)` dispatch (scenery block stays inline until Task 3).
- Forwarder contract (Global Constraints list) satisfied via properties/methods, e.g.:

```gdscript
var carrying: String:
	get: return _grid_tool.carrying
	set(v): _grid_tool.carrying = v


func _press(cell: Vector2i) -> void:
	_grid_tool._press(cell)


func _release(cell: Vector2i, over_ui: bool) -> void:
	_grid_tool._release(cell, over_ui)


func _delete_selected() -> void:
	_grid_tool._delete_selected()


func _show_crate_info(cell: Vector2i) -> void:
	_grid_tool._show_crate_info(cell)
```

with `_crate_info`/`_info_key` as forwarding properties the same way. The palette `asset_picked` lambda routes into the tool (`_grid_tool.carrying = id` + its resets).

- [ ] **Step 1:** Create the two tool files (base verbatim above; GridTool per the move inventory).
- [ ] **Step 2:** Gut the moved members/functions from level_editor.gd; add `var _grid_tool: GridTool` (constructed in `_ready` before signal wiring), `inspector()`, `rmb_menu_release`, and every forwarder.
- [ ] **Step 3:** Focused: `-gtest=res://tests/unit/test_level_editor_interactions.gd` (36 tests — the contract). Fix moves, never tests. Then FULL suite: **348 passing**.
- [ ] **Step 4:** Commit: `git commit -m "refactor: GridTool owns crate/prop interaction — shared RMB disambiguator, per-tool input state"`

---

### Task 3: SceneryTool

**Files:**
- Create: `src/editor/tools/scenery_tool.gd`
- Modify: `src/editor/level_editor.gd`

**Interfaces:**
- Produces: `SceneryTool extends EditorTool` owning (moved VERBATIM, `ed.`-qualified as in Task 2): `selected_overlay`, `_scenery_dragging`, `_scenery_drag_start_world`, `_scenery_drag_piece_origin`, `_scenery_handle`, `_scenery_drag_press_scale`, `_scenery_context`, its own `_lmb_down`, and the functions `_scenery_process` (becomes `process`), `_pick_piece`, `_scenery_press/_drag/handles helpers`, `_show_scenery_context`, `_on_scenery_context_item`, `_delete_selected_piece`, `_drop_background`, `_piece_for_overlay`, `_reopen_inspector` (if scenery-only — verify callers first; if `_rebuild` calls it, it stays on the editor and delegates).
- `_enter_scenery`/`_exit_scenery` become `switch_tool(_scenery_tool)` / `switch_tool(_grid_tool)` on the editor:

```gdscript
func switch_tool(next: EditorTool) -> void:
	_tool.exit()
	_tool = next
	_tool.enter()
```

with the old bodies split INTO the tools' `enter()`/`exit()` hooks (each hook touches only its OWN tool's state + the editor-owned UI it manages — the "reset the other mode's flags" lines DIE here because each tool has its own edge detectors). `mode` stays as a forwarding property (`get: return Mode.SCENERY if _tool == _scenery_tool else Mode.CRATES`) for the test contract; `_enter_scenery`/`_exit_scenery` become thin forwarders calling `switch_tool`.

- [ ] **Step 1:** Create scenery_tool.gd per the inventory; wire `switch_tool`; convert enter/exit.
- [ ] **Step 2:** Forwarders: `selected_overlay` property, `_delete_selected_piece`, `_drop_background`, `_pick_piece`, `_enter_scenery`, `_exit_scenery`, `_rebuild_scenery` (stays editor-side — it's document rendering, not interaction; verify and keep), `import_scenery_image` (editor-side orchestration — verify its body touches only document + panels; keep on editor).
- [ ] **Step 3:** Focused: `-gtest=res://tests/unit/test_scenery_mode.gd` (23 tests). Then FULL suite: **348 passing**, zero test edits.
- [ ] **Step 4:** Commit: `git commit -m "refactor: SceneryTool — per-tool enter/exit, cross-mode state resets die"`

---

### Task 4: Selection authority — the ONE rule

**Files:**
- Modify: `src/editor/level_editor.gd`, `src/editor/tools/grid_tool.gd`, `src/editor/tools/scenery_tool.gd`
- Test: `tests/unit/test_level_editor_interactions.gd` (append NEW tests only — existing untouched)

**Interfaces:**
- Produces, on the editor:

```gdscript
# THE rule (owner doctrine, 2026-09-06): selection is one fact; views
# render it. Nothing opens/closes/re-points the inspector, selection
# ring, or gizmo except _sync_views(). Tools WRITE the fact via the
# three setters; _rebuild re-resolves it; everything else just reads.
var selection := {"kind": "none"}
# kinds: none | cell {cell, cells, node} | overlay {index}


func select_cell(cell: Vector2i, cells: Vector2i, node: Node2D) -> void:
	selection = {"kind": "cell", "cell": cell, "cells": cells, "node": node}
	_sync_views()


func select_overlay(index: int) -> void:
	selection = {"kind": "overlay", "index": index}
	_sync_views()


func deselect() -> void:
	selection = {"kind": "none"}
	_sync_views()


func _sync_views() -> void:
	match selection.get("kind"):
		"cell":
			# ring at the piece's anchor, spanning its footprint; reduced
			# inspector for animatable props — assembled VERBATIM from
			# today's GridTool._press occupied-branch decisions
			...
		"overlay":
			...
		_:
			overlay.selected_cell = Vector2i(-1, -1)
			overlay.selected_cells = Vector2i(1, 1)
			inspector().close()
			_gizmo.piece = null
			_gizmo.visible = false
	overlay.refresh()
```

The `...` bodies are assembled from TODAY'S behavior — this task RELOCATES decisions, it does not change them: the "cell" branch does what `GridTool._press`'s occupied-branch does now (ring at anchor, footprint span, reduced-inspector open for animatable props via `_prop_entry_for`, close otherwise); the "overlay" branch does what scenery selection does now (gizmo point + full inspector open via `_reopen_inspector`'s logic). Then:

- GridTool `_press`/`_delete_prop`/`_move_prop` and SceneryTool selection sites STOP touching `overlay.selected_*`/`inspector()` directly — they call the three setters. Every `inspector().close()` sprinkled for hygiene (palette lambda, `_try_place`, crate-click, `_rebuild` head, enter/exit hooks) collapses into `deselect()` or into `_sync_views` re-resolution.
- `_rebuild()` and `_rebuild_scenery()` end with `_sync_views()` (re-resolving `selection` against the fresh nodes/dicts — if the selected thing no longer exists, downgrade to `{"kind": "none"}`). This replaces `_reopen_inspector` AND makes stale-inspector bugs structurally impossible.
- Count check (the audit metric): after this task, `grep -c "inspector()\.\(open\|close\)" src/editor/` must be ≤ 4 sites, all inside `_sync_views` (+ the scenery gizmo/full-open path if it resists unification — justify in the report if so).

- [ ] **Step 1:** Write 2 NEW tests first: (a) load-path stale-selection — select a prop, call `ed._on_clear()`-equivalent (`ed.current = LevelLayout.new(); ed._rebuild()`), assert inspector hidden + selection kind "none"; (b) rebuild re-resolution — select an animatable prop, place a crate (triggers rebuild), assert the inspector is STILL OPEN and its writes land in the CURRENT props entry (set a dial after the rebuild, assert `ed.current.props[0]` got it). Watch (b) fail today (close-on-rebuild), confirming the upgrade.
- [ ] **Step 2:** Implement selection + `_sync_views` + setter migration + rebuild re-resolution.
- [ ] **Step 3:** Focused interactions + scenery files; count check; FULL suite: **350 passing** (348 + 2), zero existing-test edits.
- [ ] **Step 4:** Commit: `git commit -m "refactor: selection is one fact — _sync_views is the only view writer, rebuilds re-resolve instead of closing"`

---

### Task 5: Registry hygiene

**Files:**
- Modify: `src/editor/editor_menu.gd`, `src/editor/level_editor.gd`, `src/editor/piece_inspector.gd`, `src/editor/scenery_panel.gd` (small)

- [ ] **Step 1:** `editor_menu.gd`: `any_dialog_open()` iterates a `_dialogs: Array` built in `_ready` from its known dialogs (replaces the hand list); editor-side popups (`_crate_info` via the tool, the two context menus) register through a small `ed.register_popup(p)` list consulted by BOTH modes' `over_ui` (closes the audit's scenery-mode Info-dialog leak).
- [ ] **Step 2:** `_mouse_over_ui` iterates a `_ui_panels: Array` registered in `_ready` (same panels as today — no visual change).
- [ ] **Step 3:** Fix the two stale comments (piece_inspector.gd:12-18 and the "pauses behaviors" line near the rebuild) to describe post-8c02d4e reality (verbs stay live; rebuild preserves them).
- [ ] **Step 4:** Replace `%SceneryPanel.get_node("%Pieces")` reach-through with a `SceneryPanel` method (e.g. `set_piece_thumbs(list)` or `pieces_list() -> ItemList` — match how it's used).
- [ ] **Step 5:** FULL suite: **350 passing**. Commit: `git commit -m "refactor: dialog/panel registries + doc truth — hand-enumerated UI lists die"`

---

## Deviations pre-declared for reviewers

- Task 4 upgrades one behavior deliberately: the inspector now SURVIVES rebuilds via re-resolution instead of closing (strictly better UX; the close-on-move/rebuild choices were stopgaps and their tests asserted closes only where written — the 2 new tests pin the upgrade; if any EXISTING test asserts a close that re-resolution keeps open, STOP and report which, do not edit it without controller sign-off).
- `_sync_views` bodies are assembled from existing behavior rather than printed verbatim in this plan — the implementer copies today's decisions from the named functions; the reviewers verify equivalence.
- Forwarders may look like boilerplate; they ARE the point — the test surface is the public API until a future cleanup retires it.
