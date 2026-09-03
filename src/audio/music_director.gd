class_name MusicDirector
extends Node

const EXTENSIONS := ["ogg", "mp3", "wav"]
const SETTINGS_PATH := "user://settings.cfg"

var _player := AudioStreamPlayer.new()
var _current_track := ""
var _tier := ""
# Background music sits under the game, not on top of it (owner: 0.25).
var _volume := 0.25
# Effects ride the Sfx bus (boom, shutter) — full volume by default.
var _sfx_volume := 1.0


func _ready() -> void:
	# keep the soundtrack alive while the tree is paused (ESC menu)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.bus = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
	add_child(_player)
	_player.finished.connect(_on_track_finished)
	# Apply the remembered volume (an untouched slider used to mean full
	# blast — the default was never pushed to the player).
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # missing file = fresh install, default rules
	set_volume_linear(float(cfg.get_value("audio", "music_volume", _volume)))
	set_sfx_volume_linear(float(cfg.get_value("audio", "sfx_volume", _sfx_volume)))


func set_volume_linear(v: float) -> void:
	_volume = clampf(v, 0.0, 1.0)
	_player.volume_db = linear_to_db(maxf(_volume, 0.0001))
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep future keys in this file intact
	cfg.set_value("audio", "music_volume", _volume)
	cfg.save(SETTINGS_PATH)


func get_volume_linear() -> float:
	return _volume


func set_sfx_volume_linear(v: float) -> void:
	_sfx_volume = clampf(v, 0.0, 1.0)
	var idx := AudioServer.get_bus_index("Sfx")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(_sfx_volume, 0.0001)))
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep sibling keys intact
	cfg.set_value("audio", "sfx_volume", _sfx_volume)
	cfg.save(SETTINGS_PATH)


func get_sfx_volume_linear() -> float:
	return _sfx_volume


func play_tier(tier: String) -> void:
	# Levels call this on every load. Same tier + song still going =
	# let it ride; a level change is not a reason to cut the music.
	if tier == _tier and _player.playing:
		return
	_tier = tier
	_play_next()


func stop() -> void:
	_tier = ""
	_player.stop()


func _play_next() -> void:
	var pool := list_pool(_tier)
	var track := pick_track(pool, _current_track)
	if track == "":
		return
	_current_track = track
	_player.stream = load(track)
	_player.play()


func _on_track_finished() -> void:
	if _tier != "":
		_play_next()


static func pick_track(pool: Array, exclude: String = "") -> String:
	if pool.is_empty():
		return ""
	var options := pool.filter(func(p): return p != exclude)
	if options.is_empty():
		options = pool
	return options[randi() % options.size()]


static func list_pool(tier: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://music/%s" % tier)
	if dir == null:
		return out
	for file in dir.get_files():
		var stripped := _strip_export_suffixes(file)
		if stripped.get_extension() in EXTENSIONS:
			var path := "res://music/%s/%s" % [tier, stripped]
			if not out.has(path):
				out.append(path)
	out.sort()
	return out


# Exported builds don't list the original filenames: imported audio
# shows as "track.mp3.import" (and remapped resources as "*.remap").
# Strip both, dedupe upstream — this bug shipped one silent kingdom.
static func _strip_export_suffixes(file: String) -> String:
	return file.trim_suffix(".remap").trim_suffix(".import")
