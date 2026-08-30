class_name LevelStore
extends RefCounted

# Finds and persists LevelLayout files. Built-ins live in the project;
# player-made levels live in the per-user data dir (user:// — survives
# updates, works on every platform including web).

const BUILTIN_DIR := "res://levels"
const USER_DIR := "user://levels"

static func list_builtin() -> Array[String]:
	return _list(BUILTIN_DIR)

static func list_user() -> Array[String]:
	return _list(USER_DIR)

static func load_layout(path: String) -> LevelLayout:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as LevelLayout

static func save_user(layout: LevelLayout, name: String) -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := "%s/%s.tres" % [USER_DIR, name.validate_filename()]
	var err := ResourceSaver.save(layout, path)
	return path if err == OK else ""

static func _list(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		var fname := file.trim_suffix(".remap")
		if fname.get_extension() == "tres":
			out.append("%s/%s" % [dir_path, fname])
	out.sort()
	return out
