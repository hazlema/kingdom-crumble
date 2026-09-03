# NarfDecor DRIFT + WANDER Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two new NarfDecor behaviors — DRIFT (axis-locked ping-pong glide for clouds) and WANDER (random roaming for butterflies) — wired through the level editor and level JSON, plus renaming the `amplitude` property to `movement`.

**Architecture:** All motion stays in NarfDecor's `_process` sine/lerp math (no Tweens — deterministic, headless-testable). The editor's piece inspector and the JSON pipeline (validate → build → clamp) gain three optional fields. The JSON field `amplitude` KEEPS its name while the GDScript property becomes `movement`.

**Tech Stack:** Godot 4.6.3 GDScript, GUT headless tests.

Spec: `docs/superpowers/specs/2026-09-03-narf-drift-wander-design.md`

## Global Constraints

- Godot binary for ALL commands: `/home/frosty/Dev/godot/bin/godot`
- Full suite command (currently **247 passing**; must stay green, grows with new tests):
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- NarfKit rule: `addons/narfkit/` has ZERO host-game references — dials are exports.
- Level JSON `FORMAT` constant does NOT change; all new overlay fields are optional with defaults; the JSON field name stays `"amplitude"` (display/property name changes only).
- Validation split (existing doctrine): wrong TYPE → `level_json.gd` returns "bad overlay"; unknown NAME → `scenery_builder.gd` warns + skips the entry.
- GDScript trap: `:=` inference fails on Variant-yielding loops — use typed loop vars (`for i: int in ...`) when iterating untyped arrays.
- Defaults everywhere: `axis` "HORIZONTAL", `travel` 120.0, `tilt` 8.0. Clamps: travel 0–2000, tilt 0–45.
- No rendered non-ASCII characters (web fonts carry no symbols).

---

### Task 1: Rename `amplitude` → `movement`

Pure rename, no behavior change. The JSON overlay key and the inspector's node names / overlay-dict key stay `amplitude` (save compat); only the GDScript property and user-facing label change.

**Files:**
- Modify: `addons/narfkit/narf_decor.gd:36-37` (the export var)
- Modify: `src/level/scenery_builder.gd:56` (property assignment)
- Modify: `src/editor/piece_inspector.gd:159` (property poke) + comments at lines 6, 16, 94
- Modify: `scenes/editor_piece_inspector.tscn:112` (label text)
- Test: `tests/unit/test_narf_decor.gd` (property name in `_piece` helper)

**Interfaces:**
- Consumes: nothing.
- Produces: `NarfDecor.movement: float` (0–180) — Tasks 2–4 use this name; `amplitude` no longer exists as a property.

- [ ] **Step 1: Rename in the component**

In `addons/narfkit/narf_decor.gd` replace:

```gdscript
## SWAY: peak tilt in degrees. BOB: peak travel in pixels.
@export_range(0.0, 180.0, 0.5) var amplitude := 6.0
```

with:

```gdscript
## How much it moves — SWAY: peak tilt in degrees. BOB: peak travel in pixels.
@export_range(0.0, 180.0, 0.5) var movement := 6.0
```

and update the two uses in `_process` (SWAY and BOB branches): `amplitude` → `movement`.

- [ ] **Step 2: Rename consumers**

