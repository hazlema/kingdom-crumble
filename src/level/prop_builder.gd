class_name PropBuilder
extends RefCounted

# Spawns non-crate pieces (class static/trampoline) as StaticBody2D
# geometry. Props are unscored scenery-with-collision: never in the
# "crates" group, never trigger targets. Unknown ids (missing pack,
# typo) warn and skip — the level still plays (spec §4).

const CELL_W := 64.0  # EditorGrid.CELL
const CELL_H := 63.0  # EditorGrid.ROW_H


static func spawn_props(parent: Node, layout: LevelLayout) -> Array[StaticBody2D]:
	var out: Array[StaticBody2D] = []
	for p in layout.props:
		var body := spawn_one(parent, p)
		if body != null:
			out.append(body)
	return out


static func spawn_one(parent: Node, prop: Dictionary) -> StaticBody2D:
	var id := str(prop.get("id", ""))
	var e := Pieces.entry(id)
	if e.is_empty() or e["class"] == "crate":
		push_warning("PropBuilder: unknown or non-prop id '%s' — skipping" % id)
		return null
	var cells: Vector2i = e["cells"]
	var anchor := Vector2(float(prop["x"]), float(prop["y"]))
	var body := StaticBody2D.new()
	body.position = footprint_center(anchor, cells)
	body.add_to_group("props")
	body.set_meta("prop_id", id)
	body.set_meta("anchor_cell", EditorGrid.world_to_cell(anchor))
	var size := Vector2(cells.x * CELL_W, cells.y * CELL_H)
	if e["class"] == "trampoline" and e["tilt"] != 0:
		var poly := CollisionPolygon2D.new()
		var hw := size.x / 2.0
		var hh := size.y / 2.0
		if e["tilt"] < 0:  # high edge on the LEFT, ramp falls to the right
			poly.polygon = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		else:  # high edge on the RIGHT
			poly.polygon = PackedVector2Array([Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		body.add_child(poly)
	else:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		body.add_child(shape)
	if e["class"] == "trampoline":
		var mat := PhysicsMaterial.new()
		mat.bounce = e["bounce"]
		body.physics_material_override = mat
	var sprite := Sprite2D.new()
	sprite.texture = e["texture"]
	body.add_child(sprite)
	parent.add_child(body)
	return body


# Anchor = leftmost bottom-most cell center; footprint extends +x/right
# and up (grid y index increases upward, world y decreases).
static func footprint_center(anchor_world: Vector2, cells: Vector2i) -> Vector2:
	return anchor_world + Vector2((cells.x - 1) * CELL_W / 2.0, -(cells.y - 1) * CELL_H / 2.0)
