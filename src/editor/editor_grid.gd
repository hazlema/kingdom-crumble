class_name EditorGrid
extends RefCounted

# Build grid (spec §4). Row 0 sits on the ground; the zone starts a
# safety margin right of the catapult. Cells match the crate's physical
# shape (64 wide x 63 tall, resting center 569 = ground 600 minus half
# height 31) so stacks spawn already settled — a 64px row pitch left
# air gaps and every stack dropped and rattled when the level started.

const CELL := 64  # column pitch = crate width
const ROW_H := 63  # row pitch = crate height
const MIN_X := 608.0
const MAX_X := 3200.0
const FLOOR_Y := 600.0
const REST_Y := 569.0  # center of a crate resting on the ground
const MAX_ROWS := 8


static func cols() -> int:
	return int((MAX_X - MIN_X) / CELL)


# Snap a world point to the nearest scenery snap corner: the crate-cell
# lattice (column left-edges every CELL px from MIN_X; row TOP edges every
# ROW_H px, derived from REST_Y so a snapped image sits flush with crates).
static func snap_scenery(p: Vector2) -> Vector2:
	var oy := REST_Y - ROW_H / 2.0  # top edge of the ground row's cell
	return Vector2(
		MIN_X + roundf((p.x - MIN_X) / CELL) * CELL,
		oy + roundf((p.y - oy) / ROW_H) * ROW_H
	)


static func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(MIN_X + c.x * CELL + CELL / 2.0, REST_Y - c.y * ROW_H)


static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - MIN_X) / CELL)), int(round((REST_Y - p.y) / ROW_H)))


static func in_zone(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < cols() and c.y >= 0 and c.y < MAX_ROWS
