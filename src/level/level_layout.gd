class_name LevelLayout
extends Resource

# A level as pure data — the generic level scene builds itself from
# one of these. Built-ins ship in res://levels/; player-made levels
# save to user://levels/ so they can be shared as single files.
# (Future: crate types, critters, decorations.)

@export var title := "Untitled"
@export var author := ""
@export var shots_override := 0  # 0 = use the difficulty preset
@export var crates: Array[Vector2] = []
