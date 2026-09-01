class_name HitTextEffect extends Control

# Floaty rising fade-out text ("+Explosive Shot"). The owner's first
# ever Godot control, rebuilt for Kingdom Crumble.

@export var text: String = "+5":
	set(value):
		text = value
		if is_node_ready():
			_apply_text()
	get:
		return text
@export var duration := 1.0  # seconds until fully faded and freed
@export var rise := 50.0  # pixels drifted upward over the duration


func _ready() -> void:
	_apply_text()
	var effect = get_tree().create_tween()
	effect.parallel().tween_property($".", "modulate:a", 0.0, duration)
	effect.parallel().tween_property($".", "position:y", position.y - rise, duration)
	effect.play()
	await effect.finished
	queue_free()


func _apply_text() -> void:
	$ColorRect/Label.text = text
	$ColorRect.size = $ColorRect/Label.get_minimum_size() + Vector2(12, 6)
