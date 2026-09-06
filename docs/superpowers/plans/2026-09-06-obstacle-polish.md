# Obstacle Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Obstacles become first-class editor citizens — drag-move with the whole footprint (the wave-1 cut, owner-vetoed 2026-09-06 morning) and a selection ring that spans the footprint — plus the wormhole `spin` sidecar option (0 = static).

**Architecture:** Editor gains a `_drag_prop` companion to `_drag_from`; `_move_prop` relocates data + occupancy + node in lockstep (delta-based, so grabbing any cell of a tramp works); `GridOverlay.selected_cells` mirrors `ghost_cells`. `spin` is a per-sidecar tunable consumed by the Wormhole class only.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **334 passing**): `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **DEPLOY FREEZE: commit locally only. NO push/export/deploy.**
- Drag-move is DELTA-based: new_anchor = old_anchor + (release_cell − press_cell); whole footprint must land on in-zone cells that are free or the piece's own; a blocked move leaves everything untouched.
- `current.props`, `occupancy`, node position, and `anchor_cell` meta must stay in lockstep through a move (the wave-1 lockstep doctrine).
- Selection: clicking ANY cell of a prop selects the whole piece — `overlay.selected_cell` = ANCHOR cell, `overlay.selected_cells` = footprint (crates: clicked cell + 1×1). Delete keeps working from any clicked cell (it reads the occupant, which every footprint cell maps to).
- `spin`: sidecar float, clamped 0.0–3.0, default 0.6 (today's feel), 0 = static; consumed by wormhole class only (stored harmlessly on others, like `tilt`).
- Crate behavior byte-identical: crate select/drag/delete paths untouched.
- GUT counts engine errors as failures; typed arrays append in tests.

---

### Task 1: Prop drag-move + footprint selection ring

**Files:**
- Modify: `src/editor/level_editor.gd`, `src/editor/grid_overlay.gd`
- Test: `tests/unit/test_level_editor_interactions.gd` (append)

**Interfaces:**
- Consumes: `Pieces.entry(id)` (`cells: Vector2i`), `PropBuilder.footprint_center(anchor_world, cells)`, `LevelEditor.footprint(anchor, cells)` (static), prop meta `prop_id`/`anchor_cell`, `occupancy` (all footprint cells → node).
- Produces: `_move_prop(body: Node2D, delta: Vector2i) -> void`; `GridOverlay.selected_cells: Vector2i`.

- [ ] **Step 1: Write the failing tests** (append to `tests/unit/test_level_editor_interactions.gd`)

```gdscript
func test_prop_selection_ring_spans_footprint_from_any_cell() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(5, 0))  # click the SECOND cell
	assert_eq(ed.overlay.selected_cell, Vector2i(4, 0), "selection snaps to the anchor")
	assert_eq(ed.overlay.selected_cells, Vector2i(2, 1), "ring spans the footprint")
	ed.carrying = "crate-wood"
	ed._press(Vector2i(8, 0))
	ed._press(Vector2i(8, 0))
	assert_eq(ed.overlay.selected_cells, Vector2i(1, 1), "crates stay 1x1")


func test_prop_drag_moves_whole_footprint() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(5, 0))          # grab by the second cell
	ed._release(Vector2i(9, 0), false)  # drag +4 columns
	assert_true(ed.occupancy.has(Vector2i(8, 0)), "new anchor occupied")
	assert_true(ed.occupancy.has(Vector2i(9, 0)), "new second cell occupied")
	assert_false(ed.occupancy.has(Vector2i(4, 0)), "old cells freed")
	assert_false(ed.occupancy.has(Vector2i(5, 0)))
	var w := EditorGrid.cell_to_world(Vector2i(8, 0))
	assert_eq(float(ed.current.props[0]["x"]), w.x, "data moved with the node")
	assert_eq(ed.occupancy[Vector2i(8, 0)].get_meta("anchor_cell"), Vector2i(8, 0), "meta updated")


func test_prop_move_blocked_by_overlap_stays_put() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(9, 0))
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(4, 0))
	ed._release(Vector2i(8, 0), false)  # footprint would hit the crate at (9,0)
	assert_true(ed.occupancy.has(Vector2i(4, 0)), "blocked move leaves the piece")
	assert_true(ed.occupancy.has(Vector2i(5, 0)))
	assert_false(ed.occupancy.has(Vector2i(8, 0)), "no half-move")
	var w := EditorGrid.cell_to_world(Vector2i(4, 0))
	assert_eq(float(ed.current.props[0]["x"]), w.x, "data untouched")
