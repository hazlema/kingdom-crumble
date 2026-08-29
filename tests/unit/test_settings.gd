extends GutTest

func test_load_chill_tier():
	assert_true(Settings.load_tier("chill"))
	assert_eq(Settings.tier, "chill")
	assert_almost_eq(Settings.preset.crate_natural_bounce, 0.6, 0.001)
	assert_almost_eq(Settings.preset.impact_force, 3.0, 0.001)

func test_hardcore_is_stingier_than_chill():
	Settings.load_tier("hardcore")
	var hard := Settings.preset
	Settings.load_tier("chill")
	assert_lt(hard.crate_natural_bounce, Settings.preset.crate_natural_bounce)
	assert_lt(hard.impact_force, Settings.preset.impact_force)

func test_unknown_tier_fails_and_keeps_state():
	Settings.load_tier("chill")
	assert_false(Settings.load_tier("polka"))
	assert_eq(Settings.tier, "chill")
