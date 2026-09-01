class_name LevelJumpDialog
extends Control

# Bare-bones in-game level picker (progression spec §4). Deliberately
# plain — the owner stylizes later. Rebuilt on every open so folder
# changes and fresh checkmarks always show.

signal level_picked(path: String)

func open(tier: String) -> void:
	for c in %List.get_children():
		%List.remove_child(c)
		c.queue_free()
	var chain := LevelChain.entries()
	for i in chain.size():
		var b := Button.new()
		var stem: String = chain[i]["stem"]
		var title: String = chain[i]["title"]
		if Progress.is_cleared(tier, stem):
			b.text = "✓  %s" % title
		elif LevelChain.is_unlocked(chain, i, tier):
			b.text = title
		else:
			b.text = "🔒  %s" % title
			b.disabled = true
		var path: String = chain[i]["path"]
		b.pressed.connect(func() -> void:
			level_picked.emit(path)
			hide())
		%List.add_child(b)
	show()

func _input(event: InputEvent) -> void:
	# _input (not unhandled) so Esc closes the dialog before the pause
	# menu can react to the same key
	if visible and event.is_action_pressed("menu"):
		hide()
		get_viewport().set_input_as_handled()
