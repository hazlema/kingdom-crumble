extends GutTest


func _dialog() -> IntroDialog:
	var d: IntroDialog = load("res://scenes/ui/intro_dialog.tscn").instantiate()
	add_child_autofree(d)
	return d


func after_each() -> void:
	get_tree().paused = false


func test_hidden_initially() -> void:
	assert_false(_dialog().visible)


func test_open_shows_pauses_and_fills() -> void:
	var d := _dialog()
	d.open("THE MEADOW", "Aim for the base!")
	assert_true(d.visible)
	assert_true(get_tree().paused, "world holds its breath while the level speaks")
	assert_eq(d.get_node("%Title").text, "THE MEADOW")
	assert_eq(d.get_node("%Body").text, "Aim for the base!")


func test_accept_dismisses_unpauses_and_signals() -> void:
	var d := _dialog()
	watch_signals(d)
	d.open("T", "hello")
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	d._input(ev)
	assert_false(d.visible)
	assert_false(get_tree().paused)
	assert_signal_emitted(d, "closed")


func test_reopens_after_dismiss() -> void:
	var d := _dialog()
	d.open("T", "hello")
	d.dismiss()
	d.open("T", "hello again")
	assert_true(d.visible)
	assert_eq(d.get_node("%Body").text, "hello again")


func test_level_with_intro_speaks_at_start() -> void:
	Level.next_layout = LevelLayout.new()
	Level.next_layout.title = "Talky"
	Level.next_layout.intro = "Welcome!"
	Level.next_layout.crates = [
		{"x": 800.0, "y": 569.0, "type": "crate-wood"},
	]
	Level.return_to_editor = true
	var lvl: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_process_frames(5)
	assert_true(lvl.get_node("%IntroDialog").visible, "the level speaks at start")
	lvl.get_node("%IntroDialog").dismiss()
	assert_false(get_tree().paused, "dismiss unpauses the tree")
	Level.return_to_editor = false
