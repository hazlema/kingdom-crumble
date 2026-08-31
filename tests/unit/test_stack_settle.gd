extends GutTest

# Crates spawned on grid cells must already be at physical rest: the
# crate shape is 64x63, so any grid pitch that leaves air gaps (or
# overlaps) makes player stacks drop and rattle the moment TEST or a
# level starts.

func test_grid_stack_spawns_at_rest() -> void:
	var layout := LevelLayout.new()
	for row in 4:
		var p := EditorGrid.cell_to_world(Vector2i(8, row))
		layout.crates.append({"x": p.x, "y": p.y, "type": "crate-wood"})
	Level.next_layout = layout
	var level: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	var start := {}
	for c in get_tree().get_nodes_in_group("crates"):
		start[c.get_instance_id()] = c.global_position
	assert_eq(start.size(), 4)
	await wait_seconds(1.5)
	var lowest: Crate = null
	for c in get_tree().get_nodes_in_group("crates"):
		var drift: Vector2 = c.global_position - start[c.get_instance_id()]
		assert_lt(drift.length(), 1.0,
			"crate drifted %.2fpx from spawn — stack is not at rest" % drift.length())
		assert_lt(absf(rad_to_deg(c.rotation)), 0.5)
		if lowest == null or c.global_position.y > lowest.global_position.y:
			lowest = c
	# Sleep must not make towers invincible: a real impact wakes them.
	var hit_x := lowest.global_position.x
	lowest.apply_central_impulse(Vector2(3000, 0))
	await wait_seconds(1.0)
	assert_gt(lowest.global_position.x - hit_x, 5.0,
		"impacted crate should wake and be knocked away")

func test_gentle_tap_does_not_topple_stack() -> void:
	# A slow boulder rolling into the tower's foot ("kissed it") must
	# wake the crates without the whole stack shaking itself down.
	var layout := LevelLayout.new()
	for row in 4:
		var p := EditorGrid.cell_to_world(Vector2i(8, row))
		layout.crates.append({"x": p.x, "y": p.y, "type": "crate-wood"})
	Level.next_layout = layout
	var level: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(level)
	var start := {}
	var lowest: Crate = null
	for c in get_tree().get_nodes_in_group("crates"):
		start[c.get_instance_id()] = c.global_position
		if lowest == null or c.global_position.y > lowest.global_position.y:
			lowest = c
	await wait_seconds(0.5)
	lowest.apply_central_impulse(Vector2(150, 0))
	await wait_seconds(2.5)
	for c in get_tree().get_nodes_in_group("crates"):
		var drift: Vector2 = c.global_position - start[c.get_instance_id()]
		assert_true(c.is_standing(), "gentle tap toppled a crate")
		assert_lt(drift.length(), 12.0,
			"gentle tap scattered a crate %.1fpx" % drift.length())
