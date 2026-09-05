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
	assert_eq(err, "trigger 'on_all_cleared': bad action '42'", "non-string action ID rejected")


func _tiny_b64() -> String:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func _layout_with_named_scenery() -> LevelLayout:
	var l := LevelLayout.new()
	l.title = "linked"
	var b64 := _tiny_b64()
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	l.images[key] = b64
	l.overlays.append({"image": key, "x": 10, "y": 20, "name": "warning"})
	l.overlays.append({"image": key, "x": 30, "y": 40, "name": "reward", "hidden": true})
	return l


func test_builder_spawns_hidden_and_named_pieces() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var pieces := SceneryBuilder.spawn(host, _layout_with_named_scenery())
	assert_eq(pieces.size(), 2)
	assert_true(pieces[0].visible, "unhidden piece shows")
	assert_eq(pieces[0].get_meta("overlay_name"), "warning")
	assert_false(pieces[1].visible, "hidden piece waits for its show")
	assert_eq(pieces[1].get_meta("overlay_name"), "reward")

	# Strict equality: integer 1 should not hide (only boolean true hides)
	var l := LevelLayout.new()
	l.title = "type-safety"
	var b64 := _tiny_b64()
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	l.images[key] = b64
	l.overlays.append({"image": key, "x": 0, "y": 0, "hidden": 1})
	var pieces2 := SceneryBuilder.spawn(host, l)
	assert_true(pieces2[0].visible, "integer 1 does not hide (only boolean true hides)")


func test_crates_carry_their_json_coords() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "coords"
	l.crates.append({"x": 320.0, "y": 512, "type": "crate-wood"})
	var crates := LevelBuilder.spawn_crates(host, l, true, func(_id: String) -> Texture2D: return null)
	assert_eq(crates.size(), 1)
	assert_eq(crates[0].get_meta("json_coords"), Vector2i(320, 512), "float x still keys as int")


func test_knocked_crate_fires_its_linked_trigger() -> void:
	var l := _layout_with_named_scenery()
	l.crates.append({"x": 5, "y": 1, "type": "crate-wood"})
	l.crates.append({"x": 7, "y": 1, "type": "crate-wood"})
	l.triggers = {"hit:5,1": ["hide:warning", "show:reward", "confetti"]}
	l.shots = 3
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	var warning: Node = null
	var reward: Node = null
	for p in lvl.get_tree().get_nodes_in_group("scenery"):
		if p.get_meta("overlay_name", "") == "warning":
			warning = p
		elif p.get_meta("overlay_name", "") == "reward":
			reward = p
	assert_not_null(warning)
	assert_true(warning.visible, "warning starts shown")
	assert_false(reward.visible, "reward starts hidden")
	var linked: Crate = null
	var unlinked: Crate = null
	for c in lvl.get_tree().get_nodes_in_group("crates"):
		if c.get_meta("json_coords") == Vector2i(5, 1):
			linked = c
		else:
			unlinked = c
	# Unlinked crate first: nothing changes.
	lvl._on_crate_knocked(unlinked)
	assert_true(warning.visible, "unlinked knock leaves scenery alone")
	# Linked crate: the whole list fires.
	var before := lvl.get_child_count()
	lvl._on_crate_knocked(linked)
	assert_false(warning.visible, "hide:warning landed")
	assert_true(reward.visible, "show:reward landed")
	assert_gt(lvl.get_child_count(), before, "confetti particles spawned on the level")


func test_unknown_scenery_name_warns_but_never_crashes() -> void:
	var l := _layout_with_named_scenery()
	l.crates.append({"x": 5, "y": 1, "type": "crate-wood"})
	l.triggers = {"hit:5,1": ["show:no_such_sign"]}
	l.shots = 3
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	var crate: Crate = lvl.get_tree().get_nodes_in_group("crates")[0]
	lvl._set_scenery_visible("no_such_sign", true)  # direct: warning path
	lvl._fire_crate_triggers(crate)  # full path: still no crash
	pass_test("warn-and-skip held")


func test_on_all_cleared_routes_show_hide_via_action_list() -> void:
	# Regression: on_all_cleared used to send actions raw to Effects.fire_all,
	# silently no-op-ing show:/hide: ids. After fix 1 it uses _fire_action_list.
	var l := _layout_with_named_scenery()
	# No crates — count_standing([]) == 0, so _settle() fires on_all_cleared.
	l.triggers = {"on_all_cleared": ["show:reward"]}
	l.shots = 3
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	var reward: Node = null
	for p in lvl.get_tree().get_nodes_in_group("scenery"):
		if p.get_meta("overlay_name", "") == "reward":
			reward = p
	assert_not_null(reward)
	assert_false(reward.visible, "reward starts hidden before settle")
	lvl._settle()
	assert_true(reward.visible, "show:reward via on_all_cleared routed correctly")


func test_round_trip_preserves_linked_trigger_keys() -> void:
	var l := _layout_with_named_scenery()
	l.crates.append({"x": 5, "y": 1, "type": "crate-wood"})
	l.triggers = {"hit:5,1": ["hide:warning", "show:reward"]}
	l.shots = 1
	var back := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(back, "serialized linked level reloads: %s" % LevelJson.last_error)
	assert_eq(back.overlays[0].get("name", ""), "warning")
	assert_eq(back.overlays[1].get("hidden", false), true)
	assert_true(back.triggers.has("hit:5,1"), "trigger entry survives")
