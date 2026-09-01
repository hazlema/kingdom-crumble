class_name DashedLine
extends Control

# Comp-faithful dashed separator (ink-muted dashes).


func _draw() -> void:
	draw_dashed_line(
		Vector2(0, size.y / 2.0),
		Vector2(size.x, size.y / 2.0),
		Color(0.5608, 0.4392, 0.2784, 0.45),
		2.0,
		6.0
	)
