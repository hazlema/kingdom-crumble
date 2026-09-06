# Animatable Props Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Props opt into scenery-style animation: sidecar `animatable: true` + per-placement `behavior`/`speed`/`amplitude` keys, edited with the existing piece inspector — sprite-only, physics glued to the grid.

**Architecture:** The prop's sprite child becomes a **NarfDecor** (extends Sprite2D, so the wormhole's `_sprite` discovery, tint sampling, and whoosh pulse keep working). PropBuilder configures its verb/dials from placement keys when the sidecar allows. The inspector gains a reduced mode reusing its existing `open(dict, NarfDecor)` contract, writing into the `current.props` entry by reference.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless, NarfKit (NarfDecor: `enum Behavior {NONE, SPIN, SWAY, BOB, DRIFT, WANDER}`, `speed`, `movement` — JSON key stays `amplitude` per save-compat convention).

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **337 passing**): `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **DEPLOY FREEZE: commit locally only. NO push/export/deploy.**
- Spec: `docs/superpowers/specs/2026-09-06-animatable-props-design.md`. Sidecar `animatable` strict bool (non-bool → named warning + false). Prop verbs curated `NONE|SPIN|SWAY|BOB` (travel verbs rejected: `"prop %d: bad behavior"`); dials numeric (`"prop %d: bad dial"`), speed clamped 0.0–2.0, amplitude clamped 0–12 px — clamped in validation AND re-clamped at spawn. Keys on a non-animatable piece: parse fine, spawn warns + ignores. No-key placements = NONE (static) — owner-approved default inversion; the wormhole's hardcoded `_process` spin is retired.
- Sprite-only: body/collision position and rotation NEVER change.
- `_move_prop` must PRESERVE unknown entry keys (duplicate + update x/y) — required fix to wave-1 code, regression-pinned.
- Crate/scenery behavior byte-identical; existing 337 tests are the net.
- GUT counts engine errors as failures; typed arrays append in tests.

---

### Task 1: Format — `animatable` sidecar + per-placement animation keys

**Files:**
- Modify: `src/level/pieces.gd` (parse_sidecar), `src/level/level_json.gd` (props validation + parse copy)
- Test: `tests/unit/test_pieces.gd` (append)

**Interfaces:**
- Produces: entry key `animatable: bool`; `LevelJson.PROP_BEHAVIORS := ["NONE", "SPIN", "SWAY", "BOB"]`; props entries round-trip `behavior`/`speed`/`amplitude`.

- [ ] **Step 1: Failing tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func test_parse_sidecar_animatable_strict_bool() -> void:
	assert_false(Pieces.parse_sidecar("t", {})["animatable"], "default off")
	assert_true(Pieces.parse_sidecar("t", {"animatable": true})["animatable"])
	assert_false(Pieces.parse_sidecar("t", {"animatable": 1})["animatable"], "non-bool warns + off")  # warns


func test_props_animation_key_validation() -> void:
	var good := _props_doc([{"id": "wormhole-blue", "x": 0, "y": 0, "behavior": "SPIN", "speed": 0.6}])
	assert_eq(LevelJson.validate(good), "")
	var travel := _props_doc([{"id": "wormhole-blue", "x": 0, "y": 0, "behavior": "WANDER"}])
	assert_eq(LevelJson.validate(travel), "prop 0: bad behavior", "travel verbs rejected for props")
	var junk := _props_doc([{"id": "wormhole-blue", "x": 0, "y": 0, "behavior": 7}])
	assert_eq(LevelJson.validate(junk), "prop 0: bad behavior")
	var dial := _props_doc([{"id": "wormhole-blue", "x": 0, "y": 0, "amplitude": "big"}])
	assert_eq(LevelJson.validate(dial), "prop 0: bad dial")


func test_props_animation_keys_round_trip() -> void:
	var l := LevelLayout.new()
	l.title = "anim-rt"
	l.props.append({"id": "wormhole-blue", "x": 100.0, "y": 500.0, "behavior": "SWAY", "speed": 1.0, "amplitude": 8.0})
	var back := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(back)
	assert_eq(back.props[0].get("behavior"), "SWAY")
	assert_eq(float(back.props[0].get("amplitude")), 8.0)
	l.props.append({"id": "block-stone", "x": 200.0, "y": 500.0})
	var back2 := LevelJson.parse(LevelJson.serialize(l))
	assert_false(back2.props[1].has("behavior"), "keyless entries stay keyless")
```

