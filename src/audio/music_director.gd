class_name MusicDirector
extends Node

const EXTENSIONS := ["ogg", "mp3", "wav"]

var _player := AudioStreamPlayer.new()
var _current_track := ""
var _tier := ""

func _ready() -> void:
	_player.bus = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
	add_child(_player)
	_player.finished.connect(_on_track_finished)

func play_tier(tier: String) -> void:
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
		# exported builds list "track.ogg.remap"; strip and re-check
		var name := file.trim_suffix(".remap")
		if name.get_extension() in EXTENSIONS:
			out.append("res://music/%s/%s" % [tier, name])
	out.sort()
	return out
