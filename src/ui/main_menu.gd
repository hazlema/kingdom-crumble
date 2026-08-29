extends Control

func _ready() -> void:
	$Buttons/Chill.pressed.connect(_start.bind("chill"))
	$Buttons/HeartPumper.pressed.connect(_start.bind("heartpumper"))
	$Buttons/Hardcore.pressed.connect(_start.bind("hardcore"))

func _start(tier: String) -> void:
	Settings.load_tier(tier)
	get_tree().change_scene_to_file("res://scenes/level_01.tscn")