- [ ] **Step 2: Run to verify failure** — focused `-gtest=res://tests/unit/test_pieces.gd`: FAIL (no animatable key; behavior unvalidated; parse drops keys).

- [ ] **Step 3: Implement**

`pieces.gd` `parse_sidecar` — beside the powerup block:

```gdscript
	var animatable := false
	var raw_anim: Variant = raw.get("animatable", false)
	if raw_anim is bool:
		animatable = raw_anim
	elif raw_anim != null and not (raw_anim is bool):
		push_warning("Pieces: %s animatable must be true/false — off" % id)
```

(the strict-bool `hidden` lesson: only literal `true` enables) — and add `"animatable": animatable` to the returned dict.

`level_json.gd` — const beside MAX_PROPS: `const PROP_BEHAVIORS := ["NONE", "SPIN", "SWAY", "BOB"]`. In the props validation loop, after the coords check:

```gdscript
			if (p as Dictionary).has("behavior"):
				var b: Variant = (p as Dictionary)["behavior"]
				if not b is String or b not in PROP_BEHAVIORS:
					return "prop %d: bad behavior" % pi
			for dial in ["speed", "amplitude"]:
				if (p as Dictionary).has(dial):
					var dv: Variant = (p as Dictionary)[dial]
					if not (dv is float or dv is int):
						return "prop %d: bad dial" % pi
```

In `parse()`'s props copy loop, preserve the optional keys with validation-time clamps:

```gdscript
	for p in data.get("props", []):
		var entry := {"id": String(p["id"]), "x": float(p["x"]), "y": float(p["y"])}
		if (p as Dictionary).has("behavior"):
			entry["behavior"] = String(p["behavior"])
		if (p as Dictionary).has("speed"):
			entry["speed"] = clampf(float(p["speed"]), 0.0, 2.0)
		if (p as Dictionary).has("amplitude"):
			entry["amplitude"] = clampf(float(p["amplitude"]), 0.0, 12.0)
		l.props.append(entry)
```

- [ ] **Step 4: Verify + commit** — focused green; full suite **340**.

```bash
git add src/level/pieces.gd src/level/level_json.gd tests/unit/test_pieces.gd
git commit -m "feat: animatable sidecar flag + per-placement animation keys in props"
```

---

### Task 2: Runtime — NarfDecor sprite children, configured from data

**Files:**
- Modify: `src/level/prop_builder.gd` (both sprite sites → NarfDecor + config), `src/level/wormhole.gd` (retire hardcoded spin), `pieces/wormhole-blue.json` + `pieces/wormhole-orange.json` (gain `"animatable": true`)
- Test: `tests/unit/test_pieces.gd` (append)

**Interfaces:**
- Consumes: Task 1's entry/placement keys; `NarfDecor` (`behavior`, `speed`, `movement`).
- Produces: prop sprite children are NarfDecor (IS-A Sprite2D — wormhole `_sprite` discovery, `_fx_tint`, and the gulp pulse untouched).

- [ ] **Step 1: Failing tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func test_animatable_placement_configures_sprite_verb() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "anim-spawn"
	var a := EditorGrid.cell_to_world(Vector2i(3, 0))
	l.props.append({"id": "wormhole-blue", "x": a.x, "y": a.y, "behavior": "SPIN", "speed": 0.8})
	var spawned := PropBuilder.spawn_props(host, l)  # lone → warns (GUT-safe)
	var sprite: NarfDecor = null
	for c in spawned[0].get_children():
		if c is NarfDecor:
			sprite = c
	assert_not_null(sprite, "prop sprite is a NarfDecor")
	assert_eq(sprite.behavior, NarfDecor.Behavior.SPIN)
	assert_eq(sprite.speed, 0.8)
	var body_rot: float = (spawned[0] as Node2D).rotation
	await wait_process_frames(5)
	assert_eq((spawned[0] as Node2D).rotation, body_rot, "body never rotates — sprite-only")


func test_keyless_placement_is_static() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "still"
	var a := EditorGrid.cell_to_world(Vector2i(3, 0))
	l.props.append({"id": "wormhole-blue", "x": a.x, "y": a.y})
	var spawned := PropBuilder.spawn_props(host, l)  # lone → warns (GUT-safe)
	var sprite: NarfDecor = spawned[0].get_children().filter(func(c): return c is NarfDecor)[0]
	assert_eq(sprite.behavior, NarfDecor.Behavior.NONE, "no keys = still portal (owner-approved default)")
	await wait_process_frames(5)
	assert_eq(sprite.rotation, 0.0, "hardcoded spin retired")


