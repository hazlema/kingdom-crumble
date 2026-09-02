extends GutTest


func _tiny_png_b64() -> String:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func _base(d := {}) -> Dictionary:
	var out := {"format": 1, "title": "T", "crates": []}
	out.merge(d)
	return out


func test_scenery_round_trips() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	var b64 := _tiny_png_b64()
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	l.images = {key: b64}
	l.overlays = [{"image": key, "x": 500.0, "y": 100.0, "behavior": "SPIN", "speed": 0.1}]
	var parsed := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(parsed)
	assert_eq(parsed.images[key], b64)
	assert_eq(parsed.overlays[0]["image"], key)
	assert_eq(str(parsed.overlays[0]["behavior"]), "SPIN")


func test_absent_scenery_unwritten() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	var s := LevelJson.serialize(l)
	assert_false(s.contains("images"))
	assert_false(s.contains("overlays"))
	assert_eq(LevelJson.parse(s).images.size(), 0)
	assert_eq(LevelJson.parse(s).overlays.size(), 0)


func test_image_key_is_8_hex_and_deterministic() -> void:
	var bytes := Marshalls.base64_to_raw(_tiny_png_b64())
	var k := LevelJson.image_key(bytes)
	assert_eq(k.length(), 8)
	assert_eq(k, LevelJson.image_key(bytes), "same bytes, same key")


func test_caps_and_shapes_rejected() -> void:
	assert_ne(LevelJson.validate(_base({"images": []})), "", "images must be a dict")
	assert_ne(LevelJson.validate(_base({"overlays": {}})), "", "overlays must be an array")
	var many := {}
	for i in LevelJson.MAX_IMAGES + 1:
		many["k%d" % i] = "aaaa"
	assert_ne(LevelJson.validate(_base({"images": many})), "")
	var big := {"k": "a".repeat(LevelJson.MAX_IMAGE_CHARS + 4)}
	assert_ne(LevelJson.validate(_base({"images": big})), "")
	var lots := []
	for i in LevelJson.MAX_OVERLAYS + 1:
		lots.append({"image": "k", "x": 0, "y": 0})
	assert_ne(LevelJson.validate(_base({"overlays": lots})), "")
	assert_ne(
		LevelJson.validate(_base({"overlays": [{"image": 7, "x": 0, "y": 0}]})), "", "bad entry"
	)
	assert_eq(
		LevelJson.validate(
			_base({"images": {"k": "aaaa"}, "overlays": [{"image": "k", "x": 1.0, "y": 2.0}]})
		),
		"",
		"well-shaped scenery passes"
	)


func test_decode_gate_is_shared_and_silent() -> void:
	assert_null(LevelJson.decode_png_b64(""))
	assert_null(LevelJson.decode_png_b64("abc"), "bad length")
	assert_null(LevelJson.decode_png_b64("YWJjZGFiY2Q="), "not png")
	assert_not_null(LevelJson.decode_png_b64(_tiny_png_b64()))
