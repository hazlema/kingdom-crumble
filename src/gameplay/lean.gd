class_name Lean
extends RefCounted

const MIN_DEG := 15.0
const MAX_DEG := 75.0
const MIN_RAD := deg_to_rad(15.0)
const MAX_RAD := deg_to_rad(75.0)


static func is_lean_angle(rotation_rad: float) -> bool:
	var tilt := absf(wrapf(rotation_rad, -PI, PI))
	return tilt >= MIN_RAD and tilt <= MAX_RAD