func test_animation_keys_on_non_animatable_warn_and_ignore() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "nope"
	var a := EditorGrid.cell_to_world(Vector2i(3, 0))
	l.props.append({"id": "block-stone", "x": a.x, "y": a.y, "behavior": "SPIN", "speed": 2.0})
	var spawned := PropBuilder.spawn_props(host, l)  # warns: not animatable (GUT-safe)
	var sprite: NarfDecor = spawned[0].get_children().filter(func(c): return c is NarfDecor)[0]
	assert_eq(sprite.behavior, NarfDecor.Behavior.NONE, "sidecar gate holds")
```

- [ ] **Step 2: Run to verify failure** — FAIL (sprites are plain Sprite2D; wormhole still spins).

- [ ] **Step 3: Implement — prop_builder.gd**

Replace BOTH sprite constructions (wormhole branch and static/tramp path) with a shared helper call `_attach_sprite(body, e, prop)`:

```gdscript
static func _attach_sprite(body: Node2D, e: Dictionary, prop: Dictionary) -> void:
	var sprite := NarfDecor.new()
	sprite.texture = e["texture"]
	var has_keys := prop.has("behavior") or prop.has("speed") or prop.has("amplitude")
	if e.get("animatable", false) == true:
		var verb := str(prop.get("behavior", "NONE"))
		var bi := NarfDecor.Behavior.keys().find(verb)
		if bi >= NarfDecor.Behavior.NONE and bi <= NarfDecor.Behavior.BOB:
			sprite.behavior = bi as NarfDecor.Behavior
		sprite.speed = clampf(float(prop.get("speed", 0.6)), 0.0, 2.0)
		sprite.movement = clampf(float(prop.get("amplitude", 6.0)), 0.0, 12.0)
	elif has_keys:
		push_warning(
			"PropBuilder: '%s' is not animatable — ignoring animation keys" % str(prop.get("id", ""))
		)
	body.add_child(sprite)
```

(spawn-side re-clamp = the spec's belt-and-suspenders; verbs above BOB can't arrive past validation but the index guard holds for hand-constructed layouts.)

- [ ] **Step 4: Implement — wormhole.gd + sidecars**

Delete `const SPIN_RAD_PER_SEC` and the whole `_process` function (the NarfDecor child animates itself; `_sprite` discovery via `c is Sprite2D` still matches — NarfDecor extends Sprite2D — and `_fx_tint`/gulp pulse are untouched). Add `"animatable": true` to both wormhole sidecars.

- [ ] **Step 5: Verify + commit** — focused green (three deliberate warnings); full suite **343**. The whoosh tests from the wormhole run must still pass (they find the sprite via `is Sprite2D` — NarfDecor qualifies).

```bash
git add src/level/prop_builder.gd src/level/wormhole.gd pieces/wormhole-blue.json pieces/wormhole-orange.json tests/unit/test_pieces.gd
git commit -m "feat: prop sprites are NarfDecors — data-driven verbs, hardcoded wormhole spin retired"
```

---

### Task 3: Editor — reduced inspector for animatable props + key-preserving moves

**Files:**
- Modify: `src/editor/piece_inspector.gd` (reduced mode), `src/editor/level_editor.gd` (open/close wiring + `_move_prop` key preservation)
- Test: `tests/unit/test_level_editor_interactions.gd` (append)

**Interfaces:**
- Consumes: `PieceInspector.open(overlay: Dictionary, piece: NarfDecor)` (existing; writes `behavior`/`speed`/`amplitude` into the dict BY REFERENCE and pokes the piece); prop bodies' NarfDecor children (Task 2); `_press`/`_move_prop`/`_delete_prop` (wave-1 polish).
- Produces: `PieceInspector.open(overlay, piece, reduced := false)` — reduced hides pivot/axis/travel/tilt, restricts the verb dropdown to NONE/SPIN/SWAY/BOB, caps the amplitude slider at 12 (normal opens restore full range/items).

- [ ] **Step 1: Failing tests** (append to `tests/unit/test_level_editor_interactions.gd`)

```gdscript
func test_selecting_animatable_prop_opens_reduced_inspector() -> void:
	ed.carrying = "wormhole-blue"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(4, 0))  # select it
	var insp: Control = ed.get_node("%PieceInspector")
	assert_true(insp.visible, "inspector opens for animatable prop")
	insp.set_behavior_by_name("SPIN")
	insp.set_speed(1.2)
	assert_eq(ed.current.props[0].get("behavior"), "SPIN", "writes land in the level data")
	assert_eq(float(ed.current.props[0].get("speed")), 1.2)


