class_name LevelStore
extends RefCounted

# Built-ins ship in res://levels; player levels live in user://levels. Both list alphabetically — stems are the ordering tool.

const BUILTIN_DIR := "res://levels"
const USER_DIR := "user://levels"


static func list_builtin() -> Array[String]:
	return _list_dir(BUILTIN_DIR)


static func list_user() -> Array[String]:
	return _list_dir(USER_DIR)


static func _list_dir(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "json":
			out.append("%s/%s" % [dir_path, f])
	out.sort()
	return out


static func load_level(path: String) -> LevelLayout:
	var text := _read(path)
	if text == "":
		LevelJson.last_error = "couldn't read the file"
		return null
	return LevelJson.parse(text)


# Saves set LevelJson.last_error on failure so callers can tell the
# author WHY. The document is validated before any file is opened
# (audit P1: the editor could save levels its own loader refused),
# and an existing file is only replaced via a temp+rename so a failed
# write never destroys the previous good save (audit P2).
static func save_user(layout: LevelLayout, stem: String) -> String:
	var safe := sanitize_stem(stem)
	if safe == "":
		LevelJson.last_error = "that name has no usable characters"
		return ""
	var text := LevelJson.serialize(layout)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		LevelJson.last_error = "internal: serialize produced non-JSON"
		return ""
	var verdict := LevelJson.validate(parsed)
	if verdict != "":
		LevelJson.last_error = verdict
		return ""
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := "%s/%s.json" % [USER_DIR, safe]
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		LevelJson.last_error = "couldn't open the file for writing"
		return ""
	f.store_string(text)
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		LevelJson.last_error = "couldn't replace the previous save"
		DirAccess.remove_absolute(tmp)
		return ""
	LevelJson.last_error = ""
	return path


static func sanitize_stem(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()
