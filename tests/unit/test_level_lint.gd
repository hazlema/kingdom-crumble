extends GutTest
# Level-file linting: validate() names the suspect, parse() records it.
func _base(extra: Dictionary = {}) -> Dictionary:
	var d := {"format": 1, "title": "t", "crates": [], "shots": 3}
	d.merge(extra, true)
	return d
func test_crate_errors_name_the_index_and_field() -> void:
	var d := _base({"crates": [{"x": 0, "y": 0, "type": "crate-wood"}, {"x": 0, "y": 0}]})
	assert_eq(LevelJson.validate(d), "crate 1: missing or non-text type")
	d = _base({"crates": [{"y": 0, "type": "crate-wood"}]})
	assert_eq(LevelJson.validate(d), "crate 0: missing x or y")
	d = _base({"crates": [{"x": "far", "y": 0, "type": "crate-wood"}]})
	assert_eq(LevelJson.validate(d), "crate 0: x/y must be numbers")
func test_overlay_errors_name_the_index_and_field() -> void:
	var d := _base({"overlays": [{"image": "abcd1234", "x": 0, "y": 0, "travel": "far"}]})
	assert_eq(LevelJson.validate(d), "overlay 0: travel/tilt must be numbers")
	d = _base({"overlays": [{"x": 0, "y": 0}]})
	assert_eq(LevelJson.validate(d), "overlay 0: missing or non-text image key")
func test_parse_records_why_it_said_no() -> void:
	assert_null(LevelJson.parse("{ not json"))
	assert_string_contains(LevelJson.last_error, "line 1")
	assert_null(LevelJson.parse('{"format": 1, "crates": []}'))
	assert_eq(LevelJson.last_error, "missing title")
	assert_not_null(LevelJson.parse('{"format": 1, "title": "ok", "crates": [], "shots": 1}'))
	assert_eq(LevelJson.last_error, "", "a clean parse clears the record")
func test_image_errors_name_the_key() -> void:
	var d := _base({"images": {"abcd1234": 7}})
	assert_eq(LevelJson.validate(d), "image 'abcd1234': not base64 text")
