extends GutTest


func test_load_chill_tier():
	# exact values are the owner's tuning dials — assert shape, not numbers
	assert_true(Settings.load_tier("chill"))
	assert_eq(Settings.tier, "chill")
	assert_gt(Settings.preset.crate_natural_bounce, 0.0)
	assert_gt(Settings.preset.impact_force, 0.0)


func test_hardcore_hits_softer_than_chill():
	# the difficulty ladder lives in impact_force (lab-verified);
	# other dials are free for the owner to tune per feel
	Settings.load_tier("hardcore")
	var hard := Settings.preset
	Settings.load_tier("chill")
	assert_lt(hard.impact_force, Settings.preset.impact_force)


func test_unknown_tier_fails_and_keeps_state():
	Settings.load_tier("chill")
	assert_false(Settings.load_tier("polka"))
	assert_eq(Settings.tier, "chill")
