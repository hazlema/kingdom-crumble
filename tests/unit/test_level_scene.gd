# tests/unit/test_level_scene.gd
extends GutTest

func test_level_01_crates_in_group():
	Settings.load_tier("chill")
	var packed: PackedScene = load("res://scenes/level_01.tscn")
	var level = add_child_autofree(packed.instantiate())
	assert_eq(get_tree().get_nodes_in_group("crates").size(), 3,
		"level_01 should have 3 nodes in group 'crates'")

func test_level_01_required_nodes_present():
	Settings.load_tier("chill")
	var packed: PackedScene = load("res://scenes/level_01.tscn")
	var level = add_child_autofree(packed.instantiate())
	assert_not_null(level.get_node_or_null("Trebuchet"), "Trebuchet must exist")
	assert_not_null(level.get_node_or_null("CameraDirector"), "CameraDirector must exist")
	assert_not_null(level.get_node_or_null("Hud"), "Hud must exist")
