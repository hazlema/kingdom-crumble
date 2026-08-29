# src/level/backdrop_mode.gd
class_name BackdropMode
extends RefCounted

const DIM_ALPHA := 0.2

var active := false

func toggle() -> float:
	active = not active
	return DIM_ALPHA if active else 1.0
