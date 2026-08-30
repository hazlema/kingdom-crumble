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
	var points := PackedVector2Array()
	var golds := PackedColorArray()
	var rims := PackedColorArray()
	for i in range(STEPS + 1):
		var t := i * DT
		points.append(velocity * t + Vector2(0, 0.5 * gravity * t * t))
		var fade := 1.0 - float(i) / STEPS
		golds.append(Color(1.0, 0.85, 0.3, 0.35 + 0.55 * fade))
		rims.append(Color(0.15, 0.1, 0.05, 0.25 + 0.4 * fade))
	# dark rim under a gold core keeps it readable against bright sky
	draw_polyline_colors(points, rims, 11.0, true)
	draw_polyline_colors(points, golds, 6.0, true)
