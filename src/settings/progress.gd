extends Node

# Per-tier level completion log (progression spec §2). Sections are
# tiers, keys are level stems: [chill] pineapple=true. Twin of the
# Unlocks store. Flags only, never code.

var path := "user://progress.cfg"
var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(path)  # missing file = fresh conqueror, not an error


func mark_cleared(tier: String, stem: String) -> void:
	_cfg.set_value(tier, stem, true)
	_cfg.save(path)


func is_cleared(tier: String, stem: String) -> bool:
	return bool(_cfg.get_value(tier, stem, false))


func use_path(p: String) -> void:
	path = p
	_cfg = ConfigFile.new()
	_cfg.load(path)
