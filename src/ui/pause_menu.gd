class_name PauseMenu
extends CanvasLayer

# ESC pause menu. Owns the ESC key and the tree pause entirely: ESC
# opens it (pausing the game) and closes it (resuming). The level only
# listens for restart/quit. Runs in PROCESS_MODE_ALWAYS so it works
# while the tree is paused; music keeps playing (MusicDirector is
# ALWAYS too) so the volume slider gives live feedback.

signal restart_requested
signal quit_requested

@onready var _resume: Button = %Resume
@onready var _restart: Button = %RestartLevel
@onready var _quit: Button = %QuitToTitle
@onready var _music_slider: HSlider = %MusicSlider

func _ready() -> void:
	visible = false
	_resume.pressed.connect(close)
	_restart.pressed.connect(func() -> void:
		close()
		restart_requested.emit())
	_quit.pressed.connect(func() -> void:
		close()
		quit_requested.emit())
	_music_slider.value = Music.get_volume_linear()
	_music_slider.value_changed.connect(Music.set_volume_linear)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		close() if visible else open()
		get_viewport().set_input_as_handled()

func open() -> void:
	visible = true
	get_tree().paused = true
	_resume.grab_focus()

func close() -> void:
	visible = false
	get_tree().paused = false
