extends Node

# Per-tier level completion log (progression spec §2). Sections are
# tiers, keys are level stems: [chill] pineapple=true. Twin of the
# Unlocks store. Flags only, never code.

var path := "user://progress.cfg"
var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(path)  # missing file = fresh conqueror, not an error
	_migrate_bare_stems()


# Pre-namespace records were bare stems shared by built-in and user
# levels alike. Collided history can't say WHICH was cleared, so bare
# stems map to the built-in when one exists (auditor's call), else to
# the user level.
func _migrate_bare_stems() -> void:
	var builtin_stems: Dictionary = {}
	for bp in LevelStore.list_builtin():
		builtin_stems[bp.get_file().get_basename()] = true
	var changed := false
	for section in _cfg.get_sections():
		for key in _cfg.get_section_keys(section):
			if (key as String).contains(":"):
				continue
			var ns := "builtin" if builtin_stems.has(key) else "user"
			_cfg.set_value(section, "%s:%s" % [ns, key], _cfg.get_value(section, key))
			_cfg.erase_section_key(section, key)
			changed = true
	if changed:
		_cfg.save(path)


func mark_cleared(tier: String, stem: String) -> void:
	_cfg.set_value(tier, stem, true)
	_cfg.save(path)


func is_cleared(tier: String, stem: String) -> bool:
	return bool(_cfg.get_value(tier, stem, false))


func use_path(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	_cfg.load(path)
