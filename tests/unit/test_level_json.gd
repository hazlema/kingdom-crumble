extends GutTest

const GOOD := """
{"format":1,"title":"Falling","author":"frosty","background":"meadow",
"shots":4,"crates":[{"x":1400,"y":572,"type":"crate-wood"}],
"triggers":{"on_all_cleared":["confetti"]}}
"""

func test_parse_good_file():
	var l := LevelJson.parse(GOOD)
	assert_not_null(l)
	assert_eq(l.title, "Falling")
	assert_eq(l.shots, 4)
	assert_eq(l.crates.size(), 1)
	assert_eq(l.crates[0]["type"], "crate-wood")
	assert_eq(l.triggers["on_all_cleared"], ["confetti"])

func test_defaults_for_absent_optionals():
	var l := LevelJson.parse('{"format":1,"title":"T","crates":[]}')
	assert_not_null(l)
	assert_eq(l.author, "")
	assert_eq(l.background, "meadow")
	assert_eq(l.shots, 0)
	assert_eq(l.triggers, {})

func test_rejects_garbage_and_bad_shapes():
	assert_null(LevelJson.parse("not json at all"))
	assert_null(LevelJson.parse('{"title":"no format"}'))
	assert_null(LevelJson.parse('{"format":99,"title":"future","crates":[]}'))
	assert_null(LevelJson.parse('{"format":1,"crates":[]}'))          # no title
	assert_null(LevelJson.parse('{"format":1,"title":"T","crates":"x"}'))
	assert_null(LevelJson.parse(
		'{"format":1,"title":"T","crates":[{"x":1,"y":2}]}'))          # no type
	assert_null(LevelJson.parse(
		'{"format":1,"title":"T","crates":[{"x":9e9,"y":2,"type":"a"}]}'))

func test_unknown_fields_ignored():
	var l := LevelJson.parse(
		'{"format":1,"title":"T","crates":[],"future_thing":123}')
	assert_not_null(l)

func test_roundtrip():
	var l := LevelJson.parse(GOOD)
	var l2 := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(l2)
	assert_eq(l2.title, l.title)
	assert_eq(l2.crates, l.crates)
	assert_eq(l2.triggers, l.triggers)
