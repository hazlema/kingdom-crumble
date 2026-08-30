# Kingdom Crumble Level Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In-game level editor: build/save/load/test/share JSON levels with a drag-and-drop crate palette, per the approved spec (docs/superpowers/specs/2026-09-01-level-editor-design.md).

**Architecture:** JSON becomes the one level format (built-ins + user levels; campaign.json orders the campaign). A shared `LevelBuilder` spawns crates for both the game and the editor (hard rule: the editor owns zero gameplay code — it instances the same environment/crate/trebuchet scenes). The editor is a separate scene composed of shared pieces plus editor-only UX (palette from a folder-scanned asset registry, 64px grid, select/move/delete, hamburger file menu, in-memory TEST round-trip via statics).

**Tech Stack:** Godot 4.6.2 (GL Compatibility), GDScript, GUT headless.

## Global Constraints

- Godot binary `$GODOT` = `/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64`; work in `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble`.
- Test command: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` (currently 38/38 green; keep it green).
- After adding files, run `$GODOT --headless --import >/dev/null 2>&1` once before tests.
- GDScript only, no new addons. Do not touch `[rendering]` in project.godot.
- **Editor owns zero gameplay code** (spec §3): it instances the same scenes and uses `LevelBuilder`; editor-owned code is editing UX only.
- Level JSON schema is spec §1 verbatim: `format` (mandatory, =1), `title`, optional `author`, `background` (id string, default "meadow"), `shots` (0/absent = preset), `crates` [{x, y, type}], `triggers` {event: [effect ids]}. Unknown fields ignored; validation never crashes, never partial-loads.
- RMB stays camera pan everywhere. DELETE deletes selection. No undo in v1.
- `git add` only files you touched (plus `.uid`/`.import` sidecars Godot generates for them) — never `git add -A`.
- The owner's editor may be closed; if a headless run reports import-lock contention, rerun once.

---

### Task 1: JSON codec — LevelLayout upgrade + parse/validate/serialize

**Files:**
- Modify: `src/level/level_layout.gd`
- Create: `src/level/level_json.gd`
- Test: `tests/unit/test_level_json.gd`

**Interfaces:**
- Produces: `LevelLayout` fields `title: String`, `author: String`, `background: String` ("meadow" default), `shots: int` (0 = preset), `crates: Array[Dictionary]` (each `{"x": float, "y": float, "type": String}`), `triggers: Dictionary` (String → Array of String).
- Produces: `LevelJson.FORMAT := 1`; `static func parse(text: String) -> LevelLayout` (null on any invalid input); `static func validate(d: Dictionary) -> String` ("" = ok, else error message); `static func serialize(layout: LevelLayout) -> String` (pretty JSON).

- [ ] **Step 1: Replace `src/level/level_layout.gd`**

```gdscript
class_name LevelLayout
extends Resource

# In-memory level data. Persisted as JSON via LevelJson (spec 2026-09-01);
# the old .tres save format is retired.

@export var title := "Untitled"
@export var author := ""
@export var background := "meadow"
@export var shots := 0  # 0 = difficulty preset decides
# Each entry: { "x": float, "y": float, "type": String }
@export var crates: Array[Dictionary] = []
# event name -> Array[String] of curated effect ids
@export var triggers := {}
```

(The old `shots_override`/`Array[Vector2]` fields are gone; Tasks 2–3 update the callers in the same commit series, so run the full suite only at the end of Task 3. For THIS task run only the new test file.)

- [ ] **Step 2: Write the failing test**

```gdscript
# tests/unit/test_level_json.gd
extends GutTest

const GOOD := """
{"format":1,"title":"Falling","author":"frosty","background":"meadow",
"shots":4,"crates":[{"x":1400,"y":572,"type":"crate-wood"}],
"triggers":{"on_all_cleared":["confetti"]}}
"""

func test_parse_good_file():
	var l := LevelJson.parse(GOOD)
	assert_not_null(l)
	assert_eq(l.title, "Falling")
	assert_eq(l.shots, 4)
	assert_eq(l.crates.size(), 1)
	assert_eq(l.crates[0]["type"], "crate-wood")
	assert_eq(l.triggers["on_all_cleared"], ["confetti"])

func test_defaults_for_absent_optionals():
	var l := LevelJson.parse('{"format":1,"title":"T","crates":[]}')
	assert_not_null(l)
	assert_eq(l.author, "")
	assert_eq(l.background, "meadow")
	assert_eq(l.shots, 0)
	assert_eq(l.triggers, {})

func test_rejects_garbage_and_bad_shapes():
	assert_null(LevelJson.parse("not json at all"))
	assert_null(LevelJson.parse('{"title":"no format"}'))
	assert_null(LevelJson.parse('{"format":99,"title":"future","crates":[]}'))
	assert_null(LevelJson.parse('{"format":1,"crates":[]}'))          # no title
	assert_null(LevelJson.parse('{"format":1,"title":"T","crates":"x"}'))
	assert_null(LevelJson.parse(
		'{"format":1,"title":"T","crates":[{"x":1,"y":2}]}'))          # no type
	assert_null(LevelJson.parse(
		'{"format":1,"title":"T","crates":[{"x":9e9,"y":2,"type":"a"}]}'))

func test_unknown_fields_ignored():
	var l := LevelJson.parse(
		'{"format":1,"title":"T","crates":[],"future_thing":123}')
	assert_not_null(l)

func test_roundtrip():
	var l := LevelJson.parse(GOOD)
	var l2 := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(l2)
	assert_eq(l2.title, l.title)
	assert_eq(l2.crates, l.crates)
	assert_eq(l2.triggers, l.triggers)
```

- [ ] **Step 3: Run, verify fails** —
`$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gselect=test_level_json -gexit`

- [ ] **Step 4: Implement `src/level/level_json.gd`**

```gdscript
class_name LevelJson
extends RefCounted

# Level file codec. JSON only — inert data, safe to share (spec §1).

const FORMAT := 1
const MAX_COORD := 100000.0
const MAX_CRATES := 500

