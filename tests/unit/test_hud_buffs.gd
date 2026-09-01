extends GutTest

func _hud() -> Node:
	var h: Node = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(h)
	return h

func test_set_buffs_draws_one_icon_per_charge() -> void:
	var h := _hud()
	h.set_buffs([&"exploding", &"exploding", &"multishot"] as Array[StringName])
	await wait_frames(1)
	assert_eq(h.get_node("BuffRow").get_child_count(), 3)

func test_set_crates_shows_standing_over_total() -> void:
	var h := _hud()
	h.set_crates(12, 15)
	assert_eq(h.get_node("%Crates").text, "CRATES: 12/15")
	assert_not_null(h.get_node("%CrateIcon").texture, "icon assigned on first update")

func test_set_buffs_empty_clears_row() -> void:
	var h := _hud()
	h.set_buffs([&"multishot"] as Array[StringName])
	await wait_frames(1)
	h.set_buffs([] as Array[StringName])
	await wait_frames(2)
	var live := 0
	for c in h.get_node("BuffRow").get_children():
		if not c.is_queued_for_deletion():
			live += 1
	assert_eq(live, 0)
