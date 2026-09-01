# Level Progression & Jump Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-tier level progression — alphabetical built-in + user level chain, clear-previous-to-unlock, persistent per-tier completion log, in-game jump dialog (pause entry + L), frontier resume from the main menu, KINGDOM CONQUERED at the end.

**Architecture:** Pure static `LevelChain` (ordering/unlock math), `Progress` ConfigFile autoload (twin of Unlocks), bare-bones `LevelJumpDialog` Control, thin integration in Level/main menu/pause menu. `campaign.json` and `LevelStore.campaign()` are deleted; both level folders list alphabetically via one shared helper.

**Tech Stack:** Godot 4.6.2, GDScript, GUT 9.6.1 headless.

## Global Constraints

- `$GODOT` = `/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64`; project dir `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble`.
- After creating any new file: `$GODOT --headless --import .` once before tests.
- Test command: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`. Suite is 126 green at start; it only grows (minus the two campaign tests this plan replaces).
- git: add ONLY touched files (+ new `.uid` sidecars). NEVER `git add -A`.
- Tabs for indentation. Spec (binding): `docs/superpowers/specs/2026-09-01-level-progression-design.md`.
- Hard rules: editor TEST sessions never log completion and never open the jump dialog; progress keys are bare stems per tier; chain rebuilt fresh on every use (no caching); broken level files are skipped with a warning, never crash anything.
- The headless test environment's `user://levels/` may contain the owner's real levels — chain tests must assert STRUCTURE (ordering, block boundaries) computed from actual listings, never hardcoded contents. Pure helpers get fabricated chains for exact cases.

## File Map

- Modify `src/level/level_store.gd` — `list_builtin()`, shared `_list_dir()`, delete `campaign()` (Task 1)
- Delete `levels/campaign.json` (Task 1)
- Create `src/settings/progress.gd` + autoload registration (Task 2)
- Create `src/level/level_chain.gd` (Task 3)
- Create `src/ui/level_jump_dialog.gd` + `scenes/ui/level_jump_dialog.tscn` (Task 4)
- Modify `src/settings/game_input.gd`, `src/ui/main_menu.gd`, `src/ui/pause_menu.gd` + `scenes/pause_menu.tscn` (Task 5)
- Modify `src/level/level.gd` + `scenes/level.tscn` (Task 6)

---

### Task 1: LevelStore — one listing rule, no manifest

**Files:**
- Modify: `src/level/level_store.gd`
- Delete: `levels/campaign.json`
- Modify: `tests/unit/test_level_store.gd`, `tests/unit/test_shipped_levels.gd`

**Interfaces:**
- Produces: `LevelStore.list_builtin() -> Array[String]` — alphabetical json paths in `res://levels`; `list_user()` unchanged in behavior. `campaign()` REMOVED (grep confirms no remaining callers after this task: current callers are the two tests being updated here).

- [ ] **Step 1: Update the tests (failing)**

In `tests/unit/test_level_store.gd`, REPLACE the whole `test_campaign_order_and_load` function with:

```gdscript
func test_list_builtin_alphabetical_and_loadable():
	var paths := LevelStore.list_builtin()
	assert_gt(paths.size(), 0, "there should be at least one built-in level")
	var sorted := paths.duplicate()
	sorted.sort()
	assert_eq(paths, sorted, "built-ins list alphabetically")
	for p in paths:
		assert_true(p.begins_with("res://levels/"), p)
		assert_true(p.ends_with(".json"), p)
```

In `tests/unit/test_shipped_levels.gd`, REPLACE the whole `test_campaign_entries_all_exist_and_load` function with:

```gdscript
func test_all_listed_builtins_load() -> void:
	for path in LevelStore.list_builtin():
		assert_not_null(LevelStore.load_level(path),
			"listed built-in failed to load: %s" % path)
```

- [ ] **Step 2: Run selected — FAIL (`list_builtin` not found):**
`$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_level_store -gexit`

- [ ] **Step 3: Implement**

