# Task 3: Toybox UI — Pause Menu Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a player-facing "TOYBOX" section to the pause menu: CheckBoxes for object packs, a theme OptionButton (with out-of-season disabling), hidden when packs() is empty, rebuilt on every open().

**Architecture:** Programmatic VBox appended inside the existing "Items" VBoxContainer in pause_menu.gd — no tscn node additions for the section itself, keeping the scene diff minimal. Rebuilt completely on every `open()` call by clearing and repopulating from `Pieces.packs()`. Three GUT tests appended to `tests/unit/test_toybox.gd`.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite expects **369 passing** (366 existing + 3 new) after completion.
- Focused suite: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_toybox.gd -gexit`
- **DEPLOY FREEZE: commit locally only. NO git push.**
- `Pieces.clock_month` must be reset to -1 in both `before_each` and `after_each` of the test file (already done — the existing helpers handle this; new tests must not break that).
- GUT counts engine errors as failures — no `load()` on user:// paths, use the Pieces API only.
- Headless tests instantiate `scenes/pause_menu.tscn` via `load(...).instantiate()` + `add_child_autofree(...)`, call `open()`, then inspect children (pattern matches `test_intro_dialog.gd`, `test_level_card.gd`).
- Editor-mode call: the TOYBOX section shows in editor mode too (it's harmless; the `set_editor_mode` method only toggles BackToEditor/JumpLevels visibility, and pack management is equally valid from the editor pause).
- Month names const array (1-based): `["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]` — index 0 is empty so `MONTHS[1]` = "January".
- Out-of-season text: `"<title> (returns in <Month>)"` where `<Month>` = `MONTHS[pack.months[0]]` (first entry in months array; documented note: multi-month packs show the first month only).
- Section hidden when `Pieces.packs()` is empty.
- A note Label reads `"Changes apply on next level load"`.

---

### Task 3: Toybox UI — tests, implementation, commit

**Files:**
- Modify: `src/ui/pause_menu.gd`
- Test: `tests/unit/test_toybox.gd` (append 3 tests)

**Interfaces:**
- Consumes: `Pieces.packs() -> Array[Dictionary]` (each has folder, title, kind, months, in_season, enabled), `Pieces.set_pack_enabled(folder, on)`, `Pieces.active_theme() -> String`, `Pieces.set_active_theme(folder)`, `Pieces.in_season(months)`
- Produces: a VBoxContainer named `"ToyboxSection"` appended to `%Items` (the existing `Center/Panel/Margin/Items` VBox), rebuilt on every `open()` call

- [ ] **Step 1: Write the 3 failing tests** (append to `tests/unit/test_toybox.gd`)

Add these lines at the END of the file (after the existing Task 2 tests, before the final closing):

```gdscript
# ---------------------------------------------------------------------------
# Task 3 Tests: Pause menu Toybox section
# ---------------------------------------------------------------------------

const MONTHS := ["", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]


func _pause_menu() -> PauseMenu:
	var pm: PauseMenu = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(pm)
	return pm


func test_toybox_section_hidden_without_packs() -> void:
	# No packs written → section must be absent or invisible
	Pieces.scan()
	var pm := _pause_menu()
	pm.open()
	var section := pm.get_node_or_null("Center/Panel/Margin/Items/ToyboxSection")
	if section != null:
		assert_false(section.visible, "ToyboxSection invisible when packs() is empty")
	else:
		pass  # absent is also acceptable


func test_object_pack_checkbox_toggles_enabled() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	_make_pack("ui_obj_pack", {"title": "My Objects", "kind": "objects"}, {"block.png": img})
	Pieces.scan()
	var pm := _pause_menu()
	pm.open()
	var section: Node = pm.get_node("Center/Panel/Margin/Items/ToyboxSection")
	assert_not_null(section, "ToyboxSection present when packs exist")
	assert_true(section.visible, "ToyboxSection visible when packs exist")
	# Find the CheckBox for ui_obj_pack
	var cb: CheckBox = null
	for child in section.get_children():
		if child is CheckBox and child.text == "My Objects":
			cb = child
			break
	assert_not_null(cb, "CheckBox with title 'My Objects' found in ToyboxSection")
	assert_true(cb.button_pressed, "CheckBox pressed=true because pack starts enabled")
	# Simulate toggle off — should call set_pack_enabled
	cb.button_pressed = false
	cb.toggled.emit(false)
	# After toggle, Pieces must reflect disabled (set_pack_enabled persists+rescans)
	var found_disabled := false
	for p in Pieces.packs():
		if p["folder"] == "ui_obj_pack" and not p["enabled"]:
			found_disabled = true
	assert_true(found_disabled, "toggling checkbox calls set_pack_enabled(folder, false)")


func test_theme_dropdown_lists_and_disables_out_of_season() -> void:
	# Create an in-season theme pack (months=[]) and an out-of-season one (months=[11], clock=3)
	_make_pack("theme_in", {"title": "Summer Theme", "kind": "theme", "months": []}, {})
	_make_pack("theme_out", {"title": "Winter Theme", "kind": "theme", "months": [11]}, {})
	Pieces.clock_month = 3  # not November → theme_out is out of season
	Pieces.scan()
	var pm := _pause_menu()
	pm.open()
	var section: Node = pm.get_node("Center/Panel/Margin/Items/ToyboxSection")
	assert_not_null(section, "ToyboxSection present")
	# Find the OptionButton
	var ob: OptionButton = null
	for child in section.get_children():
		if child is OptionButton:
			ob = child
			break
	assert_not_null(ob, "OptionButton (theme picker) found in ToyboxSection")
	# Must have at least 3 items: "Default", "Summer Theme", "Winter Theme (returns in November)"
	assert_gte(ob.item_count, 3, "OptionButton has Default + 2 theme items")
	# Find Winter Theme item and check disabled + text
	var winter_idx := -1
	for i in ob.item_count:
		if "Winter Theme" in ob.get_item_text(i):
			winter_idx = i
			break
	assert_ne(winter_idx, -1, "Winter Theme item found in OptionButton")
	assert_true(ob.is_item_disabled(winter_idx), "out-of-season theme item is disabled")
	assert_true("returns in November" in ob.get_item_text(winter_idx),
		"disabled item text contains 'returns in November'")
```

- [ ] **Step 2: Run focused suite to confirm RED**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble
/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_toybox.gd -gexit 2>&1 | tail -30
```

Expected: tests run, 3 new tests FAIL (method/node not found).

- [ ] **Step 3: Implement the Toybox section in pause_menu.gd**

Replace the contents of `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble/src/ui/pause_menu.gd` with:

```gdscript
class_name PauseMenu
extends CanvasLayer

# ESC pause menu. Owns the ESC key and the tree pause entirely: ESC
# opens it (pausing the game) and closes it (resuming). The level only
# listens for restart/quit. Runs in PROCESS_MODE_ALWAYS so it works
# while the tree is paused; music keeps playing (MusicDirector is
# ALWAYS too) so the volume slider gives live feedback.

signal restart_requested
signal quit_requested
signal back_to_editor_requested
signal jump_levels_requested

## Month names for the out-of-season label (index 0 = unused placeholder).
const MONTHS := ["", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

@onready var _resume: Button = %Resume
@onready var _restart: Button = %RestartLevel
@onready var _quit: Button = %QuitToTitle
@onready var _music_slider: HSlider = %MusicSlider

## Programmatic container for the Toybox section (appended to %Items).
var _toybox_section: VBoxContainer


func _ready() -> void:
	visible = false
	_resume.pressed.connect(close)
	_restart.pressed.connect(
		func() -> void:
			close()
			restart_requested.emit()
	)
	_quit.pressed.connect(
		func() -> void:
			close()
			quit_requested.emit()
	)
	_music_slider.value = Music.get_volume_linear()
	_music_slider.value_changed.connect(Music.set_volume_linear)
	%SfxSlider.value = Music.get_sfx_volume_linear()
	%SfxSlider.value_changed.connect(Music.set_sfx_volume_linear)
	%BackToEditor.visible = false
	%BackToEditor.pressed.connect(
		func():
			close()
			back_to_editor_requested.emit()
	)
	%JumpLevels.pressed.connect(
		func():
			close()
			jump_levels_requested.emit()
	)
	# Create the Toybox section container once; populate on open()
	_toybox_section = VBoxContainer.new()
	_toybox_section.name = "ToyboxSection"
	_toybox_section.visible = false
	%Items.add_child(_toybox_section)


func set_editor_mode(on: bool) -> void:
	%BackToEditor.visible = on
	%JumpLevels.visible = not on  # no chain inside the editor sandbox


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		close() if visible else open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	# a press with no release survives the pause and sticks forever
	Input.action_release("fire")
	_rebuild_toybox()
	_resume.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


## Rebuild the Toybox section from Pieces.packs() every open().
## Clears all children first so reopening never duplicates widgets.
func _rebuild_toybox() -> void:
	for child in _toybox_section.get_children():
		child.queue_free()
		_toybox_section.remove_child(child)

	var all_packs := Pieces.packs()
	if all_packs.is_empty():
		_toybox_section.visible = false
		return

	_toybox_section.visible = true

	# Section header
	var header := Label.new()
	header.text = "TOYBOX"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toybox_section.add_child(header)

	# Object pack checkboxes
	var object_packs := all_packs.filter(func(p): return p["kind"] == "objects")
	for pack in object_packs:
		var cb := CheckBox.new()
		cb.text = pack["title"]
		cb.button_pressed = pack["enabled"]
		var folder: String = pack["folder"]
		cb.toggled.connect(func(on: bool) -> void:
			Pieces.set_pack_enabled(folder, on)
		)
		_toybox_section.add_child(cb)

	# Theme OptionButton (only if there are theme packs)
	var theme_packs := all_packs.filter(func(p): return p["kind"] == "theme")
	if not theme_packs.is_empty():
		var theme_row := HBoxContainer.new()
		var theme_label := Label.new()
		theme_label.text = "Theme"
		theme_row.add_child(theme_label)

		var ob := OptionButton.new()
		ob.add_item("Default")  # index 0 = ""

		var active := Pieces.active_theme()
		var selected_idx := 0

		for i in theme_packs.size():
			var pack: Dictionary = theme_packs[i]
			var item_idx: int = i + 1  # offset by 1 for Default
			var folder: String = pack["folder"]
			var title: String = pack["title"]
			var in_season: bool = pack["in_season"]

			if in_season:
				ob.add_item(title)
			else:
				# Show first month in the months array
				var months: Array = pack.get("months", [])
				var month_name := ""
				if months.size() > 0:
					var m := int(months[0])
					if m >= 1 and m <= 12:
						month_name = MONTHS[m]
				ob.add_item("%s (returns in %s)" % [title, month_name])
				ob.set_item_disabled(item_idx, true)

			if folder == active:
				selected_idx = item_idx

		ob.selected = selected_idx
		ob.item_selected.connect(func(idx: int) -> void:
			if idx == 0:
				Pieces.set_active_theme("")
			else:
				var theme_idx := idx - 1
				if theme_idx < theme_packs.size():
					Pieces.set_active_theme(theme_packs[theme_idx]["folder"])
		)
		theme_row.add_child(ob)
		_toybox_section.add_child(theme_row)

	# Note label
	var note := Label.new()
	note.text = "Changes apply on next level load"
	_toybox_section.add_child(note)
```

- [ ] **Step 4: Run focused suite to confirm GREEN**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble
/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_toybox.gd -gexit 2>&1 | tail -30
```

Expected: all tests in test_toybox.gd pass (12 existing + 3 new = 15 total).

- [ ] **Step 5: Run full suite to confirm 369 passing**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble
/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | tail -20
```

Expected: 369 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble
git add tests/unit/test_toybox.gd src/ui/pause_menu.gd
git commit -m "feat: the Toybox — pack toggles and seasonal themes in the pause menu"
```

---

## Self-Review

**Spec coverage check:**
- [x] TOYBOX section under sliders — implemented as VBox appended to %Items
- [x] Per OBJECT pack: CheckBox (text=title, pressed=enabled, toggled→set_pack_enabled)
- [x] Theme OptionButton: Default + one item per THEME pack
- [x] Out-of-season items disabled with "(returns in <Month>)" text
- [x] Selection → set_active_theme
- [x] Section hidden when packs() is empty
- [x] Note Label ("Changes apply on next level load")
- [x] Month names via const array — no locale
- [x] Rebuild on open() — clear children first, repopulate
- [x] 3 tests matching the brief signatures
- [x] clock_month seam used in season test
- [x] test cleanup (existing helpers handle it)

**Placeholder scan:** No TBD/TODO/placeholder present.

**Type consistency:** `OptionButton.set_item_disabled(idx, true)` is correct Godot 4 API. `button_pressed` is the CheckBox property (not `pressed`). `item_selected` is the correct OptionButton signal.

**Edge note:** `queue_free()` + `remove_child()` in _rebuild_toybox — ordering matters. In Godot 4, `queue_free()` defers deletion to end of frame; during the same frame the node is still a child. Use `_toybox_section.get_children()` snapshot + free loop, or simply iterate and free. Better: iterate `_toybox_section.get_children()` backwards and call `child.queue_free()` — Godot removes them safely. Alternatively, loop and call `child.free()` (immediate) which is safe for UI nodes not mid-signal. The plan uses `queue_free()` + `remove_child()` — this is the correct pattern to avoid dangling-child issues during the same frame rebuild.
