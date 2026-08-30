extends GutTest

func test_builtin_meadow_loads():
	var layout := LevelStore.load_layout("res://levels/meadow.tres")
	assert_not_null(layout)
	assert_eq(layout.crates.size(), 3)
	assert_eq(layout.title, "Meadow")

func test_user_save_load_roundtrip():
	var layout := LevelLayout.new()
	layout.title = "Test Tower"
	layout.author = "gut"
	layout.crates = [Vector2(100, 100), Vector2(100, 44)]
	var path := LevelStore.save_user(layout, "gut_test_level")
	assert_ne(path, "")
	var loaded := LevelStore.load_layout(path)
	assert_not_null(loaded)
	assert_eq(loaded.title, "Test Tower")
	assert_eq(loaded.crates.size(), 2)
	assert_true(LevelStore.list_user().has(path))
	DirAccess.remove_absolute(path)

func test_missing_layout_returns_null():
	assert_null(LevelStore.load_layout("res://levels/nope.tres"))
