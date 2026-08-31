class_name DifficultyPreset
extends Resource

@export var crate_natural_bounce := 0.6
# Per-tier crate settle feel; -1 = unset, crates use the defaults in
# crate.gd (LINEAR_DAMP / ANGULAR_DAMP).
@export var crate_linear_damp := -1.0
@export var crate_angular_damp := -1.0
@export var impact_force := 3.0
@export var shots_per_level := 5
@export var charge_time := 1.5
@export var min_launch_speed := 400.0
@export var max_launch_speed := 1400.0
