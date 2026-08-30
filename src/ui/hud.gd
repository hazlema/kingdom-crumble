class_name Hud
extends CanvasLayer

signal menu_pressed

func _ready() -> void:
	%MenuButton.pressed.connect(func() -> void: menu_pressed.emit())
	%MenuButton.focus_mode = Control.FOCUS_NONE
	# FIRE! is a screen-sized spacebar: hold to charge, release to loose
	%FireButton.focus_mode = Control.FOCUS_NONE
	%FireButton.button_down.connect(func() -> void: Input.action_press("fire"))
	%FireButton.button_up.connect(func() -> void: Input.action_release("fire"))

func set_shots(n: int) -> void:
	%Shots.text = "STONES: %d" % n

func set_power(ratio: float) -> void:
	var show := ratio > 0.0
	%PowerBack.visible = show
	%PowerHeart.visible = show
	%PowerFill.offset_right = 7.0 + 294.0 * clampf(ratio, 0.0, 1.0)

func banner(title: String, sub: String) -> void:
	%Banner.text = title
	%BannerSub.text = sub
	%BannerSub.visible = sub != ""
	%BannerCenter.visible = true

func clear_banner() -> void:
	%BannerCenter.visible = false
