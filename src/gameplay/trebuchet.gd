class_name Trebuchet
extends Node2D

signal fired(velocity: Vector2)

const AIM_MIN_DEG := 20.0
const AIM_MAX_DEG := 80.0
const AIM_SPEED_DEG := 30.0

@export var arm_swing_degrees := 75.0  # negative to swing the other way

var aim_angle_deg := 45.0
var charge := 0.0
var _charging := false

func _process(_delta: float) -> void:
	if has_node("AimIndicator"):
		var indicator: Line2D = $AimIndicator
		indicator.rotation = -deg_to_rad(aim_angle_deg)
		var pt: Vector2 = indicator.points[1]
		pt.x = 90.0 + charge * 60.0
		indicator.set_point_position(1, pt)

func process_aim(delta: float) -> void:
	var dir := Input.get_axis("aim_left", "aim_right")
	aim_angle_deg = clampf(aim_angle_deg - dir * AIM_SPEED_DEG * delta,
		AIM_MIN_DEG, AIM_MAX_DEG)
	if Input.is_action_pressed("fire"):
		if not _charging:
			_play_if_present("crank")
		_charging = true
		var t: float = Settings.preset.charge_time if Settings.preset else 1.5
		charge = minf(1.0, charge + delta / t)
	elif _charging:
		_fire()

# Owner-authored animations are optional: the game runs without them
# and picks them up the moment they exist on our own AnimationPlayer.
func _play_if_present(anim: String) -> void:
	if has_node("AnimationPlayer"):
		var player: AnimationPlayer = $AnimationPlayer
		if player.has_animation(anim):
			player.play(anim)

func _fire() -> void:
	_charging = false
	var p := Settings.preset
	var v := launch_velocity(aim_angle_deg, charge,
		p.min_launch_speed if p else 400.0, p.max_launch_speed if p else 1400.0)
	var kick := 10.0 + 12.0 * charge
	charge = 0.0
	if has_node("AnimationPlayer") and $AnimationPlayer.is_playing():
		$AnimationPlayer.stop()
	if has_node("Soldier/AnimationPlayer"):
		$Soldier/AnimationPlayer.play("fire")
	_swing_arm()
	_recoil(kick)
	fired.emit(v)

# The throwing arm snaps from cocked to thrown, then eases back.
func _swing_arm() -> void:
	if not has_node("Body/Arm"):
		return
	var arm: Sprite2D = $Body/Arm
	var rest := arm.rotation
	var tw := create_tween()
	tw.tween_property(arm, "rotation", rest + deg_to_rad(arm_swing_degrees), 0.1) \
		.set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.15)
	tw.tween_property(arm, "rotation", rest, 0.6) \
		.set_ease(Tween.EASE_IN_OUT)

# The catapult lurches back on its wheels, then wobbles home.
func _recoil(kick: float) -> void:
	if not has_node("Body"):
		return
	var body: Sprite2D = $Body
	var home := body.position.x
	var tw := create_tween()
	tw.tween_property(body, "position:x", home - kick, 0.07) \
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "position:x", home, 0.55) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

static func launch_velocity(angle_deg: float, charge_amount: float,
		min_speed: float, max_speed: float) -> Vector2:
	var speed := lerpf(min_speed, max_speed, clampf(charge_amount, 0.0, 1.0))
	var rad := deg_to_rad(angle_deg)
	return Vector2(cos(rad), -sin(rad)) * speed
