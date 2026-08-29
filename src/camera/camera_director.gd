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
