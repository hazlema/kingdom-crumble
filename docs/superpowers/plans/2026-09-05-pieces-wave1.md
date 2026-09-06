# Pieces Wave 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `Pieces` registry (PNG + JSON sidecar) replaces `EditorAssets`; crates migrate onto it; static blocks and trampolines become placeable via a new level-JSON `props` array and editor multi-cell grid placement.

**Architecture:** `Pieces` (static registry, `src/level/pieces.gd`) scans `res://pieces/` for PNG+sidecar objects and serves textures/metadata to palette, editor, HUD, and game. `PropBuilder` spawns `static`/`trampoline` class objects as StaticBody2D geometry; crates keep their entire existing pipeline, only the texture authority changes. Wave 2 (packs/themes/seasons) is OUT — but ids, namespacing rules, and the registry API are shaped for it.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary for ALL commands: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **300 passing**, must stay green and grow): `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **DEPLOY FREEZE: commit locally only. NO `git push`, NO export, NO deploy.**
- Inert-data doctrine: wrong TYPE in level files → named validation error. Unknown NAME at spawn → `push_warning` + skip. Sidecar problems (asset metadata, not level data) → named `push_warning` + skip that object, clamp out-of-range numbers, ignore unknown keys.
- Sidecar schema: `class` ∈ `crate|static|trampoline` (default `crate`); `cells` 2 ints each clamped 1–4 (default `[1,1]`); `tilt` ∈ `-45|0|45` (trampoline, default 0); `bounce` float clamped 0.5–2.0 (trampoline, default 1.5); `tip` String capped 200 chars (default = id).
- Props validation: `"props must be a list"`, `"too many props"` (cap 64), `"prop %d: bad id"` (charset `^[a-z0-9_:-]{1,64}$`), `"prop %d: bad coords"` (x/y must be numbers).
- Prop `x`,`y` = world coords of the **anchor cell center** (leftmost, bottom-most cell), via `EditorGrid.cell_to_world`. Footprint extends right (+x cells) and up (+y cells).
- Props are unscored, never `hit:` trigger targets, not in the "crates" group.
- Grid math: `EditorGrid.CELL == 64` (column pitch), `EditorGrid.ROW_H == 63` (row pitch), cell y index increases UPWARD.
- GDScript traps: LevelLayout arrays are typed — `append` in tests, never assign a plain Array; GUT counts engine errors as failures (pristine output); registry scans must strip `.remap`/`.import` suffixes (export listing lesson); new PNGs need a headless `--import` pass before `load()` resolves.
- Do NOT edit export presets (gitignored, machine-local). The final task records an owner reminder instead.

---

### Task 1: Pieces registry + obstacle placeholder art

**Files:**
- Create: `src/level/pieces.gd`
- Create: `pieces/block-stone.png` + `pieces/block-stone.json`, `pieces/tramp-flat.png` + `.json`, `pieces/tramp-left.png` + `.json`, `pieces/tramp-right.png` + `.json` (generated placeholder art — owner replaces later)
- Test: `tests/unit/test_pieces.gd` (new)

**Interfaces:**
- Produces (later tasks rely on these exact signatures):
  - `Pieces.scan() -> void` (idempotent, repopulates cache)
  - `Pieces.entries() -> Array[Dictionary]` — each `{id: String, texture: Texture2D, class: String, cells: Vector2i, tilt: int, bounce: float, tip: String}`
  - `Pieces.by_class(cls: String) -> Array[Dictionary]`
  - `Pieces.entry(id: String) -> Dictionary` (empty dict if unknown)
  - `Pieces.texture_for(id: String) -> Texture2D` (null if unknown)
  - `Pieces.parse_sidecar(id: String, raw: Dictionary) -> Dictionary` (pure, clamped meta — the unit-testable core)

- [ ] **Step 1: Generate placeholder art**

Write `/tmp/claude-1000/-home-frosty-Dev-3d-Trebuchet--claude-worktrees-eager-bassi-2e72fc/d3712160-29e6-4d59-9f7e-ede98bc5abe1/scratchpad/gen_pieces_art.gd` (scratchpad, NOT the repo):

```gdscript
extends SceneTree

# Placeholder art for wave-1 obstacles. Owner replaces with real art.
func _init() -> void:
	_block()
	_tramp("res://pieces/tramp-flat.png", 0)
	_tramp("res://pieces/tramp-left.png", -1)
	_tramp("res://pieces/tramp-right.png", 1)
	quit()


func _block() -> void:
	var img := Image.create(64, 63, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.45, 0.45, 0.5))
	# darker border so stacked blocks read as bricks
	for x in 64:
		for y in [0, 1, 61, 62]:
			img.set_pixel(x, y, Color(0.3, 0.3, 0.34))
	for y in 63:
		for x in [0, 1, 62, 63]:
			img.set_pixel(x, y, Color(0.3, 0.3, 0.34))
	img.save_png("res://pieces/block-stone.png")


