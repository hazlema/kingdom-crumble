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

# World-space y of the ground plane; the arc stops there instead of
# diving through the grass.
@export var world_floor_y := 600.0

func _draw() -> void:
	if velocity == Vector2.ZERO:
		return
	var floor_local := world_floor_y - global_position.y
	var points := PackedVector2Array()
	var golds := PackedColorArray()
	var rims := PackedColorArray()
	for i in range(STEPS + 1):
		var t := i * DT
		var p := velocity * t + Vector2(0, 0.5 * gravity * t * t)
		if p.y > floor_local and not points.is_empty():
			# clip the last segment exactly at the grass line
			var prev := points[points.size() - 1]
			var k := (floor_local - prev.y) / (p.y - prev.y)
			p = prev.lerp(p, k)
			points.append(p)
			golds.append(golds[golds.size() - 1])
			rims.append(rims[rims.size() - 1])
			break
		points.append(p)
		var fade := 1.0 - float(i) / STEPS
		golds.append(Color(1.0, 0.85, 0.3, 0.35 + 0.55 * fade))
		rims.append(Color(0.15, 0.1, 0.05, 0.25 + 0.4 * fade))
	if points.size() < 2:
		return
	# dark rim under a gold core keeps it readable against bright sky
	draw_polyline_colors(points, rims, 11.0, true)
	draw_polyline_colors(points, golds, 6.0, true)
