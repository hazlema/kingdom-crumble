class_name Stone
extends RigidBody2D

func _ready() -> void:
	mass = 2.0 * (Settings.preset.impact_force if Settings.preset else 1.0)

func launch(from: Vector2, velocity: Vector2) -> void:
	global_position = from
	linear_velocity = velocity
