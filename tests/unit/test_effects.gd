extends GutTest

func test_known_ids():
	assert_true(Effects.is_known("confetti"))
	assert_true(Effects.is_known("sound:fanfare"))
	assert_false(Effects.is_known("format_hard_drive"))

func test_fire_all_counts_known_only():
	var host: Node2D = add_child_autofree(Node2D.new())
	var n := Effects.fire_all(["confetti", "nonsense"], host, Vector2.ZERO)
	assert_eq(n, 1)

func test_traversal_sound_ids_rejected():
	var host: Node2D = add_child_autofree(Node2D.new())
	assert_eq(Effects.fire_all(["sound:../../escape"], host, Vector2.ZERO), 0)
	assert_eq(Effects.fire_all(["sound:../evil"], host, Vector2.ZERO), 0)
