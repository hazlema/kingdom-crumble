extends Node

const TIER_DIR := "res://resources/difficulty"

var preset: DifficultyPreset
var tier := ""

func load_tier(tier_name: String) -> bool:
	var path := "%s/%s.tres" % [TIER_DIR, tier_name]
	if not ResourceLoader.exists(path):
		return false
	preset = load(path)
	tier = tier_name
	return true
