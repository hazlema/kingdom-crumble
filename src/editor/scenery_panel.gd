class_name SceneryPanel
extends PanelContainer

signal background_picked(id: String)
signal add_image_requested
signal done

const BACKGROUNDS: Array[String] = ["meadow"]


func _ready() -> void:
	for bg in BACKGROUNDS:
		%BackgroundList.add_item(bg)
	%BackgroundList.item_selected.connect(
		func(i: int) -> void: background_picked.emit(%BackgroundList.get_item_text(i))
	)
	%AddImageBtn.pressed.connect(func() -> void: add_image_requested.emit())
	%DoneBtn.pressed.connect(func() -> void: done.emit())
