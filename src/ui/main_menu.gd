extends Control

func _ready() -> void:
	$Buttons/Chill.pressed.connect(_start.bind("chill"))
	$Buttons/HeartPumper.pressed.connect(_start.bind("heartpumper"))
	$Buttons/Hardcore.pressed.connect(_start.bind("hardcore"))
	$Buttons/Quit.pressed.connect(_quit)

func _start(tier: String) -> void:
	Settings.load_tier(tier)
	get_tree().change_scene_to_file("res://scenes/level.tscn")

func _quit() -> void:
	get_tree().quit()
