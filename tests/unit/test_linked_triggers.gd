extends GutTest

# Linked triggers (spec 2026-09-05): crate-hit events show/hide named
# scenery and fire effects. Format layer first.


func _base(extra: Dictionary = {}) -> Dictionary:
	var d := {"format": 1, "title": "t", "crates": [], "shots": 3}
	d.merge(extra, true)
	return d


func test_known_actions_learn_show_and_hide() -> void:
	assert_true(Effects.is_known("show:reward"))
	assert_true(Effects.is_known("hide:warning_1"))
	assert_false(Effects.is_known("show:"), "empty name refused")
	assert_false(Effects.is_known("show:Bad Name"), "charset enforced")
	assert_false(Effects.is_known("shwo:reward"), "typos stay unknown")


func test_overlay_name_and_hidden_validate() -> void:
	var ov := {"image": "abcd1234", "x": 0, "y": 0}
	var good := ov.duplicate()
	good["name"] = "sign-1"
	good["hidden"] = true
	assert_eq(LevelJson.validate(_base({"overlays": [good]})), "")
	var bad := ov.duplicate()
	bad["name"] = "Bad Name!"
	assert_eq(LevelJson.validate(_base({"overlays": [bad]})), "overlay 0: bad name")
	var dupe_a := ov.duplicate()
	dupe_a["name"] = "twin"
	var dupe_b := ov.duplicate()
	dupe_b["name"] = "twin"
	assert_eq(
		LevelJson.validate(_base({"overlays": [dupe_a, dupe_b]})),
		"overlay 1: duplicate name 'twin'"
	)
	var badh := ov.duplicate()
	badh["hidden"] = "yes"
	assert_eq(
		LevelJson.validate(_base({"overlays": [badh]})), "overlay 0: hidden must be true/false"
	)


func test_trigger_events_and_actions_validate() -> void:
	assert_eq(
		LevelJson.validate(_base({"triggers": {"hit:5,1": ["show:reward", "confetti"]}})), ""
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"hit:-3,7": ["hide:warning"]}})),
		"",
		"negative coords are legal"
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"on_crate": ["confetti"]}})),
		"trigger 'on_crate': unknown event"
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"hit:5,1": "confetti"}})),
		"trigger 'hit:5,1': actions must be a list"
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"hit:5,1": ["shwo:reward"]}})),
		"trigger 'hit:5,1': bad action 'shwo:reward'"
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"on_all_cleared": ["confetti"]}})),
		"",
		"on_all_cleared happy path"
	)
	var err := LevelJson.validate(_base({"triggers": {"on_all_cleared": [42]}}))
	assert_true(err.begins_with("trigger "), "non-string action ID rejected: %s" % err)
