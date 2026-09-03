class_name Hud
extends CanvasLayer

signal menu_pressed
signal info_pressed

const FIRE_STONE := preload("res://art/assets/ui/stone.png")


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
	%FireButton.icon = FIRE_STONE
	%StatCard.get_node("%CrateIcon").texture = EditorAssets.texture_for("crate-wood")
	%StatCard.info_pressed.connect(func() -> void: info_pressed.emit())
	# The crates row is touch's H key — same Input bridge as FIRE.
	%StatCard.check_held.connect(
		func(held: bool) -> void:
			if held:
				Input.action_press("check")
			else:
				Input.action_release("check")
	)


# Alt-tabbing away mid-charge eats the release the same way.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.action_release("fire")
		Input.action_release("check")


func set_shots(n: int) -> void:
	%StatCard.set_shots(n)


func set_crates(standing: int, total: int) -> void:
	%StatCard.set_crates(standing, total)


func set_power(ratio: float) -> void:
	%StatCard.set_power(ratio)


# Short-lived level-title announcement at level start — clears itself
# unless a real banner (lean bonus, cleared) has taken the stage since.
func toast(text: String) -> void:
	banner(text, "")
	get_tree().create_timer(1.8).timeout.connect(
		func() -> void:
			if %Banner.text == text and not %BannerSub.visible:
				clear_banner()
	)


func banner(title: String, sub: String) -> void:
	%Banner.text = title
	%BannerSub.text = sub
	%BannerSub.visible = sub != ""
	%BannerCenter.visible = true


func clear_banner() -> void:
	%BannerCenter.visible = false


func set_buffs(buffs: Array[StringName]) -> void:
	%StatCard.set_buffs(buffs)
	%FireButton.icon = _fire_icon_for(buffs)


func set_level_info(title: String, number: int, has_intro := false) -> void:
	%StatCard.set_title(title)
	%StatCard.set_level_no(number)
	%StatCard.set_info(has_intro)


func _fire_icon_for(buffs: Array[StringName]) -> Texture2D:
	var kinds := {}
	for b in buffs:
		kinds[b] = true
	if kinds.size() >= 2:
		return EditorAssets.texture_for("crate-gold")
	if kinds.has(&"exploding"):
		return EditorAssets.texture_for("skull")
	if kinds.has(&"super_bounce"):
		return EditorAssets.texture_for("crate-green")
	if kinds.has(&"multishot"):
		return EditorAssets.texture_for("crate-blue")
	return FIRE_STONE
