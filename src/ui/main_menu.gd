extends Control

# The logo intro plays once per launch — returning to the menu skips to
# the settled pose (owner: "only one animation per game else it gets
# annoying"). Static var: survives scene changes, resets with the game.
static var _intro_played := false


func _ready() -> void:
	# The meadow's overture (owner pick — fits the theme). Chill-tier, so
	# starting a Chill run continues it seamlessly; other tiers switch.
	Music.play_track("res://music/chill/Mossy-Lantern.mp3", "chill")
	# Roll the owner's logo intro — or, on a return visit, jump straight
	# to its final frame (every track lands in the settled pose at once).
	$AnimationPlayer.play("intro")
	if _intro_played:
		$AnimationPlayer.seek($AnimationPlayer.current_animation_length, true)
	else:
		_intro_played = true
	$menu/Buttons/Chill.pressed.connect(_start.bind("chill"))
	$menu/Buttons/HeartPumper.pressed.connect(_start.bind("heartpumper"))
	$menu/Buttons/Hardcore.pressed.connect(_start.bind("hardcore"))
	$menu/Buttons/Editor.pressed.connect(
		func() -> void: get_tree().change_scene_to_file("res://scenes/editor.tscn")
	)
	# Browsers only grant fullscreen from a user tap, so it's a button —
	# and only a web problem; desktop players have F11 and a window manager.
	$menu/Buttons/Fullscreen.visible = OS.has_feature("web")
	$menu/Buttons/Fullscreen.pressed.connect(_toggle_fullscreen)
	$menu/Buttons/Quit.pressed.connect(_quit)


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
