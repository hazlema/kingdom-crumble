extends GutTest


func test_list_builtin_alphabetical_and_loadable():
	var paths: Array[String] = LevelStore.list_builtin()
	assert_gt(paths.size(), 0, "there should be at least one built-in level")
	var sorted: Array[String] = paths.duplicate()
	sorted.sort()
	assert_eq(paths, sorted, "built-ins list alphabetically")
	for p in paths:
		assert_true(p.begins_with("res://levels/"), p)
		assert_true(p.ends_with(".json"), p)


func test_user_save_load_roundtrip():
	var l := LevelLayout.new()
	l.title = "Gut Tower"
	l.crates = [{"x": 100.0, "y": 100.0, "type": "crate-wood"}]
	var path := LevelStore.save_user(l, "gut tower!!")
	assert_true(path.ends_with("gut_tower.json"))
	var loaded := LevelStore.load_level(path)
	assert_not_null(loaded)
	assert_eq(loaded.title, "Gut Tower")
	assert_true(LevelStore.list_user().has(path))
	DirAccess.remove_absolute(path)


func test_load_missing_or_invalid_is_null():
	assert_null(LevelStore.load_level("res://levels/nope.json"))


func test_sanitize_stem():
	assert_eq(LevelStore.sanitize_stem("My Cool Level!"), "my_cool_level")
	assert_eq(LevelStore.sanitize_stem("../../evil"), "evil")


func test_save_user_empty_stem_returns_empty():
	var l := LevelLayout.new()
	l.title = "Junk"
	var path := LevelStore.save_user(l, "!!!")
	assert_eq(path, "")
