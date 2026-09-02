extends GutTest

# Sleep-float is an owner-endorsed level-design tool ("a good bug"):
# midair crates hold position until struck. These pin it against the
# intro dialog's pause-at-spawn timing, which once burned the tuck-in
# before the physics server's first real step (floaters fell on dismiss).


func _float_one(arena: Node2D) -> Crate:
	arena.add_child(load("res://scenes/environment.tscn").instantiate())
	var layout := LevelLayout.new()
	var p := EditorGrid.cell_to_world(Vector2i(10, 4))
	layout.crates.append({"x": p.x, "y": p.y, "type": "crate-wood"})
	return LevelBuilder.spawn_crates(arena, layout, false, EditorAssets.texture_for)[0]


func after_each() -> void:
	get_tree().paused = false


func test_floater_holds_through_settled_pause_roundtrip() -> void:
	var arena := Node2D.new()
	add_child_autofree(arena)
	var floater := _float_one(arena)
	await wait_seconds(0.5)
	var y := floater.global_position.y
	get_tree().paused = true
	await wait_process_frames(20)
	get_tree().paused = false
	await wait_seconds(0.5)
	assert_true(floater.sleeping, "still a statue")
	assert_almost_eq(floater.global_position.y, y, 1.0, "no fall")


func test_floater_holds_when_paused_at_spawn_like_the_intro() -> void:
	var arena := Node2D.new()
	add_child_autofree(arena)
	var floater := _float_one(arena)
	get_tree().paused = true
	await wait_process_frames(30)
	get_tree().paused = false
	await wait_seconds(0.8)
	assert_true(floater.sleeping, "tuck-in must survive an intro-style pause")
	assert_almost_eq(
		floater.global_position.y,
		EditorGrid.cell_to_world(Vector2i(10, 4)).y,
		2.0,
		"floater held its perch after the dialog closed"
	)
