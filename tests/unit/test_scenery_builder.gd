extends GutTest


func _layout_with(overlays: Array) -> LevelLayout:
	var l := LevelLayout.new()
	l.title = "T"
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.GREEN)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	l.images = {"abcd1234": b64}
	for o in overlays:
		l.overlays.append(o)
	return l


func test_spawns_living_pieces() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := _layout_with(
		[
			{
				"image": "abcd1234",
				"x": 500.0,
				"y": 200.0,
				"behavior": "SPIN",
				"pivot": "CENTER",
				"speed": 0.5,
			}
		]
	)
	var pieces := SceneryBuilder.spawn(host, l)
	assert_eq(pieces.size(), 1)
	assert_eq(pieces[0].position, Vector2(500, 200))
	assert_eq(pieces[0].behavior, NarfDecor.Behavior.SPIN)
	assert_eq(pieces[0].pivot, NarfDecor.Pivot.CENTER)
	assert_almost_eq(pieces[0].speed, 0.5, 0.001)
	assert_not_null(pieces[0].texture)


func test_defaults_and_hostiles_skip_cleanly() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := _layout_with(
		[
			{"image": "abcd1234", "x": 1.0, "y": 2.0},
			{"image": "missing", "x": 0.0, "y": 0.0},
			{"image": "abcd1234", "x": 0.0, "y": 0.0, "behavior": "EXPLODE"},
			{"image": "abcd1234", "x": 0.0, "y": 0.0, "behavior": "BOB", "speed": 999.0},
		]
	)
	l.images["broken"] = "!!!"
	var pieces := SceneryBuilder.spawn(host, l)
	assert_eq(pieces.size(), 2, "plain + clamped spawn; missing image + unknown verb skip")
	assert_eq(pieces[0].behavior, NarfDecor.Behavior.NONE, "no verb = statue")
	assert_almost_eq(pieces[1].speed, 10.0, 0.001, "speed clamps to the dial range")


func test_no_scenery_no_nodes() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var before := host.get_child_count()
	SceneryBuilder.spawn(host, LevelLayout.new())
	assert_eq(host.get_child_count(), before)


func test_overlay_index_meta_set() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "T"
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	l.images = {"abcd1234": b64}
	# overlay[0] = missing, overlay[1] = valid
	l.overlays = [
		{"image": "missing", "x": 0.0, "y": 0.0},
		{"image": "abcd1234", "x": 10.0, "y": 10.0},
	]
	var pieces := SceneryBuilder.spawn(host, l)
	assert_eq(pieces.size(), 1)
	assert_true(pieces[0].has_meta("overlay_index"), "overlay_index meta set")
	assert_eq(pieces[0].get_meta("overlay_index"), 1, "meta index is source index 1 (not 0)")
