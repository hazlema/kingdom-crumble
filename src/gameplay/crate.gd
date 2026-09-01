class_name Crate
extends RigidBody2D

signal knocked_out(crate: Crate)

const STANDING_MAX_DEG := 45.0

# Post-impact settle feel: higher = crates calm down faster after a
# hit, lower = they slosh and rock longer. Bounce stays the per-tier
# gameplay dial (resources/difficulty/*.tres).
const LINEAR_DAMP := 0.7
# const ANGULAR_DAMP := 6.0
const ANGULAR_DAMP := 2.0
# Restitution is speed-gated: below MIN a touch is inert (a slow
# boulder kissing the tower must not detonate it), above MAX the full
# per-tier bounce applies. Linear ramp in between.
const BOUNCE_MIN_SPEED := 60.0
const BOUNCE_MAX_SPEED := 240.0
# A crate also counts as knocked out when shoved this far off its spawn
# spot — bottom-row crates slide upright along the ground and can never
# tip past 45 degrees.
const KNOCKED_OUT_DISTANCE := 48.0

var type_id := "crate-wood"
var home := Vector2.ZERO  # spawn position, captured in _ready

var _knock_reported := false

var _full_bounce := 0.5
var _mat := PhysicsMaterial.new()


func _ready() -> void:
	home = global_position
	_full_bounce = Settings.preset.crate_natural_bounce if Settings.preset else 0.5
	_mat.bounce = 0.0
	physics_material_override = _mat
	var p := Settings.preset
	linear_damp = p.crate_linear_damp if p and p.crate_linear_damp >= 0.0 else LINEAR_DAMP
	angular_damp = p.crate_angular_damp if p and p.crate_angular_damp >= 0.0 else ANGULAR_DAMP


func _physics_process(_delta: float) -> void:
	if not _knock_reported and not freeze and not is_standing():
		_knock_reported = true
		knocked_out.emit(self)
	if sleeping:
		return
	var ramp := clampf(
		(linear_velocity.length() - BOUNCE_MIN_SPEED) / (BOUNCE_MAX_SPEED - BOUNCE_MIN_SPEED),
		0.0,
		1.0
	)
	_mat.bounce = _full_bounce * ramp


func is_standing() -> bool:
	return (
		is_standing_rotation(rotation) and global_position.distance_to(home) < KNOCKED_OUT_DISTANCE
	)


static func is_standing_rotation(rotation_rad: float) -> bool:
	var tilt := absf(rad_to_deg(wrapf(rotation_rad, -PI, PI)))
	return tilt < STANDING_MAX_DEG


func apply_type(id: String, tex: Texture2D) -> void:
	type_id = id
	if tex == null:
		return
	if has_node("Skin"):
		$Skin.visible = true
		$Skin.texture = tex
	if has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.visible = false
