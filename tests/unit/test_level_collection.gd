extends GutTest

const TEST_UNLOCKS := "user://test_unlocks_collection.cfg"


func before_all():
	# Warm up the Camera2D so its one-time physics-interpolation engine
	# message doesn't land inside test_gold_refunds_a_shot and fail it.
	Level.next_layout = LevelLayout.new()
	var warm = load("res://scenes/level.tscn").instantiate()
	add_child(warm)
	await get_tree().physics_frame
	warm.queue_free()


func before_each() -> void:
	DirAccess.remove_absolute(TEST_UNLOCKS)
	Unlocks.use_path(TEST_UNLOCKS)


func after_each() -> void:
	DirAccess.remove_absolute(TEST_UNLOCKS)
	Unlocks.use_path("user://unlocks.cfg")


func _level_with(type_id: String) -> Level:
	var layout := LevelLayout.new()
	var p := EditorGrid.cell_to_world(Vector2i(12, 0))
	layout.crates.append({"x": p.x, "y": p.y, "type": type_id})
	Level.next_layout = layout
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	return l


func _knock_first(l: Level) -> void:
	var crate: Crate = l.get_tree().get_nodes_in_group("crates")[0]
	crate.position += Vector2(100, 0)
	crate.sleeping = false


func test_gold_refunds_a_shot() -> void:
	var l := _level_with("crate-gold")
	await wait_seconds(0.4)
	var before := l.shots_left
	_knock_first(l)
	await wait_physics_frames(3)
	assert_eq(l.shots_left, before + 1)


func test_skull_queues_exploding() -> void:
	var l := _level_with("skull")
	await wait_seconds(0.4)
	_knock_first(l)
	await wait_physics_frames(3)
	assert_eq(l.pending_buffs, [&"exploding"] as Array[StringName])


func test_wood_grants_nothing() -> void:
	var l := _level_with("crate-wood")
	await wait_seconds(0.4)
	_knock_first(l)
	await wait_physics_frames(3)
	assert_eq(l.pending_buffs.size(), 0)


func test_ghost_skunk_event_sets_flag_once() -> void:
	var l := _level_with("crate-ghost")
	l._ghost_roll = func() -> float: return 0.0  # force the skunk
	await wait_seconds(0.4)
	_knock_first(l)
	await wait_physics_frames(3)
	assert_true(Unlocks.has_flag("skunk"))
	assert_eq(l.pending_buffs.size(), 0, "the skunk IS the payout")


func test_refund_ignored_in_failed_state() -> void:
	# I1 regression: a late gold-crate topple after FAILED must not
	# increment shots_left or update the HUD.
	var l := _level_with("crate-gold")
	await wait_seconds(0.4)
	var before := l.shots_left
	l.state = Level.State.FAILED
	_knock_first(l)
	await wait_physics_frames(3)
	assert_eq(l.shots_left, before, "refund landed in FAILED state — I1 bug")


func test_editor_skunk_not_triggered() -> void:
	# M1 regression: the once-ever skunk ceremony must never fire during
	# editor playtests (_editor_session=true forces the plain pool).
	var l := _level_with("crate-ghost")
	l._ghost_roll = func() -> float: return 0.0  # would trigger skunk in production
	l._editor_session = true
	await wait_seconds(0.4)
	var before := l.shots_left
	_knock_first(l)
	await wait_physics_frames(3)
	assert_false(Unlocks.has_flag("skunk"), "skunk flag set during editor session — M1 bug")
	# roll=0.0 → POOL[0] = free_shot → refund; confirm pool actually ran.
	assert_eq(
		l.shots_left,
		before + 1,
		"editor session crate-ghost plain pool did not grant free_shot refund"
	)
