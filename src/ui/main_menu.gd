extends Control

func _ready() -> void:
	$Buttons/Chill.pressed.connect(_start.bind("chill"))
	$Buttons/HeartPumper.pressed.connect(_start.bind("heartpumper"))
	$Buttons/Hardcore.pressed.connect(_start.bind("hardcore"))
	$Buttons/Editor.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/editor.tscn"))
	$Buttons/Quit.pressed.connect(_quit)

func _start(tier: String) -> void:
	Settings.load_tier(tier)
	var chain := LevelChain.entries()
	if not chain.is_empty():
		Level.next_layout_path = chain[LevelChain.frontier(chain, tier)]["path"]
	get_tree().change_scene_to_file("res://scenes/level.tscn")

func _quit() -> void:
	get_tree().quit()
