class_name LevelJumpDialog
extends Control

# Pretty-pass card grid level picker (progression spec §4). Rebuilt on
# every open so folder changes and fresh checkmarks always show.

signal level_picked(path: String)

const LEVEL_CARD := preload("res://scenes/ui/level_card.tscn")


func _ready() -> void:
	%CloseBtn.pressed.connect(hide)


func open(tier: String) -> void:
	for c in %List.get_children():
		%List.remove_child(c)
		c.queue_free()
	var chain := LevelChain.entries()
	var current := _current_stem()
	var cleared_count := 0
	for i in chain.size():
		var stem: String = chain[i]["stem"]
		var cleared := Progress.is_cleared(tier, stem)
		if cleared:
			cleared_count += 1
		var card: LevelCard = LEVEL_CARD.instantiate()
		%List.add_child(card)
		card.setup(chain[i], cleared, LevelChain.is_unlocked(chain, i, tier), stem == current)
		card.picked.connect(func(path: String) -> void:
			level_picked.emit(path)
			hide())
	%ClearCount.text = "%d OF %d CLEARED" % [cleared_count, chain.size()]
	show()


func _current_stem() -> String:
	var scene := get_tree().current_scene
	if scene != null and "current_stem" in scene:
		return scene.current_stem
	return ""


func _input(event: InputEvent) -> void:
	# _input (not unhandled) so Esc closes the dialog before the pause
	# menu can react to the same key; ui_cancel covers Esc even if the
	# "menu" action is ever rebound
	if visible and (event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel")):
		hide()
		get_viewport().set_input_as_handled()
