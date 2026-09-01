# Pretty Pass Implementation Plan (UI chrome only)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the UI chrome to match the owner's comps — unified StatCard HUD, comp-styled FIRE/MENU, card-grid level select with png-or-NO-IMAGE thumbs, NOW badge, N OF M CLEARED header.

**Architecture:** New `StatCard` and `LevelCard` scenes transcribed from `art/mockups/Game UI Styles.html`; hud.tscn and level_jump_dialog.tscn restyled in place. Hud keeps its public API (set_shots/set_crates/set_power/set_buffs/toast) and forwards to the card — the existing suite is the regression net. Depth is flat-approximated (face color + bottom-ledge border).

**Tech Stack:** Godot 4.6.2, GDScript, GUT headless. Fonts at art/fonts/ (Lilita One, Nunito variable, IBM Plex Mono Medium).

## Global Constraints

- `$GODOT` = `/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64`; project `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble`. Import once after new files. Suite cmd: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` — 145 green at start, stays green.
- **SCOPE WALL (binding):** touch ONLY: scenes/hud.tscn, scenes/ui/*, src/ui/*, tests/, and ONE wiring call in src/level/level.gd (`hud.set_level_info`). NOTHING else — no gameplay, world scenes, physics, art (fonts/mockups excluded), assets.
- Spec (binding): docs/superpowers/specs/2026-09-01-pretty-pass-design.md. Comps (binding values): art/mockups/Game UI Styles.html — when a value is unclear in this plan, the comp file is the authority.
- Palette (from palette.json): ink #4b3b2a, ink-muted #8f7047, brass #d9b26a, brass-light #f0d79a, brass-dark #c39b4e, parchment #f4e7c8, parchment-light #fffaf0, danger #b5442e, fire-top #c9553a, fire-bottom #a13a24, success #2e7d32.
- git add only touched files (+ .uid). NEVER -A. Tabs. gdformat style (double blank line between funcs).

## File Map

- Create: `src/ui/dashed_line.gd` (tiny draw helper), `src/ui/stat_card.gd` + `scenes/ui/stat_card.tscn` (Task 1)
- Modify: `scenes/hud.tscn`, `src/ui/hud.gd`, `src/level/level.gd` one call (Task 1); FIRE/MENU in same files (Task 2)
- Create: `src/ui/level_card.gd` + `scenes/ui/level_card.tscn` (Task 3)
- Modify: `scenes/ui/level_jump_dialog.tscn`, `src/ui/level_jump_dialog.gd` (Task 4)
- Task 5: verification only.

---

### Task 1: StatCard + HUD rewiring

**Files:**
- Create: `src/ui/dashed_line.gd`, `src/ui/stat_card.gd`, `scenes/ui/stat_card.tscn`
- Modify: `scenes/hud.tscn`, `src/ui/hud.gd`, `src/level/level.gd` (one call)
- Test: `tests/unit/test_stat_card.gd` (create)

**Interfaces:**
- Produces: `StatCard` with `set_title(t: String)`, `set_level_no(n: int)` (n < 1 hides the chip), `set_shots(n: int)`, `set_crates(standing: int, total: int)`, `set_power(ratio: float)`, `set_buffs(buffs: Array[StringName])`.
- Hud API unchanged; gains `set_level_info(title: String, number: int)`. level.gd calls it once in `_ready` (after `current_stem` resolution): number = chain index + 1 or -1 when `current_stem == ""`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_stat_card.gd`:

