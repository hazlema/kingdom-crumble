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
	# FIRE! is a screen-sized spacebar: hold to charge, release to loose.
	# ALWAYS so the release still lands if the tree pauses mid-press —
	# a lost button_up left "fire" stuck down and froze the scout camera.
	%FireButton.process_mode = Node.PROCESS_MODE_ALWAYS
	%FireButton.focus_mode = Control.FOCUS_NONE
	%FireButton.button_down.connect(func() -> void: Input.action_press("fire"))
	%FireButton.button_up.connect(func() -> void: Input.action_release("fire"))

# Alt-tabbing away mid-charge eats the release the same way.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.action_release("fire")

func set_shots(n: int) -> void:
	%Shots.text = "STONES: %d" % n

func set_crates(standing: int, total: int) -> void:
	if %CrateIcon.texture == null:
		%CrateIcon.texture = EditorAssets.texture_for("crate-wood")
	%Crates.text = "CRATES: %d/%d" % [standing, total]

func set_power(ratio: float) -> void:
	# always on screen (owner call) — an empty bar reads "ready", and a
	# bar that vanishes mid-stick was hiding the stuck-fire bug too
	%PowerBar.visible = true
	%PowerBar.value = ratio

func banner(title: String, sub: String) -> void:
	%Banner.text = title
	%BannerSub.text = sub
	%BannerSub.visible = sub != ""
	%BannerCenter.visible = true

func clear_banner() -> void:
	%BannerCenter.visible = false

func set_buffs(buffs: Array[StringName]) -> void:
	# remove_child before queue_free: chain collections call this twice
	# in one physics frame and stale icons must not be double-counted
	for c in $BuffRow.get_children():
		$BuffRow.remove_child(c)
		c.queue_free()
	for b in buffs:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = EditorAssets.texture_for(BUFF_ICONS.get(b, ""))
		$BuffRow.add_child(icon)
