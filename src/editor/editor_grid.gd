class_name EditorGrid
extends RefCounted

# 64px build grid (spec §4). Row 0 sits on the ground; the zone starts
# a safety margin right of the catapult.

const CELL := 64
const MIN_X := 608.0
const MAX_X := 3200.0
const FLOOR_Y := 600.0
const MAX_ROWS := 8

static func cols() -> int:
	return int((MAX_X - MIN_X) / CELL)

static func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(MIN_X + c.x * CELL + CELL / 2.0,
		FLOOR_Y - c.y * CELL - CELL / 2.0)

static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - MIN_X) / CELL)),
		int(floor((FLOOR_Y - p.y) / CELL)))

static func in_zone(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < cols() and c.y >= 0 and c.y < MAX_ROWS