```gdscript
extends GutTest


func _card() -> StatCard:
	var c: StatCard = load("res://scenes/ui/stat_card.tscn").instantiate()
	add_child_autofree(c)
	return c


func test_values_reflect_in_labels() -> void:
	var c := _card()
	c.set_title("THE MEADOW")
	c.set_level_no(2)
	c.set_shots(5)
	c.set_crates(7, 7)
	c.set_power(0.5)
	assert_eq(c.get_node("%Title").text, "THE MEADOW")
	assert_eq(c.get_node("%LvlChip").text, "LVL 2")
	assert_true(c.get_node("%LvlChip").visible)
	assert_eq(c.get_node("%ShotsValue").text, "5")
	assert_eq(c.get_node("%CratesValue").text, "7/7")
	assert_almost_eq(c.get_node("%PowerBar").value, 0.5, 0.001)


func test_no_chain_position_hides_chip() -> void:
	var c := _card()
	c.set_level_no(-1)
	assert_false(c.get_node("%LvlChip").visible)


func test_buff_section_hides_when_empty() -> void:
	var c := _card()
	c.set_buffs([] as Array[StringName])
	assert_false(c.get_node("%BuffSection").visible)
	c.set_buffs([&"exploding", &"exploding"] as Array[StringName])
	assert_true(c.get_node("%BuffSection").visible)
	assert_eq(c.get_node("%BuffRow").get_child_count(), 2)


func test_hud_forwards_to_card() -> void:
	var h: Hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(h)
	h.set_shots(3)
	h.set_crates(1, 4)
	h.set_level_info("SKULL", 3)
	assert_eq(h.get_node("%StatCard/%ShotsValue").text, "3")
	assert_eq(h.get_node("%StatCard/%CratesValue").text, "1/4")
	assert_eq(h.get_node("%StatCard/%Title").text, "SKULL")
```

- [ ] **Step 2: Run selected — FAIL (StatCard not found):** `-gselect=test_stat_card`

- [ ] **Step 3: Implement**

Create `src/ui/dashed_line.gd`:

```gdscript
class_name DashedLine
extends Control

# Comp-faithful dashed separator (ink-muted dashes).


func _draw() -> void:
	draw_dashed_line(
		Vector2(0, size.y / 2.0),
		Vector2(size.x, size.y / 2.0),
		Color(0.5608, 0.4392, 0.2784, 0.45),
		2.0,
		6.0
	)
```

Create `src/ui/stat_card.gd`:

```gdscript
class_name StatCard
extends PanelContainer

# The unified HUD panel (pretty-pass spec §2), transcribed from the
# owner's comps. Values in, pixels out — no game logic.

const BUFF_ICONS := {
	&"exploding": "skull",
	&"multishot": "crate-blue",
	&"super_bounce": "crate-green",
}


func set_title(t: String) -> void:
	%Title.text = t


func set_level_no(n: int) -> void:
	%LvlChip.visible = n >= 1
	if n >= 1:
		%LvlChip.text = "LVL %d" % n


func set_shots(n: int) -> void:
	%ShotsValue.text = str(n)


func set_crates(standing: int, total: int) -> void:
	%CratesValue.text = "%d/%d" % [standing, total]


func set_power(ratio: float) -> void:
	%PowerBar.value = ratio


func set_buffs(buffs: Array[StringName]) -> void:
	%BuffSection.visible = not buffs.is_empty()
	for c in %BuffRow.get_children():
		%BuffRow.remove_child(c)
		c.queue_free()
	for b in buffs:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = EditorAssets.texture_for(BUFF_ICONS.get(b, ""))
		%BuffRow.add_child(icon)
```

Create `scenes/ui/stat_card.tscn` (values from the comp: body padding 11/14, gaps 9/10, mono 9px .16em tracking ≈ 1.4px extra spacing, values Lilita 20, icons 17):