In `src/level/level_store.gd`: DELETE the whole `campaign()` function. REPLACE the whole `list_user()` function with:

```gdscript
static func list_builtin() -> Array[String]:
	return _list_dir(BUILTIN_DIR)

static func list_user() -> Array[String]:
	return _list_dir(USER_DIR)

static func _list_dir(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "json":
			out.append("%s/%s" % [dir_path, f])
	out.sort()
	return out
```

Update the file's header comment: replace the sentence about campaign.json ordering with `# Built-ins ship in res://levels; player levels live in user://levels. Both list alphabetically — stems are the ordering tool.`

Then: `git rm levels/campaign.json`

- [ ] **Step 4: Selected tests PASS (test_level_store, test_shipped_levels); FULL suite green — expect 126 (two tests replaced, same count).**

- [ ] **Step 5: Commit**

```bash
git add src/level/level_store.gd tests/unit/test_level_store.gd tests/unit/test_shipped_levels.gd
git commit -m "feat: one listing rule — list_builtin/list_user share a helper, campaign manifest deleted"
```

---

### Task 2: Progress autoload — per-tier completion log

**Files:**
- Create: `src/settings/progress.gd`
- Modify: `project.godot` ([autoload] section)
- Test: `tests/unit/test_progress.gd` (create)

**Interfaces:**
- Produces: autoload `Progress` — `mark_cleared(tier: String, stem: String)`, `is_cleared(tier: String, stem: String) -> bool`, `use_path(p: String)` (test hook, same pattern as Unlocks).

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_progress.gd`:

```gdscript
extends GutTest

const TEST_PATH := "user://test_progress.cfg"

func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path(TEST_PATH)

func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path("user://progress.cfg")

func test_absent_file_means_nothing_cleared() -> void:
	assert_false(Progress.is_cleared("chill", "pineapple"))

func test_clear_round_trips_through_disk() -> void:
	Progress.mark_cleared("chill", "pineapple")
	assert_true(Progress.is_cleared("chill", "pineapple"))
	Progress.use_path(TEST_PATH)
	assert_true(Progress.is_cleared("chill", "pineapple"), "survives reload")

func test_tiers_are_separate_dimensions() -> void:
	Progress.mark_cleared("chill", "pineapple")
	assert_false(Progress.is_cleared("hardcore", "pineapple"))
	assert_false(Progress.is_cleared("chill", "watermelon"))
```

- [ ] **Step 2: Run selected — FAIL (`Progress` not declared):** `-gselect=test_progress`

- [ ] **Step 3: Implement**

Create `src/settings/progress.gd`:

```gdscript
extends Node

# Per-tier level completion log (progression spec §2). Sections are
# tiers, keys are level stems: [chill] pineapple=true. Twin of the
# Unlocks store. Flags only, never code.

var path := "user://progress.cfg"
var _cfg := ConfigFile.new()

func _ready() -> void:
	_cfg.load(path)  # missing file = fresh conqueror, not an error

func mark_cleared(tier: String, stem: String) -> void:
	_cfg.set_value(tier, stem, true)
	_cfg.save(path)

func is_cleared(tier: String, stem: String) -> bool:
	return bool(_cfg.get_value(tier, stem, false))