```

- [ ] **Step 2: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_level_editor_interactions.gd -gexit`
Expected: FAIL — `selected_cells` unknown; drag leaves occupancy at (4,0).

- [ ] **Step 3: Implement — grid_overlay.gd**

Add `var selected_cells := Vector2i(1, 1)` beside `selected_cell`, and replace the selection draw block:

```gdscript
	if selected_cell.x >= 0:
		var s := EditorGrid.cell_to_world(selected_cell)
		var sel_size := Vector2(selected_cells.x * 64.0 + 4.0, selected_cells.y * 63.0 + 4.0)
		var sel_top_left := Vector2(s.x - 34.0, s.y - 33.5 - (selected_cells.y - 1) * 63.0)
		draw_rect(Rect2(sel_top_left, sel_size), Color(1.0, 0.83, 0.29, 0.95), false, 4.0)
```

(For 1×1 this is a 68×67 ring vs the old 68×68 — imperceptible; footprints get a single spanning ring.)

- [ ] **Step 4: Implement — level_editor.gd**

Member beside `_drag_from`:

```gdscript
var _drag_prop: Node2D = null  # prop being drag-moved, null = none/crate
```

`_press` occupied-branch becomes (crate path byte-identical in effect):

```gdscript
	if occupancy.has(cell):
		var node: Node2D = occupancy[cell]
		if node is Crate:
			overlay.selected_cell = cell
			overlay.selected_cells = Vector2i(1, 1)
			_drag_from = cell
			_drag_prop = null
		else:
			var e := Pieces.entry(str(node.get_meta("prop_id")))
			overlay.selected_cell = node.get_meta("anchor_cell")
			overlay.selected_cells = e["cells"] if not e.is_empty() else Vector2i(1, 1)
			_drag_from = cell
			_drag_prop = node
	else:
		overlay.selected_cell = Vector2i(-1, -1)
		overlay.selected_cells = Vector2i(1, 1)
		_drag_from = Vector2i(-1, -1)
		_drag_prop = null
```

`_release` gains the prop branch (insert BEFORE the existing crate-move elif; keep that elif untouched) and clears `_drag_prop` beside `_drag_from` at the end:

```gdscript
	elif _drag_prop != null and _drag_from.x >= 0 and not over_ui and cell != _drag_from:
		_move_prop(_drag_prop, cell - _drag_from)
```

New method beside `_delete_prop`:

```gdscript
# Delta-based footprint move: data, occupancy, node, and meta in lockstep.
# A blocked target (out of zone / any foreign occupant) is a no-op.
func _move_prop(body: Node2D, delta: Vector2i) -> void:
	var pid := str(body.get_meta("prop_id"))
	var e := Pieces.entry(pid)
	if e.is_empty():
		return
	var old_anchor: Vector2i = body.get_meta("anchor_cell")
	var new_anchor := old_anchor + delta
	var cells: Vector2i = e["cells"]
	for c in footprint(new_anchor, cells):
		if not EditorGrid.in_zone(c):
			return
		var occ: Variant = occupancy.get(c)
		if occ != null and occ != body:
			return
	var old_w := EditorGrid.cell_to_world(old_anchor)
	var new_w := EditorGrid.cell_to_world(new_anchor)
	for i in current.props.size():
		var p: Dictionary = current.props[i]
		if (
			p["id"] == pid
			and is_equal_approx(float(p["x"]), old_w.x)
			and is_equal_approx(float(p["y"]), old_w.y)
		):
			current.props[i] = {"id": pid, "x": new_w.x, "y": new_w.y}
			break
	for c in footprint(old_anchor, cells):
		occupancy.erase(c)
	for c in footprint(new_anchor, cells):
		occupancy[c] = body
	body.position = PropBuilder.footprint_center(new_w, cells)
	body.set_meta("anchor_cell", new_anchor)
	overlay.selected_cell = new_anchor
	overlay.selected_cells = cells
	overlay.refresh()
```

