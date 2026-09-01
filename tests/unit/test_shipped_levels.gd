extends GutTest

# Every level that ships must parse and validate — a hand-edited json
# with a missing key should fail HERE, not at launch (the demo.json
# missing-"type" incident, 2026-08-31).

func test_all_shipped_level_files_load() -> void:
	var dir := DirAccess.open("res://levels")
	assert_not_null(dir)
	var checked := 0
	for f in dir.get_files():
		if f.get_extension() != "json":
			continue
		var l := LevelStore.load_level("res://levels/" + f)
		assert_not_null(l, "shipped level failed to load: %s" % f)
		checked += 1
	assert_gt(checked, 0, "there should be at least one shipped level")

func test_all_listed_builtins_load() -> void:
	for path in LevelStore.list_builtin():
		assert_not_null(LevelStore.load_level(path),
			"listed built-in failed to load: %s" % path)
