class_name IntroDialog
extends Control

# The level speaks (intro-dialog spec §2): optional level text shown at
# every start and re-popped from the HUD's info icon. Pauses the world
# while open; any tap or key dismisses.

signal closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open(title: String, text: String) -> void:
	%Title.text = title
	%Body.text = text
	visible = true
	get_tree().paused = true


func dismiss() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var tap: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	var key := (
		event.is_action_pressed("ui_accept")
		or event.is_action_pressed("fire")
		or event.is_action_pressed("menu")
	)
	if tap or key:
		get_viewport().set_input_as_handled()
		dismiss()
