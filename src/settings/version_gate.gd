extends Node

# Boot-order first (see [autoload]): when the TESTING box is checked and
# the game version changed since last run, wipe tester progress/unlocks
# so every build starts fresh. Unchecked (release), it only records the
# version — players never lose progress to an update.
#
# The dials live in Project Settings:
#   Application > Config > Version        (the version string — bump per build)
#   Application > Config > Testing Reset  (the checkbox: ON for testing builds;
#   custom top-level categories don't render in the settings panel — riding
#   the built-in Config category keeps both dials side by side)

const STAMP_PATH := "user://version.cfg"
const WIPE_FILES: Array[String] = ["user://progress.cfg", "user://unlocks.cfg"]


func _init() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var testing := bool(ProjectSettings.get_setting("application/config/testing_reset", false))
	apply(version, testing, WIPE_FILES, STAMP_PATH)


## Pure-ish worker, sandboxable for tests. Returns true when it wiped.
static func apply(version: String, testing: bool, files: Array[String], stamp_path: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(stamp_path)  # missing file is fine — last stays ""
	var last := str(cfg.get_value("meta", "version", ""))
	var wiped := false
	if testing and version != "" and last != "" and last != version:
		for f in files:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		wiped = true
		print("VersionGate: testing build %s -> %s — tester progress wiped" % [last, version])
	cfg.set_value("meta", "version", version)
	cfg.save(stamp_path)
	return wiped
