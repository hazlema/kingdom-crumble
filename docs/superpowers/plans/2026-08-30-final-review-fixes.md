# Final-Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 9 final-review findings in the Kingdom Crumble level editor, add tests where required, commit each item separately, then run the full suite and produce a fix report.

**Architecture:** Pure GDScript fixes across 7 source files + 2 test files. No new scenes except adding an AcceptDialog node to `scenes/editor_menu.tscn`. Each item is independent; they are ordered so static-state fixes (item 1) come before behaviour that depends on them (item 8).

**Tech Stack:** Godot 4.6, GDScript, GUT test framework (addons/gut), headless smoke via `--headless --quit-after 3`, git for per-item commits.

## Global Constraints

- Repo: `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble`, branch `level-editor`
- Godot binary: `/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64`
- GUT runner: `addons/gut/gut_cmdln.gd`; suite command: `"$GODOT" --headless res://addons/gut/gut_cmdln.gd -gtest=res://tests/unit`
- Never `git add -A`; stage only files you touched
- Per-item commits; message format: `fix: <short description>` or `test: <short description>` as appropriate
- Final report → `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble/.superpowers/sdd/final-fix-report.md`
- Suite baseline: 55 green; expect ≥ 60 after all fixes

---

### Task 1: CRITICAL — round-trip static vars in level.gd

**Files:**
- Modify: `src/level/level.gd`

**What to fix:**

In `_ready`, copy `Level.return_to_editor` into an instance var `_editor_session` and **immediately clear the static** so a subsequent scene load starts clean. Do the same alongside the existing `next_layout` consumption.

In `_physics_process` State.CLEARED/FAILED advance branch and `_settle` banner branch and `PauseMenu.set_editor_mode` call: swap `Level.return_to_editor` → `_editor_session`.

In the PauseMenu `restart_requested` handler: when `_editor_session`, re-arm both statics before `reload_current_scene`.

In the State.CLEARED/FAILED `advance` branch (ENTER to retry path): when `_editor_session`, re-arm both statics before `reload_current_scene`.

`_back_to_editor` already reads `_pristine`; only change is it no longer touches `Level.return_to_editor` (the static was already cleared in `_ready`).

- [ ] **Step 1: Read the current file**

Open `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble/src/level/level.gd` and confirm exact line numbers for `_ready`, the `PauseMenu.set_editor_mode` call, the pause `restart_requested` lambda, the `State.CLEARED,State.FAILED` advance branch, and `_back_to_editor`.

- [ ] **Step 2: Add the instance var declaration**

After `var _pristine: LevelLayout = null` (currently line 28), add:

```gdscript
var _editor_session := false
```

- [ ] **Step 3: Consume-and-clear both statics in _ready**

Replace the block inside `_ready` that reads and clears `next_layout`:

```gdscript
# Before (lines 37-40 approx):
if next_layout != null:
    layout = next_layout
    _pristine = next_layout
    next_layout = null
```

with:

```gdscript
_editor_session = Level.return_to_editor
Level.return_to_editor = false
if next_layout != null:
    layout = next_layout
    _pristine = next_layout
    next_layout = null
```

- [ ] **Step 4: Fix set_editor_mode call**

Replace:

```gdscript
$PauseMenu.set_editor_mode(Level.return_to_editor)
```

with:

```gdscript
$PauseMenu.set_editor_mode(_editor_session)
```

- [ ] **Step 5: Fix the pause restart_requested lambda**

Replace:

```gdscript
$PauseMenu.restart_requested.connect(
    func() -> void: get_tree().reload_current_scene())
```

with:

```gdscript
$PauseMenu.restart_requested.connect(func() -> void:
    if _editor_session:
        Level.next_layout = _pristine
        Level.return_to_editor = true
    get_tree().reload_current_scene())
```

- [ ] **Step 6: Fix the CLEARED/FAILED advance branch in _physics_process**

Replace:

```gdscript
State.CLEARED, State.FAILED:
    if Input.is_action_just_pressed("advance"):
        if Level.return_to_editor:
            _back_to_editor()
        else:
            get_tree().reload_current_scene()
```

with:

```gdscript
State.CLEARED, State.FAILED:
    if Input.is_action_just_pressed("advance"):
        if _editor_session:
            _back_to_editor()
        else:
            get_tree().reload_current_scene()
```

Note: when `_editor_session` is true and user presses ENTER, `_back_to_editor()` handles it (it already reads `_pristine`). When `_editor_session` is false, it's a plain restart — no re-arming needed.

But for the ENTER-restart path to re-arm (so the layout reloads identically), we must re-arm **before** calling `reload_current_scene`. The ENTER path only calls `_back_to_editor()` when `_editor_session`, so the non-editor case is untouched. The `_back_to_editor` call is the correct path — no extra reload_current_scene needed.

Wait — re-read the spec: "The pause Restart Level handler and the CLEARED/FAILED ENTER-restart path must, when _editor_session, re-arm `Level.next_layout = _pristine; Level.return_to_editor = true` BEFORE reload_current_scene so the same layout reloads." The CLEARED/FAILED ENTER path uses `_back_to_editor()` which changes to `editor.tscn`, NOT `reload_current_scene`. So the re-arm for the ENTER path happens naturally inside `_back_to_editor`. The ENTER branch is already correct after Step 6.

- [ ] **Step 7: Verify _back_to_editor is correct**

`_back_to_editor` reads `_pristine` and sets `LevelEditor.resume_layout = _pristine`, then clears `Level.return_to_editor = false` and changes scene. Since we already cleared `Level.return_to_editor` in `_ready`, this write of `false` is a no-op (already false). The function is correct as-is — no change needed.

- [ ] **Step 8: Run the full suite to verify no regressions**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit 2>&1 | tail -20
```

Expected: all previous 55 pass.

- [ ] **Step 9: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add src/level/level.gd && \
  git commit -m "fix: consume-and-clear return_to_editor static in _ready; re-arm on restart"
```

---

### Task 2: CRITICAL — type-confused JSON in level_json.gd

**Files:**
- Modify: `src/level/level_json.gd`
- Modify: `tests/unit/test_level_json.gd`

**What to fix:**

In `validate`:
1. `format` field must be `int or float` before `int()` conversion, else return "unsupported or missing format".
2. `shots` field (if present) must be `int or float`, else return "bad shots".
3. Trigger id arrays: drop entries that are not String (no `String(i)` coercion).

In `parse`:
- The trigger mapping lambda currently does `String(i)` on all entries. Change it to filter: only include entries where `i is String`.

- [ ] **Step 1: Write failing tests first**

Add to `tests/unit/test_level_json.gd`:

```gdscript
func test_format_object_is_null():
	assert_null(LevelJson.parse('{"format":{},"title":"T","crates":[]}'))

func test_format_array_is_null():
	assert_null(LevelJson.parse('{"format":[1],"title":"T","crates":[]}'))

func test_shots_object_is_null():
	assert_null(LevelJson.parse('{"format":1,"title":"T","crates":[],"shots":{}}'))

func test_non_string_trigger_ids_dropped():
	var l := LevelJson.parse('{"format":1,"title":"T","crates":[],"triggers":{"on_all_cleared":[5,{},"confetti"]}}')
	assert_not_null(l)
	assert_eq(l.triggers, {"on_all_cleared": ["confetti"]})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_level_json.gd 2>&1 | tail -30
```

Expected: 3-4 new FAIL lines.

- [ ] **Step 3: Fix validate() in level_json.gd**

Replace the format check in `validate`:

```gdscript
# Before:
if not d.has("format") or int(d.get("format", -1)) > FORMAT \
        or int(d.get("format", -1)) < 1:
    return "unsupported or missing format"
```

with:

```gdscript
var _fmt: Variant = d.get("format", null)
if not (_fmt is int or _fmt is float) \
        or int(_fmt) > FORMAT or int(_fmt) < 1:
    return "unsupported or missing format"
```

Then add a shots type check. After the existing format/title/crates checks, before the per-crate loop, insert:

```gdscript
var _shots: Variant = d.get("shots", 0)
if not (_shots is int or _shots is float):
    return "bad shots"
```

- [ ] **Step 4: Fix trigger id handling in parse()**

Replace the trigger mapping block:

```gdscript
# Before:
l.triggers[String(event)] = ids.map(
    func(i: Variant) -> String: return String(i))
```

with:

```gdscript
var str_ids: Array[String] = []
for i in ids:
    if i is String:
        str_ids.append(i)
l.triggers[String(event)] = str_ids
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_level_json.gd 2>&1 | tail -30
```

Expected: all test_level_json tests pass.

- [ ] **Step 6: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add src/level/level_json.gd tests/unit/test_level_json.gd && \
  git commit -m "fix: reject non-numeric format/shots; drop non-string trigger ids; add tests"
```

---

### Task 3: IMPORTANT — off-grid crates uneditable/duplicating in level_editor.gd

**Files:**
- Modify: `src/editor/level_editor.gd`

**What to fix:**

1. `_rebuild` must free all spawned crates by tracking what `LevelBuilder.spawn_crates` returns in `_spawned: Array[Crate]`, and calling `queue_free` on those — not on `occupancy.values()` (which may miss crates if a crate was placed at an off-grid coord).
2. Before spawning in `_rebuild`, snap all `current.crates` coords to cell centres.
3. After snapping, remove duplicate-cell entries (keep first).

- [ ] **Step 1: Add _spawned var**

In the class var block, add after `save_path := ""`:

```gdscript
var _spawned: Array[Crate] = []
```

- [ ] **Step 2: Rewrite _rebuild**

Replace the current `_rebuild` function:

```gdscript
func _rebuild() -> void:
	for c in occupancy.values():
		c.queue_free()
	occupancy.clear()
	var spawned := LevelBuilder.spawn_crates(self, current, true,
		EditorAssets.texture_for)
	for crate in spawned:
		occupancy[EditorGrid.world_to_cell(crate.position)] = crate
	overlay.refresh()
```

with:

```gdscript
func _rebuild() -> void:
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	occupancy.clear()
	# Snap all coords to cell centres and drop duplicates.
	var seen_cells: Array[Vector2i] = []
	var snapped: Array[Dictionary] = []
	for c in current.crates:
		var cell := EditorGrid.world_to_cell(Vector2(c["x"], c["y"]))
		var snapped_pos := EditorGrid.cell_to_world(cell)
		if seen_cells.has(cell):
			continue
		seen_cells.append(cell)
		snapped.append({"x": snapped_pos.x, "y": snapped_pos.y, "type": c["type"]})
	current.crates = snapped
	_spawned = LevelBuilder.spawn_crates(self, current, true, EditorAssets.texture_for)
	for crate in _spawned:
		occupancy[EditorGrid.world_to_cell(crate.position)] = crate
	overlay.refresh()
```

- [ ] **Step 3: Run the full suite**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit 2>&1 | tail -20
```

Expected: no regressions.

- [ ] **Step 4: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add src/editor/level_editor.gd && \
  git commit -m "fix: free all spawned crates in _rebuild; snap off-grid coords; drop duplicate cells"
```

---

### Task 4: IMPORTANT — unbounded triggers DoS in level_json.gd

**Files:**
- Modify: `src/level/level_json.gd`
- Modify: `tests/unit/test_level_json.gd`

**What to fix:**

In `validate`, after the format/title/crates checks, add a check on each trigger event's id list: if `ids.size() > 16` return "too many effects".

- [ ] **Step 1: Write a failing test**

Add to `tests/unit/test_level_json.gd`:

```gdscript
func test_too_many_trigger_ids_is_null():
	var ids := '["confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti","confetti"]'
	# 17 entries
	var json_str := '{"format":1,"title":"T","crates":[],"triggers":{"on_all_cleared":' + ids + '}}'
	assert_null(LevelJson.parse(json_str))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_level_json.gd 2>&1 | tail -20