func test_selecting_non_animatable_prop_keeps_inspector_closed() -> void:
	ed.carrying = "block-stone"
	ed._press(Vector2i(4, 0))
	ed._press(Vector2i(4, 0))
	var insp: Control = ed.get_node("%PieceInspector")
	assert_false(insp.visible, "statics are not animatable")


func test_move_prop_preserves_animation_keys() -> void:
	ed.carrying = "wormhole-blue"
	ed._press(Vector2i(4, 0))
	ed.current.props[0]["behavior"] = "SWAY"
	ed.current.props[0]["amplitude"] = 8.0
	ed._press(Vector2i(4, 0))
	ed._release(Vector2i(9, 0), false)
	assert_eq(ed.current.props[0].get("behavior"), "SWAY", "drag keeps the animation")
	assert_eq(float(ed.current.props[0].get("amplitude")), 8.0)
	var w := EditorGrid.cell_to_world(Vector2i(9, 0))
	assert_eq(float(ed.current.props[0]["x"]), w.x, "and still moved")
```

- [ ] **Step 2: Run to verify failure** — FAIL (inspector never opens in crate mode; move rebuilds `{id, x, y}`).

- [ ] **Step 3: Implement — piece_inspector.gd reduced mode**

`open` gains a param (existing calls unaffected):

```gdscript
func open(overlay: Dictionary, piece: NarfDecor, reduced := false) -> void:
```

At the top of `open`, before syncing controls, apply the mode (read the file for the actual control names — the code below names them per the current script; adapt identifiers, keep the requirement):

```gdscript
	_reduced = reduced
	var full := not reduced
	# advanced rows exist only for scenery
	_pivot_grid_container().visible = full   # the 9-pivot grid's parent row
	_axis_row().visible = full               # H/V radio row
	_travel_slider.get_parent().visible = full
	_tilt_slider.get_parent().visible = full
	_amplitude_slider.max_value = 60.0 if full else 12.0
	_rebuild_behavior_options(full)          # full: all 6 verbs; reduced: NONE/SPIN/SWAY/BOB
```

with `var _reduced := false` and a `_rebuild_behavior_options(full: bool)` that clears and refills the behavior OptionButton from `BEHAVIOR_NAMES` (all six) or its first four entries. `set_behavior_by_name` already guards by name lookup, so reduced mode simply never offers DRIFT/WANDER.

- [ ] **Step 4: Implement — level_editor.gd**

`_press` prop-selection branch, after setting selection/drag state:

```gdscript
			if e.get("animatable", false) == true:
				var sprite: NarfDecor = null
				for sc in node.get_children():
					if sc is NarfDecor:
						sprite = sc
				var entry := _prop_entry_for(node)
				if not entry.is_empty() and sprite != null:
					%PieceInspector.open(entry, sprite, true)
			else:
				%PieceInspector.close()
```

with the lookup helper (mirrors `_delete_prop`'s match):

```gdscript
func _prop_entry_for(body: Node2D) -> Dictionary:
	var pid := str(body.get_meta("prop_id"))
	var w := EditorGrid.cell_to_world(body.get_meta("anchor_cell"))
	for p in current.props:
		if p["id"] == pid and is_equal_approx(float(p["x"]), w.x) and is_equal_approx(float(p["y"]), w.y):
			return p
	return {}
```

Deselect (`_press` empty-cell branch), `_delete_prop`, and `_enter_scenery` call `%PieceInspector.close()` (scenery mode reopens it for overlays as today — its own paths are untouched).

`_move_prop` key preservation — replace the entry rewrite:

```gdscript
			var moved := (current.props[i] as Dictionary).duplicate()
			moved["x"] = new_w.x
			moved["y"] = new_w.y
			current.props[i] = moved
```

and after a successful move, refresh the inspector reference if it was open on this prop: `%PieceInspector.open(current.props[i], sprite, true)` using the body's NarfDecor child (or simply close it — implementer's choice; note which in the report; closing is acceptable UX, stale-dict writes are NOT).

- [ ] **Step 5: Verify + commit** — focused green (existing 33 + 3); full suite **346**. Scenery inspector tests must pass untouched (full-mode restore).

```bash
git add src/editor tests/unit/test_level_editor_interactions.gd
git commit -m "feat: animatable props edit with the scenery inspector — reduced mode, key-preserving moves"
```
