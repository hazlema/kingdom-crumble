extends GutTest

# NarfKit citizen #4: fade the world through black. Structure tests --
# the actual scene swap is exercised by every level advance in play.


func test_veil_is_built_to_cover_and_outrank_everything() -> void:
	var f := NarfFade.new()
	add_child_autofree(f)
	assert_eq(f.layer, 120, "above every game CanvasLayer")
	assert_eq(f.process_mode, Node.PROCESS_MODE_ALWAYS, "fades even while paused")
	var veil: ColorRect = f._veil
	assert_not_null(veil, "the veil exists")
	assert_eq(veil.color.a, 0.0, "starts clear")
	assert_eq(veil.anchor_right, 1.0, "full-rect cover")
	assert_eq(veil.anchor_bottom, 1.0, "full-rect cover")
	assert_eq(veil.mouse_filter, Control.MOUSE_FILTER_STOP, "eats clicks mid-fade")


func test_veil_tweens_to_black() -> void:
	var f := NarfFade.new()
	add_child_autofree(f)
	var tw := f.create_tween()
	tw.tween_property(f._veil, "color:a", 1.0, 0.05)
	await wait_seconds(0.15)
	assert_almost_eq(f._veil.color.a, 1.0, 0.01, "the veil can reach full black")
