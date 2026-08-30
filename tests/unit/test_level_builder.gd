extends GutTest

func _layout() -> LevelLayout:
	var l := LevelLayout.new()
	l.crates = [
		{"x": 100.0, "y": 500.0, "type": "crate-wood"},
		{"x": 100.0, "y": 436.0, "type": "crate-gold"},
	]
	return l

func test_spawns_positioned_typed_crates_in_group():
	var host: Node2D = add_child_autofree(Node2D.new())
	var spawned: Array[Crate] = LevelBuilder.spawn_crates(host, _layout(), false,
		func(_id: String) -> Texture2D: return null)
	assert_eq(spawned.size(), 2)
	assert_eq(spawned[0].position, Vector2(100, 500))
	assert_eq(spawned[1].type_id, "crate-gold")
	assert_true(spawned[0].is_in_group("crates"))
	assert_false(spawned[0].freeze)

func test_frozen_for_editor():
	var host: Node2D = add_child_autofree(Node2D.new())
	var spawned: Array[Crate] = LevelBuilder.spawn_crates(host, _layout(), true,
		func(_id: String) -> Texture2D: return null)
	assert_true(spawned[0].freeze)
