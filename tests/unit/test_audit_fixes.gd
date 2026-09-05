extends GutTest

# Pins for the 2026-09-05 external audit findings. Each test replays
# the audit's reproduction in miniature.

var LevelEditorScript := preload("res://src/editor/level_editor.gd")


func _tiny_png(flip: bool = false) -> String:
	var img := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.RED if not flip else Color.BLUE)
	img.set_pixel(1, 0, Color.BLUE if not flip else Color.RED)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func test_bake_keeps_image_shared_after_dedup_flip() -> void:
	# Audit 1: A and its mirror B; flip BOTH; bake. Before the fix the
	# refcount ledger lied and one referenced image got erased.
	var ed: Node = LevelEditorScript.new()
	var a := _tiny_png(false)
	var b := _tiny_png(true)
	var key_a := LevelJson.image_key(Marshalls.base64_to_raw(a))
	var key_b := LevelJson.image_key(Marshalls.base64_to_raw(b))
	ed.current.images = {key_a: a, key_b: b}
	ed.current.overlays.append({"image": key_a, "x": 0, "y": 0, "_flip_h": true})
	ed.current.overlays.append({"image": key_b, "x": 0, "y": 0, "_flip_h": true})
	ed._bake_scenery()
	for o in ed.current.overlays:
		assert_true(
			ed.current.images.has(o["image"]),
			"overlay's image %s survives the bake" % o["image"]
		)
	ed.free()


func test_overlay_cap_enforced_at_the_door() -> void:
	# Audit 2: reusing one image dodged the cap and minted unloadable saves.
	var ed: Node = LevelEditorScript.new()
	for i in LevelJson.MAX_OVERLAYS:
		ed.current.overlays.append({"image": "abcd1234", "x": 0, "y": 0})
	assert_false(ed.can_add_overlay(), "cap reached: the door is closed")
	ed.free()


func test_save_user_refuses_invalid_documents_and_bad_names() -> void:
	# Audit 2+10: never persist what the loader would refuse; name the reason.
	var layout := LevelLayout.new()
	layout.title = "cap test"
	for i in LevelJson.MAX_OVERLAYS + 1:
		layout.overlays.append({"image": "abcd1234", "x": 0, "y": 0})
	assert_eq(LevelStore.save_user(layout, "audit_probe"), "", "over-cap refused")
	assert_string_contains(LevelJson.last_error, "too many overlays")
	var ok := LevelLayout.new()
	ok.title = "fine"
	assert_eq(LevelStore.save_user(ok, "!!!"), "", "unusable name refused")
	assert_string_contains(LevelJson.last_error, "name")


func test_untyped_author_is_rejected_not_crashed() -> void:
	# Audit 9: author:42 used to pass validate then explode in parse.
	assert_null(LevelJson.parse('{"format":1,"title":"x","author":42,"crates":[],"shots":1}'))
	assert_eq(LevelJson.last_error, "author must be text")


func test_parse_strips_edit_session_keys() -> void:
	# Audit 9: underscore keys from disk are untrusted editor scratch.
	var l := LevelJson.parse(
		'{"format":1,"title":"x","crates":[],"shots":1,'
		+ '"images":{"abcd1234":""},'
		+ '"overlays":[{"image":"abcd1234","x":0,"y":0,"_scale":40.0}]}'
	)
	assert_not_null(l)
	assert_false((l.overlays[0] as Dictionary).has("_scale"), "scratch keys stripped")


func test_png_dimension_gate_blocks_amplification() -> void:
	# Audit 7: a small base64 blob must not decode into a 16MB bitmap.
	var big := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	big.fill(Color.RED)
	var b64 := Marshalls.raw_to_base64(big.save_png_to_buffer())
	assert_null(LevelJson.decode_png_b64(b64), "oversize decode refused pre-decode")
	var small := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	small.fill(Color.GREEN)
	assert_not_null(
		LevelJson.decode_png_b64(Marshalls.raw_to_base64(small.save_png_to_buffer())),
		"honest images still decode"
	)


func test_cancel_charge_disarms_pause_surprise_shot() -> void:
	# Audit 8: pause during charge used to fire on resume.
	var t := Trebuchet.new()
	add_child_autofree(t)
	t._charging = true
	t.charge = 0.7
	t.notification(NOTIFICATION_PAUSED)
	assert_false(t._charging, "pause abandons the charge")
	assert_eq(t.charge, 0.0, "no stored energy survives")


func test_trigger_sounds_ride_the_sfx_bus() -> void:
	# Audit 11: sound: effects ignored the SFX volume slider.
	var host := Node2D.new()
	add_child_autofree(host)
	Effects.fire_all(["sound:boom"], host, Vector2.ZERO)
	var found := false
	for c in host.get_children():
		if c is AudioStreamPlayer:
			found = true
			assert_eq(c.bus, &"Sfx", "trigger sound honors the Sound slider")
	assert_true(found, "the sound player spawned")