```

- [ ] **Step 3: Add the trigger-size check in validate()**

In `validate`, add after the shots check (and before `return ""`):

```gdscript
var _trig: Variant = d.get("triggers", {})
if _trig is Dictionary:
    for _event in _trig:
        var _ids: Variant = _trig[_event]
        if _ids is Array and (_ids as Array).size() > 16:
            return "too many effects"
```

- [ ] **Step 4: Run tests to verify pass**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_level_json.gd 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add src/level/level_json.gd tests/unit/test_level_json.gd && \
  git commit -m "fix: cap trigger id list at 16 entries; add DoS test"
```

---

### Task 5: IMPORTANT — silent load failure in editor_menu.gd + level_editor.gd

**Files:**
- Modify: `scenes/editor_menu.tscn`
- Modify: `src/editor/editor_menu.gd`
- Modify: `src/editor/level_editor.gd`

**What to fix:**

1. Add an `AcceptDialog` named `LoadError` to `scenes/editor_menu.tscn` with unique name and dialog text "Couldn't load that level file."
2. Add `func show_load_error() -> void` on `EditorMenu` that calls `%LoadError.popup_centered()`.
3. In `level_editor.gd`'s `_on_load` handler, when `loaded == null`, call `menu.show_load_error()` instead of silently returning.

- [ ] **Step 1: Add LoadError node to editor_menu.tscn**

Open `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble/scenes/editor_menu.tscn` and append a new node at the end (after the `ClearConfirm` node block):

```
[node name="LoadError" type="AcceptDialog" parent="."]
unique_name_in_owner = true
title = "Load Error"
dialog_text = "Couldn't load that level file."
size = Vector2i(320, 100)
```

- [ ] **Step 2: Add show_load_error() to editor_menu.gd**

In `src/editor/editor_menu.gd`, add after the `open_save_as` function:

```gdscript
func show_load_error() -> void:
	%LoadError.popup_centered()
```

- [ ] **Step 3: Fix _on_load in level_editor.gd**

Replace:

```gdscript
func _on_load(path: String) -> void:
	var loaded := LevelStore.load_level(path)
	if loaded == null:
		return
	current = loaded
	save_path = path
	_rebuild()
```

with:

```gdscript
func _on_load(path: String) -> void:
	var loaded := LevelStore.load_level(path)
	if loaded == null:
		menu.show_load_error()
		return
	current = loaded
	save_path = path
	_rebuild()
```

- [ ] **Step 4: Run the full suite**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit 2>&1 | tail -20
```

Expected: no regressions.

- [ ] **Step 5: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add scenes/editor_menu.tscn src/editor/editor_menu.gd src/editor/level_editor.gd && \
  git commit -m "fix: show LoadError dialog when load_level returns null instead of silent ignore"
```

---

### Task 6: IMPORTANT — unknown crate type silent in level_builder.gd

**Files:**
- Modify: `src/level/level_builder.gd`

**What to fix:**

In `spawn_crates`, when `tex_lookup.call(c["type"])` returns `null` AND the id is not `"crate-wood"` (the default), emit a `push_warning`.

- [ ] **Step 1: Read level_builder.gd and crate.gd**

Already read above. `spawn_crates` calls `crate.apply_type(c["type"], tex_lookup.call(c["type"]))`. We need to capture the texture result, check it, and warn if null and id != "crate-wood".

- [ ] **Step 2: Modify spawn_crates**

Replace:

```gdscript
crate.apply_type(c["type"], tex_lookup.call(c["type"]))
```

with:

