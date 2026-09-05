class_name LevelJson
extends RefCounted

# Level file codec. JSON only — inert data, safe to share (spec §1).

const FORMAT := 1
const MAX_COORD := 100000.0
const MAX_CRATES := 500
const MAX_THUMB_CHARS := 600_000  # ~450 KB decoded — a 416x256 PNG fits many times over
const MAX_INTRO_CHARS := 600  # a hearty paragraph; hard wall for blobs
const MAX_IMAGES := 8
const MAX_IMAGE_CHARS := 600_000
const MAX_OVERLAYS := 16

# Why the last parse() said no -- shown to the level author verbatim,
# so every message names the suspect ("crate 13: missing type").
static var last_error := ""

# Compiled once for the class; validates base64 alphabet before decoding.
# Marshalls.base64_to_raw emits an engine error on bad chars — untrusted data
# must degrade silently, so we pre-screen rather than let it through.
static var _b64_rx := RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")


# Returns the first 8 hex characters of the SHA-256 hash of the given bytes.
static func image_key(png_bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(png_bytes)
	return ctx.finish().hex_encode().substr(0, 8)


# Shared PNG gate: validates base64 string, decodes to Image, or returns null
# silently on any failure. Hostile or corrupt blobs degrade silently —
# a bad image can disappoint, never crash (spec §4).
static func decode_png_b64(b64: String) -> Image:
	if b64 == "":
		return null
	# base64 encodes 3 bytes per 4 chars (with padding); any other length is
	# invalid and Marshalls.base64_to_raw behavior is undefined — reject early.
	if b64.length() % 4 != 0:
		return null
	# Alphabet check: Marshalls.base64_to_raw emits an engine error on bad
	# chars which GUT counts as a test failure; untrusted data must not reach it.
	if _b64_rx.search(b64) == null:
		return null
	var buf := Marshalls.base64_to_raw(b64)
	if buf.is_empty():
		return null
	# load_png_from_buffer emits engine errors on non-PNG bytes (confirmed by
	# test — 4 errors per call, GUT treats those as failures). Guard with the
	# 8-byte PNG magic signature before calling into the driver. Residual: a
	# correct magic prefix on a corrupt body still reaches the driver and logs
	# its errors — the != OK guard keeps the degrade correct, so hostile files
	# can spam the log but never crash or mis-render.
	const PNG_MAGIC := [137, 80, 78, 71, 13, 10, 26, 10]
	if buf.size() < PNG_MAGIC.size():
		return null
	for i in PNG_MAGIC.size():
		if buf[i] != PNG_MAGIC[i]:
			return null
	var img := Image.new()
	if img.load_png_from_buffer(buf) != OK:
		return null
	return img


static func parse(text: String) -> LevelLayout:
	# Use JSON class to avoid console errors on invalid input
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		last_error = "line %d: %s" % [json.get_error_line() + 1, json.get_error_message()]
		return null
	var data: Variant = json.data
	if not data is Dictionary:
		last_error = "top level must be an object"
		return null
	var verdict := validate(data)
	if verdict != "":
		last_error = verdict
		return null
	last_error = ""
	var l := LevelLayout.new()
	l.title = data["title"]
	l.author = data.get("author", "")
	l.background = data.get("background", "meadow")
	l.thumb = str(data.get("thumb", ""))
	l.intro = str(data.get("intro", ""))
	l.shots = int(data.get("shots", 0))
	for c in data["crates"]:
		l.crates.append({"x": float(c["x"]), "y": float(c["y"]), "type": String(c["type"])})
	var trig: Variant = data.get("triggers", {})
	if trig is Dictionary:
		for event in trig:
			var ids: Variant = trig[event]
			if ids is Array:
				var str_ids: Array[String] = []
				for i in ids:
					if i is String:
						str_ids.append(i)
				l.triggers[String(event)] = str_ids
	l.images = (data.get("images", {}) as Dictionary).duplicate()
	var raw_overlays: Variant = data.get("overlays", [])
	var typed_overlays: Array[Dictionary] = []
	for entry in (raw_overlays as Array):
		if entry is Dictionary:
			typed_overlays.append((entry as Dictionary).duplicate())
	l.overlays = typed_overlays
	return l


static func validate(d: Dictionary) -> String:
	var _fmt: Variant = d.get("format", null)
	if not (_fmt is int or _fmt is float) or int(_fmt) > FORMAT or int(_fmt) < 1:
		return "unsupported or missing format"
	if not d.get("title", "") is String or d.get("title", "") == "":
		return "missing title"
	if not d.get("crates") is Array:
		return "crates must be a list"
	if (d["crates"] as Array).size() > MAX_CRATES:
		return "too many crates"
	for ci in (d["crates"] as Array).size():
		var c: Variant = d["crates"][ci]
		if not c is Dictionary:
			return "crate %d: not an object" % ci
		if not c.has("x") or not c.has("y"):
			return "crate %d: missing x or y" % ci
		if not c.get("type", null) is String:
			return "crate %d: missing or non-text type" % ci
		if not (c["x"] is float or c["x"] is int) or not (c["y"] is float or c["y"] is int):
			return "crate %d: x/y must be numbers" % ci
		if absf(float(c["x"])) > MAX_COORD or absf(float(c["y"])) > MAX_COORD:
			return "crate %d: out of bounds" % ci
	var _shots: Variant = d.get("shots", 0)
	if not (_shots is int or _shots is float):
		return "shots must be a number"
	var _trig: Variant = d.get("triggers", {})
	if _trig is Dictionary:
		for _event in _trig:
			var _ids: Variant = _trig[_event]
			if _ids is Array and (_ids as Array).size() > 16:
				return "trigger '%s': too many effects (max 16)" % _event
	var _thumb: Variant = d.get("thumb", "")
	if not _thumb is String:
		return "bad thumb"
	if (_thumb as String).length() > MAX_THUMB_CHARS:
		return "thumb too large"
	var _intro: Variant = d.get("intro", "")
	if not _intro is String:
		return "bad intro"
	if (_intro as String).length() > MAX_INTRO_CHARS:
		return "intro too long"
	var _images: Variant = d.get("images", {})
	if not _images is Dictionary:
		return "bad images"
	if (_images as Dictionary).size() > MAX_IMAGES:
		return "too many images"
	for _key in (_images as Dictionary):
		if not _key is String or (_key as String).length() > 16:
			return "images: bad key '%s'" % str(_key)
		var _val: Variant = (_images as Dictionary)[_key]
		if not _val is String:
			return "image '%s': not base64 text" % _key
		if (_val as String).length() > MAX_IMAGE_CHARS:
			return "image '%s': too large" % _key
	var _overlays: Variant = d.get("overlays", [])
	if not _overlays is Array:
		return "bad overlays"
	if (_overlays as Array).size() > MAX_OVERLAYS:
		return "too many overlays"
	for oi in (_overlays as Array).size():
		var _entry: Variant = _overlays[oi]
		if not _entry is Dictionary:
			return "overlay %d: not an object" % oi
		var _img: Variant = (_entry as Dictionary).get("image", null)
		if not _img is String:
			return "overlay %d: missing or non-text image key" % oi
		var _ox: Variant = (_entry as Dictionary).get("x", null)
		var _oy: Variant = (_entry as Dictionary).get("y", null)
		if not (_ox is float or _ox is int) or not (_oy is float or _oy is int):
			return "overlay %d: x/y must be numbers" % oi
		if absf(float(_ox)) > MAX_COORD or absf(float(_oy)) > MAX_COORD:
			return "overlay %d: out of bounds" % oi
		# Optional dials: wrong TYPES are rejected here (a typed read in
		# the builder would abort the whole spawn); unknown NAMES are the
		# builder's skip-with-warning department.
		var _b: Variant = (_entry as Dictionary).get("behavior", "NONE")
		var _p: Variant = (_entry as Dictionary).get("pivot", "CENTER")
		if not _b is String or not _p is String:
			return "overlay %d: behavior/pivot must be text" % oi
		var _sp: Variant = (_entry as Dictionary).get("speed", 0.0)
		var _am: Variant = (_entry as Dictionary).get("amplitude", 0.0)
		if not (_sp is float or _sp is int) or not (_am is float or _am is int):
			return "overlay %d: speed/amplitude must be numbers" % oi
		var _ax: Variant = (_entry as Dictionary).get("axis", "HORIZONTAL")
		if not _ax is String:
			return "overlay %d: axis must be text" % oi
		var _tr: Variant = (_entry as Dictionary).get("travel", 0.0)
		var _ti: Variant = (_entry as Dictionary).get("tilt", 0.0)
		if not (_tr is float or _tr is int) or not (_ti is float or _ti is int):
			return "overlay %d: travel/tilt must be numbers" % oi
	return ""


static func serialize(layout: LevelLayout) -> String:
	var d := {
		"format": FORMAT,
		"title": layout.title,
		"background": layout.background,
		"shots": layout.shots,
		"crates": layout.crates,
		"triggers": layout.triggers,
	}
	if layout.author != "":
		d["author"] = layout.author
	if layout.thumb != "":
		d["thumb"] = layout.thumb
	if layout.intro != "":
		d["intro"] = layout.intro
	if layout.images.size() > 0:
		d["images"] = layout.images
	if layout.overlays.size() > 0:
		# Strip edit-session underscore keys (e.g. _rot, _scale, _flip_h, _flip_v)
		# before serializing so they never reach disk.
		var clean_overlays: Array = []
		for entry in layout.overlays:
			var clean: Dictionary = {}
			for k in (entry as Dictionary):
				if not (k as String).begins_with("_"):
					clean[k] = entry[k]
			clean_overlays.append(clean)
		d["overlays"] = clean_overlays
	return JSON.stringify(d, "  ")
