extends GutTest

# Mr. Skunk's lean-bonus cameo: grows up from the grass, hugs his
# heart, sinks away — and cleans up after himself.


func test_pop_spawns_and_retires_the_cameo() -> void:
	var arena := Node2D.new()
	add_child_autofree(arena)
	SkunkPeek.pop(arena, Vector2(1000, 500))
	var skunk: Sprite2D = null
	for c in arena.get_children():
		if c is Sprite2D:
			skunk = c
	assert_not_null(skunk, "the skunk answers the call")
	assert_not_null(skunk.texture)
	assert_almost_eq(skunk.global_position.y, EditorGrid.FLOOR_Y + 24.0, 0.5, "rises from the grass line")
	await wait_seconds(SkunkPeek.RISE_TIME + SkunkPeek.PEEK_TIME + SkunkPeek.SINK_TIME + 0.4)
	assert_false(is_instance_valid(skunk), "and takes his leave")


func test_ceremony_prefers_the_flip_reveal_when_portraits_exist() -> void:
	if (
		not ResourceLoader.exists("res://assets/characters/skunk/photo-front.png")
		or not ResourceLoader.exists("res://assets/characters/skunk/photo-back.png")
	):
		pass_test("no portrait pair authored — sheet animation is the contract")
		return
	var frame: RareUnlockFrame = load("res://scenes/ui/rare_unlock_frame.tscn").instantiate()
	add_child_autofree(frame)
	frame.show_unlock("Rare Unlock", RareUnlockFrame.skunk_frames())
	var found: NarfFlip = null
	for c in frame.get_node("%Anim").get_parent().get_children():
		if c is NarfFlip:
			found = c
	assert_not_null(found, "the portrait flips into view")
	assert_false(frame.get_node("%Anim").visible, "sheet animation stands down")
