extends GutTest


func _card() -> LevelCard:
	var c: LevelCard = load("res://scenes/ui/level_card.tscn").instantiate()
	add_child_autofree(c)
	return c


func _entry(stem: String) -> Dictionary:
	return {"stem": stem, "path": "user://levels/%s.json" % stem, "title": stem}


func test_missing_png_shows_no_image() -> void:
	var c := _card()
	c.setup(_entry("definitely_has_no_png"), false, true, false)
	assert_true(c.get_node("%NoImage").visible)
	assert_false(c.get_node("%Thumb").visible)


func test_sibling_png_becomes_thumb() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	img.save_png("user://levels/card_png_probe.png")
	var c := _card()
	c.setup(_entry("card_png_probe"), false, true, false)
	assert_true(c.get_node("%Thumb").visible)
	assert_not_null(c.get_node("%Thumb").texture)
	DirAccess.remove_absolute("user://levels/card_png_probe.png")


func test_locked_card_disabled_and_greyed() -> void:
	var c := _card()
	c.setup(_entry("x"), false, false, false)
	assert_true(c.disabled)
	assert_lt(c.get_node("%ThumbBox").modulate.v, 1.0)


func test_now_badge_only_when_now() -> void:
	var c := _card()
	c.setup(_entry("x"), false, true, true)
	assert_true(c.get_node("%NowBadge").visible)
	c.setup(_entry("x"), true, true, false)
	assert_false(c.get_node("%NowBadge").visible)


func test_press_emits_path() -> void:
	var c := _card()
	c.setup(_entry("pick_me"), false, true, false)
	watch_signals(c)
	c.pressed.emit()
	assert_signal_emitted_with_parameters(c, "picked", ["user://levels/pick_me.json"])


func _tiny_png_b64() -> String:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func test_embedded_thumb_shows() -> void:
	var card := _card()
	var entry := {
		"path": "user://levels/gut_no_such.json",
		"stem": "gut_no_such",
		"title": "T",
		"thumb": _tiny_png_b64(),
	}
	card.setup(entry, false, true, false)
	assert_true(card.get_node("%Thumb").visible)
	assert_not_null(card.get_node("%Thumb").texture)
	assert_false(card.get_node("%NoImage").visible)


func test_garbage_thumb_degrades_to_no_image() -> void:
	var card := _card()
	var entry := {
		"path": "user://levels/gut_no_such.json",
		"stem": "gut_no_such",
		"title": "T",
		"thumb": "!!!not/base64@@@",
	}
	card.setup(entry, false, true, false)
	assert_false(card.get_node("%Thumb").visible)
	assert_true(card.get_node("%NoImage").visible)


func test_bad_length_thumb_degrades_silently() -> void:
	# "abc" passes the alphabet check but length % 4 != 0 — the length gate
	# must catch it before Marshalls is called, so no engine error is emitted.
	var card := _card()
	var entry := {
		"path": "user://levels/gut_no_such.json",
		"stem": "gut_no_such",
		"title": "T",
		"thumb": "abc",
	}
	card.setup(entry, false, true, false)
	assert_false(card.get_node("%Thumb").visible)
	assert_true(card.get_node("%NoImage").visible)


func test_valid_base64_non_png_degrades_silently() -> void:
	# "YWJjZGVmZ2g=" decodes to the ASCII string "abcdefgh" — valid base64 but
	# not a PNG. The magic-signature gate must reject it before the engine's
	# PNG driver ever sees it (the driver spams engine errors on garbage —
	# GUT would fail this test if any slipped through).
	var card := _card()
	var entry := {
		"path": "user://levels/gut_no_such.json",
		"stem": "gut_no_such",
		"title": "T",
		"thumb": "YWJjZGVmZ2g=",
	}
	card.setup(entry, false, true, false)
	assert_false(card.get_node("%Thumb").visible)
	assert_true(card.get_node("%NoImage").visible)


func test_embedded_thumb_beats_sibling_png() -> void:
	var sibling := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	sibling.fill(Color.BLUE)
	DirAccess.make_dir_recursive_absolute("user://levels")
	sibling.save_png("user://levels/gut_pref.png")
	var card := _card()
	var entry := {
		"path": "user://levels/gut_pref.json",
		"stem": "gut_pref",
		"title": "T",
		"thumb": _tiny_png_b64(),
	}
	card.setup(entry, false, true, false)
	DirAccess.remove_absolute("user://levels/gut_pref.png")
	var tex: Texture2D = card.get_node("%Thumb").texture
	assert_eq(tex.get_width(), 4, "embedded (4px) wins over sibling png (8px)")
