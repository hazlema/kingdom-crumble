class_name Crate
extends RigidBody2D

const STANDING_MAX_DEG := 45.0

# Post-impact settle feel: higher = crates calm down faster after a
# hit, lower = they slosh and rock longer. Bounce stays the per-tier
# gameplay dial (resources/difficulty/*.tres).
const LINEAR_DAMP := 0.7
const ANGULAR_DAMP := 6.0
# Restitution is speed-gated: below MIN a touch is inert (a slow
# boulder kissing the tower must not detonate it), above MAX the full
# per-tier bounce applies. Linear ramp in between.
const BOUNCE_MIN_SPEED := 60.0
const BOUNCE_MAX_SPEED := 240.0

var type_id := "crate-wood"

var _full_bounce := 0.5
var _mat := PhysicsMaterial.new()

func _ready() -> void:
	_full_bounce = Settings.preset.crate_natural_bounce if Settings.preset else 0.5
	_mat.bounce = 0.0
	physics_material_override = _mat
	linear_damp = LINEAR_DAMP
	angular_damp = ANGULAR_DAMP

func _physics_process(_delta: float) -> void:
	if sleeping:
		return
	var ramp := clampf((linear_velocity.length() - BOUNCE_MIN_SPEED) \
		/ (BOUNCE_MAX_SPEED - BOUNCE_MIN_SPEED), 0.0, 1.0)
	_mat.bounce = _full_bounce * ramp

func is_standing() -> bool:
	return is_standing_rotation(rotation)

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
