# Kingdom Crumble First Playable — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One playable level: aim and fire a trebuchet, topple a crate tower, earn lean bonuses, with three camera modes, chill-tier music/difficulty, and placeholder art.

**Architecture:** Small single-purpose GDScript files under `src/`, scenes under `scenes/`, unit-testable logic kept in static/pure functions (launch math, lean rules, camera transitions, standing checks), scene wiring kept thin. Difficulty knobs live in a `DifficultyPreset` Resource loaded into a `Settings` autoload. GUT runs headless for TDD.

**Tech Stack:** Godot 4.6.2 (GL Compatibility renderer), GDScript, GUT 9.x for tests.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64` — alias in every command as `$GODOT`. Every shell block assumes: `export GODOT=/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64` and `cd /home/frosty/Dev/godot/v4.6/Kingdom-Crumble`.
- Renderer stays `gl_compatibility` (web export requirement). Do not touch `[rendering]` in `project.godot`.
- Crates NEVER self-move (spec). No moving platforms, no kinematic crates.
- All tunable gameplay values read from `Settings.preset` (never hardcoded in gameplay scripts).
- GDScript only. No addons besides GUT (dev-only, committed).
- Tasks marked **[OWNER]** are done by the owner in the Godot editor (learning exercise) — Claude implements everything else and must keep the game runnable *without* the owner tasks being done yet.
- Run the full test suite with:
  `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`

---

### Task 1: GUT test harness

**Files:**
- Create: `addons/gut/` (vendored from GitHub release)
- Create: `tests/unit/test_smoke.gd`

**Interfaces:**
- Produces: headless test command used by every later task.

- [ ] **Step 1: Vendor GUT**

```bash
git clone --depth 1 https://github.com/bitwes/Gut.git /tmp/gut-checkout
cp -r /tmp/gut-checkout/addons/gut addons/gut
```

(If the default branch fails against 4.6, use the latest `9.x` release tag instead: `git clone --depth 1 --branch v9.4.0 ...` — pick the newest 9.x.)

- [ ] **Step 2: Write smoke test**

```gdscript
# tests/unit/test_smoke.gd
extends GutTest

func test_math_still_works():
	assert_eq(1 + 1, 2)
```

- [ ] **Step 3: Run headless, verify pass**

Run: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: `1 passed`, exit code 0. (First run may emit import noise — rerun once if it fails on imports.)

- [ ] **Step 4: Commit**

```bash
git add addons/gut tests
git commit -m "test: vendor GUT and add smoke test"
```

---

### Task 2: DifficultyPreset resource + Settings autoload + tier files

**Files:**
- Create: `src/settings/difficulty_preset.gd`
- Create: `src/settings/settings.gd`
- Create: `resources/difficulty/chill.tres`, `resources/difficulty/heartpumper.tres`, `resources/difficulty/hardcore.tres`
- Modify: `project.godot` (autoload section)
- Test: `tests/unit/test_settings.gd`

**Interfaces:**
- Produces: autoload `Settings` with `preset: DifficultyPreset`, `tier: String`, `func load_tier(tier_name: String) -> bool`. Preset fields: `crate_natural_bounce: float`, `impact_force: float`, `shots_per_level: int`, `charge_time: float`, `min_launch_speed: float`, `max_launch_speed: float`.

- [ ] **Step 1: Write failing test**

```gdscript
# tests/unit/test_settings.gd
extends GutTest

func test_load_chill_tier():
	assert_true(Settings.load_tier("chill"))
	assert_eq(Settings.tier, "chill")
	assert_almost_eq(Settings.preset.crate_natural_bounce, 0.6, 0.001)
	assert_almost_eq(Settings.preset.impact_force, 3.0, 0.001)

func test_hardcore_is_stingier_than_chill():
	Settings.load_tier("hardcore")
	var hard := Settings.preset
	Settings.load_tier("chill")
	assert_lt(hard.crate_natural_bounce, Settings.preset.crate_natural_bounce)
	assert_lt(hard.impact_force, Settings.preset.impact_force)

func test_unknown_tier_fails_and_keeps_state():
	Settings.load_tier("chill")
	assert_false(Settings.load_tier("polka"))
	assert_eq(Settings.tier, "chill")
```

- [ ] **Step 2: Run, verify fails** (Settings autoload missing)

- [ ] **Step 3: Implement**

```gdscript
# src/settings/difficulty_preset.gd
class_name DifficultyPreset
extends Resource

@export var crate_natural_bounce := 0.6
@export var impact_force := 3.0
@export var shots_per_level := 5
@export var charge_time := 1.5
@export var min_launch_speed := 400.0
@export var max_launch_speed := 1400.0
```

```gdscript
# src/settings/settings.gd
extends Node

const TIER_DIR := "res://resources/difficulty"

