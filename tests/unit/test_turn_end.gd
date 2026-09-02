extends GutTest

# Turn-end stone retirement: a boom+bounce cluster stone never frees
# itself and once kept exploding through the next aiming phase. When
# the turn settles, restless stones fade out; sleeping rubble stays.


func test_settle_retires_awake_stones_keeps_rubble() -> void:
	Level.next_layout = LevelLayout.new()
	Level.next_layout.title = "T"
	Level.next_layout.crates = [{"x": 800.0, "y": 569.0, "type": "crate-wood"}]
	Level.return_to_editor = true
	var lvl: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_seconds(0.5)
	var restless: Stone = load("res://scenes/stone.tscn").instantiate()
	restless.super_bounce = true
	lvl.add_child(restless)
	restless.launch(Vector2(900, 300), Vector2(200, -100))
	var rubble: Stone = load("res://scenes/stone.tscn").instantiate()
	lvl.add_child(rubble)
	rubble.launch(Vector2(1100, 300), Vector2.ZERO)
	rubble.sleeping = true
	lvl._active_stones = [restless, rubble] as Array[Stone]
	lvl._retire_restless_stones()
	await wait_seconds(0.6)
	assert_false(is_instance_valid(restless), "restless stone retires with its turn")
	assert_true(is_instance_valid(rubble), "sleeping rubble stays")
	Level.return_to_editor = false


func test_idle_rule_barely_moving_counts_as_done() -> void:
	Level.next_layout = LevelLayout.new()
	Level.next_layout.title = "T"
	Level.next_layout.crates = [{"x": 800.0, "y": 569.0, "type": "crate-wood"}]
	Level.return_to_editor = true
	var lvl: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_seconds(0.3)
	var s: Stone = load("res://scenes/stone.tscn").instantiate()
	lvl.add_child(s)
	s.launch(Vector2(900, 100), Vector2.ZERO)
	s.sleeping = false
	s.linear_velocity = Vector2(5, 0)
	assert_true(lvl._is_idle(s), "a crawling body is done")
	s.linear_velocity = Vector2(300, 0)
	assert_false(lvl._is_idle(s), "a flying body is not")
	s.queue_free()
	Level.return_to_editor = false
