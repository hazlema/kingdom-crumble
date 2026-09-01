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
