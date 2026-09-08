extends GutTest

const USER_LEVELS_DIR := "user://levels"


func after_each() -> void:
	# Clean up any oversized test files we may have created
	if FileAccess.file_exists("user://levels/audit_oversized_test.json"):
		DirAccess.remove_absolute("user://levels/audit_oversized_test.json")


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


# ---------------------------------------------------------------------------
# Audit 2026-09-08 — Finding 8: pre-read size cap for level documents
# ---------------------------------------------------------------------------

## LevelJson.MAX_FILE_BYTES must exist and be 8_000_000.
## Arithmetic: thumb 600k + 8 images x 600k + json slack = ~5.4MB; 8MB is
## comfortably above that while still bounding hostile allocation.
func test_level_json_max_file_bytes_constant_exists() -> void:
	assert_true(
		"MAX_FILE_BYTES" in LevelJson,
		"LevelJson.MAX_FILE_BYTES must exist (pre-read cap constant)"
	)
	assert_eq(LevelJson.MAX_FILE_BYTES, 8_000_000,
		"MAX_FILE_BYTES must equal 8_000_000")


## An oversized level file (cap + 1 byte) must be rejected WITHOUT loading the content.
## The junk bytes would error the JSON parser if read — assert no engine errors fired.
func test_oversized_level_rejected_before_parse() -> void:
	# Write a file of exactly MAX_FILE_BYTES + 1 bytes of junk content
	DirAccess.make_dir_recursive_absolute(USER_LEVELS_DIR)
	var path := "user://levels/audit_oversized_test.json"
	var junk_file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(junk_file, "should be able to write test file")
	# Write junk that would cause JSON parse error if read
	# Writing bytes in chunks to reach cap+1 efficiently
	var chunk := "X".repeat(1000).to_utf8_buffer()
	var total := LevelJson.MAX_FILE_BYTES + 1
	var written := 0
	while written < total:
		var to_write := mini(1000, total - written)
		junk_file.store_buffer(chunk.slice(0, to_write))
		written += to_write
	junk_file.close()
	# Verify file is the right size
	var _check := FileAccess.open(path, FileAccess.READ)
	var actual_size: int = _check.get_length() if _check != null else 0
	_check = null
	assert_eq(actual_size, LevelJson.MAX_FILE_BYTES + 1, "file is cap+1 bytes")
	# load_level must return null WITHOUT causing engine errors (GUT counts those as failures)
	var result := LevelStore.load_level(path)
	assert_null(result, "oversized level must be rejected — returns null")
	# Cleanup
	DirAccess.remove_absolute(path)


## A valid level just under the cap must still load.
func test_valid_level_at_comfortable_size_loads() -> void:
	var l := LevelLayout.new()
	l.title = "Size Cap Test"
	l.crates = [{"x": 100.0, "y": 100.0, "type": "crate-wood"}]
	var path := LevelStore.save_user(l, "size_cap_test")
	assert_ne(path, "", "save succeeded")
	var loaded := LevelStore.load_level(path)
	assert_not_null(loaded, "valid level loads fine")
	assert_eq(loaded.title, "Size Cap Test")
	DirAccess.remove_absolute(path)