func _tramp(path: String, lean: int) -> void:
	var img := Image.create(128, 63, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 128:
		# flat: springy top band; leaning: a 45-degree ramp band
		var top := 8
		if lean == -1:
			top = int(float(x) / 128.0 * 47.0) + 8  # high on the LEFT
		elif lean == 1:
			top = int(float(127 - x) / 128.0 * 47.0) + 8  # high on the RIGHT
		for y in range(top, 63):
			var c := Color(0.85, 0.3, 0.3) if y < top + 10 else Color(0.5, 0.32, 0.2)
			img.set_pixel(x, y, c)
	img.save_png(path)
```

Run (from repo root; bare `-s` scripts have no autoloads — none needed here):

```bash
mkdir -p pieces
/home/frosty/Dev/godot/bin/godot --headless -s /tmp/claude-1000/-home-frosty-Dev-3d-Trebuchet--claude-worktrees-eager-bassi-2e72fc/d3712160-29e6-4d59-9f7e-ede98bc5abe1/scratchpad/gen_pieces_art.gd
/home/frosty/Dev/godot/bin/godot --headless --import
```

Expected: 4 PNGs exist under `pieces/`, import pass runs clean.

- [ ] **Step 2: Write the sidecars**

`pieces/block-stone.json`:

```json
{ "class": "static", "tip": "Immutable stone. Deflects everything." }
```

`pieces/tramp-flat.json`:

```json
{ "class": "trampoline", "cells": [2, 1], "tilt": 0, "bounce": 1.5, "tip": "Bounces stones straight up." }
```

`pieces/tramp-left.json`:

```json
{ "class": "trampoline", "cells": [2, 1], "tilt": -45, "bounce": 1.5, "tip": "Launches stones up and to the left." }
```

`pieces/tramp-right.json`:

```json
{ "class": "trampoline", "cells": [2, 1], "tilt": 45, "bounce": 1.5, "tip": "Launches stones up and to the right." }
```

- [ ] **Step 3: Write the failing tests**

`tests/unit/test_pieces.gd`:

```gdscript
extends GutTest

# Wave-1 Pieces registry: PNG + JSON sidecar, clamped, warn-skip on junk.


func before_all() -> void:
	Pieces.scan()


func test_parse_sidecar_defaults_to_plain_crate() -> void:
	var meta := Pieces.parse_sidecar("crate-wood", {})
	assert_eq(meta["class"], "crate")
	assert_eq(meta["cells"], Vector2i(1, 1))
	assert_eq(meta["tip"], "crate-wood")


func test_parse_sidecar_clamps_and_curates() -> void:
	var meta := Pieces.parse_sidecar(
		"t", {"class": "trampoline", "cells": [9, 0], "tilt": 30, "bounce": 99.0, "tip": "x".repeat(500)}
	)
	assert_eq(meta["cells"], Vector2i(4, 1), "cells clamped 1-4")
	assert_eq(meta["tilt"], 0, "tilt outside curated set falls back to 0")
	assert_eq(meta["bounce"], 2.0, "bounce clamped to 2.0")
	assert_eq(meta["tip"].length(), 200, "tip capped")


func test_parse_sidecar_rejects_unknown_class() -> void:
	var meta := Pieces.parse_sidecar("t", {"class": "cannon"})
	assert_true(meta.is_empty(), "unknown class = skip signal (empty dict)")


func test_scan_finds_obstacles_with_metadata() -> void:
	var tramp := Pieces.entry("tramp-left")
	assert_eq(tramp["class"], "trampoline")
	assert_eq(tramp["cells"], Vector2i(2, 1))
	assert_eq(tramp["tilt"], -45)
	assert_not_null(tramp["texture"])
	var block := Pieces.entry("block-stone")
	assert_eq(block["class"], "static")
	assert_eq(block["cells"], Vector2i(1, 1))


func test_unknown_id_is_empty_and_null() -> void:
	assert_true(Pieces.entry("no-such-piece").is_empty())
	assert_null(Pieces.texture_for("no-such-piece"))
```

- [ ] **Step 4: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_pieces.gd -gexit`
Expected: FAIL — `Pieces` not declared.

- [ ] **Step 5: Implement the registry**

`src/level/pieces.gd`:

```gdscript
class_name Pieces
extends RefCounted

# One registry for everything placeable (spec: pieces-design §1-2).
# res://pieces/ holds baked content: one PNG per object + optional JSON
# sidecar. Sidecars SELECT AND TUNE curated classes, never define
# behavior. No sidecar = plain 1x1 crate. Wave 2 adds user://toybox
# packs; scan() is shaped so a second root is additive.

const ROOT := "res://pieces"
const CLASSES := ["crate", "static", "trampoline"]
const TILTS := [-45, 0, 45]
const MAX_CELL := 4
const TIP_CAP := 200

static var _cache := {}  # id -> entry Dictionary


static func scan() -> void:
	_cache = {}
	_scan_dir(ROOT)


static func _scan_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d in dir.get_directories():
		_scan_dir("%s/%s" % [dir_path, d])  # subfolders are organizational
	for f in dir.get_files():
		# Export listings disguise files as .import/.remap (music lesson).
		var file_name := f.trim_suffix(".remap").trim_suffix(".import")
		if file_name.get_extension() != "png":
			continue
		var id := file_name.get_basename()
		if _cache.has(id):
			continue
		var raw := {}
		var sidecar_path := "%s/%s.json" % [dir_path, id]
		if FileAccess.file_exists(sidecar_path):
			var parsed: Variant = JSON.parse_string(
				FileAccess.open(sidecar_path, FileAccess.READ).get_as_text()
			)
			if parsed is Dictionary:
				raw = parsed
			else:
				push_warning("Pieces: %s sidecar is not a JSON object — skipping" % id)
				continue
		var meta := parse_sidecar(id, raw)
		if meta.is_empty():
			continue  # parse_sidecar already warned
		meta["id"] = id
		meta["texture"] = load("%s/%s" % [dir_path, file_name]) as Texture2D
		_cache[id] = meta


# Pure sidecar interpretation: clamped meta, or {} to skip the object.
static func parse_sidecar(id: String, raw: Dictionary) -> Dictionary:
	var cls := str(raw.get("class", "crate"))
	if cls not in CLASSES:
		push_warning("Pieces: %s has unknown class '%s' — skipping" % [id, cls])
		return {}
	var cells := Vector2i(1, 1)
	var raw_cells: Variant = raw.get("cells")
	if raw_cells is Array and (raw_cells as Array).size() == 2:
		var rc := raw_cells as Array
		if (rc[0] is float or rc[0] is int) and (rc[1] is float or rc[1] is int):
			cells = Vector2i(clampi(int(rc[0]), 1, MAX_CELL), clampi(int(rc[1]), 1, MAX_CELL))
	var tilt := 0
	var raw_tilt: Variant = raw.get("tilt", 0)
	if (raw_tilt is float or raw_tilt is int) and int(raw_tilt) in TILTS:
		tilt = int(raw_tilt)
	var bounce := 1.5
	var raw_bounce: Variant = raw.get("bounce", 1.5)
	if raw_bounce is float or raw_bounce is int:
		bounce = clampf(float(raw_bounce), 0.5, 2.0)
	var tip := str(raw.get("tip", id)).left(TIP_CAP)
	return {"class": cls, "cells": cells, "tilt": tilt, "bounce": bounce, "tip": tip}


static func entries() -> Array[Dictionary]:
	if _cache.is_empty():
		scan()
	var out: Array[Dictionary] = []
	for id in _cache.keys():
		out.append(_cache[id])
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


static func by_class(cls: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries():
		if e["class"] == cls:
			out.append(e)
	return out


static func entry(id: String) -> Dictionary:
	if _cache.is_empty():
		scan()
	return _cache.get(id, {})


static func texture_for(id: String) -> Texture2D:
	var e := entry(id)
	return e.get("texture") if not e.is_empty() else null
```

- [ ] **Step 6: Run focused test to verify pass**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_pieces.gd -gexit`
Expected: 5/5 PASS, no engine errors. (Note: `test_parse_sidecar_rejects_unknown_class` legitimately triggers one `push_warning` — GUT-safe.)

- [ ] **Step 7: Full suite, then commit**

Run the full suite. Expected: **305 passing** (300 + 5).

```bash
git add src/level/pieces.gd pieces/ tests/unit/test_pieces.gd
git commit -m "feat: Pieces registry — PNG+sidecar objects, obstacle placeholder art"
```

---

### Task 2: The gutting — crates migrate, EditorAssets dies

**Files:**
- Move: `assets/editor/crates/*.png` (+ `.png.import`) → `pieces/`; each `<id>.txt` tooltip becomes `pieces/<id>.json` (`{"tip": "<text>"}`); delete the `.txt` files and the now-empty `assets/editor/crates/`
- Delete: `src/editor/editor_assets.gd` (+ `.uid`), `tests/unit/test_editor_assets.gd` (+ `.uid`)
- Modify: `src/level/level.gd:237`, `src/editor/level_editor.gd:54,371,442`, `src/editor/editor_palette.gd:11`, `src/ui/hud.gd:21,106-112`, `src/ui/stat_card.gd:66`, `tests/unit/test_stone_enchants.gd:28`, `tests/unit/test_sleep_float.gd:14`, `tests/unit/test_stat_card.gd:60` (and any other `EditorAssets.` hit from a fresh grep)
- Test: extend `tests/unit/test_pieces.gd`

**Interfaces:**
- Consumes: `Pieces.scan/by_class/texture_for/entry` from Task 1.
- Produces: `EditorAssets` no longer exists anywhere; `Pieces.by_class("crate")` feeds the palette; entry key for tooltips is `tip` (EditorAssets used `description` — update the palette line).

- [ ] **Step 1: Write the failing migration tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func test_all_crate_ids_resolve_through_pieces() -> void:
	# Migration pin: every shipped crate face must be served by Pieces.
	for id in ["crate-wood", "crate-blue", "crate-gold", "crate-green", "crate-ghost", "skull"]:
		var e := Pieces.entry(id)
		assert_false(e.is_empty(), "%s registered" % id)
		assert_eq(e["class"], "crate", "%s is a crate" % id)
		assert_not_null(e["texture"], "%s has art" % id)


func test_crate_tooltips_survived_txt_to_sidecar() -> void:
	assert_ne(Pieces.entry("crate-gold")["tip"], "crate-gold", "gold kept its .txt tooltip text")
```

Run focused: expected FAIL (crate PNGs not yet under `pieces/`).

- [ ] **Step 2: Move the art**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble
for f in assets/editor/crates/*.png assets/editor/crates/*.png.import; do git mv "$f" pieces/; done
```

For each `assets/editor/crates/<id>.txt`: create `pieces/<id>.json` containing `{"tip": "<file contents, stripped>"}`, then `git rm assets/editor/crates/<id>.txt`. Remove the empty dir. Run `/home/frosty/Dev/godot/bin/godot --headless --import` afterward.

- [ ] **Step 3: Repoint every caller**

Fresh grep first — the line numbers below are as of plan-writing:

```bash
grep -rn "EditorAssets" src/ tests/ --include=*.gd
```

Replacements (all mechanical):
- `src/level/level.gd:237`: `return EditorAssets.texture_for(id)` → `return Pieces.texture_for(id)`
- `src/editor/level_editor.gd:54`: `EditorAssets.scan()` → `Pieces.scan()`
- `src/editor/level_editor.gd:371`: `EditorAssets.texture_for` → `Pieces.texture_for`
- `src/editor/level_editor.gd:442`: `EditorAssets.texture_for(id)` → `Pieces.texture_for(id)`
- `src/editor/editor_palette.gd:11`: `for entry in EditorAssets.crates():` → `for entry in Pieces.by_class("crate"):` and the tooltip line `b.tooltip_text = entry["description"]` → `b.tooltip_text = entry["tip"]`
- `src/ui/hud.gd` (4 sites) and `src/ui/stat_card.gd:66`: `EditorAssets.texture_for(...)` → `Pieces.texture_for(...)`
- `tests/unit/test_stone_enchants.gd:28`, `tests/unit/test_sleep_float.gd:14`, `tests/unit/test_stat_card.gd:60`: `EditorAssets.texture_for` → `Pieces.texture_for`
- Delete `src/editor/editor_assets.gd`, its `.uid`, `tests/unit/test_editor_assets.gd`, its `.uid`.

- [ ] **Step 4: Verify**

Focused `test_pieces.gd`: 7/7 PASS. Then FULL suite. Expected: **303 passing** (305 + 2 new − 4 deleted with `test_editor_assets.gd`). Also verify zero remaining references:

```bash
grep -rn "EditorAssets" src/ tests/ scenes/ --include=*.gd --include=*.tscn
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: crates migrate to Pieces — EditorAssets deleted, one texture authority"
```

---

### Task 3: `props` in the level format

**Files:**
- Modify: `src/level/level_layout.gd` (new field + doc comment), `src/level/level_json.gd` (validate/parse/serialize)
- Test: extend `tests/unit/test_pieces.gd`

**Interfaces:**
- Produces: `LevelLayout.props: Array[Dictionary]` (entries `{id: String, x: float, y: float}`); `LevelJson.validate` errors exactly: `"props must be a list"`, `"too many props"`, `"prop %d: bad id"`, `"prop %d: bad coords"`; `LevelJson.MAX_PROPS := 64`; `LevelJson._prop_id_rx` matching `^[a-z0-9_:-]{1,64}$`.

- [ ] **Step 1: Write the failing tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func _props_doc(props: Variant) -> Dictionary:
	return {"title": "p", "background": "meadow", "crates": [], "props": props}


func test_props_validation_matrix() -> void:
	assert_eq(LevelJson.validate(_props_doc([])), "")
	assert_eq(LevelJson.validate(_props_doc([{"id": "tramp-left", "x": 1024, "y": 569}])), "")
	assert_eq(
		LevelJson.validate(_props_doc([{"id": "thanksgiving:turkey", "x": 0, "y": 0}])),
		"",
		"namespaced ids are legal"
	)
	assert_eq(LevelJson.validate(_props_doc("nope")), "props must be a list")
	assert_eq(LevelJson.validate(_props_doc([{"id": "BAD CAPS", "x": 0, "y": 0}])), "prop 0: bad id")
	assert_eq(LevelJson.validate(_props_doc([{"id": "ok", "x": "left", "y": 0}])), "prop 0: bad coords")
	assert_eq(LevelJson.validate(_props_doc([{"x": 0, "y": 0}])), "prop 0: bad id")
	var many := []
	for i in 65:
		many.append({"id": "block-stone", "x": i, "y": 0})
	assert_eq(LevelJson.validate(_props_doc(many)), "too many props")


func test_props_round_trip() -> void:
	var l := LevelLayout.new()
	l.title = "rt"
	l.props.append({"id": "tramp-right", "x": 1024.0, "y": 569.0})
	var back := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(back)
	assert_eq(back.props.size(), 1)
	assert_eq(back.props[0]["id"], "tramp-right")
	assert_eq(float(back.props[0]["x"]), 1024.0)


func test_level_without_props_still_parses() -> void:
	var l := LevelLayout.new()
	l.title = "legacy"
	var back := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(back, "props key optional — old levels unaffected")
	assert_eq(back.props.size(), 0)
```

Run focused: expected FAIL (`props` not on LevelLayout / not validated).

- [ ] **Step 2: Implement**

`src/level/level_layout.gd` — after the `crates` field (line 17), add:

```gdscript
# props: placed non-crate pieces [{id:String, x:float, y:float}] —
# unscored StaticBody geometry (blocks, trampolines). See Pieces.
@export var props: Array[Dictionary] = []
```

`src/level/level_json.gd`:

1. Class-level, beside `MAX_CRATES`:

```gdscript
const MAX_PROPS := 64
static var _prop_id_rx := RegEx.create_from_string("^[a-z0-9_:-]{1,64}$")
```

2. In `validate()`, after the crates block (after line ~160, mirror its structure):

```gdscript
	if d.has("props"):
		if not d.get("props") is Array:
			return "props must be a list"
		if (d["props"] as Array).size() > MAX_PROPS:
			return "too many props"
		for pi in (d["props"] as Array).size():
			var p: Variant = (d["props"] as Array)[pi]
			if not p is Dictionary:
				return "prop %d: bad id" % pi
			var pid: Variant = (p as Dictionary).get("id")
			if not pid is String or _prop_id_rx.search(pid) == null:
				return "prop %d: bad id" % pi
			var px: Variant = (p as Dictionary).get("x")
			var py: Variant = (p as Dictionary).get("y")
			if not (px is float or px is int) or not (py is float or py is int):
				return "prop %d: bad coords" % pi
```

3. In `parse()`, after the crates copy loop (line ~117):

```gdscript
	for p in data.get("props", []):
		l.props.append({"id": String(p["id"]), "x": float(p["x"]), "y": float(p["y"])})
```

4. In `serialize()`, in the dict beside `"crates": layout.crates` (line ~262):

```gdscript
		"props": layout.props,
```

- [ ] **Step 3: Verify + commit**

Focused: all `test_pieces.gd` green. Full suite expected: **306 passing** (303 + 3 new test functions).

```bash
git add src/level/level_layout.gd src/level/level_json.gd tests/unit/test_pieces.gd
git commit -m "feat: level format learns props — validated placed obstacles"
```

---

### Task 4: PropBuilder — spawning blocks and trampolines

**Files:**
- Create: `src/level/prop_builder.gd`
- Modify: `src/level/level.gd` (spawn props at level start)
- Test: extend `tests/unit/test_pieces.gd`

**Interfaces:**
- Consumes: `Pieces.entry(id)` (Task 1), `LevelLayout.props` (Task 3).
- Produces:
  - `PropBuilder.spawn_one(parent: Node, prop: Dictionary) -> StaticBody2D` (null + warning if unknown id)
  - `PropBuilder.spawn_props(parent: Node, layout: LevelLayout) -> Array[StaticBody2D]`
  - Spawned bodies: in group `"props"`, meta `"prop_id"` = id, meta `"anchor_cell"` = `Vector2i`; trampolines carry `physics_material_override.bounce` from their entry.
  - `PropBuilder.footprint_center(anchor_world: Vector2, cells: Vector2i) -> Vector2`

- [ ] **Step 1: Write the failing tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func test_spawn_props_builds_static_geometry() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "geo"
	var anchor := EditorGrid.cell_to_world(Vector2i(3, 0))
	l.props.append({"id": "block-stone", "x": anchor.x, "y": anchor.y})
	l.props.append({"id": "tramp-left", "x": anchor.x + 128.0, "y": anchor.y})
	var spawned := PropBuilder.spawn_props(host, l)
	assert_eq(spawned.size(), 2)
	assert_true(spawned[0] is StaticBody2D)
	assert_true(spawned[0].is_in_group("props"))
	assert_false(spawned[0].is_in_group("crates"), "props are unscored")
	assert_eq(spawned[1].get_meta("prop_id"), "tramp-left")
	assert_eq(spawned[1].physics_material_override.bounce, 1.5, "sidecar bounce applied")
	# 2x1 footprint: body centered half a cell right of the anchor
	assert_almost_eq(spawned[1].position.x, anchor.x + 128.0 + 32.0, 0.01)


func test_spawn_props_skips_unknown_id_with_warning() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "orphan"
	l.props.append({"id": "thanksgiving:turkey", "x": 700.0, "y": 569.0})
	var spawned := PropBuilder.spawn_props(host, l)  # warns (missing pack) — GUT-safe
	assert_eq(spawned.size(), 0, "unknown id warn-skips, never crashes")
```

Run focused: expected FAIL — `PropBuilder` not declared.

- [ ] **Step 2: Implement**

`src/level/prop_builder.gd`:

```gdscript
class_name PropBuilder
extends RefCounted

# Spawns non-crate pieces (class static/trampoline) as StaticBody2D
# geometry. Props are unscored scenery-with-collision: never in the
# "crates" group, never trigger targets. Unknown ids (missing pack,
# typo) warn and skip — the level still plays (spec §4).

const CELL_W := 64.0  # EditorGrid.CELL
const CELL_H := 63.0  # EditorGrid.ROW_H


static func spawn_props(parent: Node, layout: LevelLayout) -> Array[StaticBody2D]:
	var out: Array[StaticBody2D] = []
	for p in layout.props:
		var body := spawn_one(parent, p)
		if body != null:
			out.append(body)
	return out


static func spawn_one(parent: Node, prop: Dictionary) -> StaticBody2D:
	var id := str(prop.get("id", ""))
	var e := Pieces.entry(id)
	if e.is_empty() or e["class"] == "crate":
		push_warning("PropBuilder: unknown or non-prop id '%s' — skipping" % id)
		return null
	var cells: Vector2i = e["cells"]
	var anchor := Vector2(float(prop["x"]), float(prop["y"]))
	var body := StaticBody2D.new()
	body.position = footprint_center(anchor, cells)
	body.add_to_group("props")
	body.set_meta("prop_id", id)
	body.set_meta("anchor_cell", EditorGrid.world_to_cell(anchor))
	var size := Vector2(cells.x * CELL_W, cells.y * CELL_H)
	if e["class"] == "trampoline" and e["tilt"] != 0:
		var poly := CollisionPolygon2D.new()
		var hw := size.x / 2.0
		var hh := size.y / 2.0
		if e["tilt"] < 0:  # high edge on the LEFT, ramp falls to the right
			poly.polygon = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		else:  # high edge on the RIGHT
			poly.polygon = PackedVector2Array([Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		body.add_child(poly)
	else:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		body.add_child(shape)
	if e["class"] == "trampoline":
		var mat := PhysicsMaterial.new()
		mat.bounce = e["bounce"]
		body.physics_material_override = mat
	var sprite := Sprite2D.new()
	sprite.texture = e["texture"]
	body.add_child(sprite)
	parent.add_child(body)
	return body


# Anchor = leftmost bottom-most cell center; footprint extends +x/right
# and up (grid y index increases upward, world y decreases).
static func footprint_center(anchor_world: Vector2, cells: Vector2i) -> Vector2:
	return anchor_world + Vector2((cells.x - 1) * CELL_W / 2.0, -(cells.y - 1) * CELL_H / 2.0)
```

`src/level/level.gd` — in `_ready` beside `_spawn_crates()` (line 84):

```gdscript
	_spawn_crates()
	PropBuilder.spawn_props(self, layout)
```

- [ ] **Step 3: Verify + commit**

Focused green; full suite expected: **308 passing**.

```bash
git add src/level/prop_builder.gd src/level/level.gd tests/unit/test_pieces.gd
git commit -m "feat: PropBuilder spawns blocks and trampolines — unscored bouncing geometry"
```

---

### Task 5: Editor — OBSTACLES palette + multi-cell grid placement

**Files:**
- Modify: `src/editor/editor_palette.gd`, `src/editor/level_editor.gd`, `src/editor/grid_overlay.gd`
- Test: extend `tests/unit/test_level_editor_interactions.gd`

**Interfaces:**
- Consumes: `Pieces.by_class/entry`, `PropBuilder.spawn_one/footprint_center`.
- Produces: `LevelEditor.footprint(anchor: Vector2i, cells: Vector2i) -> Array[Vector2i]` (static); occupancy values are now `Node2D` (Crate OR prop body — discriminate with `is Crate`); `GridOverlay.ghost_cells: Vector2i`.

- [ ] **Step 1: Write the failing tests** (append to `tests/unit/test_level_editor_interactions.gd`)

```gdscript
func test_prop_placement_occupies_full_footprint() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	assert_eq(ed.current.props.size(), 1, "prop recorded")
	assert_true(ed.occupancy.has(Vector2i(4, 0)), "anchor cell occupied")
	assert_true(ed.occupancy.has(Vector2i(5, 0)), "second cell occupied")
	assert_eq(ed.occupancy[Vector2i(4, 0)], ed.occupancy[Vector2i(5, 0)], "same node both cells")
	assert_eq(ed.carrying, "")


func test_prop_placement_blocked_by_partial_overlap() -> void:
	ed.carrying = "crate-wood"
	ed._press(Vector2i(5, 0))
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))  # cell 5,0 is taken — whole footprint must refuse
	assert_eq(ed.current.props.size(), 0)
	assert_false(ed.occupancy.has(Vector2i(4, 0)))
	assert_eq(ed.carrying, "tramp-flat", "still carrying after refused drop")


func test_crate_cannot_land_on_prop_cell() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed.carrying = "crate-wood"
	ed._press(Vector2i(5, 0))
	assert_eq(ed.current.crates.size(), 0, "prop cell refuses crates")


func test_prop_delete_frees_all_cells() -> void:
	ed.carrying = "tramp-flat"
	ed._press(Vector2i(4, 0))
	ed.overlay.selected_cell = Vector2i(5, 0)  # select via the SECOND cell
	ed._delete_selected()
	assert_eq(ed.current.props.size(), 0)
	assert_false(ed.occupancy.has(Vector2i(4, 0)))
	assert_false(ed.occupancy.has(Vector2i(5, 0)))


func test_prop_round_trips_through_rebuild() -> void:
	ed.carrying = "block-stone"
	ed._press(Vector2i(2, 1))
	ed._rebuild()
	assert_true(ed.occupancy.has(Vector2i(2, 1)), "prop survives rebuild")
	assert_false(ed.occupancy[Vector2i(2, 1)] is Crate, "and is not a crate")
```

Run focused: expected FAIL (props unhandled by `_press`).

- [ ] **Step 2: Implement — level_editor.gd**

a. Static footprint helper (beside `crate_trigger_key`):

```gdscript
static func footprint(anchor: Vector2i, cells: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in cells.x:
		for j in cells.y:
			out.append(Vector2i(anchor.x + i, anchor.y + j))
	return out
```

b. `_try_place` learns classes (replace the existing body):

```gdscript
func _try_place(cell: Vector2i) -> void:
	var e := Pieces.entry(carrying)
	if e.is_empty():
		return
	if e["class"] == "crate":
		if EditorGrid.in_zone(cell) and not occupancy.has(cell):
			_place(carrying, cell)
			carrying = ""
		return
	var cells: Vector2i = e["cells"]
	for c in footprint(cell, cells):
		if not EditorGrid.in_zone(c) or occupancy.has(c):
			return  # whole footprint or nothing; keep carrying
	var w := EditorGrid.cell_to_world(cell)
	var prop := {"id": carrying, "x": w.x, "y": w.y}
	current.props.append(prop)
	var body := PropBuilder.spawn_one(self, prop)
	for c in footprint(cell, cells):
		occupancy[c] = body
	carrying = ""
	overlay.refresh()
```

c. `_delete_selected` (line ~438) gains a prop branch — read the current body first; the crate path stays untouched; ADD before it:

```gdscript
	var node: Variant = occupancy.get(overlay.selected_cell)
	if node != null and not node is Crate:
		_delete_prop(node)
		return
```

and the helper:

```gdscript
func _delete_prop(body: Node2D) -> void:
	var anchor: Vector2i = body.get_meta("anchor_cell")
	var pid: String = body.get_meta("prop_id")
	for i in current.props.size():
		var pw := EditorGrid.world_to_cell(Vector2(current.props[i]["x"], current.props[i]["y"]))
		if current.props[i]["id"] == pid and pw == anchor:
			current.props.remove_at(i)
			break
	var cells: Vector2i = Pieces.entry(pid)["cells"]
	for c in footprint(anchor, cells):
		occupancy.erase(c)
	body.queue_free()
	overlay.selected_cell = Vector2i(-1, -1)
	overlay.refresh()
```

d. `_rebuild` (line ~350): after the crate spawn/occupancy loop, spawn props and register footprints (skip-with-warning on any occupied/out-of-zone footprint cell — mirrors crate dedupe):

```gdscript
	var kept_props: Array[Dictionary] = []
	for p in current.props:
		var anchor := EditorGrid.world_to_cell(Vector2(p["x"], p["y"]))
		var e := Pieces.entry(str(p["id"]))
		if e.is_empty() or e["class"] == "crate":
			push_warning("editor: dropping unknown prop '%s'" % p.get("id"))
			continue
		var blocked := false
		for c in LevelEditor.footprint(anchor, e["cells"]):
			if not EditorGrid.in_zone(c) or occupancy.has(c):
				blocked = true
				break
		if blocked:
			push_warning("editor: dropping overlapping prop '%s'" % p["id"])
			continue
		var snapped := EditorGrid.cell_to_world(anchor)
		var kept := {"id": str(p["id"]), "x": snapped.x, "y": snapped.y}
		kept_props.append(kept)
		var body := PropBuilder.spawn_one(self, kept)
		for c in LevelEditor.footprint(anchor, e["cells"]):
			occupancy[c] = body
	current.props = kept_props
```

e. `_press`/`_release` drag-move: the existing move path is crate-only. Guard it — in `_press`, only set `_drag_from` when the occupant `is Crate` (props are placed/deleted, not dragged, in wave 1 — YAGNI over spec §6's "drag-move moves the whole footprint": deleting and re-placing a 2-cell piece is one click more; note this deviation for the reviewer). In `_move` (line ~427) add a first-line guard: `if not occupancy.get(from) is Crate: return`.

f. Info menu guard (`_process` RMB block from the crate-Info feature): only `_show_crate_context` when `occupancy.get(cell) is Crate`.

g. `_update_ghost` + palette pick: when `carrying` changes (asset_picked handler) set `overlay.ghost_cells = Pieces.entry(id).get("cells", Vector2i(1, 1))`; ghost-ok check tests the whole footprint free + in-zone.

- [ ] **Step 3: Implement — grid_overlay.gd ghost footprint**

Add `var ghost_cells := Vector2i(1, 1)` beside `ghost_tex`, and replace the ghost draw (lines 25–28):

```gdscript
	if ghost_cell.x >= 0 and ghost_tex:
		var p := EditorGrid.cell_to_world(ghost_cell)
		var tint := Color(0.6, 1.0, 0.6, 0.6) if ghost_ok else Color(1.0, 0.4, 0.4, 0.6)
		var size := Vector2(ghost_cells.x * 64.0, ghost_cells.y * 63.0)
		var top_left := Vector2(p.x - 32.0, p.y - 31.5 - (ghost_cells.y - 1) * 63.0)
		draw_texture_rect(ghost_tex, Rect2(top_left, size), false, tint)
```

- [ ] **Step 4: Implement — editor_palette.gd sections**

Replace `_ready`'s crate loop with two sections (the scene's %Grid stays the crates grid; OBSTACLES gets a sibling label + grid appended programmatically):

```gdscript
func _ready() -> void:
	for entry in Pieces.by_class("crate"):
		%Grid.add_child(_piece_button(entry))
	var box := %Grid.get_parent()
	var header := Label.new()
	header.text = "OBSTACLES"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(header)
	var ob_grid := GridContainer.new()
	ob_grid.columns = (%Grid as GridContainer).columns
	box.add_child(ob_grid)
	for cls in ["static", "trampoline"]:
		for entry in Pieces.by_class(cls):
			ob_grid.add_child(_piece_button(entry))
	%TitleBar.gui_input.connect(_on_title_input)


func _piece_button(entry: Dictionary) -> Button:
	var b := Button.new()
	b.icon = entry["texture"]
	b.expand_icon = true
	b.custom_minimum_size = Vector2(72, 72)
	b.tooltip_text = entry["tip"]
	b.focus_mode = Control.FOCUS_NONE
	var id: String = entry["id"]
	b.button_down.connect(func() -> void: asset_picked.emit(id))
	return b
```

- [ ] **Step 5: Verify + commit**

Focused `test_level_editor_interactions.gd` all green (existing 20 + 5 new). Full suite expected: **313 passing**.

```bash
git add src/editor tests/unit/test_level_editor_interactions.gd
git commit -m "feat: editor places obstacles — OBSTACLES palette, multi-cell footprints, spanning ghost"
```

---

### Task 6: Verification sweep (no new code)

**Files:** none created; report only.

- [ ] **Step 1: Full suite twice** — both runs **313 passing**, output pristine (the deliberate warn-skip tests are the only warnings, and they are inside passing tests).
- [ ] **Step 2: Migration greps come back empty**

```bash
grep -rn "EditorAssets" src/ tests/ scenes/ --include=*.gd --include=*.tscn
ls assets/editor/ 2>/dev/null
```

Expected: no `EditorAssets` hits; `assets/editor/` gone or empty of crates.

- [ ] **Step 3: Shipped levels still load** — run the existing `test_shipped_levels.gd` focused; also assert by eye in the report: `levels/*.json` contain no `props` key (backward-compat path exercised by `test_level_without_props_still_parses`).
- [ ] **Step 4: Owner reminder recorded in the task report (NOT a preset edit):**

> Export presets (machine-local, gitignored) need TWO things before the next repackage: (1) `pieces/` PNGs ride the existing `all_resources` filter automatically, BUT (2) the JSON sidecars are non-resource files — add `pieces/*.json` to *Resources → Filters to export non-resource files* in EVERY preset (Linux, Web, Web Itch, Windows, macOS), or the registry finds art with no metadata in exports. Same class of bug as the music-folder lesson.

- [ ] **Step 5: Commit anything outstanding; report done.**

---

## Deviations pre-declared for reviewers

- Prop drag-move is deferred (delete + re-place covers it, wave 1); spec §6 mentions footprint drag-move — flagged as an intentional YAGNI cut, owner can veto.
- `Pieces.parse_sidecar` returns `{}` for unknown class rather than a default — the spec's warn-and-skip for sidecar junk.
- Placeholder art is deliberately crude; the owner replaces PNGs in place (ids/sidecars stay).