`_update_ghost` drag branch learns props (and the footprint ok-check must treat the piece's own cells as free). Replace the held-lookup block and the non-crate ok loop:

```gdscript
	if id == "" and _drag_from.x >= 0 and _lmb_down:
		var held: Variant = occupancy.get(_drag_from)
		if held != null and held is Crate:
			id = (held as Crate).type_id
		elif _drag_prop != null:
			id = str(_drag_prop.get_meta("prop_id"))
```

and in the footprint check:

```gdscript
		for c in footprint(cell, ghost_cells):
			var occ: Variant = occupancy.get(c)
			if not EditorGrid.in_zone(c) or (occ != null and occ != _drag_prop):
				ok = false
				break
```

Also anchor the drag ghost to the piece, not the cursor: after computing `var cell := _mouse_cell()`, add:

```gdscript
	if _drag_prop != null and _lmb_down:
		cell += (_drag_prop.get_meta("anchor_cell") as Vector2i) - _drag_from
```

Hygiene: `_enter_scenery` resets `_drag_prop = null` beside its `_drag_from` reset; `_delete_prop` sets `_drag_prop = null` and `overlay.selected_cells = Vector2i(1, 1)` when it clears the selection.

- [ ] **Step 5: Verify + commit**

Focused file green (existing 30 + 3 new); full suite expected: **337 passing**.

```bash
git add src/editor tests/unit/test_level_editor_interactions.gd
git commit -m "feat: obstacles drag-move as whole footprints — spanning selection ring, lockstep data"
```

---

### Task 2: Wormhole `spin` sidecar option

**Files:**
- Modify: `src/level/pieces.gd` (parse_sidecar), `src/level/wormhole.gd` (var replaces const usage), `src/level/prop_builder.gd` (pass-through)
- Test: `tests/unit/test_pieces.gd` (append)

**Interfaces:**
- Consumes: `parse_sidecar` clamp conventions; PropBuilder wormhole branch.
- Produces: entry key `spin: float`; `Wormhole.spin: float`.

- [ ] **Step 1: Write the failing tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func test_parse_sidecar_spin_clamped() -> void:
	assert_eq(Pieces.parse_sidecar("t", {})["spin"], 0.6, "default = today's feel")
	assert_eq(Pieces.parse_sidecar("t", {"spin": 0})["spin"], 0.0, "0 = static")
	assert_eq(Pieces.parse_sidecar("t", {"spin": 99.0})["spin"], 3.0, "clamped high")
	assert_eq(Pieces.parse_sidecar("t", {"spin": "fast"})["spin"], 0.6, "non-number falls back")


func test_wormhole_spin_zero_is_static() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "static-spin"
	var a := EditorGrid.cell_to_world(Vector2i(3, 0))
	l.props.append({"id": "wormhole-blue", "x": a.x, "y": a.y})
	var spawned := PropBuilder.spawn_props(host, l)  # lone → warns (GUT-safe)
	var hole: Wormhole = spawned[0]
	assert_eq(hole.spin, 0.6, "builder passes the sidecar spin (default)")
	hole.spin = 0.0
	await wait_process_frames(2)
	var rot_before: float = hole._sprite.rotation if hole._sprite else 0.0
	hole._process(1.0)
	var rot_after: float = hole._sprite.rotation if hole._sprite else 0.0
	assert_eq(rot_before, rot_after, "spin 0 = static portal")
```

- [ ] **Step 2: Run to verify failure** — FAIL: no `spin` key.

- [ ] **Step 3: Implement**

`pieces.gd` `parse_sidecar`, beside the bounce block:

```gdscript
	var spin := 0.6
	var raw_spin: Variant = raw.get("spin", 0.6)
	if raw_spin is float or raw_spin is int:
		spin = clampf(float(raw_spin), 0.0, 3.0)
```

and add `"spin": spin` to the returned dictionary.

`wormhole.gd`: replace the const usage — keep `const SPIN_RAD_PER_SEC := 0.6` as the documented default, add `var spin := SPIN_RAD_PER_SEC`, and `_process` rotates by `spin * delta`.

`prop_builder.gd` wormhole branch, beside the meta lines: `hole.spin = e["spin"]`.

- [ ] **Step 4: Verify + commit**

Focused green; full suite expected: **339 passing**.

```bash
git add src/level/pieces.gd src/level/wormhole.gd src/level/prop_builder.gd tests/unit/test_pieces.gd
git commit -m "feat: wormhole spin is a sidecar dial — 0 = static, default keeps today's feel"
```
