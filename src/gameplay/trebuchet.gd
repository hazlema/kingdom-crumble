class_name Trebuchet
extends Node2D

signal fired(velocity: Vector2)

const AIM_MIN_DEG := 20.0
const AIM_MAX_DEG := 80.0
const AIM_SPEED_DEG := 30.0

var aim_angle_deg := 45.0
var charge := 0.0
var _charging := false

func _process(_delta: float) -> void:
	if has_node("AimIndicator"):
		var indicator := $AimIndicator
		indicator.rotation = -deg_to_rad(aim_angle_deg)
		var pt := indicator.points[1]
		pt.x = 90.0 + charge * 60.0
		indicator.set_point_position(1, pt)

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