func use_path(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	_cfg.load(path)
```

In `project.godot` `[autoload]`, add AFTER the `Unlocks=...` line:

```
Progress="*res://src/settings/progress.gd"
```

- [ ] **Step 4: Selected PASS; FULL suite green (126 + 3 = 129).**

- [ ] **Step 5: Commit**

```bash
git add src/settings/progress.gd src/settings/progress.gd.uid project.godot tests/unit/test_progress.gd tests/unit/test_progress.gd.uid
git commit -m "feat: Progress autoload — per-tier completion log, twin of Unlocks"
```

---

### Task 3: LevelChain — ordering and unlock math

**Files:**
- Create: `src/level/level_chain.gd`
- Test: `tests/unit/test_level_chain.gd` (create)

**Interfaces:**
- Consumes: `LevelStore.list_builtin()/list_user()/load_level()`, `Progress.is_cleared`.
- Produces: `LevelChain.entries() -> Array[Dictionary]` (`{"stem","path","title"}`), `is_unlocked(chain: Array, index: int, tier: String) -> bool`, `frontier(chain: Array, tier: String) -> int`, `next_index_after(chain: Array, stem: String) -> int`. Helpers take the chain as a parameter — fabricated chains in tests.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_level_chain.gd`:

```gdscript
extends GutTest

const TEST_PATH := "user://test_chain_progress.cfg"

func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path(TEST_PATH)

func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path("user://progress.cfg")

func _fruit_chain() -> Array:
	return [
		{"stem": "apple", "path": "user://levels/apple.json", "title": "Apple"},
		{"stem": "pineapple", "path": "user://levels/pineapple.json", "title": "Pineapple"},
		{"stem": "watermelon", "path": "user://levels/watermelon.json", "title": "Watermelon"},
	]

func test_entries_structure_and_order() -> void:
	var chain := LevelChain.entries()
	assert_gt(chain.size(), 0, "chain should include the built-ins")
	var seen_user := false
	var prev_stem := ""
	for e in chain:
		assert_true(e.has("stem") and e.has("path") and e.has("title"))
		var is_user: bool = e["path"].begins_with("user://")
		if seen_user:
			assert_true(is_user, "built-ins never follow user levels")
		if is_user and not seen_user:
			seen_user = true
			prev_stem = ""
		if prev_stem != "":
			assert_true(e["stem"] >= prev_stem, "each block is alphabetical")
		prev_stem = e["stem"]

func test_first_level_always_unlocked() -> void:
	assert_true(LevelChain.is_unlocked(_fruit_chain(), 0, "chill"))

func test_pineapple_rule() -> void:
	var chain := _fruit_chain()
	assert_false(LevelChain.is_unlocked(chain, 1, "chill"),
		"apple uncleared locks pineapple")
	Progress.mark_cleared("chill", "apple")
	assert_true(LevelChain.is_unlocked(chain, 1, "chill"),
		"apple cleared unlocks pineapple — even inserted later")
	assert_false(LevelChain.is_unlocked(chain, 1, "hardcore"),
		"per-tier: hardcore pineapple stays locked")

func test_frontier() -> void:
	var chain := _fruit_chain()
	assert_eq(LevelChain.frontier(chain, "chill"), 0, "fresh log starts at 0")
	Progress.mark_cleared("chill", "apple")
	assert_eq(LevelChain.frontier(chain, "chill"), 1)
	Progress.mark_cleared("chill", "pineapple")
	Progress.mark_cleared("chill", "watermelon")
	assert_eq(LevelChain.frontier(chain, "chill"), 2, "all cleared parks at last")

func test_next_index_after() -> void:
	var chain := _fruit_chain()
	assert_eq(LevelChain.next_index_after(chain, "apple"), 1)
	assert_eq(LevelChain.next_index_after(chain, "watermelon"), -1, "end of chain")
	assert_eq(LevelChain.next_index_after(chain, "durian"), -1, "unknown stem")
```

- [ ] **Step 2: Run selected — FAIL (`LevelChain` not found):** `-gselect=test_level_chain`

- [ ] **Step 3: Implement**

Create `src/level/level_chain.gd`:

```gdscript
class_name LevelChain
extends RefCounted

# The one ordered level chain (progression spec §1): built-ins then
# user levels, each block alphabetical by stem. Rebuilt fresh on every
# call — add/delete/rename in the folders is instantly reflected.

static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in LevelStore.list_builtin() + LevelStore.list_user():
		var layout := LevelStore.load_level(path)
		if layout == null:
			push_warning("Chain skips unloadable level: %s" % path)
			continue
		out.append({
			"stem": path.get_file().get_basename(),
			"path": path,
			"title": layout.title,
		})
	return out

static func is_unlocked(chain: Array, index: int, tier: String) -> bool:
	if index < 0 or index >= chain.size():
		return false
	if index == 0:
		return true
	return Progress.is_cleared(tier, chain[index - 1]["stem"])

static func frontier(chain: Array, tier: String) -> int:
	for i in chain.size():
		if not Progress.is_cleared(tier, chain[i]["stem"]):
			return i
	return chain.size() - 1

static func next_index_after(chain: Array, stem: String) -> int:
	for i in chain.size():
		if chain[i]["stem"] == stem:
			return i + 1 if i + 1 < chain.size() else -1
	return -1
```

- [ ] **Step 4: Selected PASS; FULL suite green (129 + 5 = 134).**

- [ ] **Step 5: Commit**

```bash
git add src/level/level_chain.gd src/level/level_chain.gd.uid tests/unit/test_level_chain.gd tests/unit/test_level_chain.gd.uid
git commit -m "feat: LevelChain — alphabetical two-block chain, Pineapple rule, frontier math"
```

---

### Task 4: LevelJumpDialog — bare-bones picker

**Files:**
- Create: `src/ui/level_jump_dialog.gd`, `scenes/ui/level_jump_dialog.tscn`
- Test: `tests/unit/test_level_jump_dialog.gd` (create)

**Interfaces:**
- Consumes: `LevelChain`, `Progress`.
- Produces: `LevelJumpDialog` (Control) — `signal level_picked(path: String)`, `func open(tier: String)` (rebuilds list, shows), Esc closes. Deliberately plain; the owner stylizes later.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_level_jump_dialog.gd`:

```gdscript
extends GutTest

const TEST_PATH := "user://test_jump_progress.cfg"

func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path(TEST_PATH)

func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path("user://progress.cfg")

func _dialog() -> LevelJumpDialog:
	var d: LevelJumpDialog = load("res://scenes/ui/level_jump_dialog.tscn").instantiate()
	add_child_autofree(d)
	return d

func test_open_builds_one_button_per_entry() -> void:
	var d := _dialog()
	d.open("chill")
	var chain := LevelChain.entries()
	assert_eq(d.get_node("%List").get_child_count(), chain.size())
	assert_true(d.visible)

func test_first_button_unlocked_rest_follow_progress() -> void:
	var d := _dialog()
	d.open("chill")
	var buttons := d.get_node("%List").get_children()
	assert_false(buttons[0].disabled, "first level is always playable")
	if buttons.size() > 1:
		var chain := LevelChain.entries()
		var expect_locked := not Progress.is_cleared("chill", chain[0]["stem"])
		assert_eq(buttons[1].disabled, expect_locked)

func test_pick_emits_path_and_hides() -> void:
	var d := _dialog()
	d.open("chill")
	var chain := LevelChain.entries()
	watch_signals(d)
	d.get_node("%List").get_child(0).pressed.emit()
	assert_signal_emitted_with_parameters(d, "level_picked", [chain[0]["path"]])
	assert_false(d.visible)
```

- [ ] **Step 2: Run selected — FAIL:** `-gselect=test_level_jump_dialog`

- [ ] **Step 3: Implement**

Create `src/ui/level_jump_dialog.gd`:

```gdscript
class_name LevelJumpDialog
extends Control

# Bare-bones in-game level picker (progression spec §4). Deliberately
# plain — the owner stylizes later. Rebuilt on every open so folder
# changes and fresh checkmarks always show.

signal level_picked(path: String)

func open(tier: String) -> void:
	for c in %List.get_children():
		%List.remove_child(c)
		c.queue_free()
	var chain := LevelChain.entries()
	for i in chain.size():
		var b := Button.new()
		var stem: String = chain[i]["stem"]
		var title: String = chain[i]["title"]
		if Progress.is_cleared(tier, stem):
			b.text = "✓  %s" % title
		elif LevelChain.is_unlocked(chain, i, tier):
			b.text = title
		else:
			b.text = "🔒  %s" % title
			b.disabled = true
		var path: String = chain[i]["path"]
		b.pressed.connect(func() -> void:
			level_picked.emit(path)
			hide())
		%List.add_child(b)
	show()

func _input(event: InputEvent) -> void:
	# _input (not unhandled) so Esc closes the dialog before the pause
	# menu can react to the same key
	if visible and event.is_action_pressed("menu"):
		hide()
		get_viewport().set_input_as_handled()
```

Create `scenes/ui/level_jump_dialog.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/level_jump_dialog.gd" id="1"]

[node name="LevelJumpDialog" type="Control"]
visible = false
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("1")

[node name="Center" type="CenterContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2

[node name="Panel" type="PanelContainer" parent="Center"]
layout_mode = 2

[node name="VBox" type="VBoxContainer" parent="Center/Panel"]
layout_mode = 2
theme_override_constants/separation = 10

[node name="Title" type="Label" parent="Center/Panel/VBox"]
layout_mode = 2
theme_override_font_sizes/font_size = 28
horizontal_alignment = 1
text = "LEVELS"

[node name="Scroll" type="ScrollContainer" parent="Center/Panel/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(420, 440)

[node name="List" type="VBoxContainer" parent="Center/Panel/VBox/Scroll"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 6
```

- [ ] **Step 4: Selected PASS; FULL suite green (134 + 3 = 137).**

- [ ] **Step 5: Commit**

```bash
git add src/ui/level_jump_dialog.gd src/ui/level_jump_dialog.gd.uid scenes/ui/level_jump_dialog.tscn tests/unit/test_level_jump_dialog.gd tests/unit/test_level_jump_dialog.gd.uid
git commit -m "feat: LevelJumpDialog — bare-bones picker with checkmarks and locks"
```

---

### Task 5: Entry points — keybind, menu frontier, pause entry

**Files:**
- Modify: `src/settings/game_input.gd`, `src/ui/main_menu.gd`, `src/ui/pause_menu.gd`, `scenes/pause_menu.tscn`
- Test: `tests/unit/test_game_input.gd` (create — tiny)

**Interfaces:**
- Produces: InputMap action `jump_levels` (KEY_L); `PauseMenu.jump_levels_requested` signal + `%JumpLevels` button (hidden in editor sessions via extended `set_editor_mode`); main-menu tier buttons resume the tier frontier.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_game_input.gd`:

```gdscript
extends GutTest

func test_jump_levels_action_registered() -> void:
	GameInput.ensure_actions()
	assert_true(InputMap.has_action("jump_levels"))
```

- [ ] **Step 2: Run selected — FAIL:** `-gselect=test_game_input`

- [ ] **Step 3: Implement**

`src/settings/game_input.gd` — add to `BINDINGS` (after the "menu" entry):

```gdscript
	"jump_levels": [KEY_L],
```

`src/ui/main_menu.gd` — the tier buttons currently call a `_start(tier)`-style handler that loads the tier and changes scene. Locate that handler and add frontier resolution between `Settings.load_tier(tier)` and the scene change:

```gdscript
	var chain := LevelChain.entries()
	if not chain.is_empty():
		Level.next_layout_path = chain[LevelChain.frontier(chain, tier)]["path"]
```

(If the handler's exact shape differs, preserve its existing behavior and insert these lines after the tier load; note any deviation in your report.)

`scenes/pause_menu.tscn` — add a sibling button directly AFTER the `BackToEditor` node block:

```
[node name="JumpLevels" type="Button" parent="Center/Panel/Margin/Items"]
unique_name_in_owner = true
theme_override_font_sizes/font_size = 20
text = "Jump to Level"
```

`src/ui/pause_menu.gd`:
- Add signal: `signal jump_levels_requested`
- In `_ready`, add: `%JumpLevels.pressed.connect(func(): close(); jump_levels_requested.emit())`
- REPLACE `set_editor_mode` with:

```gdscript
func set_editor_mode(on: bool) -> void:
	%BackToEditor.visible = on
	%JumpLevels.visible = not on  # no chain inside the editor sandbox
```

- [ ] **Step 4: Selected PASS; FULL suite green (137 + 1 = 138).**

- [ ] **Step 5: Commit**

```bash
git add src/settings/game_input.gd src/ui/main_menu.gd src/ui/pause_menu.gd scenes/pause_menu.tscn tests/unit/test_game_input.gd tests/unit/test_game_input.gd.uid
git commit -m "feat: progression entry points — L keybind, pause Jump to Level, tier buttons resume frontier"
```

---

### Task 6: Level integration — record, advance, conquer, jump

**Files:**
- Modify: `src/level/level.gd`, `scenes/level.tscn`
- Test: `tests/unit/test_level_progression.gd` (create)

**Interfaces:**
- Consumes: everything above.
- Produces: `Level.current_stem: String`; `_record_clear()`; `_next_path_after_clear() -> String` ("" = end of chain); jump dialog instanced in level.tscn as `%JumpDialog` under Hud.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_level_progression.gd`:

```gdscript
extends GutTest

const TEST_PATH := "user://test_levelprog.cfg"

func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path(TEST_PATH)

func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path("user://progress.cfg")

func _level_for_first_builtin() -> Level:
	Level.next_layout_path = LevelStore.list_builtin()[0]
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	return l

func test_current_stem_derived_from_path() -> void:
	var l := _level_for_first_builtin()
	var expected: String = LevelStore.list_builtin()[0].get_file().get_basename()
	assert_eq(l.current_stem, expected)

func test_record_clear_writes_tier_and_stem() -> void:
	var l := _level_for_first_builtin()
	l._record_clear()
	assert_true(Progress.is_cleared(Settings.tier, l.current_stem))

func test_editor_session_never_records() -> void:
	Level.next_layout = LevelLayout.new()
	Level.return_to_editor = true
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	l._record_clear()
	var cfg := ConfigFile.new()
	cfg.load(TEST_PATH)
	assert_eq(cfg.get_sections().size(), 0, "sandbox clears must not log")

func test_next_path_after_clear_walks_the_chain() -> void:
	var l := _level_for_first_builtin()
	var chain := LevelChain.entries()
	if chain.size() > 1:
		assert_eq(l._next_path_after_clear(), chain[1]["path"])
	l.current_stem = chain[chain.size() - 1]["stem"]
	assert_eq(l._next_path_after_clear(), "", "end of chain returns empty")

func test_jump_dialog_present_and_wired() -> void:
	var l := _level_for_first_builtin()
	var dialog: LevelJumpDialog = l.get_node("%JumpDialog")
	assert_not_null(dialog)
	assert_false(dialog.visible)
```

- [ ] **Step 2: Run selected — FAIL (`current_stem` missing):** `-gselect=test_level_progression`

- [ ] **Step 3: Implement**

`scenes/level.tscn` — add ext_resource (next free id) and a node under Hud. Add with the other ext_resources:

```
[ext_resource type="PackedScene" path="res://scenes/ui/level_jump_dialog.tscn" id="<next-free-id>"]
```

and directly after the Hud node's own block (as a CHILD: parent="Hud"):

```
[node name="JumpDialog" parent="Hud" instance=ExtResource("<next-free-id>")]
unique_name_in_owner = true
```

`src/level/level.gd`:

1. Add instance vars near `pending_buffs`:

```gdscript
var current_stem := ""
var _chain_end := false
```

2. In `_ready`, in the `else:` branch that resolves `path` (after `layout = LevelStore.load_level(path)` and its fallback), add at the end of that branch:

```gdscript
		current_stem = path.get_file().get_basename()
```

3. In `_ready`, after the PauseMenu wiring block, add:

```gdscript
	if has_node("PauseMenu"):
		$PauseMenu.jump_levels_requested.connect(_open_jump)
	%JumpDialog.level_picked.connect(func(picked: String) -> void:
		Level.next_layout_path = picked
		get_tree().paused = false
		get_tree().reload_current_scene())
```

4. In `_physics_process`, next to the backdrop_toggle check, add:

```gdscript
	if not _editor_session and Input.is_action_just_pressed("jump_levels"):
		_open_jump()
```

5. Add the helpers at the end of the file:

```gdscript
func _open_jump() -> void:
	%JumpDialog.open(Settings.tier)

# Log the clear — never from the editor sandbox, never for pathless
# layouts (spec: testing is just testing).
func _record_clear() -> void:
	if _editor_session or current_stem == "":
		return
	Progress.mark_cleared(Settings.tier, current_stem)

# "" when the chain is conquered.
func _next_path_after_clear() -> String:
	var chain := LevelChain.entries()
	var nxt := LevelChain.next_index_after(chain, current_stem)
	return "" if nxt == -1 else chain[nxt]["path"]
```

6. In `_settle`, REPLACE the CLEARED branch's banner lines (keep the trigger/effects code that follows):

```gdscript
	if standing == 0:
		state = State.CLEARED
		_record_clear()
		_chain_end = current_stem != "" and _next_path_after_clear() == ""
		if _editor_session:
			hud.banner("KINGDOM CRUMBLED!", "press ENTER to return to editor")
		elif _chain_end:
			hud.banner("KINGDOM CONQUERED!", "press ENTER for the throne room")
		else:
			hud.banner("KINGDOM CRUMBLED!", "press ENTER for the next level")
```

7. In `_physics_process` CLEARED/FAILED advance, REPLACE the non-editor `else:` branch:

```gdscript
				else:
					if state == State.CLEARED:
						if _chain_end:
							get_tree().change_scene_to_file(
								"res://scenes/main_menu.tscn")
							return
						var nxt := _next_path_after_clear()
						if nxt != "":
							Level.next_layout_path = nxt
						Level.carry_buffs = pending_buffs.duplicate()
					get_tree().reload_current_scene()
```

- [ ] **Step 4: Selected PASS; FULL suite green (138 + 5 = 143). Run twice.**

- [ ] **Step 5: Commit**

```bash
git add src/level/level.gd scenes/level.tscn tests/unit/test_level_progression.gd tests/unit/test_level_progression.gd.uid
git commit -m "feat: progression lives — clears log per tier, ENTER walks the chain, L jumps, conquest exits"
```

---

### Task 7: Whole-feature verification

**Files:** none (verification only).

- [ ] **Step 1: FULL suite green, twice** (expect 143, 0 failures both runs).
- [ ] **Step 2: Three-scene smoke** — `for s in main_menu level editor; do timeout 8 $GODOT --headless scenes/$s.tscn 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"; done` → no output.
- [ ] **Step 3: Editor isolation** — `grep -rn "Progress\|LevelChain\|jump_levels\|JumpDialog" src/editor/` → no matches.
- [ ] **Step 4: Manifest gone** — `grep -rn "campaign" src/ tests/ levels/ 2>/dev/null` → no matches.
- [ ] **Step 5: No commit (nothing changed); report results.**

---

## Post-plan notes (controller, not tasks)

- Final whole-branch review (most capable model), fix wave, merge.
- AFTER merge: the owner-requested cleanup pass — gdformat over src/ and tests/ (if gdtoolkit available; otherwise skip formatting), dead-code scan, modularity/simplification review with fixes. Separate commits, suite green throughout.
- Owner will rename built-ins to control order (stems are ordering keys now); renaming a stem orphans its checkmark — owner knows.
- Dialog visuals deliberately bare — owner mockups later (KingdomDialog family).

**Cleanup safety rule (owner, binding):** the cleanup/optimize pass starts
ONLY from a fully committed, merged, green state — and runs on its own
branch with per-concern commits (format / dead code / refactors separate),
so any regression is a one-command revert. Feature work and cleanup never
share a commit.
