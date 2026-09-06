# Wormholes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paired portals (class `wormhole` in the Pieces system): a stone enters one, exits its twin with velocity preserved; pairing by id, exactly-two rule, odd counts inert.

**Architecture:** New `Wormhole` node (`src/level/wormhole.gd`, Area2D) owns spin, teleport, arrival-immunity, and the static `link_pairs` pass. `PropBuilder.spawn_one` grows a wormhole branch (return type widens to `Node2D`); `spawn_props` links pairs after spawning. Registry/level-format/editor changes are one-liners — wormholes are ordinary props.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary for ALL commands: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **321 passing**, must stay green and grow): `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **DEPLOY FREEZE: commit locally only. NO `git push`, NO export, NO deploy.**
- Spec: `docs/superpowers/specs/2026-09-06-wormholes-design.md`. Stones only (trigger = `body is Stone`, the crate.gd:72 idiom — stones have NO group); the teleport helper takes any RigidBody2D (crate door open). Velocity preserved EXACTLY (no re-aim). Pairing: an id placed exactly twice links; 1 or 3+ → `push_warning("wormhole '%s': needs exactly 2, found %d — inert")` and ALL of that id stay inert. Arrival immunity via the partner's `_arrivals` set cleared on `body_exited` — NO timers.
- Teleport must be deferred and followed by `reset_physics_interpolation()` (camera-teleport lesson).
- Level format untouched — wormholes are plain `props` entries. No editor UI beyond the palette class list.
- GDScript traps: LevelLayout typed arrays — `append` in tests; GUT counts engine errors as failures (deliberate warn-path tests only); new PNGs need a headless `--import` pass; physics tests use `wait_physics_frames`, never `wait_seconds`.
- Art-gen script lives in the scratchpad, NOT the repo.

---

### Task 1: Wormhole node + registry class + placeholder art

**Files:**
- Create: `src/level/wormhole.gd`
- Modify: `src/level/pieces.gd` (CLASSES const)
- Create: `pieces/wormhole-blue.png` + `.json`, `pieces/wormhole-orange.png` + `.json` (generated placeholders)
- Test: `tests/unit/test_pieces.gd` (append)

**Interfaces:**
- Consumes: `Pieces.parse_sidecar` (Task-1-wave-1 clamps apply; `tilt`/`bounce` simply ignored for this class — no code change needed for that).
- Produces (Task 2/3 rely on): `class_name Wormhole extends Area2D` with `var partner: Wormhole`, `func expect_arrival(body: Node) -> void`, `func _on_body_entered(body: Node) -> void` (connected in `_ready`), `static func link_pairs(nodes: Array) -> void` (groups by `prop_id` meta); `Pieces.CLASSES` includes `"wormhole"`.

- [ ] **Step 1: Generate placeholder art**

Write `/tmp/claude-1000/-home-frosty-Dev-3d-Trebuchet--claude-worktrees-eager-bassi-2e72fc/d3712160-29e6-4d59-9f7e-ede98bc5abe1/scratchpad/gen_wormhole_art.gd`:

```gdscript
extends SceneTree

# Placeholder swirl portals, 64x126 (1x2 cells). Owner replaces later.
func _init() -> void:
	_swirl("res://pieces/wormhole-blue.png", Color(0.25, 0.45, 0.95))
	_swirl("res://pieces/wormhole-orange.png", Color(0.95, 0.55, 0.15))
	quit()


