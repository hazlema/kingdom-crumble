class_name TrajectoryPreview
extends Node2D

# Dotted arc predicting the stone's flight, drawn in local space from
# the launch point. Fed the same velocity the stone will launch with,
# so it never lies.

const STEPS := 26
const DT := 0.07

var velocity := Vector2.ZERO:
	set(v):
		velocity = v
		queue_redraw()

var gravity := 980.0

func _draw() -> void:
	if velocity == Vector2.ZERO:
		return
	for i in range(1, STEPS + 1):
		var t := i * DT
		var p := velocity * t + Vector2(0, 0.5 * gravity * t * t)
		var fade := 1.0 - float(i) / STEPS
		draw_circle(p, 2.5 + 3.0 * fade, Color(1.0, 0.83, 0.29, 0.25 + 0.55 * fade))
