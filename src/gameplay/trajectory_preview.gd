class_name TrajectoryPreview
extends Node2D

# Animated aiming arrow in the style of SMG's Risk: the arc repeatedly
# draws itself from the launch point toward the predicted landing spot,
# arrowhead riding the tip. The path is the stone's real physics.

const STEPS := 26
const DT := 0.07
const CYCLE_SEC := 1.1  # one grow cycle
const HOLD_FRACTION := 0.2  # portion of the cycle spent fully drawn

# Cream core, ink rim (theme palette) — near-opaque since playtest
# feedback: the old 40%-alpha white vanished on phone screens.
const CORE := Color(1.0, 0.98, 0.94, 0.9)
const RIM := Color(0.22, 0.16, 0.09, 0.6)

var velocity := Vector2.ZERO:
	set(v):
		velocity = v
		queue_redraw()

var gravity := 980.0
var _cycle := 0.0

# World-space y of the ground plane; the arc stops there instead of
# diving through the grass.
@export var world_floor_y := 600.0


func _process(delta: float) -> void:
	if not visible:
		return
	_cycle = fmod(_cycle + delta / CYCLE_SEC, 1.0)
	queue_redraw()


func _draw() -> void:
	if velocity == Vector2.ZERO:
		return
	var path := _build_path()
	if path.size() < 2:
		return

	# Reveal fraction: grow, then hold fully drawn briefly. Never
	# shorter than a stub — a zero-length arrow is an invisible frame
	# (the flicker at every cycle restart).
	var reveal := minf(_cycle / (1.0 - HOLD_FRACTION), 1.0)
	reveal = ease(reveal, 0.6)  # fast start, soft landing
	reveal = lerpf(0.15, 1.0, reveal)
	var end_f := 1.0 + reveal * float(path.size() - 1)
	var shown := PackedVector2Array()
	for i in range(int(end_f)):
		shown.append(path[i])
	var frac := end_f - floorf(end_f)
	if int(end_f) < path.size() and frac > 0.0:
		shown.append(path[int(end_f) - 1].lerp(path[int(end_f)], frac))
	if shown.size() < 2:
		return

	var tip := shown[shown.size() - 1]
	var dir := (tip - shown[shown.size() - 2]).normalized()

	draw_polyline(shown, RIM, 13.0, true)
	draw_polyline(shown, CORE, 7.0, true)
	_draw_head(tip, dir, 30.0, RIM)
	_draw_head(tip, dir, 24.0, CORE)


# Full arc from launch to the grass line, in local space.
func _build_path() -> PackedVector2Array:
	var floor_local := world_floor_y - global_position.y
	var path := PackedVector2Array()
	for i in range(STEPS + 1):
		var t := i * DT
		var p := velocity * t + Vector2(0, 0.5 * gravity * t * t)
		if p.y > floor_local and not path.is_empty():
			var prev := path[path.size() - 1]
			var k := (floor_local - prev.y) / (p.y - prev.y)
			path.append(prev.lerp(p, k))
			break
		path.append(p)
	return path


# World position of the arrow's end (the predicted landing spot) —
# what the camera keeps in frame while the shot charges.
func end_global() -> Vector2:
	if velocity == Vector2.ZERO:
		return global_position
	var path := _build_path()
	if path.is_empty():
		return global_position
	return global_position + path[path.size() - 1]


func _draw_head(tip: Vector2, dir: Vector2, size: float, color: Color) -> void:
	var side := dir.orthogonal()
	var head := PackedVector2Array(
		[
			tip + dir * size,
			tip - side * size * 0.45,
			tip + side * size * 0.45,
		]
	)
	draw_colored_polygon(head, color)