static func parse(text: String) -> LevelLayout:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return null
	if validate(data) != "":
		return null
	var l := LevelLayout.new()
	l.title = data["title"]
	l.author = data.get("author", "")
	l.background = data.get("background", "meadow")
	l.shots = int(data.get("shots", 0))
	for c in data["crates"]:
		l.crates.append({"x": float(c["x"]), "y": float(c["y"]),
			"type": String(c["type"])})
	var trig: Variant = data.get("triggers", {})
	if trig is Dictionary:
		for event in trig:
			var ids: Variant = trig[event]
			if ids is Array:
				l.triggers[String(event)] = ids.map(
					func(i: Variant) -> String: return String(i))
	return l

static func validate(d: Dictionary) -> String:
	if not d.has("format") or int(d.get("format", -1)) > FORMAT \
			or int(d.get("format", -1)) < 1:
		return "unsupported or missing format"
	if not d.get("title", "") is String or d.get("title", "") == "":
		return "missing title"
	if not d.get("crates") is Array:
		return "crates must be a list"
	if (d["crates"] as Array).size() > MAX_CRATES:
		return "too many crates"
	for c in d["crates"]:
		if not c is Dictionary or not c.has("x") or not c.has("y") \
				or not c.get("type", null) is String:
			return "bad crate entry"
		if not (c["x"] is float or c["x"] is int) \
				or not (c["y"] is float or c["y"] is int):
			return "bad crate coords"
		if absf(float(c["x"])) > MAX_COORD or absf(float(c["y"])) > MAX_COORD:
			return "crate out of bounds"
	return ""

static func serialize(layout: LevelLayout) -> String:
	var d := {
		"format": FORMAT,
		"title": layout.title,
		"background": layout.background,
		"shots": layout.shots,
		"crates": layout.crates,
		"triggers": layout.triggers,
	}
	if layout.author != "":
		d["author"] = layout.author
	return JSON.stringify(d, "  ")
```

- [ ] **Step 5: Run the new test file, verify passes** (same `-gselect` command)
- [ ] **Step 6: Commit** — `feat: JSON level codec with hard validation`

---

### Task 2: LevelStore on JSON + campaign manifest + migration

**Files:**
- Modify: `src/level/level_store.gd` (full rewrite below)
- Create: `levels/demo.json`, `levels/campaign.json`
- Delete: `levels/meadow.tres`
- Modify: `src/level/level.gd` (loading section)
- Modify: `src/ui/main_menu.gd` (no change needed to buttons; verify path only)
- Test: rewrite `tests/unit/test_level_layout.gd` → delete it; create `tests/unit/test_level_store.gd`

**Interfaces:**
- Consumes: `LevelJson.parse/serialize` (Task 1).
- Produces: `LevelStore.BUILTIN_DIR := "res://levels"`, `USER_DIR := "user://levels"`; `static func campaign() -> Array[String]` (ordered builtin paths from campaign.json); `static func list_user() -> Array[String]`; `static func load_level(path: String) -> LevelLayout` (null on any failure); `static func save_user(layout: LevelLayout, stem: String) -> String` (path or ""); `static func sanitize_stem(s: String) -> String`.

- [ ] **Step 1: Create `levels/demo.json`**

```json
{
  "format": 1,
  "title": "Demo",
  "author": "Kingdom Crumble",
  "background": "meadow",
  "shots": 0,
  "crates": [
    { "x": 1400, "y": 572, "type": "crate-wood" },
    { "x": 1400, "y": 516, "type": "crate-wood" },
    { "x": 1400, "y": 460, "type": "crate-wood" }
  ],
  "triggers": { "on_all_cleared": ["confetti"] }
}
```

- [ ] **Step 2: Create `levels/campaign.json`**

```json
["demo"]
```

- [ ] **Step 3: `git rm levels/meadow.tres`**

- [ ] **Step 4: Failing test `tests/unit/test_level_store.gd`** (also `git rm tests/unit/test_level_layout.gd` — it tests the retired .tres flow)

```gdscript
extends GutTest

func test_campaign_order_and_load():
	var paths := LevelStore.campaign()
	assert_eq(paths.size(), 1)
	assert_true(paths[0].ends_with("demo.json"))
	var l := LevelStore.load_level(paths[0])
	assert_not_null(l)
	assert_eq(l.title, "Demo")
	assert_eq(l.crates.size(), 3)

func test_user_save_load_roundtrip():
	var l := LevelLayout.new()
	l.title = "Gut Tower"
	l.crates = [{"x": 100.0, "y": 100.0, "type": "crate-wood"}]
	var path := LevelStore.save_user(l, "gut tower!!")
	assert_true(path.ends_with("gut_tower.json"))
	var loaded := LevelStore.load_level(path)
	assert_not_null(loaded)
	assert_eq(loaded.title, "Gut Tower")
	assert_true(LevelStore.list_user().has(path))
	DirAccess.remove_absolute(path)

func test_load_missing_or_invalid_is_null():
	assert_null(LevelStore.load_level("res://levels/nope.json"))

func test_sanitize_stem():
	assert_eq(LevelStore.sanitize_stem("My Cool Level!"), "my_cool_level")
	assert_eq(LevelStore.sanitize_stem("../../evil"), "evil")
```

- [ ] **Step 5: Run, verify fails**

- [ ] **Step 6: Rewrite `src/level/level_store.gd`**

```gdscript
class_name LevelStore
extends RefCounted

# Level files on disk. Built-ins ship in res://levels (ordered by
# campaign.json); player levels live in user://levels. All JSON.

const BUILTIN_DIR := "res://levels"
const USER_DIR := "user://levels"

static func campaign() -> Array[String]:
	var out: Array[String] = []
	var text := _read(BUILTIN_DIR + "/campaign.json")
	var data: Variant = JSON.parse_string(text) if text != "" else null
	if data is Array:
		for stem in data:
			out.append("%s/%s.json" % [BUILTIN_DIR, String(stem)])
	return out

static func list_user() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "json":
			out.append("%s/%s" % [USER_DIR, f])
	out.sort()
	return out

static func load_level(path: String) -> LevelLayout:
	var text := _read(path)
	return null if text == "" else LevelJson.parse(text)

static func save_user(layout: LevelLayout, stem: String) -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := "%s/%s.json" % [USER_DIR, sanitize_stem(stem)]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(LevelJson.serialize(layout))
	f.close()
	return path

