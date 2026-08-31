class_name Hud
extends CanvasLayer

signal menu_pressed

const BUFF_ICONS := {
	&"exploding": "skull",
	&"multishot": "crate-blue",
	&"super_bounce": "crate-green",
}

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
	%PowerBar.visible = ratio > 0.0
	%PowerBar.value = ratio

func banner(title: String, sub: String) -> void:
	%Banner.text = title
	%BannerSub.text = sub
	%BannerSub.visible = sub != ""
	%BannerCenter.visible = true

func clear_banner() -> void:
	%BannerCenter.visible = false

func set_buffs(buffs: Array[StringName]) -> void:
	for c in $BuffRow.get_children():
		c.queue_free()
	for b in buffs:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = EditorAssets.texture_for(BUFF_ICONS.get(b, ""))
		$BuffRow.add_child(icon)
