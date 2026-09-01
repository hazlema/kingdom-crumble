class_name ThumbFraming
extends RefCounted

# Owner's framing algorithm (thumb-capture spec §1): box the crates,
# pad, grow to 13:8 with the dominant side winning, anchor the bottom
# at the grass strip, slide (never shrink) if the top would leave the
# painted background. Pure math — deterministic from level data alone,
# so every thumbnail is framed identically regardless of editor view.

const ASPECT_W := 13.0
const ASPECT_H := 8.0
const MIN_W := 416.0
const MIN_H := 256.0
const PAD := 48.0
const GRASS_STRIP := 32.0  # bottom edge sits this far below FLOOR_Y
const TOP_LIMIT := -1350.0  # background stays painted above this y
const HALF_CRATE := Vector2(32.0, 31.5)


static func capture_rect(crates: Array) -> Rect2:
	var content := _content_box(crates)
	var bottom := EditorGrid.FLOOR_Y + GRASS_STRIP
	var content_w := content.size.x + PAD * 2.0
	var content_h := bottom - (content.position.y - PAD)
	var h := maxf(maxf(content_h, content_w * ASPECT_H / ASPECT_W), MIN_H)
	var w := h * ASPECT_W / ASPECT_H
	var top := bottom - h
	if top < TOP_LIMIT:
		top = TOP_LIMIT  # slide down, never shrink (owner gotcha #2)
	var center_x := content.get_center().x
	return Rect2(center_x - w / 2.0, top, w, h)


static func _content_box(crates: Array) -> Rect2:
	if crates.is_empty():
		var origin := EditorGrid.cell_to_world(Vector2i(0, 0))
		return Rect2(origin - HALF_CRATE, HALF_CRATE * 2.0)
	var box := Rect2(Vector2(crates[0]["x"], crates[0]["y"]), Vector2.ZERO)
	for c in crates:
		box = box.expand(Vector2(c["x"], c["y"]))
	return box.grow_individual(HALF_CRATE.x, HALF_CRATE.y, HALF_CRATE.x, HALF_CRATE.y)
