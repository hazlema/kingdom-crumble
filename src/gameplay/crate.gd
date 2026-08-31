class_name Crate
extends RigidBody2D

const STANDING_MAX_DEG := 45.0

# Post-impact settle feel: higher = crates calm down faster after a
# hit, lower = they slosh and rock longer. Bounce stays the per-tier
# gameplay dial (resources/difficulty/*.tres).
const LINEAR_DAMP := 0.3
const ANGULAR_DAMP := 3.0

var type_id := "crate-wood"

func _ready() -> void:
	var mat := PhysicsMaterial.new()
	mat.bounce = Settings.preset.crate_natural_bounce if Settings.preset else 0.5
	physics_material_override = mat
	linear_damp = LINEAR_DAMP
	angular_damp = ANGULAR_DAMP

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
