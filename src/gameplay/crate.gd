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
