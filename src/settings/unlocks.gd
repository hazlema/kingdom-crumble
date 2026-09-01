extends Node

# Persistent unlock flags — the game's first save data (spec §4).
# Flags only, never code. ConfigFile at user://unlocks.cfg.

var path := "user://unlocks.cfg"
var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(path)  # a missing file is a fresh player, not an error


func has_flag(flag: String) -> bool:
	return bool(_cfg.get_value("unlocks", flag, false))


func set_flag(flag: String) -> void:
	_cfg.set_value("unlocks", flag, true)
	_cfg.save(path)


func use_path(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	_cfg.load(path)
