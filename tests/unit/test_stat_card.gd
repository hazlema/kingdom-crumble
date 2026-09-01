extends GutTest


func _card() -> StatCard:
	var c: StatCard = load("res://scenes/ui/stat_card.tscn").instantiate()
	add_child_autofree(c)
	return c


func test_values_reflect_in_labels() -> void:
	var c := _card()
	c.set_title("THE MEADOW")
	c.set_level_no(2)
	c.set_shots(5)
	c.set_crates(7, 7)
	c.set_power(0.5)
	assert_eq(c.get_node("%Title").text, "THE MEADOW")
	assert_eq(c.get_node("%LvlChip").text, "LVL 2")
	assert_true(c.get_node("%LvlChip").visible)
	assert_eq(c.get_node("%ShotsValue").text, "5")
	assert_eq(c.get_node("%CratesValue").text, "7/7")
	assert_almost_eq(c.get_node("%PowerBar").value, 0.5, 0.001)


func test_no_chain_position_hides_chip() -> void:
	var c := _card()
	c.set_level_no(-1)
	assert_false(c.get_node("%LvlChip").visible)


func test_buff_section_hides_when_empty() -> void:
	var c := _card()
	c.set_buffs([] as Array[StringName])
	assert_false(c.get_node("%BuffSection").visible)
	c.set_buffs([&"exploding", &"exploding"] as Array[StringName])
	assert_true(c.get_node("%BuffSection").visible)
	assert_eq(c.get_node("%BuffRow").get_child_count(), 2)


func test_hud_forwards_to_card() -> void:
	var h: Hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(h)
	h.set_shots(3)
	h.set_crates(1, 4)
	h.set_level_info("SKULL", 3)
	assert_eq(h.get_node("%StatCard/%ShotsValue").text, "3")
	assert_eq(h.get_node("%StatCard/%CratesValue").text, "1/4")
	assert_eq(h.get_node("%StatCard/%Title").text, "SKULL")
