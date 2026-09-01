class_name StatCard
extends PanelContainer

# The unified HUD panel (pretty-pass spec §2), transcribed from the
# owner's comps. Values in, pixels out — no game logic.

const BUFF_ICONS := {
	&"exploding": "skull",
	&"multishot": "crate-blue",
	&"super_bounce": "crate-green",
}


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
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = EditorAssets.texture_for(BUFF_ICONS.get(b, ""))
		%BuffRow.add_child(icon)
