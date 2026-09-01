extends GutTest


func test_carry_consumed_and_cleared_on_ready() -> void:
	Level.carry_buffs = [&"exploding", &"multishot"] as Array[StringName]
	Level.next_layout = LevelLayout.new()
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	assert_eq(l.pending_buffs, [&"exploding", &"multishot"] as Array[StringName])
	assert_eq(Level.carry_buffs.size(), 0, "static cleared after consumption")


func test_no_carry_means_empty_queue() -> void:
	Level.next_layout = LevelLayout.new()
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	assert_eq(l.pending_buffs.size(), 0)