```gdscript
var _tex: Texture2D = tex_lookup.call(c["type"])
if _tex == null and c["type"] != "crate-wood":
    push_warning("Unknown crate type: %s" % c["type"])
crate.apply_type(c["type"], _tex)
```

- [ ] **Step 3: Run the full suite**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit 2>&1 | tail -20
```

Expected: no regressions.

- [ ] **Step 4: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add src/level/level_builder.gd && \
  git commit -m "fix: push_warning for unknown crate type instead of silent default"
```

---

### Task 7: MINOR — Effects.is_known alignment in effects.gd

**Files:**
- Modify: `src/level/effects.gd`
- Modify: `tests/unit/test_effects.gd`

**What to fix:**

`is_known` currently returns `true` for any string starting with `"sound:"` — including ones with `/`, `\`, or `..` that `_sound` would reject. Mirror `_sound`'s guard in `is_known` so the two are consistent.

- [ ] **Step 1: Write failing tests**

Add to `tests/unit/test_effects.gd`:

```gdscript
func test_is_known_rejects_traversal_sound_ids():
	assert_false(Effects.is_known("sound:../../evil"))
	assert_false(Effects.is_known("sound:foo/bar"))
	assert_false(Effects.is_known("sound:a\\b"))
	assert_false(Effects.is_known("sound:a..b"))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_effects.gd 2>&1 | tail -20
```

- [ ] **Step 3: Fix is_known in effects.gd**

Replace:

```gdscript
static func is_known(id: String) -> bool:
	return id == "confetti" or id.begins_with("sound:")
```

with:

```gdscript
static func is_known(id: String) -> bool:
	if id == "confetti":
		return true
	if id.begins_with("sound:"):
		var name := id.trim_prefix("sound:")
		if name.contains("/") or name.contains("\\") or name.contains(".."):
			return false
		return true
	return false
```

- [ ] **Step 4: Run tests to verify pass**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_effects.gd 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add src/level/effects.gd tests/unit/test_effects.gd && \
  git commit -m "fix: is_known mirrors _sound traversal guard; add tests"
```

---

### Task 8: MINOR — banner text in editor session in level.gd

**Files:**
- Modify: `src/level/level.gd`

**What to fix:**

In `_settle`, when `_editor_session` is true, show different sub-text for the CLEARED and FAILED banners.

- [ ] **Step 1: Fix CLEARED banner text in _settle**

In `_settle`, replace:

```gdscript
hud.banner("KINGDOM CRUMBLED!", "press ENTER to play again")
```

with:

```gdscript
var _cleared_sub := "press ENTER to return to editor" if _editor_session \
    else "press ENTER to play again"
hud.banner("KINGDOM CRUMBLED!", _cleared_sub)
```

- [ ] **Step 2: Fix FAILED banner text in _settle**

Replace:

```gdscript
hud.banner("OUT OF STONES", "press ENTER to retry")
```

with:

```gdscript
var _failed_sub := "press ENTER to return to editor" if _editor_session \
    else "press ENTER to retry"
hud.banner("OUT OF STONES", _failed_sub)
```

- [ ] **Step 3: Run the full suite**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit 2>&1 | tail -20
```

- [ ] **Step 4: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add src/level/level.gd && \
  git commit -m "fix: editor-session banners say 'return to editor' instead of play-again/retry"
```

---

### Task 9: MINOR — empty stem guard in level_store.gd

**Files:**
- Modify: `src/level/level_store.gd`
- Modify: `tests/unit/test_level_store.gd`

**What to fix:**

In `save_user`, if `sanitize_stem(stem) == ""`, return `""` immediately without writing any file.

- [ ] **Step 1: Write a failing test**

Add to `tests/unit/test_level_store.gd`:

```gdscript
func test_save_user_empty_stem_returns_empty():
	var l := LevelLayout.new()
	l.title = "Junk"
	var path := LevelStore.save_user(l, "!!!")
	assert_eq(path, "")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_level_store.gd 2>&1 | tail -20
```

