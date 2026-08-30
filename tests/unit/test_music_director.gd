extends GutTest

var MusicDirector = preload("res://src/audio/music_director.gd")

func test_pick_from_empty_pool_is_empty_string():
	assert_eq(MusicDirector.pick_track([]), "")

func test_pick_avoids_exclude_when_possible():
	for i in 20:
		assert_eq(MusicDirector.pick_track(["a", "b"], "a"), "b")

func test_pick_allows_exclude_when_only_option():
	assert_eq(MusicDirector.pick_track(["a"], "a"), "a")

func test_list_pool_finds_chill_tracks():
	var pool: Array = MusicDirector.list_pool("chill")
	assert_gt(pool.size(), 0, "chill tier should have tracks")
	for path in pool:
		assert_true(path.begins_with("res://music/chill/"), path)

func test_list_pool_of_missing_tier_dir_is_empty():
	assert_eq(MusicDirector.list_pool("polka"), [])

func test_volume_clamps_high():
	Music.set_volume_linear(1.5)
	assert_eq(Music.get_volume_linear(), 1.0)
	Music.set_volume_linear(1.0)

func test_volume_clamps_low():
	Music.set_volume_linear(-0.2)
	assert_eq(Music.get_volume_linear(), 0.0)
	Music.set_volume_linear(1.0)