`src/level/scenery_builder.gd:56` becomes (JSON key unchanged — that's the point):

```gdscript
		# JSON field keeps the old name "amplitude" for save compat.
		piece.movement = clampf(float(entry.get("amplitude", 6.0)), 0.0, 180.0)
```

`src/editor/piece_inspector.gd:159`: `_piece.amplitude = v` → `_piece.movement = v`.
In the header comment (lines 5–18): change `amplitude HSlider (0-60)` to `movement HSlider (0-60, overlay key "amplitude")` and `Speed, amplitude, and pivot ARE applied live` to `Speed, movement, and pivot ARE applied live`. Line 94 comment: `# --- Pre-populate movement (overlay key "amplitude") ---`. Do NOT rename `set_amplitude`, `_amplitude_slider`, `%AmplitudeSlider`, or the `_overlay["amplitude"]` key.

`scenes/editor_piece_inspector.tscn:112`: `text = "Amplitude:"` → `text = "Movement:"`.

`tests/unit/test_narf_decor.gd:11`: `d.amplitude = 10.0` → `d.movement = 10.0`. Test name `test_bob_moves_vertically_within_amplitude` → `test_bob_moves_vertically_within_movement`.

- [ ] **Step 3: Verify no stragglers**

Run: `grep -rn "\.amplitude" src/ addons/ tests/ scenes/`
Expected: no matches (grep for the PROPERTY access `.amplitude`; string key `"amplitude"` matches are fine and expected).

- [ ] **Step 4: Run the full suite**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: 247 passing, 0 failing.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename NarfDecor amplitude -> movement (JSON field name unchanged)"
```

---

### Task 2: DRIFT + WANDER verbs in NarfDecor

**Files:**
- Modify: `addons/narfkit/narf_decor.gd`
- Modify: `addons/narfkit/README.md` (document both verbs + the rename)
- Test: `tests/unit/test_narf_decor.gd`

**Interfaces:**
- Consumes: `movement` rename from Task 1.
- Produces: `NarfDecor.Behavior.DRIFT` (=4), `NarfDecor.Behavior.WANDER` (=5), `NarfDecor.DriftAxis.{HORIZONTAL, VERTICAL}`, properties `axis: DriftAxis`, `travel: float` (0–2000), `tilt: float` (0–45), internals `_home_pos: Vector2`, `_rng: RandomNumberGenerator`, `_hop_start/_hop_target: Vector2`, `_hop_p: float`, `_hop_active: bool`. Tasks 3–4 rely on the enum VALUE NAMES (mapped by string).

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_narf_decor.gd`. These step `_process` by hand (no awaits) for determinism — home is set explicitly because `_ready` captured position before we moved it:

```gdscript
func _stepper(b: NarfDecor.Behavior, home: Vector2) -> NarfDecor:
	var d := NarfDecor.new()
	d.behavior = b
	d.speed = 1.0
	d.travel = 100.0
	add_child_autofree(d)
	d.position = home
	d._home_pos = home
	return d


func test_drift_horizontal_pingpongs_in_range() -> void:
	var d := _stepper(NarfDecor.Behavior.DRIFT, Vector2(500, 300))
	d.axis = NarfDecor.DriftAxis.HORIZONTAL
	var max_dx := 0.0
	var y_moved := false
	for i in 200:
		d._process(1.0 / 60.0)
		max_dx = maxf(max_dx, absf(d.position.x - 500.0))
		y_moved = y_moved or not is_equal_approx(d.position.y, 300.0)
	assert_between(max_dx, 50.0, 100.5, "roams its range, never past it")
	assert_false(y_moved, "horizontal drift leaves y alone")


func test_drift_vertical_pingpongs_in_range() -> void:
	var d := _stepper(NarfDecor.Behavior.DRIFT, Vector2(500, 300))
	d.axis = NarfDecor.DriftAxis.VERTICAL
	var max_dy := 0.0
	var x_moved := false
	for i in 200:
		d._process(1.0 / 60.0)
		max_dy = maxf(max_dy, absf(d.position.y - 300.0))
		x_moved = x_moved or not is_equal_approx(d.position.x, 500.0)
	assert_between(max_dy, 50.0, 100.5, "roams its range, never past it")
	assert_false(x_moved, "vertical drift leaves x alone")


func test_wander_never_escapes_the_roam_circle() -> void:
	var d := _stepper(NarfDecor.Behavior.WANDER, Vector2(400, 400))
	d.speed = 2.0
	d._rng.seed = 12345
	var worst := 0.0
	for i in 600:
		d._process(1.0 / 60.0)
		worst = maxf(worst, d.position.distance_to(Vector2(400, 400)))
	assert_between(worst, 1.0, 100.5, "actually roams, but stays inside travel radius")


func test_wander_flies_nose_first_and_lands_level() -> void:
	var d := _stepper(NarfDecor.Behavior.WANDER, Vector2(400, 400))
	d.speed = 2.0
	d.tilt = 10.0
	d._rng.seed = 777
	var tilt_ok := true
	var checked_hops := 0
	for i in 600:
		d._process(1.0 / 60.0)
		var off := absf(angle_difference(d.rotation, d._home_rotation))
		tilt_ok = tilt_ok and off <= deg_to_rad(10.0) + 0.001
		if d._hop_active:
			assert_eq(d.flip_h, d._hop_target.x < d._hop_start.x, "faces its heading")
		else:
			checked_hops += 1
			assert_almost_eq(angle_difference(d.rotation, d._home_rotation), 0.0, 0.001, "level at rest")
	assert_true(tilt_ok, "banking never exceeds the tilt dial")
	assert_gt(checked_hops, 0, "at least one hop completed during the test")
```

Note: `assert_eq(d.flip_h, ...)` runs many times — that's fine, each iteration is a real check of the same invariant.

- [ ] **Step 2: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_narf_decor.gd -gexit`
Expected: FAIL — parse errors on `Behavior.DRIFT` / `DriftAxis` (they don't exist yet).

- [ ] **Step 3: Implement in `addons/narfkit/narf_decor.gd`**

Full new content of the changed regions:

```gdscript
enum Behavior { NONE, SPIN, SWAY, BOB, DRIFT, WANDER }
enum DriftAxis { HORIZONTAL, VERTICAL }
```

New exports after `movement`:

```gdscript
## DRIFT: which way the piece slides.
@export var axis := DriftAxis.HORIZONTAL
## DRIFT: max distance either side of placement. WANDER: roam radius. Pixels.
@export_range(0.0, 2000.0, 1.0) var travel := 120.0
## WANDER: peak banking angle while flying, in degrees. Level at rest.
@export_range(0.0, 45.0, 0.5) var tilt := 8.0
```

Replace the `_home_y` internals block with:

```gdscript
var _t := 0.0
var _home_rotation := 0.0
var _home_pos := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
# WANDER hop state — glide from _hop_start to _hop_target as _hop_p runs 0..1.
var _hop_start := Vector2.ZERO
var _hop_target := Vector2.ZERO
var _hop_p := 0.0
var _hop_active := false


func _ready() -> void:
	_apply_pivot()
	_home_rotation = rotation
	_home_pos = position
```

`_process` gains two branches (and BOB switches to `_home_pos.y`):

```gdscript
		Behavior.BOB:
			position.y = _home_pos.y + movement * sin(_t * speed * TAU)
		Behavior.DRIFT:
			var axis_vec := Vector2.RIGHT if axis == DriftAxis.HORIZONTAL else Vector2.DOWN
			position = _home_pos + axis_vec * travel * sin(_t * speed * TAU)
		Behavior.WANDER:
			_wander(delta)
```

New function at the end (before `_apply_pivot`):

```gdscript
# Butterfly logic: pick a uniform random point inside the roam circle,
# smoothstep-glide to it over 1/speed seconds, repeat. Flips to fly
# nose-first (art assumed to face right — flip the PNG if it doesn't)
# and banks into the turn, always level at each endpoint.
func _wander(delta: float) -> void:
	if not _hop_active:
		_hop_start = position
		var r := travel * sqrt(_rng.randf())
		_hop_target = _home_pos + Vector2.from_angle(_rng.randf() * TAU) * r
		_hop_p = 0.0
		_hop_active = true
		flip_h = _hop_target.x < _hop_start.x
	_hop_p = minf(_hop_p + delta * maxf(speed, 0.01), 1.0)
	var q := _hop_p * _hop_p * (3.0 - 2.0 * _hop_p)
	position = _hop_start.lerp(_hop_target, q)
	var hsign := -1.0 if flip_h else 1.0
	rotation = _home_rotation + hsign * deg_to_rad(tilt) * sin(_hop_p * PI)
	if _hop_p >= 1.0:
		_hop_active = false
```

Also update the top doc comment's verb list to mention DRIFT and WANDER, matching the file's voice.

- [ ] **Step 4: README**

In `addons/narfkit/README.md`, in the NarfDecor section: rename amplitude→movement where mentioned, and add DRIFT (axis + travel dials, ± sine glide from placement) and WANDER (travel = roam radius, tilt = banking degrees, flips to face travel) in the same style as the existing verb docs.

- [ ] **Step 5: Run the full suite**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: all passing (251 total: 247 + 4 new).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: NarfDecor learns DRIFT (axis ping-pong) and WANDER (roam circle + banking)"
```

---

### Task 3: JSON pipeline — validate, build, clamp

**Files:**
- Modify: `src/level/level_json.gd:180-184` (overlay dial validation)
- Modify: `src/level/scenery_builder.gd:43-58` (axis mapping + new clamps)
- Modify: `src/level/level_layout.gd:22` (doc comment)
- Test: `tests/unit/test_scenery_format.gd` (validation), `tests/unit/test_scenery_builder.gd` (mapping/clamps/skip)

**Interfaces:**
- Consumes: `NarfDecor.DriftAxis` keys, `piece.axis/travel/tilt` from Task 2.
- Produces: overlay JSON accepts optional `"axis"` (String), `"travel"`, `"tilt"` (numbers) — Task 4 writes these keys from the inspector.

- [ ] **Step 1: Write the failing tests**

In `tests/unit/test_scenery_format.gd`, find `test_wrong_typed_dials_rejected` (line ~87) and mirror its structure — it builds a minimal valid layout dict and flips one dial to a wrong type, expecting a "bad overlay" verdict from validation. Add, using the SAME helper/scaffold that test uses:

```gdscript
func test_wrong_typed_drift_dials_rejected() -> void:
	# Same scaffold as test_wrong_typed_dials_rejected, one field at a time:
	# axis must be String; travel and tilt must be numbers.
	# axis = 7 -> "bad overlay"
	# travel = "far" -> "bad overlay"
	# tilt = [] -> "bad overlay"
	# and a fully-typed entry (axis="VERTICAL", travel=300.0, tilt=12.0) -> "" (valid)
```

(Write it as real code copying the sibling test's dict-building calls — read that test first; it is the template.)

In `tests/unit/test_scenery_builder.gd`, mirror the existing spawn tests' scaffold (they build a LevelLayout with an images dict + overlays array and call `SceneryBuilder.spawn`):

```gdscript
func test_drift_fields_map_and_clamp() -> void:
	# overlay: behavior "DRIFT", axis "VERTICAL", travel 9999.0, tilt 99.0
	# expect: piece.behavior == NarfDecor.Behavior.DRIFT
	#         piece.axis == NarfDecor.DriftAxis.VERTICAL
	#         piece.travel == 2000.0  (clamped)
	#         piece.tilt == 45.0      (clamped)


func test_drift_fields_default_when_absent() -> void:
	# overlay with behavior "WANDER" and NO axis/travel/tilt keys
	# expect: axis HORIZONTAL, travel 120.0, tilt 8.0


func test_unknown_axis_name_skips_entry_with_warning() -> void:
	# overlay with axis "DIAGONAL" -> spawn returns 0 pieces for it
	# (same warning+skip pattern as unknown behavior/pivot tests in this file)
```

(Again: real code, copied from this file's existing scaffolds.)

- [ ] **Step 2: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_scenery_format.gd -gtest=res://tests/unit/test_scenery_builder.gd -gexit`
Expected: new tests FAIL (validation accepts wrong types; builder lacks the properties' mapping).

- [ ] **Step 3: Implement validation**

In `src/level/level_json.gd`, directly after the existing `_sp`/`_am` type check (line ~184), same style:

```gdscript
		var _ax: Variant = (_entry as Dictionary).get("axis", "HORIZONTAL")
		if not _ax is String:
			return "bad overlay"
		var _tr: Variant = (_entry as Dictionary).get("travel", 0.0)
		var _ti: Variant = (_entry as Dictionary).get("tilt", 0.0)
		if not (_tr is float or _tr is int) or not (_ti is float or _ti is int):
			return "bad overlay"
```

- [ ] **Step 4: Implement builder mapping**

In `src/level/scenery_builder.gd`, after the pivot mapping block (line ~48), add:

```gdscript
		# Map axis name; unknown name → warning and skip entry.
		var axis_keys := NarfDecor.DriftAxis.keys()
		var axis_name: String = entry.get("axis", "HORIZONTAL")
		var axis_idx: int = axis_keys.find(axis_name)
		if axis_idx == -1:
			push_warning("SceneryBuilder: unknown axis '%s' — skipping overlay" % axis_name)
			continue
```

and after the `piece.movement` line:

```gdscript
		piece.axis = axis_idx as NarfDecor.DriftAxis
		piece.travel = clampf(float(entry.get("travel", 120.0)), 0.0, 2000.0)
		piece.tilt = clampf(float(entry.get("tilt", 8.0)), 0.0, 45.0)
```

Update `src/level/level_layout.gd:22` doc comment to:

```gdscript
# Scenery placements: {image, x, y, behavior?, pivot?, speed?, amplitude?, axis?, travel?, tilt?}
```

- [ ] **Step 5: Run the full suite**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: all passing (255 total: 251 + 4 new).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: level JSON carries optional axis/travel/tilt overlay dials"
```

---

### Task 4: Editor piece inspector — new verbs + dials

**Files:**
- Modify: `src/editor/piece_inspector.gd`
- Modify: `scenes/editor_piece_inspector.tscn`
- Test: `tests/unit/test_scenery_mode.gd`

**Interfaces:**
- Consumes: enum names from Task 2; overlay keys `"axis"`, `"travel"`, `"tilt"` (validated in Task 3).
- Produces: `PieceInspector.set_axis_by_name(name: String)`, `set_travel(v: float)`, `set_tilt(v: float)` — setter API in the file's existing style (dict is source of truth, guarded UI sync).

- [ ] **Step 1: Write the failing tests**

In `tests/unit/test_scenery_mode.gd`, find the existing PieceInspector tests (they instantiate `res://scenes/editor_piece_inspector.tscn`, call `open(overlay, piece)`, then drive setters and assert the overlay dict). Add, using the same scaffold:

```gdscript
func test_inspector_offers_all_six_behaviors() -> void:
	# after _ready: inspector's %BehaviorOption.item_count == 6
	# and get_item_text(4) == "DRIFT", get_item_text(5) == "WANDER"


func test_axis_setter_writes_dict_and_radio_buttons() -> void:
	# open() with empty-ish overlay; set_axis_by_name("VERTICAL")
	# expect overlay["axis"] == "VERTICAL", piece.axis == NarfDecor.DriftAxis.VERTICAL,
	# %AxisV.button_pressed == true and %AxisH.button_pressed == false


func test_travel_and_tilt_setters_write_dict_and_piece() -> void:
	# set_travel(640.0) -> overlay["travel"] == 640.0, piece.travel == 640.0,
	#   %TravelSlider.value == 640.0
	# set_tilt(20.0) -> overlay["tilt"] == 20.0, piece.tilt == 20.0,
	#   %TiltSlider.value == 20.0


func test_open_prepopulates_drift_dials() -> void:
	# open() with overlay {"axis": "VERTICAL", "travel": 500.0, "tilt": 30.0}
	# expect %AxisV pressed, %TravelSlider.value == 500.0, %TiltSlider.value == 30.0
	# open() with overlay missing those keys -> %AxisH pressed, 120.0, 8.0
```

(Real code — copy the instantiation/open scaffold from this file's existing inspector tests.)

- [ ] **Step 2: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_scenery_mode.gd -gexit`
Expected: FAIL — item_count is 4; `%AxisH` etc. don't exist.

- [ ] **Step 3: Scene additions**

In `scenes/editor_piece_inspector.tscn`:
1. Change the root's `offset_top = 560.0` to `offset_top = 380.0` (the panel grows ~180px taller; keeps its bottom on a 1080 screen).
2. Append after the `AmplitudeSlider` node:

```
[node name="Separator4" type="HSeparator" parent="Box"]

[node name="AxisLabel" type="Label" parent="Box"]
theme_override_font_sizes/font_size = 13
text = "Axis:"

[node name="AxisRow" type="HBoxContainer" parent="Box"]

[node name="AxisH" type="Button" parent="Box/AxisRow"]
unique_name_in_owner = true
custom_minimum_size = Vector2(130, 28)
theme_override_font_sizes/font_size = 12
text = "H"
toggle_mode = true
button_pressed = true

[node name="AxisV" type="Button" parent="Box/AxisRow"]
unique_name_in_owner = true
custom_minimum_size = Vector2(130, 28)
theme_override_font_sizes/font_size = 12
text = "V"
toggle_mode = true

[node name="Separator5" type="HSeparator" parent="Box"]

[node name="TravelLabel" type="Label" parent="Box"]
theme_override_font_sizes/font_size = 13
text = "Travel:"

[node name="TravelSlider" type="HSlider" parent="Box"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 28)
min_value = 0.0
max_value = 2000.0
step = 1.0
value = 120.0

[node name="Separator6" type="HSeparator" parent="Box"]

[node name="TiltLabel" type="Label" parent="Box"]
theme_override_font_sizes/font_size = 13
text = "Tilt:"

[node name="TiltSlider" type="HSlider" parent="Box"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 28)
min_value = 0.0
max_value = 45.0
step = 0.5
value = 8.0
```

- [ ] **Step 4: Script additions in `src/editor/piece_inspector.gd`**

Const: `const BEHAVIOR_NAMES := ["NONE", "SPIN", "SWAY", "BOB", "DRIFT", "WANDER"]` (comment above it: indices 0-5). Const below it: `const AXIS_NAMES := ["HORIZONTAL", "VERTICAL"]`.

Node refs (with the others):

```gdscript
var _axis_h: Button
var _axis_v: Button
var _travel_slider: HSlider
var _tilt_slider: HSlider
```

In `_ready()` after the amplitude wiring:

```gdscript
	_axis_h = %AxisH
	_axis_v = %AxisV
	_travel_slider = %TravelSlider
	_tilt_slider = %TiltSlider
	_axis_h.toggled.connect(func(pressed: bool) -> void:
		if pressed and not _updating:
			set_axis_by_name("HORIZONTAL")
	)
	_axis_v.toggled.connect(func(pressed: bool) -> void:
		if pressed and not _updating:
			set_axis_by_name("VERTICAL")
	)
	_travel_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			set_travel(v)
	)
	_tilt_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			set_tilt(v)
	)
```

In `open()` after the amplitude pre-populate:

```gdscript
	# --- Pre-populate drift dials ---
	_press_axis(String(overlay.get("axis", "HORIZONTAL")))
	_travel_slider.value = float(overlay.get("travel", 120.0))
	_tilt_slider.value = float(overlay.get("tilt", 8.0))
```

Setters, in the file's exact style:

```gdscript
func set_axis_by_name(name: String) -> void:
	if _overlay.is_empty():
		return
	if not name in AXIS_NAMES:
		return
	_overlay["axis"] = name
	if is_instance_valid(_piece):
		_piece.axis = AXIS_NAMES.find(name) as NarfDecor.DriftAxis
	_press_axis(name)


func set_travel(v: float) -> void:
	if _overlay.is_empty():
		return
	_overlay["travel"] = v
	if is_instance_valid(_piece):
		_piece.travel = v
	if not is_equal_approx(_travel_slider.value, v):
		_updating = true
		_travel_slider.value = v
		_updating = false


func set_tilt(v: float) -> void:
	if _overlay.is_empty():
		return
	_overlay["tilt"] = v
	if is_instance_valid(_piece):
		_piece.tilt = v
	if not is_equal_approx(_tilt_slider.value, v):
		_updating = true
		_tilt_slider.value = v
		_updating = false
```

Helper (next to `_press_pivot_button`):

```gdscript
# Radio-press the axis pair. Sets _updating to suppress re-entrant toggles.
func _press_axis(name: String) -> void:
	_updating = true
	_axis_h.button_pressed = name == "HORIZONTAL"
	_axis_v.button_pressed = name != "HORIZONTAL"
	_updating = false
```

- [ ] **Step 5: Run the full suite**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: all passing (259 total: 255 + 4 new).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: editor inspector offers DRIFT/WANDER with axis, travel, and tilt dials"
```