- [ ] **Step 3: Add the guard in save_user**

Replace:

```gdscript
static func save_user(layout: LevelLayout, stem: String) -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := "%s/%s.json" % [USER_DIR, sanitize_stem(stem)]
```

with:

```gdscript
static func save_user(layout: LevelLayout, stem: String) -> String:
	var safe := sanitize_stem(stem)
	if safe == "":
		return ""
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := "%s/%s.json" % [USER_DIR, safe]
```

Also update the `f.store_string` block to use `path` (it already does, since we just moved where `path` is assigned — check the rest of the function still uses `path` not `sanitize_stem(stem)` again).

Full updated function:

```gdscript
static func save_user(layout: LevelLayout, stem: String) -> String:
	var safe := sanitize_stem(stem)
	if safe == "":
		return ""
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := "%s/%s.json" % [USER_DIR, safe]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(LevelJson.serialize(layout))
	f.close()
	return path
```

- [ ] **Step 4: Run tests to verify pass**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_level_store.gd 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add src/level/level_store.gd tests/unit/test_level_store.gd && \
  git commit -m "fix: save_user returns empty string without writing when stem sanitizes to empty"
```

---

### Task 10: Full suite + smoke + fix report

**Files:**
- Create: `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble/.superpowers/sdd/final-fix-report.md`

- [ ] **Step 1: Run the full suite**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  /home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless res://addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit 2>&1 | tee /tmp/gut-full.txt | tail -30
```

Expected: ≥ 60 tests pass, 0 failures.

- [ ] **Step 2: Smoke editor.tscn**

```bash
/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless --quit-after 3 res://scenes/editor.tscn 2>&1 | grep -iE "error|script|parse" | head -20
```

Expected: no errors.

- [ ] **Step 3: Smoke level.tscn**

```bash
/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless --quit-after 3 res://scenes/level.tscn 2>&1 | grep -iE "error|script|parse" | head -20
```

Expected: no errors.

- [ ] **Step 4: Smoke main_menu.tscn**

```bash
/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64 \
  --headless --quit-after 3 res://scenes/main_menu.tscn 2>&1 | grep -iE "error|script|parse" | head -20
```

Expected: no errors.

- [ ] **Step 5: Write fix report**

Write to `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble/.superpowers/sdd/final-fix-report.md`. Include:
- Per-item: what was changed, which files, commit hash, test output tail
- Overall suite line count (N passed, 0 failed)
- Any concerns

- [ ] **Step 6: Commit the report**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble && \
  git add .superpowers/sdd/final-fix-report.md && \
  git commit -m "docs: final-fix-report for 9 review findings"
```

---

## Self-Review

Checking spec coverage:

| Item | Task | Covered |
|------|------|---------|
| 1. CRITICAL round-trip statics | Task 1 | yes |
| 2. CRITICAL type-confused JSON | Task 2 | yes |
| 3. IMPORTANT off-grid crates | Task 3 | yes |
| 4. IMPORTANT unbounded triggers | Task 4 | yes |
| 5. IMPORTANT silent load failure | Task 5 | yes |
| 6. IMPORTANT unknown crate type | Task 6 | yes |
| 7. MINOR Effects.is_known | Task 7 | yes |
| 8. MINOR banner text editor session | Task 8 | yes |
| 9. MINOR empty stem guard | Task 9 | yes |
| Full suite + smoke + report | Task 10 | yes |

Placeholder scan: none found.

Type consistency notes:
- `_spawned: Array[Crate]` declared in class vars, used in `_rebuild` — consistent.
- `_editor_session: bool` declared as `var _editor_session := false` — consistent across all references.
- `show_load_error()` named consistently in EditorMenu gd and level_editor.gd call site.
- `safe` local var in `save_user` replaces inline `sanitize_stem(stem)` call — rest of function uses `path` consistently.