```
[gd_scene load_steps=8 format=3]

[ext_resource type="Script" path="res://src/ui/stat_card.gd" id="1"]
[ext_resource type="Script" path="res://src/ui/dashed_line.gd" id="2"]
[ext_resource type="FontFile" path="res://art/fonts/LilitaOne-Regular.ttf" id="f_disp"]
[ext_resource type="FontFile" path="res://art/fonts/IBMPlexMono-Medium.ttf" id="f_mono"]
[ext_resource type="Texture2D" path="res://art/assets/ui/stone.png" id="t_stone"]

[sub_resource type="StyleBoxFlat" id="pwr_bg"]
bg_color = Color(1, 0.9804, 0.9412, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.5608, 0.4392, 0.2784, 0.45)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_right = 9
corner_radius_bottom_left = 9

[sub_resource type="StyleBoxFlat" id="pwr_fill"]
bg_color = Color(0.851, 0.698, 0.4157, 1)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_right = 9
corner_radius_bottom_left = 9

[node name="StatCard" type="PanelContainer"]
offset_left = 24.0
offset_top = 18.0
offset_right = 344.0
mouse_filter = 2

[node name="Body" type="VBoxContainer" parent="."]
layout_mode = 2
theme_override_constants/separation = 9

[node name="Header" type="HBoxContainer" parent="Body"]
layout_mode = 2
theme_override_constants/separation = 10

[node name="Title" type="Label" parent="Body/Header"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3
theme_override_fonts/font = ExtResource("f_disp")
theme_override_font_sizes/font_size = 22
text = "LEVEL"

[node name="LvlChip" type="Label" parent="Body/Header"]
unique_name_in_owner = true
layout_mode = 2
size_flags_vertical = 4
theme_override_fonts/font = ExtResource("f_mono")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.5608, 0.4392, 0.2784, 1)
text = "LVL 1"

[node name="Dash1" type="Control" parent="Body"]
custom_minimum_size = Vector2(0, 4)
layout_mode = 2
script = ExtResource("2")

[node name="ShotsRow" type="HBoxContainer" parent="Body"]
layout_mode = 2
theme_override_constants/separation = 10

[node name="StoneIcon" type="TextureRect" parent="Body/ShotsRow"]
custom_minimum_size = Vector2(20, 20)
layout_mode = 2
expand_mode = 1
stretch_mode = 5
texture = ExtResource("t_stone")

[node name="ShotsLabel" type="Label" parent="Body/ShotsRow"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_fonts/font = ExtResource("f_mono")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.5608, 0.4392, 0.2784, 1)
text = "STONES"

[node name="ShotsValue" type="Label" parent="Body/ShotsRow"]
unique_name_in_owner = true
layout_mode = 2
theme_override_fonts/font = ExtResource("f_disp")
theme_override_font_sizes/font_size = 20
text = "0"

[node name="Dash2" type="Control" parent="Body"]
custom_minimum_size = Vector2(0, 4)
layout_mode = 2
script = ExtResource("2")

[node name="CratesRow" type="HBoxContainer" parent="Body"]
layout_mode = 2
theme_override_constants/separation = 10

[node name="CrateIcon" type="TextureRect" parent="Body/CratesRow"]
unique_name_in_owner = true
custom_minimum_size = Vector2(20, 20)
layout_mode = 2
expand_mode = 1
stretch_mode = 5

[node name="CratesLabel" type="Label" parent="Body/CratesRow"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_fonts/font = ExtResource("f_mono")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.5608, 0.4392, 0.2784, 1)
text = "CRATES"

[node name="CratesValue" type="Label" parent="Body/CratesRow"]
unique_name_in_owner = true
layout_mode = 2
theme_override_fonts/font = ExtResource("f_disp")
theme_override_font_sizes/font_size = 20
text = "0/0"

[node name="PwrRow" type="HBoxContainer" parent="Body"]
layout_mode = 2
theme_override_constants/separation = 10

[node name="PwrLabel" type="Label" parent="Body/PwrRow"]
layout_mode = 2
theme_override_fonts/font = ExtResource("f_mono")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.5608, 0.4392, 0.2784, 1)
text = "PWR"

[node name="PowerBar" type="ProgressBar" parent="Body/PwrRow"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 18)
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 4
theme_override_styles/background = SubResource("pwr_bg")
theme_override_styles/fill = SubResource("pwr_fill")
max_value = 1.0
step = 0.001
show_percentage = false

[node name="BuffSection" type="VBoxContainer" parent="Body"]
unique_name_in_owner = true
visible = false
layout_mode = 2
theme_override_constants/separation = 9

[node name="Dash3" type="Control" parent="Body/BuffSection"]
custom_minimum_size = Vector2(0, 4)
layout_mode = 2
script = ExtResource("2")

[node name="BuffRow" type="HBoxContainer" parent="Body/BuffSection"]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 6
```

