# src/level/level.gd
class_name Level
extends Node2D

enum State { AIMING, FLIGHT, RESOLVING, CLEARED, FAILED }

const STONE_SCENE := preload("res://scenes/stone.tscn")
const DEFAULT_LAYOUT := "res://levels/demo.json"
const RESOLVE_MIN := 1.5
const RESOLVE_MAX := 6.0

# Set this before changing to the level scene to play any layout —
# built-in, or a player-made file from user://levels/.
static var next_layout_path := ""

var layout: LevelLayout
var state := State.AIMING
var shots_left := 0
var _resolve_clock := 0.0
var _ledger := LeanLedger.new()
var _active_stone: Stone
var _backdrop := BackdropMode.new()
var _checking := false

@onready var trebuchet: Trebuchet = $Trebuchet
@onready var cam: CameraDirector = $CameraDirector
@onready var hud: Hud = $Hud

func _ready() -> void:
	if Settings.preset == null:
		Settings.load_tier("chill")
	var path := next_layout_path if next_layout_path != "" else DEFAULT_LAYOUT
	layout = LevelStore.load_level(path)
	if layout == null:
		layout = LevelStore.load_level(DEFAULT_LAYOUT)
	_spawn_crates()
	shots_left = layout.shots if layout.shots > 0 \
		else Settings.preset.shots_per_level
	hud.set_shots(shots_left)
	Music.play_tier(Settings.tier)
	trebuchet.fired.connect(_on_fired)
	hud.menu_pressed.connect(func() -> void:
		if has_node("PauseMenu"):
			$PauseMenu.open())
	if has_node("PauseMenu"):
		$PauseMenu.restart_requested.connect(
			func() -> void: get_tree().reload_current_scene())
		$PauseMenu.quit_requested.connect(
			func() -> void: get_tree().change_scene_to_file(
				"res://scenes/main_menu.tscn"))

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("backdrop_toggle"):
		_apply_backdrop_alpha(_backdrop.toggle())
	_update_crate_check()
	match state:
		State.AIMING:
			trebuchet.process_aim(delta)
			hud.set_power(trebuchet.charge)
			if Input.get_axis("scout_left", "scout_right") != 0.0:
				cam.set_mode(CameraDirector.next_mode(cam.mode, "scout_input"))
			elif Input.get_axis("aim_left", "aim_right") != 0.0 \
					or Input.is_action_pressed("fire"):
				cam.set_mode(CameraDirector.next_mode(cam.mode, "aim_input"))
		State.FLIGHT:
			_resolve_clock += delta
			if _resolve_clock > RESOLVE_MIN and (_all_sleeping() or _resolve_clock > RESOLVE_MAX):
				_settle()
		State.RESOLVING:
			pass
		State.CLEARED, State.FAILED:
			if Input.is_action_just_pressed("advance"):
				get_tree().reload_current_scene()

func _spawn_crates() -> void:
	LevelBuilder.spawn_crates(self, layout, false, _crate_texture)

# Task 4 swaps this to the EditorAssets registry lookup.
func _crate_texture(_id: String) -> Texture2D:
	return null

func _on_fired(velocity: Vector2) -> void:
	shots_left -= 1
	hud.set_shots(shots_left)
	hud.set_power(0.0)
	var stone: Stone = STONE_SCENE.instantiate()
	add_child(stone)
	stone.launch(trebuchet.get_node("LaunchPoint").global_position, velocity)
	if trebuchet.loaded_texture and stone.has_node("Visual"):
		stone.get_node("Visual").texture = trebuchet.loaded_texture
	_active_stone = stone
	cam.follow_target = stone
	cam.set_mode(CameraDirector.next_mode(cam.mode, "fired"))
	_resolve_clock = 0.0
	state = State.FLIGHT

func _settle() -> void:
	state = State.RESOLVING
	await _award_leans()
	cam.set_mode(CameraDirector.next_mode(cam.mode, "settled"))
	var standing := count_standing(_crates())
	if standing == 0:
		state = State.CLEARED
		hud.banner("KINGDOM CRUMBLED!", "press ENTER to play again")
	elif shots_left <= 0:
		state = State.FAILED
		hud.banner("OUT OF STONES", "press ENTER to retry")
	else:
		trebuchet.recock()  # ammo remains: reset the arm and reload
		state = State.AIMING

func _award_leans() -> void:
	for crate in _crates():
		if not Lean.is_lean_angle(crate.rotation):
			continue
		var bodies: Array = crate.get_colliding_bodies()
		for i in bodies.size():
			var other: Node = bodies[i]
			if other is Crate and _ledger.claim(crate.get_instance_id(), other.get_instance_id()):
				hud.banner("LEAN BONUS!", "")
				await get_tree().create_timer(1.2).timeout
				hud.clear_banner()

# Hold H: standing crates glow green, fallen ones red — what's left
# to hit at a glance. Preserves backdrop-mode alpha.
func _update_crate_check() -> void:
	var want := Input.is_action_pressed("check")
	if want == _checking:
		return
	_checking = want
	for crate in _crates():
		var a: float = crate.modulate.a
		var c := Color.WHITE
		if _checking:
			c = Color(0.55, 1.0, 0.55) if crate.is_standing() else Color(1.0, 0.45, 0.45)
		c.a = a
		crate.modulate = c

func _apply_backdrop_alpha(alpha: float) -> void:
	var targets: Array = [trebuchet]
	targets.append_array(_crates())
	if is_instance_valid(_active_stone):
		targets.append(_active_stone)
	var tween := create_tween().set_parallel(true)
	for target in targets:
		tween.tween_property(target, "modulate:a", alpha, 0.25)

func _crates() -> Array:
	return get_tree().get_nodes_in_group("crates")

func _stone_is_done() -> bool:
	if not is_instance_valid(_active_stone):
		return true
	if _active_stone.global_position.y > 2000.0:
		return true
	return _active_stone.sleeping

func _all_sleeping() -> bool:
	if not _stone_is_done():
		return false
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