static func sanitize_stem(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")

static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()
```

- [ ] **Step 7: Update `src/level/level.gd`** — replace the layout constants/loading:

```gdscript
const DEFAULT_LAYOUT := "res://levels/demo.json"
```

and in `_ready()` the loading block becomes:

```gdscript
	var path := next_layout_path if next_layout_path != "" else DEFAULT_LAYOUT
	layout = LevelStore.load_level(path)
	if layout == null:
		layout = LevelStore.load_level(DEFAULT_LAYOUT)
	_spawn_crates()
	shots_left = layout.shots if layout.shots > 0 \
		else Settings.preset.shots_per_level
```

and `_spawn_crates()` interim body (Task 3 replaces it with LevelBuilder):

```gdscript
func _spawn_crates() -> void:
	for c in layout.crates:
		var crate: Crate = CRATE_SCENE.instantiate()
		crate.position = Vector2(c["x"], c["y"])
		crate.add_to_group("crates")
		add_child(crate)
```

- [ ] **Step 8: Import pass, run FULL suite, verify green** (level scene tests exercise the new loader)
- [ ] **Step 9: Commit** — `feat: JSON level store, campaign manifest, demo level (tres retired)`

---

### Task 3: Typed crates + shared LevelBuilder

**Files:**
- Modify: `scenes/crate.tscn` (add a `Skin` Sprite2D; keep physics/nodes otherwise)
- Modify: `src/gameplay/crate.gd` (add `apply_type`)
- Create: `src/level/level_builder.gd`
- Modify: `src/level/level.gd` (`_spawn_crates` uses builder)
- Test: `tests/unit/test_level_builder.gd`

**Interfaces:**
- Consumes: `EditorAssets.texture_for(id)` DOES NOT EXIST YET — builder takes a texture lookup `Callable` instead, so Task 4 can plug the registry in without circular deps.
- Produces: `Crate.type_id: String`; `func apply_type(id: String, tex: Texture2D) -> void` (sets `$Skin.texture` when tex != null). `LevelBuilder.spawn_crates(parent: Node, layout: LevelLayout, frozen: bool, tex_lookup: Callable) -> Array[Crate]` — instances crate.tscn per entry, positions it, applies type, adds to group "crates", sets `freeze = frozen`, adds as child of parent.

- [ ] **Step 1: crate.tscn** — add under the root (after the existing AnimatedSprite2D node block):

```
[node name="Skin" type="Sprite2D" parent="."]
```

(No texture by default: existing AnimatedSprite2D remains the wood look. `apply_type` hides the AnimatedSprite2D and shows Skin only when a texture is provided, so the game's current look is unchanged until types differ.)

- [ ] **Step 2: `src/gameplay/crate.gd`** — add:

```gdscript
var type_id := "crate-wood"

func apply_type(id: String, tex: Texture2D) -> void:
	type_id = id
	if tex == null:
		return
	if has_node("Skin"):
		$Skin.texture = tex
	if has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.visible = false
```

- [ ] **Step 3: Failing test `tests/unit/test_level_builder.gd`**

```gdscript
extends GutTest

func _layout() -> LevelLayout:
	var l := LevelLayout.new()
	l.crates = [
		{"x": 100.0, "y": 500.0, "type": "crate-wood"},
		{"x": 100.0, "y": 436.0, "type": "crate-gold"},
	]
	return l

func test_spawns_positioned_typed_crates_in_group():
	var host := add_child_autofree(Node2D.new())
	var spawned := LevelBuilder.spawn_crates(host, _layout(), false,
		func(_id: String) -> Texture2D: return null)
	assert_eq(spawned.size(), 2)
	assert_eq(spawned[0].position, Vector2(100, 500))
	assert_eq(spawned[1].type_id, "crate-gold")
	assert_true(spawned[0].is_in_group("crates"))
	assert_false(spawned[0].freeze)

func test_frozen_for_editor():
	var host := add_child_autofree(Node2D.new())
	var spawned := LevelBuilder.spawn_crates(host, _layout(), true,
		func(_id: String) -> Texture2D: return null)
	assert_true(spawned[0].freeze)
```

- [ ] **Step 4: Run, verify fails**

- [ ] **Step 5: `src/level/level_builder.gd`**

```gdscript
class_name LevelBuilder
extends RefCounted

# The ONE place layouts become crates — used by the game level and the
# editor preview alike (spec §3: editor owns zero gameplay code).

const CRATE_SCENE := preload("res://scenes/crate.tscn")

static func spawn_crates(parent: Node, layout: LevelLayout, frozen: bool,
		tex_lookup: Callable) -> Array[Crate]:
	var out: Array[Crate] = []
	for c in layout.crates:
		var crate: Crate = CRATE_SCENE.instantiate()
		crate.position = Vector2(c["x"], c["y"])
		crate.freeze = frozen
		crate.add_to_group("crates")
		parent.add_child(crate)
		crate.apply_type(c["type"], tex_lookup.call(c["type"]))
		out.append(crate)
	return out
```

- [ ] **Step 6: `level.gd` `_spawn_crates` becomes** (Task 4 upgrades `_crate_texture` to the registry)

```gdscript
func _spawn_crates() -> void:
	LevelBuilder.spawn_crates(self, layout, false, _crate_texture)

# Task 4 swaps this to the EditorAssets registry lookup.
func _crate_texture(_id: String) -> Texture2D:
	return null
```

- [ ] **Step 7: Import pass, run FULL suite, verify green**
- [ ] **Step 8: Commit** — `feat: typed crates via shared LevelBuilder`

---

### Task 4: Editor asset registry (folder = behavior)

**Files:**
- Create: `assets/editor/crates/*.png` (+ `.txt` sidecars) — copy the six from `art/assets/crates_64/`: crate-wood, crate-gold, crate-blue, crate-green, crate-ghost, skull. Sidecar texts: wood "A standard crate", gold "A golden (bonus) crate", blue "A sturdy blue crate", green "A mossy green crate", ghost "A spooky phantom crate", skull "Ancient royal remains".
- Create: `src/editor/editor_assets.gd`
- Modify: `src/level/level.gd` (`_crate_texture` uses registry)
- Test: `tests/unit/test_editor_assets.gd`

**Interfaces:**
- Produces: `EditorAssets.scan() -> void` (idempotent, caches); `EditorAssets.crates() -> Array[Dictionary]` each `{"id": String, "texture": Texture2D, "description": String}` sorted by id; `EditorAssets.texture_for(id: String) -> Texture2D` (null if unknown).

- [ ] **Step 1: Copy assets** —
`mkdir -p assets/editor/crates && for f in crate-wood crate-gold crate-blue crate-green crate-ghost skull; do cp art/assets/crates_64/$f.png assets/editor/crates/; done` then write each `.txt` sidecar with the description above (one line each).

- [ ] **Step 2: Failing test `tests/unit/test_editor_assets.gd`**

```gdscript
extends GutTest

func before_each() -> void:
	EditorAssets.scan()

func test_finds_six_crates_sorted():
	var list := EditorAssets.crates()
	assert_eq(list.size(), 6)
	assert_eq(list[0]["id"], "crate-blue")  # alpha order
	assert_not_null(list[0]["texture"])

func test_sidecar_descriptions():
	for e in EditorAssets.crates():
		if e["id"] == "crate-gold":
			assert_string_contains(e["description"], "golden")

func test_texture_for():
	assert_not_null(EditorAssets.texture_for("crate-wood"))
	assert_null(EditorAssets.texture_for("crate-imaginary"))
```

- [ ] **Step 3: Run, verify fails**

- [ ] **Step 4: `src/editor/editor_assets.gd`**

```gdscript
class_name EditorAssets
extends RefCounted

# Folder-is-behavior asset registry (spec §2). Drop a PNG in
# assets/editor/<behavior>/ and it becomes placeable; an optional
# <name>.txt beside it is the palette tooltip.

const ROOT := "res://assets/editor"

static var _cache := {}

static func scan() -> void:
	_cache = {}
	for behavior in ["crates"]:
		var entries: Array[Dictionary] = []
		var dir_path := "%s/%s" % [ROOT, behavior]
		var dir := DirAccess.open(dir_path)
		if dir == null:
			_cache[behavior] = entries
			continue
		for f in dir.get_files():
			var name := f.trim_suffix(".remap").trim_suffix(".import")
			if name.get_extension() != "png" or _has(entries, name.get_basename()):
				continue
			var id := name.get_basename()
			var tex: Texture2D = load("%s/%s" % [dir_path, name])
			var desc := id
			var txt_path := "%s/%s.txt" % [dir_path, id]
			if FileAccess.file_exists(txt_path):
				desc = FileAccess.open(txt_path, FileAccess.READ) \
					.get_as_text().strip_edges()
			entries.append({"id": id, "texture": tex, "description": desc})
		entries.sort_custom(func(a, b): return a["id"] < b["id"])
		_cache[behavior] = entries

static func crates() -> Array[Dictionary]:
	if _cache.is_empty():
		scan()
	return _cache.get("crates", [] as Array[Dictionary])

static func texture_for(id: String) -> Texture2D:
	for e in crates():
		if e["id"] == id:
			return e["texture"]
	return null

static func _has(entries: Array[Dictionary], id: String) -> bool:
	for e in entries:
		if e["id"] == id:
			return true
	return false
```

- [ ] **Step 5: `level.gd`** — `_crate_texture` becomes:

```gdscript
func _crate_texture(id: String) -> Texture2D:
	return EditorAssets.texture_for(id)
```

- [ ] **Step 6: Import pass, FULL suite green** (crates in game now wear registry skins by type — demo level is all wood, visuals unchanged)
- [ ] **Step 7: Commit** — `feat: folder-scanned editor asset registry with tooltips`

---

### Task 5: Shared environment scene extraction

**Files:**
- Create: `scenes/environment.tscn` (Background instance + GroundVisual ColorRect with the grass ShaderMaterial + Ground StaticBody2D + WorldBoundaryShape2D — moved verbatim from level.tscn)
- Modify: `scenes/level.tscn` (replace those nodes with one `Environment` instance; keep node name `GroundVisual` etc. inside the new scene; level.gd does not reference them by path, verify with grep)
- Test: existing `tests/unit/test_level_scene.gd` still passes (guards the extraction)

**Interfaces:**
- Produces: `scenes/environment.tscn` — self-contained world dressing both the level and the editor instance. Root `Node2D` named `Environment` containing `Background` (background.tscn instance), `GroundVisual`, `Ground`.

- [ ] **Step 1:** Create `scenes/environment.tscn` by moving the `Background`, `GroundVisual` (with the `grass_mat` ShaderMaterial sub-resource + shader ext_resource), `Ground` + `Shape` blocks out of `scenes/level.tscn` into the new scene under a `Node2D` root named `Environment`. Then in `level.tscn` add `[ext_resource ... environment.tscn]` and one instance node `[node name="Environment" parent="." instance=...]` where the old blocks were. `grep -n "GroundVisual\|Background" src/` must show no scene-path references (only the backdrop-dim code touching trebuchet/crates — verify).
- [ ] **Step 2:** Import pass; FULL suite; headless smoke `$GODOT --headless scenes/level.tscn --quit-after 120` — no script/parse errors.
- [ ] **Step 3: Commit** — `refactor: extract shared environment scene (level + editor both dress the same world)`

---

### Task 6: Grid math

**Files:**
- Create: `src/editor/editor_grid.gd`
- Test: `tests/unit/test_editor_grid.gd`

**Interfaces:**
- Produces: `EditorGrid.CELL := 64`, `MIN_X := 608.0`, `MAX_X := 3200.0`, `FLOOR_Y := 600.0`, `MAX_ROWS := 8`; `static func world_to_cell(p: Vector2) -> Vector2i` (col, row: row 0 = ground row); `static func cell_to_world(c: Vector2i) -> Vector2` (crate center for that cell); `static func in_zone(c: Vector2i) -> bool`; `static func cols() -> int`.

- [ ] **Step 1: Failing test `tests/unit/test_editor_grid.gd`**

```gdscript
extends GutTest

func test_cell_to_world_ground_row_matches_proven_stack():
	assert_eq(EditorGrid.cell_to_world(Vector2i(0, 0)), Vector2(640, 568))
	assert_eq(EditorGrid.cell_to_world(Vector2i(0, 1)), Vector2(640, 504))

func test_world_to_cell_roundtrip():
	for c in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(EditorGrid.cols() - 1, 7)]:
		assert_eq(EditorGrid.world_to_cell(EditorGrid.cell_to_world(c)), c)

func test_zone_bounds():
	assert_true(EditorGrid.in_zone(Vector2i(0, 0)))
	assert_false(EditorGrid.in_zone(Vector2i(-1, 0)))
	assert_false(EditorGrid.in_zone(Vector2i(0, EditorGrid.MAX_ROWS)))
	assert_false(EditorGrid.in_zone(Vector2i(EditorGrid.cols(), 0)))
```

- [ ] **Step 2: Run, verify fails**

- [ ] **Step 3: `src/editor/editor_grid.gd`**

```gdscript
class_name EditorGrid
extends RefCounted

# 64px build grid (spec §4). Row 0 sits on the ground; the zone starts
# a safety margin right of the catapult.

const CELL := 64
const MIN_X := 608.0
const MAX_X := 3200.0
const FLOOR_Y := 600.0
const MAX_ROWS := 8

static func cols() -> int:
	return int((MAX_X - MIN_X) / CELL)

static func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(MIN_X + c.x * CELL + CELL / 2.0,
		FLOOR_Y - c.y * CELL - CELL / 2.0)

static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - MIN_X) / CELL)),
		int(floor((FLOOR_Y - p.y) / CELL)))

static func in_zone(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < cols() and c.y >= 0 and c.y < MAX_ROWS
```

- [ ] **Step 4: Run, verify passes**
- [ ] **Step 5: Commit** — `feat: editor grid math`

---

### Task 7: Palette panel

**Files:**
- Create: `src/editor/editor_palette.gd`, `scenes/editor_palette.tscn`

**Interfaces:**
- Consumes: `EditorAssets.crates()`.
- Produces: `EditorPalette` (Control) with `signal asset_picked(id: String)` — emitted on button press-down (the editor enters carry/ghost mode). Buttons show the asset texture as icon, tooltip = description. Panel is draggable by its title strip (floaty WoW-style box).

- [ ] **Step 1: `src/editor/editor_palette.gd`**

```gdscript
class_name EditorPalette
extends PanelContainer

signal asset_picked(id: String)

var _drag := false
var _drag_off := Vector2.ZERO

func _ready() -> void:
	for entry in EditorAssets.crates():
		var b := Button.new()
		b.icon = entry["texture"]
		b.expand_icon = true
		b.custom_minimum_size = Vector2(72, 72)
		b.tooltip_text = entry["description"]
		b.focus_mode = Control.FOCUS_NONE
		var id: String = entry["id"]
		b.button_down.connect(func() -> void: asset_picked.emit(id))
		%Grid.add_child(b)
	%TitleBar.gui_input.connect(_on_title_input)

func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		_drag_off = get_global_mouse_position() - global_position
	elif event is InputEventMouseMotion and _drag:
		global_position = get_global_mouse_position() - _drag_off
```

- [ ] **Step 2: `scenes/editor_palette.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/editor/editor_palette.gd" id="1"]

[node name="EditorPalette" type="PanelContainer"]
offset_left = 24.0
offset_top = 140.0
offset_right = 344.0
script = ExtResource("1")

[node name="Box" type="VBoxContainer" parent="."]

[node name="TitleBar" type="Label" parent="Box"]
unique_name_in_owner = true
theme_override_font_sizes/font_size = 22
horizontal_alignment = 1
text = "CRATES"
mouse_filter = 0

[node name="Grid" type="GridContainer" parent="Box"]
unique_name_in_owner = true
columns = 4
theme_override_constants/h_separation = 8
theme_override_constants/v_separation = 8
```

- [ ] **Step 3:** Import pass; FULL suite stays green (no gameplay change).
- [ ] **Step 4: Commit** — `feat: floaty editor asset palette`

---

### Task 8: Editor scene — grid overlay, place/select/move/delete

**Files:**
- Create: `src/editor/level_editor.gd`, `scenes/editor.tscn`
- Create: `src/editor/grid_overlay.gd`

**Interfaces:**
- Consumes: environment.tscn, trebuchet.tscn, editor_palette, EditorGrid, LevelBuilder, EditorAssets, LevelJson/LevelStore.
- Produces: `LevelEditor` with `static var resume_layout: LevelLayout` (used by the TEST round-trip, Task 9) and `var current: LevelLayout`; scene `res://scenes/editor.tscn`. Occupancy is a Dictionary `Vector2i -> Crate`.

- [ ] **Step 1: `src/editor/grid_overlay.gd`**

```gdscript
class_name GridOverlay
extends Node2D

# Faint build-zone grid + ghost/selection markers, all draw-only.

var ghost_cell := Vector2i(-1, -1)
var ghost_ok := false
var ghost_tex: Texture2D
var selected_cell := Vector2i(-1, -1)

func _draw() -> void:
	var col := Color(1, 1, 1, 0.14)
	for cx in range(EditorGrid.cols() + 1):
		var x := EditorGrid.MIN_X + cx * EditorGrid.CELL
		draw_line(Vector2(x, EditorGrid.FLOOR_Y),
			Vector2(x, EditorGrid.FLOOR_Y - EditorGrid.MAX_ROWS * EditorGrid.CELL), col, 2)
	for ry in range(EditorGrid.MAX_ROWS + 1):
		var y := EditorGrid.FLOOR_Y - ry * EditorGrid.CELL
		draw_line(Vector2(EditorGrid.MIN_X, y), Vector2(EditorGrid.MAX_X, y), col, 2)
	if ghost_cell.x >= 0 and ghost_tex:
		var p := EditorGrid.cell_to_world(ghost_cell)
		var tint := Color(0.6, 1.0, 0.6, 0.6) if ghost_ok else Color(1.0, 0.4, 0.4, 0.6)
		draw_texture_rect(ghost_tex,
			Rect2(p - Vector2(32, 32), Vector2(64, 64)), false, tint)
	if selected_cell.x >= 0:
		var s := EditorGrid.cell_to_world(selected_cell)
		draw_rect(Rect2(s - Vector2(34, 34), Vector2(68, 68)),
			Color(1.0, 0.83, 0.29, 0.95), false, 4.0)

func refresh() -> void:
	queue_redraw()
```

- [ ] **Step 2: `src/editor/level_editor.gd`**

```gdscript
class_name LevelEditor
extends Node2D

# Editing UX only — world visuals and crate spawning are the game's own
# scenes via LevelBuilder (spec §3 hard rule).

static var resume_layout: LevelLayout = null

var current := LevelLayout.new()
var occupancy := {}           # Vector2i -> Crate
var carrying := ""            # asset id while placing, "" = none
var moving_from := Vector2i(-1, -1)

@onready var overlay: GridOverlay = $GridOverlay
@onready var palette: EditorPalette = $Ui/Palette

func _ready() -> void:
	EditorAssets.scan()
	palette.asset_picked.connect(func(id: String) -> void:
		carrying = id
		overlay.selected_cell = Vector2i(-1, -1))
	if resume_layout != null:
		current = resume_layout
		resume_layout = null
	_rebuild()

func _rebuild() -> void:
	for c in occupancy.values():
		c.queue_free()
	occupancy.clear()
	var spawned := LevelBuilder.spawn_crates(self, current, true,
		EditorAssets.texture_for)
	for crate in spawned:
		occupancy[EditorGrid.world_to_cell(crate.position)] = crate
	overlay.refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_ghost()
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_click()
		elif carrying != "" and _mouse_cell().x >= 0:
			_on_click()  # drag-release placement
	elif event is InputEventKey and event.pressed \
			and event.keycode == KEY_DELETE:
		_delete_selected()
	elif event.is_action_pressed("menu") and carrying != "":
		carrying = ""
		_update_ghost()

func _mouse_cell() -> Vector2i:
	return EditorGrid.world_to_cell(get_global_mouse_position())

func _update_ghost() -> void:
	if carrying == "":
		overlay.ghost_cell = Vector2i(-1, -1)
	else:
		var cell := _mouse_cell()
		overlay.ghost_cell = cell
		overlay.ghost_tex = EditorAssets.texture_for(carrying)
		overlay.ghost_ok = EditorGrid.in_zone(cell) \
			and not occupancy.has(cell)
	overlay.refresh()

func _on_click() -> void:
	var cell := _mouse_cell()
	if carrying != "":
		if EditorGrid.in_zone(cell) and not occupancy.has(cell):
			_place(carrying, cell)
			carrying = ""
			_update_ghost()
		return
	if moving_from.x >= 0 and EditorGrid.in_zone(cell) \
			and not occupancy.has(cell):
		_move(moving_from, cell)
		moving_from = Vector2i(-1, -1)
		return
	if occupancy.has(cell):
		overlay.selected_cell = cell
		moving_from = cell
	else:
		overlay.selected_cell = Vector2i(-1, -1)
		moving_from = Vector2i(-1, -1)
	overlay.refresh()

func _place(id: String, cell: Vector2i) -> void:
	var w := EditorGrid.cell_to_world(cell)
	current.crates.append({"x": w.x, "y": w.y, "type": id})
	_rebuild()

func _move(from: Vector2i, to: Vector2i) -> void:
	var fw := EditorGrid.cell_to_world(from)
	var tw := EditorGrid.cell_to_world(to)
	for c in current.crates:
		if is_equal_approx(c["x"], fw.x) and is_equal_approx(c["y"], fw.y):
			c["x"] = tw.x
			c["y"] = tw.y
			break
	overlay.selected_cell = to
	_rebuild()

func _delete_selected() -> void:
	var cell: Vector2i = overlay.selected_cell
	if cell.x < 0:
		return
	var w := EditorGrid.cell_to_world(cell)
	for i in current.crates.size():
		var c: Dictionary = current.crates[i]
		if is_equal_approx(c["x"], w.x) and is_equal_approx(c["y"], w.y):
			current.crates.remove_at(i)
			break
	overlay.selected_cell = Vector2i(-1, -1)
	moving_from = Vector2i(-1, -1)
	_rebuild()
```

- [ ] **Step 3: `scenes/editor.tscn`**

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://src/editor/level_editor.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/environment.tscn" id="2"]
[ext_resource type="PackedScene" path="res://scenes/trebuchet.tscn" id="3"]
[ext_resource type="Script" path="res://src/editor/grid_overlay.gd" id="4"]
[ext_resource type="PackedScene" path="res://scenes/editor_palette.tscn" id="5"]

[node name="LevelEditor" type="Node2D"]
script = ExtResource("1")

[node name="Environment" parent="." instance=ExtResource("2")]

[node name="Trebuchet" parent="." instance=ExtResource("3")]
position = Vector2(200, 600)

[node name="GridOverlay" type="Node2D" parent="."]
script = ExtResource("4")

[node name="Camera" type="Camera2D" parent="."]
position = Vector2(960, 160)
limit_left = -400
limit_top = -1400
limit_right = 3400
limit_bottom = 700

[node name="Ui" type="CanvasLayer" parent="."]

[node name="Palette" parent="Ui" instance=ExtResource("5")]
unique_name_in_owner = true
```

(Camera: plain Camera2D; RMB pan comes in Step 4 by reusing CameraDirector? No — CameraDirector's modes are gameplay logic. Give the editor its own 20-line pan: add to `level_editor.gd` `_unhandled_input` mouse-motion branch:)

```gdscript
	if event is InputEventMouseMotion \
			and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		$Camera.global_position -= event.relative
```

- [ ] **Step 4:** Import pass; FULL suite; smoke `$GODOT --headless scenes/editor.tscn --quit-after 120` — no errors.
- [ ] **Step 5: Commit** — `feat: level editor scene — grid, ghost placement, select/move/delete`

---

### Task 9: Hamburger menu + save/load/clear dialogs

**Files:**
- Create: `src/editor/editor_menu.gd`, `scenes/editor_menu.tscn`
- Modify: `src/editor/level_editor.gd` + `scenes/editor.tscn` (instance the menu, wire signals)

**Interfaces:**
- Produces: `EditorMenu` (CanvasLayer) with signals `save_requested`, `save_as_requested(stem: String)`, `load_requested(path: String)`, `clear_requested`, `exit_requested`, `test_requested`, `background_picked(id: String)` (spec §7: a Background submenu listing `EditorMenu.BACKGROUNDS := ["meadow"]`; editor wiring sets `current.background = id`). A ☰ button top-right opens a panel: TEST · Save · Save As · Load · Clear · Open Levels Folder · Exit to Menu. Save As opens a LineEdit dialog; Load opens an ItemList of `LevelStore.list_user()` titles; Clear opens a ConfirmationDialog. "Open Levels Folder" runs `OS.shell_open(ProjectSettings.globalize_path(LevelStore.USER_DIR))` (after ensuring the dir exists).
- Editor wiring in `level_editor.gd`: track `var save_path := ""`; `save_requested` → if `save_path == ""` behave as Save As, else overwrite via `LevelStore.save_user` using the existing stem; `save_as_requested(stem)` → `current.title = stem` if title untitled, save, remember path; `load_requested(path)` → `current = LevelStore.load_level(path)` (ignore null), `_rebuild()`; `clear_requested` → `current.crates.clear()`, `_rebuild()`; `exit_requested` → `change_scene_to_file("res://scenes/main_menu.tscn")`; `test_requested` → Task 10.

- [ ] **Step 1:** Build `editor_menu.tscn`: CanvasLayer → ☰ Button (top-right, anchors like the HUD gear) → PanelContainer `%Panel` (hidden, top-right, VBox of the six Buttons) → `%SaveAsDialog` (ConfirmationDialog + LineEdit `%StemEdit`), `%LoadDialog` (ConfirmationDialog + ItemList `%LevelList`), `%ClearConfirm` (ConfirmationDialog "Clear the whole level?"). Script wires buttons → signals, fills `%LevelList` from `LevelStore.list_user()` on open (display each file's parsed `title`, keep path in metadata).

```gdscript
class_name EditorMenu
extends CanvasLayer

signal save_requested
signal save_as_requested(stem: String)
signal load_requested(path: String)
signal clear_requested
signal exit_requested
signal test_requested
signal background_picked(id: String)

const BACKGROUNDS: Array[String] = ["meadow"]

func _ready() -> void:
	%MenuBtn.pressed.connect(func() -> void: %Panel.visible = not %Panel.visible)
	%TestBtn.pressed.connect(func() -> void: _pick(test_requested))
	%SaveBtn.pressed.connect(func() -> void: _pick(save_requested))
	%SaveAsBtn.pressed.connect(func() -> void:
		%Panel.visible = false
		%SaveAsDialog.popup_centered())
	%LoadBtn.pressed.connect(_open_load)
	%ClearBtn.pressed.connect(func() -> void:
		%Panel.visible = false
		%ClearConfirm.popup_centered())
	%FolderBtn.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(LevelStore.USER_DIR)
		OS.shell_open(ProjectSettings.globalize_path(LevelStore.USER_DIR)))
	%ExitBtn.pressed.connect(func() -> void: _pick(exit_requested))
	for bg in BACKGROUNDS:
		%BackgroundList.add_item(bg)
	%BackgroundList.item_selected.connect(func(i: int) -> void:
		background_picked.emit(%BackgroundList.get_item_text(i)))
	%SaveAsDialog.confirmed.connect(func() -> void:
		if %StemEdit.text.strip_edges() != "":
			save_as_requested.emit(%StemEdit.text.strip_edges()))
	%LoadDialog.confirmed.connect(func() -> void:
		var sel: PackedInt32Array = %LevelList.get_selected_items()
		if sel.size() > 0:
			load_requested.emit(%LevelList.get_item_metadata(sel[0])))
	%ClearConfirm.confirmed.connect(func() -> void: clear_requested.emit())

func _pick(sig: Signal) -> void:
	%Panel.visible = false
	sig.emit()

func _open_load() -> void:
	%Panel.visible = false
	%LevelList.clear()
	for path in LevelStore.list_user():
		var l := LevelStore.load_level(path)
		var idx: int = %LevelList.add_item(l.title if l else path.get_file())
		%LevelList.set_item_metadata(idx, path)
	%LoadDialog.popup_centered()
```

- [ ] **Step 2:** Wire in `level_editor.gd._ready()` per the Interfaces block above (exact signal handlers).
- [ ] **Step 3:** Import pass; FULL suite; editor smoke run.
- [ ] **Step 4: Commit** — `feat: editor hamburger — save/save-as/load/clear/folder/exit`

---

### Task 10: TEST round-trip + main menu EDITOR button

**Files:**
- Modify: `src/level/level.gd` (accept in-memory layout + return-to-editor), `src/ui/pause_menu.gd` + `scenes/pause_menu.tscn` (Back to Editor button), `src/editor/level_editor.gd` (test_requested), `src/ui/main_menu.gd` + `scenes/main_menu.tscn` (EDITOR button)

**Interfaces:**
- Produces: `Level.next_layout: LevelLayout` static (preferred over `next_layout_path` when set; consumed+cleared in `_ready`); `Level.return_to_editor: bool` static. When `return_to_editor`: pause menu shows `%BackToEditor`; CLEARED/FAILED advance returns to the editor instead of reloading; returning sets `LevelEditor.resume_layout` to the played layout (positions as authored, not as toppled — keep the pristine copy).

- [ ] **Step 1: `level.gd`** — add statics and consume:

```gdscript
static var next_layout: LevelLayout = null
static var return_to_editor := false
var _pristine: LevelLayout = null
```

In `_ready` loading block, before path logic:

```gdscript
	if next_layout != null:
		layout = next_layout
		_pristine = next_layout
		next_layout = null
	else:
		var path := next_layout_path if next_layout_path != "" else DEFAULT_LAYOUT
		layout = LevelStore.load_level(path)
		if layout == null:
			layout = LevelStore.load_level(DEFAULT_LAYOUT)
```

In the CLEARED/FAILED advance handler and as a new pause-menu connection:

```gdscript
func _back_to_editor() -> void:
	LevelEditor.resume_layout = _pristine
	Level.return_to_editor = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/editor.tscn")
```

CLEARED/FAILED branch becomes:

```gdscript
			if Input.is_action_just_pressed("advance"):
				if Level.return_to_editor:
					_back_to_editor()
				else:
					get_tree().reload_current_scene()
```

Pause wiring in `_ready` (next to the other PauseMenu connections):

```gdscript
		$PauseMenu.back_to_editor_requested.connect(_back_to_editor)
		$PauseMenu.set_editor_mode(Level.return_to_editor)
```

- [ ] **Step 2: pause_menu** — add `%BackToEditor` Button between RestartLevel and MusicRow in the tscn; script adds:

```gdscript
signal back_to_editor_requested

func set_editor_mode(on: bool) -> void:
	%BackToEditor.visible = on
```

and in `_ready`: `%BackToEditor.visible = false` plus
`%BackToEditor.pressed.connect(func(): close(); back_to_editor_requested.emit())`.

- [ ] **Step 3: editor `test_requested`**

```gdscript
func _on_test() -> void:
	Level.next_layout = current
	Level.return_to_editor = true
	get_tree().change_scene_to_file("res://scenes/level.tscn")
```

- [ ] **Step 4: main menu** — add to `scenes/main_menu.tscn` Buttons VBox after Hardcore: `[node name="Editor" type="Button" parent="Buttons"] text = "EDITOR"`; in `main_menu.gd._ready()`:

```gdscript
	$Buttons/Editor.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/editor.tscn"))
```

- [ ] **Step 5:** Import pass; FULL suite; smoke editor + level scenes.
- [ ] **Step 6: Commit** — `feat: TEST round-trip and main-menu EDITOR entry`

---

### Task 11: Triggers — confetti + sound on on_all_cleared

**Files:**
- Create: `src/level/effects.gd`
- Modify: `src/level/level.gd` (fire on CLEARED)
- Test: `tests/unit/test_effects.gd`

**Interfaces:**
- Produces: `Effects.fire_all(ids: Array, host: Node2D, at: Vector2) -> int` (returns count of effects it recognized; unknown ids ignored with `push_warning`); supported: `"confetti"`, `"sound:<name>"` where name must exist in `res://assets/sfx/<name>.ogg` (approved-list-by-directory; missing file = ignored+warning). `static func is_known(id: String) -> bool` (pure, testable).

- [ ] **Step 1: Failing test**

```gdscript
# tests/unit/test_effects.gd
extends GutTest

func test_known_ids():
	assert_true(Effects.is_known("confetti"))
	assert_true(Effects.is_known("sound:fanfare"))
	assert_false(Effects.is_known("format_hard_drive"))

func test_fire_all_counts_known_only():
	var host := add_child_autofree(Node2D.new())
	var n := Effects.fire_all(["confetti", "nonsense"], host, Vector2.ZERO)
	assert_eq(n, 1)
```

- [ ] **Step 2: Run, verify fails**

- [ ] **Step 3: `src/level/effects.gd`**

```gdscript
class_name Effects
extends RefCounted

# Curated effect library for level triggers (spec §8). Effects are data
# ids, never code — the whole reason shared levels are safe.

const SFX_DIR := "res://assets/sfx"

static func is_known(id: String) -> bool:
	return id == "confetti" or id.begins_with("sound:")

static func fire_all(ids: Array, host: Node2D, at: Vector2) -> int:
	var fired := 0
	for id in ids:
		var s := String(id)
		if s == "confetti":
			_confetti(host, at)
			fired += 1
		elif s.begins_with("sound:"):
			if _sound(host, s.trim_prefix("sound:")):
				fired += 1
		else:
			push_warning("Unknown effect id: %s" % s)
	return fired

static func _confetti(host: Node2D, at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.emitting = true
	p.one_shot = true
	p.amount = 120
	p.lifetime = 1.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 700)
	p.initial_velocity_min = 300.0
	p.initial_velocity_max = 700.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color_ramp = _confetti_colors()
	host.add_child(p)
	host.get_tree().create_timer(3.0).timeout.connect(p.queue_free)

static func _confetti_colors() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.83, 0.29))
	g.add_point(0.33, Color(0.91, 0.28, 0.25))
	g.add_point(0.66, Color(0.31, 0.66, 0.9))
	g.set_color(1, Color(0.55, 0.79, 0.47))
	return g

static func _sound(host: Node2D, name: String) -> bool:
	var path := "%s/%s.ogg" % [SFX_DIR, name]
	if not ResourceLoader.exists(path):
		push_warning("No such sound effect: %s" % name)
		return false
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	host.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return true
```

(`assets/sfx/` starts empty — the sound half activates the moment the owner drops `.ogg` files in; ids stay validated by file existence.)

- [ ] **Step 4: `level.gd`** — in `_settle()`, inside the `standing == 0` branch after the banner:

```gdscript
			var effects: Array = layout.triggers.get("on_all_cleared", [])
			if not effects.is_empty():
				var center := Vector2(1400, 400)
				if not _crates().is_empty():
					center = _crates()[0].global_position
				Effects.fire_all(effects, self, center)
```

- [ ] **Step 5:** Import pass; FULL suite green.
- [ ] **Step 6: Commit** — `feat: curated trigger effects — confetti + sound on level clear`

---

### Task 12: Final verification

- [ ] FULL suite green; count strictly greater than 38.
- [ ] Headless smoke: `main_menu`, `level`, `editor` scenes each load with 0 script/parse errors.
- [ ] `grep -rn "meadow.tres\|shots_override\|Array\[Vector2\]" src/ tests/ scenes/` → no hits (migration complete).
- [ ] `grep -rn "preload.*crate\|instantiate" src/editor/` → editor spawns crates only via LevelBuilder (spec §3 audit).
- [ ] Manual checklist for the owner: menu → EDITOR → place/stack crates → select/move/DEL → Save As → Clear → Load it back → TEST → knock it down → Back to Editor (layout pristine) → Exit to Menu → campaign Demo level still plays with confetti on clear.
