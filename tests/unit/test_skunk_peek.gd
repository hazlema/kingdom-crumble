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