Modify `scenes/hud.tscn`: DELETE the node blocks for `PowerBar` (the stat_bar instance), `StonesRow` (+children `StoneIcon`, `Shots`), `CratesRow` (+children), and `BuffRow`; delete the now-unused ext_resources they referenced (stone/gear icon refs that nothing else uses — keep any still used by other nodes). ADD instead (top of the node list, right after the root Hud node):

```
[node name="StatCard" parent="." instance=ExtResource("<new-id-for-res://scenes/ui/stat_card.tscn>")]
unique_name_in_owner = true
```

(Add the matching `[ext_resource type="PackedScene" path="res://scenes/ui/stat_card.tscn" id="<new-id>"]` and bump load_steps.)

Modify `src/ui/hud.gd`: REPLACE the bodies of `set_shots`, `set_crates`, `set_power`, `set_buffs` with forwards, keep signatures; DELETE the `BUFF_ICONS` const (moved into StatCard); ADD `set_level_info`:

```gdscript
func set_shots(n: int) -> void:
	%StatCard.set_shots(n)


func set_crates(standing: int, total: int) -> void:
	%StatCard.set_crates(standing, total)


func set_power(ratio: float) -> void:
	%StatCard.set_power(ratio)


func set_buffs(buffs: Array[StringName]) -> void:
	%StatCard.set_buffs(buffs)


func set_level_info(title: String, number: int) -> void:
	%StatCard.set_title(title)
	%StatCard.set_level_no(number)
```

Also in `_ready`, set the crate icon once: `%StatCard.get_node("%CrateIcon").texture = EditorAssets.texture_for("crate-wood")`.

Modify `src/level/level.gd` — ONE wiring call in `_ready`, directly after the `hud.toast(layout.title)` block:

```gdscript
	var _chain := LevelChain.entries()
	var _pos := -1
	for i in _chain.size():
		if _chain[i]["stem"] == current_stem and current_stem != "":
			_pos = i + 1
			break
	hud.set_level_info(layout.title, _pos)
```

- [ ] **Step 4: Import; selected PASS; FULL suite green (145 + 4 = 149). The old hud tests (test_hud_buffs) exercise the forwarded API — if any assert against the deleted hud nodes (`BuffRow` path), update those assertions to the StatCard paths (`%StatCard/%BuffRow`) — behavior identical, locations moved. Note every such edit in your report.**

- [ ] **Step 5: Commit**

```bash
git add src/ui/dashed_line.gd src/ui/dashed_line.gd.uid src/ui/stat_card.gd src/ui/stat_card.gd.uid scenes/ui/stat_card.tscn scenes/hud.tscn src/ui/hud.gd src/level/level.gd tests/unit/test_stat_card.gd tests/unit/test_stat_card.gd.uid tests/unit/test_hud_buffs.gd
git commit -m "feat: StatCard — the unified parchment HUD panel from the comps"
```

---

### Task 2: FIRE and MENU restyle + dynamic FIRE icon

**Files:**
- Modify: `scenes/hud.tscn`, `src/ui/hud.gd`
- Test: append to `tests/unit/test_stat_card.gd`

**Interfaces:**
- Consumes: existing `%FireButton`, `%MenuButton` nodes and their wiring (press/release actions, menu_pressed) — wiring MUST NOT change.
- Produces: comp-styled buttons; `Hud.set_buffs` additionally updates the FIRE icon.

- [ ] **Step 1: Write the failing test** (append to test_stat_card.gd):

