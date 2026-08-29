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
var _active_stone: Stone

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
		State.FLIGHT:
			_resolve_clock += delta
			if _resolve_clock > RESOLVE_MIN and (_all_sleeping() or _resolve_clock > RESOLVE_MAX):
				_settle()
		State.RESOLVING:
			pass
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
