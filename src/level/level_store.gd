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
	return null if text == "" else LevelJson.parse(text)

static func save_user(layout: LevelLayout, stem: String) -> String:
	var safe := sanitize_stem(stem)
	if safe == "":
		return ""
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := "%s/%s.json" % [USER_DIR, safe]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(LevelJson.serialize(layout))
	f.close()
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