func _swirl(path: String, tint: Color) -> void:
	var img := Image.create(64, 126, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(32, 63)
	for x in 64:
		for y in 126:
			var d := Vector2((x - c.x) / 32.0, (y - c.y) / 63.0)
			var r := d.length()
			if r < 1.0:
				# darker toward the middle + a spiral band for swirl feel
				var ang := atan2(d.y, d.x)
				var band := 0.5 + 0.5 * sin(ang * 3.0 + r * 9.0)
				var shade := lerpf(0.35, 1.0, band) * lerpf(0.4, 1.0, r)
				img.set_pixel(x, y, Color(tint.r * shade, tint.g * shade, tint.b * shade, 0.95))
	img.save_png(path)
```

Run:

```bash
/home/frosty/Dev/godot/bin/godot --headless -s /tmp/claude-1000/-home-frosty-Dev-3d-Trebuchet--claude-worktrees-eager-bassi-2e72fc/d3712160-29e6-4d59-9f7e-ede98bc5abe1/scratchpad/gen_wormhole_art.gd
/home/frosty/Dev/godot/bin/godot --headless --import
```

Expected: both PNGs exist under `pieces/`, import clean.

- [ ] **Step 2: Write the sidecars**

`pieces/wormhole-blue.json`:

```json
{ "class": "wormhole", "cells": [1, 2], "tip": "Warp! Stones exit at its twin. Place exactly two." }
```

`pieces/wormhole-orange.json`:

```json
{ "class": "wormhole", "cells": [1, 2], "tip": "A second, independent warp pair. Place exactly two." }
```

- [ ] **Step 3: Write the failing tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func test_wormhole_sidecars_register() -> void:
	var blue := Pieces.entry("wormhole-blue")
	assert_eq(blue["class"], "wormhole")
	assert_eq(blue["cells"], Vector2i(1, 2))
	assert_not_null(blue["texture"])
	assert_eq(Pieces.entry("wormhole-orange")["class"], "wormhole")


func test_link_pairs_wires_exactly_two() -> void:
	var a := Wormhole.new()
	var b := Wormhole.new()
	a.set_meta("prop_id", "wormhole-blue")
	b.set_meta("prop_id", "wormhole-blue")
	autofree(a)
	autofree(b)
	Wormhole.link_pairs([a, b])
	assert_eq(a.partner, b)
	assert_eq(b.partner, a)


func test_link_pairs_odd_counts_stay_inert() -> void:
	var lone := Wormhole.new()
	lone.set_meta("prop_id", "wormhole-orange")
	autofree(lone)
	Wormhole.link_pairs([lone])  # warns (GUT-safe)
	assert_null(lone.partner, "1 portal = inert")
	var t1 := Wormhole.new()
	var t2 := Wormhole.new()
	var t3 := Wormhole.new()
	for t in [t1, t2, t3]:
		t.set_meta("prop_id", "wormhole-blue")
		autofree(t)
	Wormhole.link_pairs([t1, t2, t3])  # warns (GUT-safe)
	assert_null(t1.partner, "3 portals = all inert")
	assert_null(t2.partner)
	assert_null(t3.partner)
```

- [ ] **Step 4: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_pieces.gd -gexit`
Expected: FAIL — `Wormhole` not declared; `wormhole` class rejected by registry.

- [ ] **Step 5: Implement**

`src/level/pieces.gd` — one line:

```gdscript
const CLASSES := ["crate", "static", "trampoline", "wormhole"]
```

`src/level/wormhole.gd`:

```gdscript
class_name Wormhole
extends Area2D

# Paired portal (spec 2026-09-06-wormholes-design.md): a Stone entering
# teleports to `partner` with velocity untouched. Pairing = same prop_id
# placed exactly twice; odd counts stay inert (partner == null).
# Arrival immunity: a teleported-in stone is ignored by this portal
# until it fully leaves once — no timers, framerate-proof.

const SPIN_RAD_PER_SEC := 0.6

var partner: Wormhole = null
var _arrivals := {}  # body -> true while it must exit before re-trigger
var _sprite: Sprite2D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	for c in get_children():
		if c is Sprite2D:
			_sprite = c
			break


func _process(delta: float) -> void:
	if _sprite != null:
		_sprite.rotation += SPIN_RAD_PER_SEC * delta


func _on_body_entered(body: Node) -> void:
	if partner == null or not body is Stone:
		return
	if _arrivals.has(body):
		return
	partner.expect_arrival(body)
	_teleport.call_deferred(body)


# Takes any RigidBody2D on purpose — the future crate-transit flag
# reuses this path unchanged (spec: crate door open).
func _teleport(body: Node) -> void:
	if not is_instance_valid(body) or partner == null:
		return
	(body as Node2D).global_position = partner.global_position
	body.reset_physics_interpolation()


func expect_arrival(body: Node) -> void:
	_arrivals[body] = true


func _on_body_exited(body: Node) -> void:
	_arrivals.erase(body)


# Wire portals after spawn: ids placed exactly twice link; anything
# else warns and stays inert — the level always plays (inert doctrine).
static func link_pairs(nodes: Array) -> void:
	var by_id := {}
	for n in nodes:
		if n is Wormhole:
			var pid: String = n.get_meta("prop_id", "")
			if not by_id.has(pid):
				by_id[pid] = []
			by_id[pid].append(n)
	for pid in by_id:
		var group: Array = by_id[pid]
		if group.size() == 2:
			group[0].partner = group[1]
			group[1].partner = group[0]
		else:
			push_warning("wormhole '%s': needs exactly 2, found %d — inert" % [pid, group.size()])
```

- [ ] **Step 6: Focused test passes**

Run the Step 4 command. Expected: all green (two deliberate warnings from the odd-count test — GUT-safe).

- [ ] **Step 7: Full suite, commit**

Full suite expected: **324 passing** (321 + 3).

```bash
git add src/level/wormhole.gd src/level/pieces.gd pieces/ tests/unit/test_pieces.gd
git commit -m "feat: Wormhole class + registry entry — id-paired portals, placeholder swirls"
```

---

### Task 2: PropBuilder spawns and links wormholes

**Files:**
- Modify: `src/level/prop_builder.gd` (wormhole branch; `spawn_one`/`spawn_props` return types widen to `Node2D`), `src/editor/level_editor.gd` (`_spawned_props` type widens), `src/editor/editor_palette.gd` (class list)
- Test: `tests/unit/test_pieces.gd` (append)

**Interfaces:**
- Consumes: `Wormhole` + `Wormhole.link_pairs` (Task 1).
- Produces (Task 3 relies on): `spawn_props` returns linked wormholes (partner wired) alongside statics; wormhole bodies carry the same `prop_id`/`anchor_cell` meta and "props" group as other props; `collision_mask` covers the stone's collision layer.

- [ ] **Step 1: Check the stone's collision layer**

```bash
grep -n "collision_layer\|collision_mask" scenes/stone.tscn src/gameplay/stone.gd
```

If nothing is set, Godot's default is layer 1 → the Area's `collision_mask = 1` below is correct. If stone.tscn sets a layer, use that value instead and note it in your report.

- [ ] **Step 2: Write the failing tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func test_spawn_props_builds_linked_wormholes() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "warp-spawn"
	var a := EditorGrid.cell_to_world(Vector2i(2, 0))
	var b := EditorGrid.cell_to_world(Vector2i(20, 0))
	l.props.append({"id": "wormhole-blue", "x": a.x, "y": a.y})
	l.props.append({"id": "wormhole-blue", "x": b.x, "y": b.y})
	var spawned := PropBuilder.spawn_props(host, l)
	assert_eq(spawned.size(), 2)
	assert_true(spawned[0] is Wormhole)
	assert_true(spawned[0].is_in_group("props"))
	assert_eq(spawned[0].get_meta("prop_id"), "wormhole-blue")
	assert_eq((spawned[0] as Wormhole).partner, spawned[1], "pair auto-linked")
	assert_eq((spawned[1] as Wormhole).partner, spawned[0])


func test_spawn_props_lone_wormhole_spawns_inert() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "lone"
	var a := EditorGrid.cell_to_world(Vector2i(4, 0))
	l.props.append({"id": "wormhole-orange", "x": a.x, "y": a.y})
	var spawned := PropBuilder.spawn_props(host, l)  # warns (GUT-safe)
	assert_eq(spawned.size(), 1, "spawns as scenery")
	assert_null((spawned[0] as Wormhole).partner, "but inert")
```

Run focused: expected FAIL (spawn_one warn-skips the unknown class branch → size 0).

- [ ] **Step 3: Implement — prop_builder.gd**

Widen the signatures and add the branch. Replace `spawn_props`/`spawn_one` declarations and add the wormhole block before the static/trampoline shape code:

```gdscript
static func spawn_props(parent: Node, layout: LevelLayout) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for p in layout.props:
		var body := spawn_one(parent, p)
		if body != null:
			out.append(body)
	Wormhole.link_pairs(out)
	return out


static func spawn_one(parent: Node, prop: Dictionary) -> Node2D:
```

Inside `spawn_one`, after the meta/anchor computation and before the StaticBody2D construction, branch on class (restructure so the shared parts — anchor, cells, size — compute first; the wormhole branch builds an Area2D instead of a StaticBody2D):

```gdscript
	if e["class"] == "wormhole":
		var hole := Wormhole.new()
		hole.position = footprint_center(anchor, cells)
		hole.add_to_group("props")
		hole.set_meta("prop_id", id)
		hole.set_meta("anchor_cell", EditorGrid.world_to_cell(anchor))
		hole.collision_mask = 1  # stones ride the default physics layer (verified Step 1)
		var wshape := CollisionShape2D.new()
		var wrect := RectangleShape2D.new()
		wrect.size = size
		wshape.shape = wrect
		hole.add_child(wshape)
		var wsprite := Sprite2D.new()
		wsprite.texture = e["texture"]
		hole.add_child(wsprite)
		parent.add_child(hole)
		return hole
```

Keep the existing StaticBody2D path for static/trampoline byte-identical (only the declared return type changes).

- [ ] **Step 4: Implement — editor one-liners**

- `src/editor/level_editor.gd`: `var _spawned_props: Array[StaticBody2D] = []` → `var _spawned_props: Array[Node2D] = []` (and any `as StaticBody2D`/typed locals the compiler flags — read the compile errors, adjust types only).
- `src/editor/editor_palette.gd`: the obstacles loop `for cls in ["static", "trampoline"]:` → `for cls in ["static", "trampoline", "wormhole"]:`.

- [ ] **Step 5: Verify + commit**

Focused green (the lone-wormhole test carries one deliberate warning). Full suite expected: **326 passing** (324 + 2). Editor tests from wave 1 (multi-cell placement etc.) must still pass — they cover the type widening.

```bash
git add src/level/prop_builder.gd src/editor tests/unit/test_pieces.gd
git commit -m "feat: PropBuilder spawns wormholes — Area2D portals, auto-linked pairs, palette entry"
```

---

### Task 3: Teleport physics — the warp itself

**Files:**
- Modify: nothing new expected (`wormhole.gd` already carries the logic from Task 1 — this task PROVES it under real physics and fixes what the proof finds)
- Test: `tests/unit/test_pieces.gd` (append)

**Interfaces:**
- Consumes: linked wormholes from `spawn_props` (Task 2); `load("res://scenes/stone.tscn").instantiate()` (the test_stone_enchants pattern) — stones are RigidBody2D with `class_name Stone`.

- [ ] **Step 1: Write the failing/proving tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func _warp_pair(host: Node2D) -> Array:
	var l := LevelLayout.new()
	l.title = "e2e"
	var a := EditorGrid.cell_to_world(Vector2i(2, 0))
	var b := EditorGrid.cell_to_world(Vector2i(24, 0))
	l.props.append({"id": "wormhole-blue", "x": a.x, "y": a.y})
	l.props.append({"id": "wormhole-blue", "x": b.x, "y": b.y})
	return [PropBuilder.spawn_props(host, l), a, b]


func test_stone_warps_with_velocity_preserved() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var parts := _warp_pair(host)
	var a: Vector2 = parts[1]
	var b: Vector2 = parts[2]
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.gravity_scale = 0.0
	stone.global_position = a + Vector2(-150, 0)
	stone.linear_velocity = Vector2(600, 0)
	host.add_child(stone)
	autofree(stone)
	await wait_physics_frames(40)
	assert_gt(stone.global_position.x, b.x, "stone crossed the map via the warp")
	assert_almost_eq(stone.linear_velocity.x, 600.0, 30.0, "speed preserved (minor damp tolerated)")
	assert_almost_eq(stone.linear_velocity.y, 0.0, 5.0, "direction preserved")


func test_arrival_immunity_blocks_instant_return() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var parts := _warp_pair(host)
	var spawned: Array = parts[0]
	var exit_hole: Wormhole = spawned[1]
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.gravity_scale = 0.0
	host.add_child(stone)
	autofree(stone)
	exit_hole.expect_arrival(stone)
	stone.global_position = exit_hole.global_position
	stone.linear_velocity = Vector2.ZERO
	await wait_physics_frames(20)
	assert_almost_eq(
		stone.global_position.x, exit_hole.global_position.x, 2.0,
		"arrived stone parks in the exit portal — no ping-pong back"
	)


func test_crates_do_not_warp() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var parts := _warp_pair(host)
	var a: Vector2 = parts[1]
	var crate := RigidBody2D.new()  # any non-Stone body
	var cshape := CollisionShape2D.new()
	var crect := RectangleShape2D.new()
	crect.size = Vector2(40, 40)
	cshape.shape = crect
	crate.add_child(cshape)
	crate.gravity_scale = 0.0
	crate.global_position = a
	host.add_child(crate)
	autofree(crate)
	await wait_physics_frames(15)
	assert_almost_eq(crate.global_position.x, a.x, 5.0, "non-stones stay put")
```

- [ ] **Step 2: Run and diagnose**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_pieces.gd -gexit`

If the warp test fails, debug in this order (most likely causes first): (1) stone's collision layer vs the Area's `collision_mask` (fix the mask in prop_builder.gd); (2) the deferred teleport landing a frame late — raise the wait, not the logic; (3) monitoring defaults. Fix in `wormhole.gd`/`prop_builder.gd` as evidence dictates. If physics waits deadlock, remember: `wait_physics_frames`, and no paused tree here.

- [ ] **Step 3: Full suite, commit**

Full suite expected: **329 passing** (326 + 3), pristine beyond deliberate warnings.

```bash
git add tests/unit/test_pieces.gd src/level/wormhole.gd src/level/prop_builder.gd
git commit -m "feat: wormholes warp — velocity-preserving teleport proven under physics"
```

---

### Task 4: Verification sweep (no new code)

- [ ] **Step 1:** Full suite twice — both **329 passing**.
- [ ] **Step 2:** Grep hygiene: `grep -rn "wormhole" src/ --include=*.gd` shows only pieces.gd (CLASSES), wormhole.gd, prop_builder.gd, editor_palette.gd. Level format untouched: `git diff 7aea395..HEAD -- src/level/level_json.gd` is empty.
- [ ] **Step 3:** Report the owner note: wormhole PNGs are placeholders (replace in `pieces/`, ids/sidecars stay); the pieces/*.json export-filter reminder from wave 1 now also covers the two new sidecars — nothing new to do, same checklist item.

---

## Deviations pre-declared for reviewers

- Task 3 velocity asserts use tight tolerances rather than exact equality — stones may carry linear damp; direction and speed-within-tolerance is the observable contract.
- The editor canvas never links pairs (spawn_one is called per-prop there) — portals spin but are inert while editing; TEST runs the real level scene and links. This matches spec §5.
- Placeholder art is deliberately crude; owner replaces PNGs in place.
