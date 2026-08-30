extends GutTest

func test_known_ids():
	assert_true(Effects.is_known("confetti"))
	assert_true(Effects.is_known("sound:fanfare"))
	assert_false(Effects.is_known("format_hard_drive"))

func test_fire_all_counts_known_only():
	var host: Node2D = add_child_autofree(Node2D.new())
	var n := Effects.fire_all(["confetti", "nonsense"], host, Vector2.ZERO)
	assert_eq(n, 1)
