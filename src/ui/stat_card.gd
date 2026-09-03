class_name StatCard
extends PanelContainer

# The unified HUD panel (pretty-pass spec §2), transcribed from the
# owner's comps. Values in, pixels out — no game logic.

signal info_pressed
signal check_held(held: bool)

const BUFF_ICONS := {
	&"exploding": "skull",
	&"multishot": "crate-blue",
	&"super_bounce": "crate-green",
}


func _ready() -> void:
	%InfoBtn.pressed.connect(func() -> void: info_pressed.emit())
	# Touch home for the H check (playtester ask): press-and-hold the
	# CRATES row. A finger sliding off the row counts as release.
	%CratesRow.gui_input.connect(_on_crates_row_input)
	%CratesRow.mouse_exited.connect(func() -> void: check_held.emit(false))


func _on_crates_row_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		check_held.emit(event.pressed)


func set_info(has_intro: bool) -> void:
	%InfoBtn.visible = has_intro


func set_title(t: String) -> void:
	%Title.text = t


func set_level_no(n: int) -> void:
	%LvlChip.visible = n >= 1
	if n >= 1:
		%LvlChip.text = "LVL %d" % n


func set_shots(n: int) -> void:
	%ShotsValue.text = str(n)


func set_crates(standing: int, total: int) -> void:
	%CratesValue.text = "%d/%d" % [standing, total]


func set_power(ratio: float) -> void:
	%PowerBar.value = ratio


func set_buffs(buffs: Array[StringName]) -> void:
	%BuffSection.visible = not buffs.is_empty()
	for c in %BuffRow.get_children():
		%BuffRow.remove_child(c)
		c.queue_free()
	for b in buffs:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = EditorAssets.texture_for(BUFF_ICONS.get(b, ""))
		%BuffRow.add_child(icon)
