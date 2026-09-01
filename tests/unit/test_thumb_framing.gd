extends GutTest

const EPS := 0.001


func _crate(cell: Vector2i) -> Dictionary:
	var w := EditorGrid.cell_to_world(cell)
	return {"x": w.x, "y": w.y, "type": "crate-wood"}


func _wide_row(n: int) -> Array:
	var out: Array = []
	for cx in n:
		out.append(_crate(Vector2i(cx, 0)))
	return out


func _aspect(r: Rect2) -> float:
	return r.size.x / r.size.y


func test_single_crate_gets_minimum_box() -> void:
	var r := ThumbFraming.capture_rect([_crate(Vector2i(0, 0))])
	assert_almost_eq(r.size.x, 416.0, EPS)
	assert_almost_eq(r.size.y, 256.0, EPS)


func test_aspect_is_always_13_8() -> void:
	var tall: Array = []
	for cy in 8:
		tall.append(_crate(Vector2i(0, cy)))
	for crates in [[_crate(Vector2i(2, 2))], _wide_row(30), tall]:
		var r := ThumbFraming.capture_rect(crates)
		assert_almost_eq(_aspect(r), 13.0 / 8.0, EPS)


func test_bottom_anchors_at_grass_strip() -> void:
	var r := ThumbFraming.capture_rect([_crate(Vector2i(0, 0))])
	assert_almost_eq(r.end.y, EditorGrid.FLOOR_Y + 32.0, EPS)


func test_wide_level_grows_height_uniformly() -> void:
	var r := ThumbFraming.capture_rect(_wide_row(30))
	assert_gt(r.size.x, 1920.0)
	assert_almost_eq(r.size.y, r.size.x * 8.0 / 13.0, EPS)


func test_all_crate_centers_inside() -> void:
	var crates: Array = []
	for cx in 12:
		crates.append(_crate(Vector2i(cx, cx % 8)))
	var r := ThumbFraming.capture_rect(crates)
	for c in crates:
		assert_true(r.has_point(Vector2(c["x"], c["y"])), "crate center inside rect")


func test_empty_level_is_deterministic_min_box() -> void:
	var r := ThumbFraming.capture_rect([])
	assert_almost_eq(r.size.x, 416.0, EPS)
	assert_almost_eq(r.size.y, 256.0, EPS)
	assert_almost_eq(r.end.y, 632.0, EPS)


func test_top_limit_slides_without_resize() -> void:
	# Fabricated sky-high crate (unreachable via the 8-row grid) — the
	# clamp must translate the box down, never resize it.
	var crates: Array = [{"x": 1000.0, "y": -2000.0, "type": "crate-wood"}]
	var r := ThumbFraming.capture_rect(crates)
	assert_true(r.position.y >= ThumbFraming.TOP_LIMIT - EPS, "top clamped to limit")
	assert_almost_eq(_aspect(r), 13.0 / 8.0, EPS)
