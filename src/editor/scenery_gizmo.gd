class_name SceneryGizmo
extends Node2D

# Draw-only overlay: selection rect, corner resize handles, rotate lollipop.
# The editor updates `piece` and `cam_zoom` each frame and calls queue_redraw().
# Hit-testing lives in the EDITOR so unit tests can exercise it directly.

const HANDLE_RADIUS := 8.0
const ROTATE_LOLLIPOP_DIST := 40.0

# Set by LevelEditor every frame while a piece is selected.
var piece: NarfDecor = null
var cam_zoom := Vector2.ONE


func _draw() -> void:
	if piece == null or not is_instance_valid(piece):
		return

	var tex := piece.texture
	if tex == null:
		return

	# Piece rect in local (world) space, accounting for its offset.
	var rect := piece.get_rect()
	var pos := piece.position
	var rot := piece.rotation
	var scale := piece.scale

	# Transform corners to draw-space (this Node2D has no own transform; it
	# shares the scene root so its coordinate space == world space).
	var corners := _rect_corners(rect, pos, rot, scale)

	# Draw selection outline (yellow).
	var outline_color := Color(1.0, 0.83, 0.29, 0.95)
	for i in 4:
		draw_line(corners[i], corners[(i + 1) % 4], outline_color, 2.0 / cam_zoom.x)

	# Corner handles (resize, aspect-locked).
	var handle_r := HANDLE_RADIUS / cam_zoom.x
	var handle_color := Color(1.0, 1.0, 1.0, 0.9)
	for c in corners:
		draw_circle(c, handle_r, handle_color)
		draw_arc(c, handle_r, 0, TAU, 16, outline_color, 1.5 / cam_zoom.x)

	# Rotate lollipop above the top edge midpoint.
	var top_mid := (corners[0] + corners[1]) * 0.5
	var up_dir := Vector2(-sin(rot), -cos(rot))  # piece's local "up" in world
	var lollipop_pos := top_mid + up_dir * (ROTATE_LOLLIPOP_DIST / cam_zoom.x)
	draw_line(top_mid, lollipop_pos, outline_color, 2.0 / cam_zoom.x)
	draw_circle(lollipop_pos, handle_r, Color(0.4, 0.8, 1.0, 0.9))
	draw_arc(lollipop_pos, handle_r, 0, TAU, 16, outline_color, 1.5 / cam_zoom.x)


# Returns 4 world-space corners [top-left, top-right, bottom-right, bottom-left]
# of `rect` after applying `pos`, `rot`, `scale`.
static func _rect_corners(
	rect: Rect2, pos: Vector2, rot: float, scale: Vector2
) -> Array[Vector2]:
	var tl := rect.position
	var br := rect.end
	var locals: Array[Vector2] = [
		tl,
		Vector2(br.x, tl.y),
		br,
		Vector2(tl.x, br.y),
	]
	var out: Array[Vector2] = []
	for lp in locals:
		var sp := lp * scale
		var rotated := Vector2(
			sp.x * cos(rot) - sp.y * sin(rot), sp.x * sin(rot) + sp.y * cos(rot)
		)
		out.append(pos + rotated)
	return out
