class_name Hud
extends CanvasLayer

signal menu_pressed

func _ready() -> void:
	%MenuButton.pressed.connect(func() -> void: menu_pressed.emit())
	# the MENU button shouldn't steal keyboard focus from gameplay
	%MenuButton.focus_mode = Control.FOCUS_NONE

func set_shots(n: int) -> void:
	%Shots.text = "STONES: %d" % n

func set_power(ratio: float) -> void:
	%PowerBack.visible = ratio > 0.0
	%PowerFill.offset_right = 4.0 + 296.0 * clampf(ratio, 0.0, 1.0)

func banner(title: String, sub: String) -> void:
	%Banner.text = title
	%BannerSub.text = sub
	%BannerSub.visible = sub != ""
	%BannerCenter.visible = true

func clear_banner() -> void:
	%BannerCenter.visible = false