```gdscript
func test_fire_icon_tracks_queue() -> void:
	var h: Hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(h)
	var fire: Button = h.get_node("%FireButton")
	h.set_buffs([] as Array[StringName])
	var plain: Texture2D = fire.icon
	h.set_buffs([&"exploding"] as Array[StringName])
	assert_ne(fire.icon, plain, "exploding queue changes the FIRE icon")
	h.set_buffs([&"exploding", &"super_bounce"] as Array[StringName])
	assert_eq(fire.icon, EditorAssets.texture_for("crate-gold"), "2+ types = gold")
	h.set_buffs([] as Array[StringName])
	assert_eq(fire.icon, plain, "empty queue restores the stone")
```

- [ ] **Step 2: Selected run — FAIL (icon never changes).**

- [ ] **Step 3: Implement**

`scenes/hud.tscn` — restyle both buttons with scene-local styleboxes (add as sub_resources; fire-top face + 5px fire-bottom bottom-only ledge, radius 24; MENU brass-light face + brass-dark ledge, radius 24; label font Lilita via theme_override_fonts using the existing font ext_resource pattern from stat_card):

FIRE (`FireButton` node keeps name/anchors/signals; adjust size for ≥48px):

```
theme_override_styles/normal → StyleBoxFlat: bg #c9553a, border_width_bottom 5, border_color #a13a24, radius 24, content margins 20/10/20/12
theme_override_styles/hover → same with bg lightened to #d4664b
theme_override_styles/pressed → bg #a13a24, border_width_top 5 (bottom 0), border_color #7d2c1b
theme_override_fonts/font = Lilita, font_size 26, font colors #fffaf0
text = "FIRE!"
expand_icon = true
```

MENU (`MenuButton`): same recipe with brass-light face `#f0d79a`, brass-dark ledge `#c39b4e`, ink text, font_size 20, `text = "☰  MENU"`, radius 24. Remove its old gear icon/stylebox if present.

`src/ui/hud.gd` — extend `set_buffs` (after forwarding) and preload the stone:

```gdscript
const FIRE_STONE := preload("res://art/assets/ui/stone.png")


func _fire_icon_for(buffs: Array[StringName]) -> Texture2D:
	var kinds := {}
	for b in buffs:
		kinds[b] = true
	if kinds.size() >= 2:
		return EditorAssets.texture_for("crate-gold")
	if kinds.has(&"exploding"):
		return EditorAssets.texture_for("skull")
	if kinds.has(&"super_bounce"):
		return EditorAssets.texture_for("crate-green")
	if kinds.has(&"multishot"):
		return EditorAssets.texture_for("crate-blue")
	return FIRE_STONE
```

and in `set_buffs`: `%FireButton.icon = _fire_icon_for(buffs)`. Also set the default in `_ready`: `%FireButton.icon = FIRE_STONE`.

- [ ] **Step 4: Selected PASS; FULL suite green (149 + 1 = 150).**

- [ ] **Step 5: Commit**

```bash
git add scenes/hud.tscn src/ui/hud.gd tests/unit/test_stat_card.gd
git commit -m "feat: FIRE and MENU wear the comps — ledge depth, Lilita, dynamic FIRE icon"
```

---

### Task 3: LevelCard component

**Files:**
- Create: `src/ui/level_card.gd`, `scenes/ui/level_card.tscn`
- Test: `tests/unit/test_level_card.gd` (create)

**Interfaces:**
- Produces: `LevelCard` (Button root) — `signal picked(path: String)`; `func setup(entry: Dictionary, cleared: bool, unlocked: bool, is_now: bool) -> void` (entry = LevelChain shape {stem, path, title}).
- Thumb source: `entry.path.get_basename() + ".png"` — `ResourceLoader.exists` for res://, `FileAccess.file_exists` + `Image.load_from_file` for user://.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_level_card.gd`:

```gdscript
extends GutTest


func _card() -> LevelCard:
	var c: LevelCard = load("res://scenes/ui/level_card.tscn").instantiate()
	add_child_autofree(c)
	return c


func _entry(stem: String) -> Dictionary:
	return {"stem": stem, "path": "user://levels/%s.json" % stem, "title": stem}


func test_missing_png_shows_no_image() -> void:
	var c := _card()
	c.setup(_entry("definitely_has_no_png"), false, true, false)
	assert_true(c.get_node("%NoImage").visible)
	assert_false(c.get_node("%Thumb").visible)


func test_sibling_png_becomes_thumb() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	img.save_png("user://levels/card_png_probe.png")
	var c := _card()
	c.setup(_entry("card_png_probe"), false, true, false)
	assert_true(c.get_node("%Thumb").visible)
	assert_not_null(c.get_node("%Thumb").texture)
	DirAccess.remove_absolute("user://levels/card_png_probe.png")


func test_locked_card_disabled_and_greyed() -> void:
	var c := _card()
	c.setup(_entry("x"), false, false, false)
	assert_true(c.disabled)
	assert_lt(c.get_node("%ThumbBox").modulate.v, 1.0)


func test_now_badge_only_when_now() -> void:
	var c := _card()
	c.setup(_entry("x"), false, true, true)
	assert_true(c.get_node("%NowBadge").visible)
	c.setup(_entry("x"), true, true, false)
	assert_false(c.get_node("%NowBadge").visible)


func test_press_emits_path() -> void:
	var c := _card()
	c.setup(_entry("pick_me"), false, true, false)
	watch_signals(c)
	c.pressed.emit()
	assert_signal_emitted_with_parameters(c, "picked", ["user://levels/pick_me.json"])
```

- [ ] **Step 2: Selected — FAIL (LevelCard not found).**

- [ ] **Step 3: Implement**

Create `src/ui/level_card.gd`:

```gdscript
class_name LevelCard
extends Button

# One level in the jump grid (pretty-pass spec §4). Thumb comes from
# the level's sibling <stem>.png when it exists — the owner's two-file
# convention; a future capture pipeline needs no changes here.

signal picked(path: String)

var _path := ""


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(_path))


func setup(entry: Dictionary, cleared: bool, unlocked: bool, is_now: bool) -> void:
	_path = entry["path"]
	%Title.text = entry["title"]
	%StateIcon.text = "✓" if cleared else ("🔒" if not unlocked else "")
	%StateIcon.visible = %StateIcon.text != ""
	disabled = not unlocked
	%NowBadge.visible = is_now
	var tex := _sibling_thumb(entry["path"])
	%Thumb.visible = tex != null
	%NoImage.visible = tex == null
	if tex != null:
		%Thumb.texture = tex
	%ThumbBox.modulate = Color(1, 1, 1) if unlocked else Color(0.55, 0.55, 0.55)
	if is_now:
		add_theme_stylebox_override("normal", _now_ring())
	else:
		remove_theme_stylebox_override("normal")


func _sibling_thumb(level_path: String) -> Texture2D:
	var png := level_path.get_basename() + ".png"
	if png.begins_with("res://"):
		return load(png) if ResourceLoader.exists(png) else null
	if FileAccess.file_exists(png):
		var img := Image.load_from_file(png)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


func _now_ring() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.9804, 0.9412, 1)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.7098, 0.2667, 0.1804, 1)
	sb.set_corner_radius_all(8)
	return sb
```

Create `scenes/ui/level_card.tscn`:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://src/ui/level_card.gd" id="1"]
[ext_resource type="FontFile" path="res://art/fonts/IBMPlexMono-Medium.ttf" id="f_mono"]

[sub_resource type="StyleBoxFlat" id="card_face"]
bg_color = Color(1, 0.9804, 0.9412, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.5608, 0.4392, 0.2784, 0.6)
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_right = 8
corner_radius_bottom_left = 8

[sub_resource type="StyleBoxFlat" id="thumb_ph"]
bg_color = Color(0.9569, 0.9059, 0.7843, 1)
corner_radius_top_left = 6
corner_radius_top_right = 6

