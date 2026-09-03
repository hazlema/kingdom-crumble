extends Control


func _ready() -> void:
	# The meadow's overture (owner pick — fits the theme). Chill-tier, so
	# starting a Chill run continues it seamlessly; other tiers switch.
	Music.play_track("res://music/chill/Mossy-Lantern.mp3", "chill")
	$Buttons/Chill.pressed.connect(_start.bind("chill"))
	$Buttons/HeartPumper.pressed.connect(_start.bind("heartpumper"))
	$Buttons/Hardcore.pressed.connect(_start.bind("hardcore"))
	$Buttons/Editor.pressed.connect(
		func() -> void: get_tree().change_scene_to_file("res://scenes/editor.tscn")
	)
	# Browsers only grant fullscreen from a user tap, so it's a button —
	# and only a web problem; desktop players have F11 and a window manager.
	$Buttons/Fullscreen.visible = OS.has_feature("web")
	$Buttons/Fullscreen.pressed.connect(_toggle_fullscreen)
	$Buttons/Quit.pressed.connect(_quit)


func _toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN
	)


func _start(tier: String) -> void:
	Settings.load_tier(tier)
	var chain := LevelChain.entries()
	if not chain.is_empty():
		Level.next_layout_path = chain[LevelChain.frontier(chain, tier)]["path"]
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func _quit() -> void:
	get_tree().quit()
