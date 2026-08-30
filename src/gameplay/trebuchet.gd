class_name Trebuchet
extends Node2D

signal fired(velocity: Vector2)

const AIM_MIN_DEG := 20.0
const AIM_MAX_DEG := 80.0
const AIM_SPEED_DEG := 30.0

@export var arm_swing_degrees := 75.0  # negative to swing the other way

var aim_angle_deg := 45.0
var charge := 0.0
var loaded_texture: Texture2D
var _charging := false
var _arm_rest := 0.0

# Distance from the arm's pivot boss to the cup center, in arm-canvas
# pixels (measured on frame0 during registration).
const CUP_OFFSET_PX := 333.0

func _ready() -> void:
	if has_node("Body/Arm"):
		_arm_rest = $Body/Arm.rotation
		# Release happens with the arm vertical: the cup sits one
		# arm-length above the pivot. Seat the launch point and the
		# trajectory preview there, derived from the live rig so
		# editor rearrangements stay honest.
		var body: Sprite2D = $Body
		var apex: Vector2 = body.position \
			+ body.scale * ($Body/Arm.position + Vector2(0, -CUP_OFFSET_PX))
		if has_node("LaunchPoint"):
			$LaunchPoint.position = apex
		if has_node("TrajectoryPreview"):
			$TrajectoryPreview.position = apex
	_load_stone()
	# The soldier returns to his idle bob after any one-shot animation.
	if has_node("Soldier/AnimationPlayer"):
		var sp: AnimationPlayer = $Soldier/AnimationPlayer
		sp.animation_finished.connect(func(_anim: StringName) -> void:
			if sp.has_animation("idle"):
				sp.play("idle"))

# Drop the next stone into the cup; it rides the arm for free.
func _load_stone() -> void:
	if not has_node("Body/Arm/LoadedStone"):
		return
	loaded_texture = Stone.VARIANTS[randi() % Stone.VARIANTS.size()]
	var preview: Sprite2D = $Body/Arm/LoadedStone
	preview.texture = loaded_texture
	preview.visible = true

func _process(_delta: float) -> void:
	if has_node("TrajectoryPreview"):
		var p := Settings.preset
		var tp: TrajectoryPreview = $TrajectoryPreview
		tp.gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
		tp.velocity = launch_velocity(aim_angle_deg, charge,
			p.min_launch_speed if p else 400.0, p.max_launch_speed if p else 1400.0)

func process_aim(delta: float) -> void:
	var dir := Input.get_axis("aim_left", "aim_right")
	aim_angle_deg = clampf(aim_angle_deg - dir * AIM_SPEED_DEG * delta,
		AIM_MIN_DEG, AIM_MAX_DEG)
	if Input.is_action_pressed("fire"):
		if not _charging:
			_play_if_present("crank")
			recock()
			if has_node("TrajectoryPreview"):
				$TrajectoryPreview.visible = true
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
	if has_node("Body/Arm/LoadedStone"):
		$Body/Arm/LoadedStone.visible = false
	if has_node("TrajectoryPreview"):
		$TrajectoryPreview.visible = false
	if has_node("AnimationPlayer") and $AnimationPlayer.is_playing():
		$AnimationPlayer.stop()
	if has_node("Soldier/AnimationPlayer"):
		$Soldier/AnimationPlayer.play("fire")
	_swing_arm()
	_recoil(kick)
	fired.emit(v)

# The throwing arm snaps from cocked to thrown and holds there,
# spent, until the next crank re-cocks it.
func _swing_arm() -> void:
	if not has_node("Body/Arm"):
		return
	var arm: Sprite2D = $Body/Arm
	var tw := create_tween()
	tw.tween_property(arm, "rotation",
		_arm_rest + deg_to_rad(arm_swing_degrees), 0.1) \
		.set_ease(Tween.EASE_OUT)

# Winds the arm back down to its cocked rest pose and loads the next
# stone. Called when cranking starts, and by the level after a shot
# settles with ammo remaining.
func recock() -> void:
	if not has_node("Body/Arm"):
		return
	var arm: Sprite2D = $Body/Arm
	if is_equal_approx(arm.rotation, _arm_rest):
		return
	var tw := create_tween()
	tw.tween_property(arm, "rotation", _arm_rest, 0.5) \
		.set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_load_stone)

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