[sub_resource type="StyleBoxFlat" id="now_badge"]
bg_color = Color(0.7098, 0.2667, 0.1804, 1)
corner_radius_top_left = 5
corner_radius_top_right = 5
corner_radius_bottom_right = 5
corner_radius_bottom_left = 5
content_margin_left = 8.0
content_margin_top = 2.0
content_margin_right = 8.0
content_margin_bottom = 2.0

[node name="LevelCard" type="Button"]
custom_minimum_size = Vector2(220, 170)
theme_override_styles/normal = SubResource("card_face")
theme_override_styles/hover = SubResource("card_face")
theme_override_styles/pressed = SubResource("card_face")
theme_override_styles/disabled = SubResource("card_face")
script = ExtResource("1")

[node name="V" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 6.0
offset_top = 6.0
offset_right = -6.0
offset_bottom = -6.0
theme_override_constants/separation = 6
mouse_filter = 2

[node name="ThumbBox" type="Panel" parent="V"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 110)
layout_mode = 2
size_flags_vertical = 3
theme_override_styles/panel = SubResource("thumb_ph")
mouse_filter = 2

[node name="Thumb" type="TextureRect" parent="V/ThumbBox"]
unique_name_in_owner = true
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
expand_mode = 1
stretch_mode = 6
mouse_filter = 2

[node name="NoImage" type="Label" parent="V/ThumbBox"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
horizontal_alignment = 1
vertical_alignment = 1
theme_override_fonts/font = ExtResource("f_mono")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(0.5608, 0.4392, 0.2784, 1)
text = "NO IMAGE"
mouse_filter = 2

[node name="NowBadge" type="Label" parent="V/ThumbBox"]
unique_name_in_owner = true
visible = false
layout_mode = 0
offset_left = 8.0
offset_top = 8.0
offset_right = 62.0
offset_bottom = 28.0
theme_override_styles/normal = SubResource("now_badge")
theme_override_fonts/font = ExtResource("f_mono")
theme_override_font_sizes/font_size = 11
theme_override_colors/font_color = Color(1, 0.9804, 0.9412, 1)
horizontal_alignment = 1
text = "NOW"
mouse_filter = 2

[node name="TitleRow" type="HBoxContainer" parent="V"]
layout_mode = 2
theme_override_constants/separation = 8
mouse_filter = 2

[node name="StateIcon" type="Label" parent="V/TitleRow"]
unique_name_in_owner = true
layout_mode = 2
theme_override_font_sizes/font_size = 16
mouse_filter = 2

[node name="Title" type="Label" parent="V/TitleRow"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3
theme_override_font_sizes/font_size = 16
mouse_filter = 2
```

- [ ] **Step 4: Import; selected PASS; FULL suite green (150 + 5 = 155).**

- [ ] **Step 5: Commit**

```bash
git add src/ui/level_card.gd src/ui/level_card.gd.uid scenes/ui/level_card.tscn tests/unit/test_level_card.gd tests/unit/test_level_card.gd.uid
git commit -m "feat: LevelCard — png-or-NO-IMAGE thumb, states, NOW badge (two-file convention)"
```

---

### Task 4: Jump dialog becomes the card grid

**Files:**
- Modify: `scenes/ui/level_jump_dialog.tscn`, `src/ui/level_jump_dialog.gd`
- Modify: `tests/unit/test_level_jump_dialog.gd` (adjust structural assertions)

**Interfaces:**
- Public surface unchanged: `signal level_picked(path)`, `open(tier)`, Esc/close behavior, `%CloseBtn` still exists (now the red X). Existing tests that count children of `%List` keep working — `%List` becomes the GridContainer.

- [ ] **Step 1: Update tests (failing)** — in `tests/unit/test_level_jump_dialog.gd`, adjust ONLY structural expectations: children of `%List` are now `LevelCard` (Button subclasses, so `.disabled` asserts still work); the pick test presses `get_child(0).pressed.emit()` same as before; ADD one test:

```gdscript
func test_header_counts_cleared() -> void:
	var d := _dialog()
	d.open("chill")
	var chain := LevelChain.entries()
	var cleared := 0
	for e in chain:
		if Progress.is_cleared("chill", e["stem"]):
			cleared += 1
	assert_eq(d.get_node("%ClearCount").text, "%d OF %d CLEARED" % [cleared, chain.size()])
```

- [ ] **Step 2: Selected — FAIL (%ClearCount missing).**

- [ ] **Step 3: Implement**

`scenes/ui/level_jump_dialog.tscn` — restructure the panel contents: Title row = "LEVELS" (Lilita 28) left + `%ClearCount` Label (IBM Plex Mono 11, ink-muted) right; dashed rule under it (DashedLine, as in stat_card); `%List` becomes a `GridContainer` (columns = 3, h/v separation 14) inside the ScrollContainer (min size 740x520); `%CloseBtn` becomes a 44x44 circular danger button anchored to the panel's top-right corner (anchors 1,0; offsets -22..22 so it floats half-out like the comp), StyleBoxFlat bg #b5442e radius 22 with parchment "✕" text, ink border 2. Keep node NAMES `List` and `CloseBtn` with unique_name_in_owner (public surface).

`src/ui/level_jump_dialog.gd` — `open(tier)` rebuild loop now instantiates cards:

```gdscript
const LEVEL_CARD := preload("res://scenes/ui/level_card.tscn")


func open(tier: String) -> void:
	for c in %List.get_children():
		%List.remove_child(c)
		c.queue_free()
	var chain := LevelChain.entries()
	var current := _current_stem()
	var cleared_count := 0
	for i in chain.size():
		var stem: String = chain[i]["stem"]
		var cleared := Progress.is_cleared(tier, stem)
		if cleared:
			cleared_count += 1
		var card: LevelCard = LEVEL_CARD.instantiate()
		%List.add_child(card)
		card.setup(chain[i], cleared, LevelChain.is_unlocked(chain, i, tier), stem == current)
		card.picked.connect(func(path: String) -> void:
			level_picked.emit(path)
			hide())
	%ClearCount.text = "%d OF %d CLEARED" % [cleared_count, chain.size()]
	show()


func _current_stem() -> String:
	var scene := get_tree().current_scene
	if scene != null and "current_stem" in scene:
		return scene.current_stem
	return ""
```

(Esc `_input` handler and `%CloseBtn.pressed → hide` wiring unchanged.)

- [ ] **Step 4: Import; selected PASS; FULL suite green (155 + 1 = 156, minus any count drift from restructured assertions — report exact numbers). Run twice.**

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/level_jump_dialog.tscn src/ui/level_jump_dialog.gd tests/unit/test_level_jump_dialog.gd
git commit -m "feat: level select is a card grid — thumbs, NOW ring, N OF M CLEARED, red X"
```

---

### Task 5: Verification sweep (no code)

- [ ] **Step 1:** FULL suite green, twice; record final count.
- [ ] **Step 2:** Three-scene smoke (main_menu, level, editor — 8s headless each, no SCRIPT ERROR/Parse Error).
- [ ] **Step 3:** SCOPE WALL check: `git diff main...HEAD --name-only` contains ONLY: scenes/hud.tscn, scenes/ui/*, src/ui/*, src/level/level.gd, tests/*, docs/*. Confirm the level.gd diff is exactly the one set_level_info wiring block.
- [ ] **Step 4:** Report; no commit.

## Post-plan notes (controller)

- Final whole-branch review (most capable model) with the comps open — fidelity is a review criterion, not just correctness; then fix wave, merge.
- Owner will screenshot levels into `<stem>.png` siblings at leisure — cards light up with zero code.
- IBM Plex Mono letter-spacing: Godot lacks per-label tracking; the mono face at small sizes carries the look. Note for the owner if the meta labels feel tight vs comps.
