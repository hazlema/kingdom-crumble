class_name Stone
extends RigidBody2D

const VARIANTS: Array[Texture2D] = [
	preload("res://art/assets/stones_64/stone-1.png"),
	preload("res://art/assets/stones_64/stone-2.png"),
	preload("res://art/assets/stones_64/stone-3.png"),
	preload("res://art/assets/stones_64/stone-4.png"),
]

func _ready() -> void:
	mass = 2.0 * (Settings.preset.impact_force if Settings.preset else 1.0)
	$Visual.texture = VARIANTS[randi() % VARIANTS.size()]

func launch(from: Vector2, velocity: Vector2) -> void:
	global_position = from
	linear_velocity = velocity
