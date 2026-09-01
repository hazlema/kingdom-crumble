extends GutTest


func _arena() -> Node2D:
	var a := Node2D.new()
	add_child_autofree(a)
	a.add_child(load("res://scenes/environment.tscn").instantiate())
	return a


func _stack(arena: Node2D, col: int, rows: int) -> Array[Crate]:
	var layout := LevelLayout.new()
	for row in rows:
		var p := EditorGrid.cell_to_world(Vector2i(col, row))
		layout.crates.append({"x": p.x, "y": p.y, "type": "crate-wood"})
	return LevelBuilder.spawn_crates(arena, layout, false, EditorAssets.texture_for)


func test_super_bounce_stone_bounces_off_ground() -> void:
	var arena := _arena()
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.super_bounce = true
	arena.add_child(stone)
	stone.launch(Vector2(800, 400), Vector2(300, 300))
	var bounced := false
	for i in 120:
		await wait_physics_frames(1)
		if stone.linear_velocity.y < -50.0:
			bounced = true
			break
	assert_true(bounced, "stone should rebound upward after hitting the ground")


func test_plain_stone_does_not_bounce() -> void:
	var arena := _arena()
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	arena.add_child(stone)
	stone.launch(Vector2(800, 400), Vector2(300, 300))
	var bounced := false
	for i in 120:
		await wait_physics_frames(1)
		if stone.linear_velocity.y < -50.0:
			bounced = true
			break
	assert_false(bounced)


func test_exploding_stone_shoves_crates_in_radius() -> void:
	var arena := _arena()
	var crates := _stack(arena, 12, 3)
	await wait_seconds(0.4)
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.exploding = true
	arena.add_child(stone)
	var target := EditorGrid.cell_to_world(Vector2i(12, 0))
	stone.launch(target + Vector2(-120, -40), Vector2(500, 0))
	await wait_seconds(2.0)
	var downed := 0
	for c in crates:
		if not c.is_standing():
			downed += 1
	assert_gt(downed, 1, "blast should knock out more than a direct hit's worth")


func test_boom_without_bounce_frees_the_stone() -> void:
	var arena := _arena()
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.exploding = true
	arena.add_child(stone)
	stone.launch(Vector2(800, 500), Vector2(200, 200))
	await wait_seconds(2.0)
	assert_false(is_instance_valid(stone), "one boom, then gone")


func test_bounce_explode_stone_survives_first_boom() -> void:
	var arena := _arena()
	var stone: Stone = load("res://scenes/stone.tscn").instantiate()
	stone.exploding = true
	stone.super_bounce = true
	arena.add_child(stone)
	stone.launch(Vector2(800, 500), Vector2(400, 100))
	await wait_seconds(0.8)
	assert_true(is_instance_valid(stone), "skipping cluster bomb lives past boom one")