var preset: DifficultyPreset
var tier := ""

func load_tier(tier_name: String) -> bool:
	var path := "%s/%s.tres" % [TIER_DIR, tier_name]
	if not ResourceLoader.exists(path):
		return false
	preset = load(path)
	tier = tier_name
	return true
```

`resources/difficulty/chill.tres`:

```
[gd_resource type="Resource" script_class="DifficultyPreset" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/settings/difficulty_preset.gd" id="1"]

[resource]
script = ExtResource("1")
crate_natural_bounce = 0.6
impact_force = 3.0
shots_per_level = 5
charge_time = 1.5
min_launch_speed = 400.0
max_launch_speed = 1400.0
```

`heartpumper.tres`: same file with `crate_natural_bounce = 0.45`, `impact_force = 2.0`, `shots_per_level = 4`.
`hardcore.tres`: `crate_natural_bounce = 0.3`, `impact_force = 1.0`, `shots_per_level = 3`.

Add to `project.godot` (new section, keep existing sections untouched):

```
[autoload]

Settings="*res://src/settings/settings.gd"
```

- [ ] **Step 4: Run tests, verify pass**
- [ ] **Step 5: Commit** — `feat: difficulty presets as resources with Settings autoload`

---

### Task 3: Input actions autoload

**Files:**
- Create: `src/settings/game_input.gd`
- Modify: `project.godot` (autoload)
- Test: `tests/unit/test_game_input.gd`

**Interfaces:**
- Produces: actions `aim_left`, `aim_right`, `fire`, `advance`, `scout_left`, `scout_right` registered in `InputMap` at startup by autoload `GameInput` (registration in code, not project.godot — readable and testable). Static `func ensure_actions() -> void` (idempotent).

- [ ] **Step 1: Failing test**

```gdscript
# tests/unit/test_game_input.gd
extends GutTest

func test_actions_registered():
	GameInput.ensure_actions()
	for action in ["aim_left", "aim_right", "fire", "advance", "scout_left", "scout_right"]:
		assert_true(InputMap.has_action(action), action)

func test_ensure_actions_is_idempotent():
	GameInput.ensure_actions()
	GameInput.ensure_actions()
	assert_true(InputMap.has_action("fire"))
```

- [ ] **Step 2: Run, verify fails**
- [ ] **Step 3: Implement**

```gdscript
# src/settings/game_input.gd
extends Node

const BINDINGS := {
	"aim_left": [KEY_LEFT, KEY_A],
	"aim_right": [KEY_RIGHT, KEY_D],
	"fire": [KEY_SPACE],
	"advance": [KEY_ENTER],
	"scout_left": [KEY_COMMA, KEY_Q],
	"scout_right": [KEY_PERIOD, KEY_E],
}

func _ready() -> void:
	ensure_actions()

static func ensure_actions() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for keycode in BINDINGS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = keycode
				InputMap.action_add_event(action, ev)
```

Autoload: `GameInput="*res://src/settings/game_input.gd"`

- [ ] **Step 4: Run tests, verify pass**
- [ ] **Step 5: Commit** — `feat: input actions registered in code via GameInput autoload`

---

### Task 4: Music director

**Files:**
- Create: `src/audio/music_director.gd`
- Modify: `project.godot` (autoload `Music`)
- Test: `tests/unit/test_music_director.gd`

**Interfaces:**
- Produces: autoload `Music` with `func play_tier(tier: String) -> void`, `func stop() -> void`; statics `func pick_track(pool: Array, exclude: String = "") -> String` and `func list_pool(tier: String) -> Array` (scans `res://music/<tier>/` for `.ogg`/`.mp3`/`.wav`; empty folder → `[]`, never crashes).

- [ ] **Step 1: Failing test**

```gdscript
# tests/unit/test_music_director.gd
extends GutTest

func test_pick_from_empty_pool_is_empty_string():
	assert_eq(MusicDirector.pick_track([]), "")

func test_pick_avoids_exclude_when_possible():
	for i in 20:
		assert_eq(MusicDirector.pick_track(["a", "b"], "a"), "b")

func test_pick_allows_exclude_when_only_option():
	assert_eq(MusicDirector.pick_track(["a"], "a"), "a")

func test_list_pool_of_empty_tier_dir():
	assert_eq(MusicDirector.list_pool("chill"), [])
```

(Note: `list_pool` test assumes `music/chill/` currently has no audio files; when tracks land, change the assertion to `assert_true(... .size() > 0)`.)

- [ ] **Step 2: Run, verify fails**
- [ ] **Step 3: Implement**

```gdscript
# src/audio/music_director.gd
class_name MusicDirector
extends Node

const EXTENSIONS := ["ogg", "mp3", "wav"]

var _player := AudioStreamPlayer.new()
var _current_track := ""
var _tier := ""

func _ready() -> void:
	_player.bus = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
	add_child(_player)
	_player.finished.connect(_on_track_finished)

func play_tier(tier: String) -> void:
	_tier = tier
	_play_next()

func stop() -> void:
	_tier = ""
	_player.stop()

func _play_next() -> void:
	var pool := list_pool(_tier)
	var track := pick_track(pool, _current_track)
	if track == "":
		return
	_current_track = track
	_player.stream = load(track)
	_player.play()

func _on_track_finished() -> void:
	if _tier != "":
		_play_next()

static func pick_track(pool: Array, exclude: String = "") -> String:
	if pool.is_empty():
		return ""
	var options := pool.filter(func(p): return p != exclude)
	if options.is_empty():
		options = pool
	return options[randi() % options.size()]

static func list_pool(tier: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://music/%s" % tier)
	if dir == null:
		return out
	for file in dir.get_files():
		# exported builds list "track.ogg.remap"; strip and re-check
		var name := file.trim_suffix(".remap")
		if name.get_extension() in EXTENSIONS:
			out.append("res://music/%s/%s" % [tier, name])
	out.sort()
	return out
```

Autoload: `Music="*res://src/audio/music_director.gd"`

- [ ] **Step 4: Run tests, verify pass**
- [ ] **Step 5: Commit** — `feat: music director with per-tier pools`

---

### Task 5: Crate scene + standing logic

**Files:**
- Create: `src/gameplay/crate.gd`, `scenes/crate.tscn`
- Test: `tests/unit/test_crate.gd`

**Interfaces:**
- Produces: `Crate` (RigidBody2D scene, 64×64) with `static func is_standing_rotation(rotation_rad: float) -> bool` (tilt < 45°), `func is_standing() -> bool`, and physics material bounce taken from `Settings.preset.crate_natural_bounce` in `_ready()`. `contact_monitor` on, `max_contacts_reported = 8` (lean detection needs contacts).

- [ ] **Step 1: Failing test**

```gdscript
# tests/unit/test_crate.gd
extends GutTest

func test_upright_is_standing():
	assert_true(Crate.is_standing_rotation(0.0))
	assert_true(Crate.is_standing_rotation(deg_to_rad(30)))
	assert_true(Crate.is_standing_rotation(deg_to_rad(-44)))

func test_tipped_is_not_standing():
	assert_false(Crate.is_standing_rotation(deg_to_rad(46)))
	assert_false(Crate.is_standing_rotation(deg_to_rad(90)))
	assert_false(Crate.is_standing_rotation(deg_to_rad(180)))

func test_full_turn_wraps_to_standing():
	assert_true(Crate.is_standing_rotation(TAU))
```

- [ ] **Step 2: Run, verify fails**
- [ ] **Step 3: Implement**

```gdscript
# src/gameplay/crate.gd
class_name Crate
extends RigidBody2D

const STANDING_MAX_DEG := 45.0

func _ready() -> void:
	var mat := PhysicsMaterial.new()
	mat.bounce = Settings.preset.crate_natural_bounce if Settings.preset else 0.5
	physics_material_override = mat

func is_standing() -> bool:
	return is_standing_rotation(rotation)

static func is_standing_rotation(rotation_rad: float) -> bool:
	var tilt := absf(rad_to_deg(wrapf(rotation_rad, -PI, PI)))
	return tilt < STANDING_MAX_DEG
```

`scenes/crate.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://src/gameplay/crate.gd" id="1"]

[sub_resource type="RectangleShape2D" id="shape"]
size = Vector2(64, 64)

[node name="Crate" type="RigidBody2D"]
mass = 4.0
contact_monitor = true
max_contacts_reported = 8
script = ExtResource("1")

[node name="Shape" type="CollisionShape2D" parent="."]
shape = SubResource("shape")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -32.0
offset_top = -32.0
offset_right = 32.0
offset_bottom = 32.0
color = Color(0.72, 0.5, 0.25, 1)
```

- [ ] **Step 4: Run tests, verify pass**
- [ ] **Step 5: Commit** — `feat: crate body with standing check`

---

### Task 6: Lean rules + once-only ledger

**Files:**
- Create: `src/gameplay/lean.gd`, `src/gameplay/lean_ledger.gd`
- Test: `tests/unit/test_lean.gd`

**Interfaces:**
- Produces: `Lean.is_lean_angle(rotation_rad: float) -> bool` (15°–75° tilt, spec values), `LeanLedger.claim(a_id: int, b_id: int) -> bool` (true first time per unordered pair, false after), `LeanLedger.pair_key(a: int, b: int) -> String`.

- [ ] **Step 1: Failing test**

```gdscript
# tests/unit/test_lean.gd
extends GutTest

func test_lean_band():
	assert_false(Lean.is_lean_angle(deg_to_rad(10)))   # basically upright
	assert_true(Lean.is_lean_angle(deg_to_rad(15)))
	assert_true(Lean.is_lean_angle(deg_to_rad(-40)))
	assert_true(Lean.is_lean_angle(deg_to_rad(75)))
	assert_false(Lean.is_lean_angle(deg_to_rad(80)))   # basically fallen

func test_ledger_pays_once_per_pair_either_order():
	var ledger := LeanLedger.new()
	assert_true(ledger.claim(7, 3))
	assert_false(ledger.claim(3, 7))
	assert_true(ledger.claim(7, 4))

func test_pair_key_is_order_independent():
	assert_eq(LeanLedger.pair_key(9, 2), LeanLedger.pair_key(2, 9))
```

- [ ] **Step 2: Run, verify fails**
- [ ] **Step 3: Implement**

```gdscript
# src/gameplay/lean.gd
class_name Lean
extends RefCounted

const MIN_DEG := 15.0
const MAX_DEG := 75.0

static func is_lean_angle(rotation_rad: float) -> bool:
	var tilt := absf(rad_to_deg(wrapf(rotation_rad, -PI, PI)))
	return tilt >= MIN_DEG and tilt <= MAX_DEG
```

```gdscript
# src/gameplay/lean_ledger.gd
class_name LeanLedger
extends RefCounted

var _paid := {}

static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

func claim(a_id: int, b_id: int) -> bool:
	var key := pair_key(a_id, b_id)
	if _paid.has(key):
		return false
	_paid[key] = true
	return true
```

- [ ] **Step 4: Run tests, verify pass**
- [ ] **Step 5: Commit** — `feat: lean band rules and once-only pair ledger`

---

### Task 7: Stone + trebuchet firing

**Files:**
- Create: `src/gameplay/stone.gd`, `scenes/stone.tscn`
- Create: `src/gameplay/trebuchet.gd`, `scenes/trebuchet.tscn`
- Test: `tests/unit/test_trebuchet.gd`

**Interfaces:**
- Consumes: `Settings.preset.charge_time/min_launch_speed/max_launch_speed/impact_force`.
- Produces: `Trebuchet` node with signal `fired(velocity: Vector2)`, properties `aim_angle_deg: float` (20–80, default 45), `charge: float` (0–1); methods `func process_aim(delta: float) -> void` (reads input), `static func launch_velocity(angle_deg: float, charge: float, min_speed: float, max_speed: float) -> Vector2`. `Stone` (RigidBody2D, `mass` scaled by `impact_force`) with `func launch(from: Vector2, velocity: Vector2) -> void`. Trebuchet plays `$Soldier/AnimationPlayer` animation `"fire"` **iff that node exists** (owner rig contract, Task 11).

- [ ] **Step 1: Failing test**

```gdscript
# tests/unit/test_trebuchet.gd
extends GutTest

func test_launch_velocity_at_zero_charge_uses_min_speed():
	var v := Trebuchet.launch_velocity(45.0, 0.0, 400.0, 1400.0)
	assert_almost_eq(v.length(), 400.0, 0.1)

func test_launch_velocity_at_full_charge_uses_max_speed():
	var v := Trebuchet.launch_velocity(45.0, 1.0, 400.0, 1400.0)
	assert_almost_eq(v.length(), 1400.0, 0.1)

func test_launch_velocity_points_up_and_right():
	var v := Trebuchet.launch_velocity(45.0, 0.5, 400.0, 1400.0)
	assert_gt(v.x, 0.0)
	assert_lt(v.y, 0.0)  # up is -y in Godot

func test_charge_clamps():
	var v := Trebuchet.launch_velocity(45.0, 7.0, 400.0, 1400.0)
	assert_almost_eq(v.length(), 1400.0, 0.1)
```

- [ ] **Step 2: Run, verify fails**
- [ ] **Step 3: Implement**

```gdscript
# src/gameplay/stone.gd
class_name Stone
extends RigidBody2D

func _ready() -> void:
	mass = 2.0 * (Settings.preset.impact_force if Settings.preset else 1.0)

func launch(from: Vector2, velocity: Vector2) -> void:
	global_position = from
	linear_velocity = velocity
```

```gdscript
# src/gameplay/trebuchet.gd
class_name Trebuchet
extends Node2D

signal fired(velocity: Vector2)

const AIM_MIN_DEG := 20.0
const AIM_MAX_DEG := 80.0
const AIM_SPEED_DEG := 30.0

var aim_angle_deg := 45.0
var charge := 0.0
var _charging := false

func process_aim(delta: float) -> void:
	var dir := Input.get_axis("aim_left", "aim_right")
	aim_angle_deg = clampf(aim_angle_deg - dir * AIM_SPEED_DEG * delta,
		AIM_MIN_DEG, AIM_MAX_DEG)
	if Input.is_action_pressed("fire"):
		_charging = true
		var t: float = Settings.preset.charge_time if Settings.preset else 1.5
		charge = minf(1.0, charge + delta / t)
	elif _charging:
		_fire()

func _fire() -> void:
	_charging = false
	var p := Settings.preset
	var v := launch_velocity(aim_angle_deg, charge,
		p.min_launch_speed if p else 400.0, p.max_launch_speed if p else 1400.0)
	charge = 0.0
	if has_node("Soldier/AnimationPlayer"):
		$Soldier/AnimationPlayer.play("fire")
	fired.emit(v)

static func launch_velocity(angle_deg: float, charge_amount: float,
		min_speed: float, max_speed: float) -> Vector2:
	var speed := lerpf(min_speed, max_speed, clampf(charge_amount, 0.0, 1.0))
	var rad := deg_to_rad(angle_deg)
	return Vector2(cos(rad), -sin(rad)) * speed
```

`scenes/stone.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://src/gameplay/stone.gd" id="1"]

[sub_resource type="CircleShape2D" id="shape"]
radius = 14.0

[node name="Stone" type="RigidBody2D"]
script = ExtResource("1")

[node name="Shape" type="CollisionShape2D" parent="."]
shape = SubResource("shape")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -14.0
offset_top = -14.0
offset_right = 14.0
offset_bottom = 14.0
color = Color(0.4, 0.4, 0.42, 1)
```

`scenes/trebuchet.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/gameplay/trebuchet.gd" id="1"]

[node name="Trebuchet" type="Node2D"]
script = ExtResource("1")

[node name="Frame" type="ColorRect" parent="."]
offset_left = -40.0
offset_top = -80.0
offset_right = 40.0
offset_bottom = 0.0
color = Color(0.5, 0.33, 0.16, 1)

[node name="LaunchPoint" type="Marker2D" parent="."]
position = Vector2(0, -90)
```

- [ ] **Step 4: Run tests, verify pass**
- [ ] **Step 5: Commit** — `feat: trebuchet charge/fire and stone projectile`

---

### Task 8: Camera director

**Files:**
- Create: `src/camera/camera_director.gd`
- Test: `tests/unit/test_camera_director.gd`

**Interfaces:**
- Produces: `CameraDirector` (extends Camera2D) with `enum Mode { AIM, FOLLOW, SCOUT }`, `var mode: int`, `var follow_target: Node2D`, `static func next_mode(current: int, event: String) -> int` for events `"fired"`, `"settled"`, `"scout_input"`, `"aim_input"`. Level calls `set_mode(m)`; `_physics_process` handles per-mode position (AIM → home marker, FOLLOW → target, SCOUT → keyboard pan).

- [ ] **Step 1: Failing test**

```gdscript
# tests/unit/test_camera_director.gd
extends GutTest

func test_firing_always_grabs_camera():
	for m in [CameraDirector.Mode.AIM, CameraDirector.Mode.SCOUT]:
		assert_eq(CameraDirector.next_mode(m, "fired"), CameraDirector.Mode.FOLLOW)

func test_settle_returns_home():
	assert_eq(CameraDirector.next_mode(CameraDirector.Mode.FOLLOW, "settled"),
		CameraDirector.Mode.AIM)

func test_scout_only_from_aim():
	assert_eq(CameraDirector.next_mode(CameraDirector.Mode.AIM, "scout_input"),
		CameraDirector.Mode.SCOUT)
	assert_eq(CameraDirector.next_mode(CameraDirector.Mode.FOLLOW, "scout_input"),
		CameraDirector.Mode.FOLLOW)

func test_aim_input_snaps_back_from_scout():
	assert_eq(CameraDirector.next_mode(CameraDirector.Mode.SCOUT, "aim_input"),
		CameraDirector.Mode.AIM)
```

- [ ] **Step 2: Run, verify fails**
- [ ] **Step 3: Implement**

```gdscript
# src/camera/camera_director.gd
class_name CameraDirector
extends Camera2D

enum Mode { AIM, FOLLOW, SCOUT }

const SCOUT_SPEED := 900.0

var mode := Mode.AIM
var follow_target: Node2D
var home_position := Vector2.ZERO

func _ready() -> void:
	home_position = global_position
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0

func set_mode(m: int) -> void:
	mode = m
	if m == Mode.AIM:
		follow_target = null

func _physics_process(delta: float) -> void:
	match mode:
		Mode.AIM:
			global_position = home_position
		Mode.FOLLOW:
			if is_instance_valid(follow_target):
				global_position = follow_target.global_position
		Mode.SCOUT:
			var dir := Input.get_axis("scout_left", "scout_right")
			global_position.x += dir * SCOUT_SPEED * delta

static func next_mode(current: int, event: String) -> int:
	match event:
		"fired":
			return Mode.FOLLOW
		"settled":
			return Mode.AIM if current == Mode.FOLLOW else current
		"scout_input":
			return Mode.SCOUT if current == Mode.AIM else current
		"aim_input":
			return Mode.AIM if current == Mode.SCOUT else current
	return current
```

- [ ] **Step 4: Run tests, verify pass**
- [ ] **Step 5: Commit** — `feat: three-mode camera director`

---

### Task 9: HUD

**Files:**
- Create: `src/ui/hud.gd`, `scenes/hud.tscn`

**Interfaces:**
- Produces: `Hud` (CanvasLayer) with `func set_shots(n: int)`, `func set_power(ratio: float)` (0–1, hides bar at 0), `func banner(title: String, sub: String)`, `func clear_banner()`.

No unit test (pure presentation); verified in Task 10's manual run.

- [ ] **Step 1: Implement**

```gdscript
# src/ui/hud.gd
class_name Hud
extends CanvasLayer

func set_shots(n: int) -> void:
	$Shots.text = "Stones: %d" % n

func set_power(ratio: float) -> void:
	$PowerBack.visible = ratio > 0.0
	$PowerBack/PowerFill.size.x = 300.0 * clampf(ratio, 0.0, 1.0)

func banner(title: String, sub: String) -> void:
	$Banner.text = title
	$BannerSub.text = sub
	$Banner.visible = true
	$BannerSub.visible = true

func clear_banner() -> void:
	$Banner.visible = false
	$BannerSub.visible = false
```

`scenes/hud.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/hud.gd" id="1"]

[node name="Hud" type="CanvasLayer"]
script = ExtResource("1")

[node name="Shots" type="Label" parent="."]
offset_left = 16.0
offset_top = 12.0
offset_right = 240.0
offset_bottom = 40.0
theme_override_font_sizes/font_size = 22
text = "Stones: 0"

[node name="PowerBack" type="ColorRect" parent="."]
visible = false
offset_left = 16.0
offset_top = 48.0
offset_right = 320.0
offset_bottom = 66.0
color = Color(0, 0, 0, 0.4)

[node name="PowerFill" type="ColorRect" parent="PowerBack"]
offset_right = 0.0
offset_bottom = 18.0
color = Color(1, 0.83, 0.29, 1)

[node name="Banner" type="Label" parent="."]
visible = false
anchor_left = 0.0
anchor_right = 1.0
offset_top = 180.0
offset_bottom = 250.0
theme_override_font_sizes/font_size = 52
horizontal_alignment = 1
text = "BANNER"

[node name="BannerSub" type="Label" parent="."]
visible = false
anchor_left = 0.0
anchor_right = 1.0
offset_top = 252.0
offset_bottom = 290.0
theme_override_font_sizes/font_size = 20
horizontal_alignment = 1
text = "sub"
```

- [ ] **Step 2: Commit** — `feat: minimal HUD (shots, power bar, banner)`

---

### Task 10: Level 1 — game flow wiring

**Files:**
- Create: `src/level/level.gd`, `scenes/level_01.tscn`
- Test: `tests/unit/test_level_logic.gd`

**Interfaces:**
- Consumes: everything above, by the exact names in earlier Produces blocks.
- Produces: playable `scenes/level_01.tscn`; `Level.count_standing(crates: Array) -> int` (static, testable); level states `AIMING/FLIGHT/RESOLVING/CLEARED/FAILED`; lean check on settle awards via `LeanLedger` and prints/banners the bonus.

- [ ] **Step 1: Failing test**

```gdscript
# tests/unit/test_level_logic.gd
extends GutTest

func test_count_standing_counts_only_upright():
	var rotations := [0.0, deg_to_rad(30), deg_to_rad(80), deg_to_rad(170)]
	assert_eq(Level.count_standing_rotations(rotations), 2)
```

- [ ] **Step 2: Run, verify fails**
- [ ] **Step 3: Implement**

```gdscript
# src/level/level.gd
class_name Level
extends Node2D

enum State { AIMING, FLIGHT, RESOLVING, CLEARED, FAILED }

const STONE_SCENE := preload("res://scenes/stone.tscn")
const RESOLVE_MIN := 1.5
const RESOLVE_MAX := 6.0

var state := State.AIMING
var shots_left := 0
var _resolve_clock := 0.0
var _ledger := LeanLedger.new()

@onready var trebuchet: Trebuchet = $Trebuchet
@onready var cam: CameraDirector = $CameraDirector
@onready var hud: Hud = $Hud

func _ready() -> void:
	if Settings.preset == null:
		Settings.load_tier("chill")
	shots_left = Settings.preset.shots_per_level
	hud.set_shots(shots_left)
	Music.play_tier(Settings.tier)
	trebuchet.fired.connect(_on_fired)

func _physics_process(delta: float) -> void:
	match state:
		State.AIMING:
			trebuchet.process_aim(delta)
			hud.set_power(trebuchet.charge)
			if Input.get_axis("scout_left", "scout_right") != 0.0:
				cam.set_mode(CameraDirector.next_mode(cam.mode, "scout_input"))
			elif Input.get_axis("aim_left", "aim_right") != 0.0 \
					or Input.is_action_pressed("fire"):
				cam.set_mode(CameraDirector.next_mode(cam.mode, "aim_input"))
		State.FLIGHT, State.RESOLVING:
			_resolve_clock += delta
			if _resolve_clock > RESOLVE_MIN and (_all_sleeping() or _resolve_clock > RESOLVE_MAX):
				_settle()
		State.CLEARED, State.FAILED:
			if Input.is_action_just_pressed("advance"):
				get_tree().reload_current_scene()

func _on_fired(velocity: Vector2) -> void:
	shots_left -= 1
	hud.set_shots(shots_left)
	hud.set_power(0.0)
	var stone: Stone = STONE_SCENE.instantiate()
	add_child(stone)
	stone.launch(trebuchet.get_node("LaunchPoint").global_position, velocity)
	cam.follow_target = stone
	cam.set_mode(CameraDirector.next_mode(cam.mode, "fired"))
	_resolve_clock = 0.0
	state = State.FLIGHT

func _settle() -> void:
	_award_leans()
	cam.set_mode(CameraDirector.next_mode(cam.mode, "settled"))
	var standing := count_standing(_crates())
	if standing == 0:
		state = State.CLEARED
		hud.banner("KINGDOM CRUMBLED!", "press ENTER to play again")
	elif shots_left <= 0:
		state = State.FAILED
		hud.banner("OUT OF STONES", "press ENTER to retry")
	else:
		state = State.AIMING

func _award_leans() -> void:
	for crate in _crates():
		if not Lean.is_lean_angle(crate.rotation):
			continue
		for i in crate.get_colliding_bodies().size():
			var other := crate.get_colliding_bodies()[i]
			if other is Crate and _ledger.claim(crate.get_instance_id(), other.get_instance_id()):
				hud.banner("LEAN BONUS!", "")
				await get_tree().create_timer(1.2).timeout
				if state == State.AIMING or state == State.RESOLVING or state == State.FLIGHT:
					hud.clear_banner()

func _crates() -> Array:
	return get_tree().get_nodes_in_group("crates")

func _all_sleeping() -> bool:
	for crate in _crates():
		if not crate.sleeping:
			return false
	return true

static func count_standing(crates: Array) -> int:
	var rotations := crates.map(func(c): return c.rotation)
	return count_standing_rotations(rotations)

static func count_standing_rotations(rotations: Array) -> int:
	var n := 0
	for r in rotations:
		if Crate.is_standing_rotation(r):
			n += 1
	return n
```

`scenes/level_01.tscn` — ground is a StaticBody2D strip, trebuchet left, 3-crate tower right, camera centered, sky/ground ColorRects as placeholder parallax. Every crate is in group `crates`:

```
[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://src/level/level.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/trebuchet.tscn" id="2"]
[ext_resource type="PackedScene" path="res://scenes/crate.tscn" id="3"]
[ext_resource type="Script" path="res://src/camera/camera_director.gd" id="4"]
[ext_resource type="PackedScene" path="res://scenes/hud.tscn" id="5"]

[sub_resource type="WorldBoundaryShape2D" id="ground_shape"]

[node name="Level" type="Node2D"]
script = ExtResource("1")

[node name="Sky" type="ColorRect" parent="."]
offset_left = -2000.0
offset_top = -1200.0
offset_right = 4000.0
offset_bottom = 600.0
color = Color(0.53, 0.7, 0.9, 1)

[node name="GroundVisual" type="ColorRect" parent="."]
offset_left = -2000.0
offset_top = 600.0
offset_right = 4000.0
offset_bottom = 1200.0
color = Color(0.42, 0.56, 0.3, 1)

[node name="Ground" type="StaticBody2D" parent="."]
position = Vector2(0, 600)

[node name="Shape" type="CollisionShape2D" parent="Ground"]
shape = SubResource("ground_shape")

[node name="Trebuchet" parent="." instance=ExtResource("2")]
position = Vector2(200, 600)

[node name="Crate1" parent="." instance=ExtResource("3")]
position = Vector2(1400, 568)
groups = ["crates"]

[node name="Crate2" parent="." instance=ExtResource("3")]
position = Vector2(1400, 502)
groups = ["crates"]

[node name="Crate3" parent="." instance=ExtResource("3")]
position = Vector2(1400, 436)
groups = ["crates"]

[node name="CameraDirector" type="Camera2D" parent="."]
position = Vector2(800, 400)
script = ExtResource("4")

[node name="Hud" parent="." instance=ExtResource("5")]
```

- [ ] **Step 4: Run tests, verify pass**

- [ ] **Step 5: Manual playtest (owner or Claude via editor run)**

Run: `$GODOT scenes/level_01.tscn`
Verify: arrows aim, hold SPACE charges the bar, release fires; camera chases the stone; tower topples; knock all three over → "KINGDOM CRUMBLED!"; Q/E scouts the level; ENTER restarts after clear/fail.

- [ ] **Step 6: Commit** — `feat: level 1 game flow — aim, fire, resolve, lean bonus, clear/fail`

---

### Task 11: Main menu (music-tier selection) + main scene

**Files:**
- Create: `src/ui/main_menu.gd`, `scenes/main_menu.tscn`
- Modify: `project.godot` (`run/main_scene`)

**Interfaces:**
- Consumes: `Settings.load_tier`, `Music.play_tier`.
- Produces: three buttons — Chill / Heart-Pumper / Hardcore — each calls `Settings.load_tier(tier)` then changes scene to `res://scenes/level_01.tscn`.

- [ ] **Step 1: Implement**

```gdscript
# src/ui/main_menu.gd
extends Control

func _ready() -> void:
	$Buttons/Chill.pressed.connect(_start.bind("chill"))
	$Buttons/HeartPumper.pressed.connect(_start.bind("heartpumper"))
	$Buttons/Hardcore.pressed.connect(_start.bind("hardcore"))

func _start(tier: String) -> void:
	Settings.load_tier(tier)
	get_tree().change_scene_to_file("res://scenes/level_01.tscn")
```

`scenes/main_menu.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/main_menu.gd" id="1"]

[node name="MainMenu" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Title" type="Label" parent="."]
anchor_left = 0.0
anchor_right = 1.0
offset_top = 120.0
offset_bottom = 200.0
theme_override_font_sizes/font_size = 64
horizontal_alignment = 1
text = "KINGDOM CRUMBLE"

[node name="Buttons" type="VBoxContainer" parent="."]
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -140.0
offset_top = -60.0
offset_right = 140.0
offset_bottom = 120.0
theme_override_constants/separation = 16

[node name="Chill" type="Button" parent="Buttons"]
text = "🌿  Chill"

[node name="HeartPumper" type="Button" parent="Buttons"]
text = "🔥  Heart-Pumper"

[node name="Hardcore" type="Button" parent="Buttons"]
text = "💀  Hardcore"
```

Add to `project.godot` `[application]`: `run/main_scene="res://scenes/main_menu.tscn"`

- [ ] **Step 2: Manual verify**

Run: `$GODOT` (project root — runs main scene)
Expected: title + three buttons; each starts level 1 with that tier's preset (hardcore = 3 stones on the HUD, chill = 5).

- [ ] **Step 3: Run full test suite, verify green**
- [ ] **Step 4: Commit** — `feat: music-tier main menu`

---

### Task 12: **[OWNER]** Skeleton2D soldier rig

**Files (owner, in editor):**
- Create: `scenes/soldier.tscn`

**The contract the code relies on (from Task 7):** trebuchet looks for an *optional* child at `Trebuchet/Soldier` with an `AnimationPlayer` containing a `"fire"` animation. Until it exists, the game runs fine without it.

Owner steps (guide, not gospel — this is the learning exercise):
- [ ] Cut `art/characters/soldier-side-parts.png` into per-part PNGs (GIMP/Krita: head, torso, front arm, back arm, boots) → save under `art/characters/soldier_parts/`
- [ ] New scene: root `Node2D` named `Soldier`; add `Skeleton2D` + `Bone2D` chain (hip → torso → head; torso → arm bones); add each part as `Sprite2D`, bind with `RemoteTransform2D` or bone painting
- [ ] Add `AnimationPlayer`; create `"idle"` (subtle bob, loop) and `"fire"` (arm pull + release, ~0.6 s)
- [ ] Save as `scenes/soldier.tscn`; instance it inside `scenes/trebuchet.tscn` as child named `Soldier`, positioned beside the frame
- [ ] Playtest: firing should trigger the animation (code from Task 7 picks it up automatically)
- [ ] Commit: `feat: soldier rig with fire animation`

---

## Verification (after all tasks)

- [ ] Full suite green: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- [ ] Menu → chill → clear the tower → CRUMBLED banner → ENTER replays
- [ ] Hardcore shows 3 stones vs chill's 5 (preset plumbing proven end-to-end)
- [ ] Create a deliberate lean (soft shot into the tower) → LEAN BONUS fires once, not again on the next settle
- [ ] Q/E scouts, touching arrows/space snaps camera home
