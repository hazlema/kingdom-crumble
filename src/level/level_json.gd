class_name LevelJson
extends RefCounted

# Level file codec. JSON only — inert data, safe to share (spec §1).

const FORMAT := 1
const MAX_COORD := 100000.0
const MAX_CRATES := 500

static func parse(text: String) -> LevelLayout:
	# Use JSON class to avoid console errors on invalid input
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return null
	var data: Variant = json.data
	if not data is Dictionary:
		return null
	if validate(data) != "":
		return null
	var l := LevelLayout.new()
	l.title = data["title"]
	l.author = data.get("author", "")
	l.background = data.get("background", "meadow")
	l.shots = int(data.get("shots", 0))
	for c in data["crates"]:
		l.crates.append({"x": float(c["x"]), "y": float(c["y"]),
			"type": String(c["type"])})
	var trig: Variant = data.get("triggers", {})
	if trig is Dictionary:
		for event in trig:
			var ids: Variant = trig[event]
			if ids is Array:
				l.triggers[String(event)] = ids.map(
					func(i: Variant) -> String: return String(i))
	return l

static func validate(d: Dictionary) -> String:
	if not d.has("format") or int(d.get("format", -1)) > FORMAT \
			or int(d.get("format", -1)) < 1:
		return "unsupported or missing format"
	if not d.get("title", "") is String or d.get("title", "") == "":
		return "missing title"
	if not d.get("crates") is Array:
		return "crates must be a list"
	if (d["crates"] as Array).size() > MAX_CRATES:
		return "too many crates"
	for c in d["crates"]:
		if not c is Dictionary or not c.has("x") or not c.has("y") \
				or not c.get("type", null) is String:
			return "bad crate entry"
		if not (c["x"] is float or c["x"] is int) \
				or not (c["y"] is float or c["y"] is int):
			return "bad crate coords"
		if absf(float(c["x"])) > MAX_COORD or absf(float(c["y"])) > MAX_COORD:
			return "crate out of bounds"
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
	return JSON.stringify(d, "  ")
