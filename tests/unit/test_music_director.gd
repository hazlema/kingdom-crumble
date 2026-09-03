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


func test_volume_persists_to_settings_cfg() -> void:
	var before: float = Music.get_volume_linear()
	Music.set_volume_linear(0.42)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	assert_almost_eq(float(cfg.get_value("audio", "music_volume", -1.0)), 0.42, 0.001)
	Music.set_volume_linear(before)


func test_sfx_bus_exists_and_volume_persists() -> void:
	assert_ne(AudioServer.get_bus_index("Sfx"), -1, "Sfx bus loaded from default_bus_layout")
	var before: float = Music.get_sfx_volume_linear()
	Music.set_sfx_volume_linear(0.42)
	var idx := AudioServer.get_bus_index("Sfx")
	assert_almost_eq(AudioServer.get_bus_volume_db(idx), linear_to_db(0.42), 0.01)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	assert_almost_eq(float(cfg.get_value("audio", "sfx_volume", -1.0)), 0.42, 0.001)
	Music.set_sfx_volume_linear(before)


func test_export_suffixes_stripped_for_all_disguises() -> void:
	assert_eq(MusicDirector._strip_export_suffixes("song.mp3.import"), "song.mp3")
	assert_eq(MusicDirector._strip_export_suffixes("song.ogg.remap"), "song.ogg")
	assert_eq(MusicDirector._strip_export_suffixes("song.mp3"), "song.mp3")
	assert_eq(MusicDirector._strip_export_suffixes("song.wav"), "song.wav")


func test_same_tier_replay_keeps_current_track() -> void:
	# Regression: levels call play_tier on every load; same tier with the
	# song still going must NOT reroll the track mid-listen (owner nit).
	Music.play_tier("chill")
	var first: String = Music._current_track
	assert_true(Music._player.playing, "track should be rolling")
	for i in 5:
		Music.play_tier("chill")
	assert_eq(Music._current_track, first, "a level change is not a reason to cut the music")
	Music.stop()
