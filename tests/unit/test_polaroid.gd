extends GutTest


func _polaroid() -> Polaroid:
	var p: Polaroid = load("res://scenes/ui/polaroid.tscn").instantiate()
	add_child_autofree(p)
	return p


func _tiny_png_b64() -> String:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func test_hidden_until_shown_and_ignores_mouse() -> void:
	var p := _polaroid()
	assert_false(p.visible)
	assert_eq(p.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_show_b64_displays_shot_and_caption() -> void:
	var p := _polaroid()
	p.show_b64(_tiny_png_b64(), "SKULL KEEP")
	assert_true(p.visible)
	assert_not_null(p.get_node("%Shot").texture)
	assert_eq(p.get_node("%Caption").text, "SKULL KEEP")


func test_non_png_input_never_shows() -> void:
	# Valid base64, decodes to "abcdefgh" — the magic gate must reject it
	# BEFORE the engine's PNG driver (which spams engine errors) runs.
	var p := _polaroid()
	p.show_b64("YWJjZGFiY2Q=", "NOPE")
	assert_false(p.visible)


func test_runs_its_course_and_hides() -> void:
	var p := _polaroid()
	p.show_b64(_tiny_png_b64(), "T")
	await wait_seconds(Polaroid.DROP_TIME + Polaroid.HOLD_TIME + Polaroid.FADE_TIME + 0.4)
	assert_false(p.visible)
