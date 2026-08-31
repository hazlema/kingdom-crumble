extends GutTest

# Owner tunes crate damping per difficulty tier: DifficultyPreset may
# carry crate_linear_damp / crate_angular_damp; when unset (-1) crates
# fall back to the defaults in crate.gd.

var _saved_preset: DifficultyPreset
var _saved_tier: String

func before_each() -> void:
	_saved_preset = Settings.preset
	_saved_tier = Settings.tier

func after_each() -> void:
	Settings.preset = _saved_preset
	Settings.tier = _saved_tier

func _spawn_crate() -> Crate:
	var c: Crate = load("res://scenes/crate.tscn").instantiate()
	c.freeze = true
	add_child_autofree(c)
	return c

func test_preset_damp_overrides_defaults() -> void:
	var p := DifficultyPreset.new()
	p.crate_linear_damp = 1.4
	p.crate_angular_damp = 9.0
	Settings.preset = p
	var c := _spawn_crate()
	assert_almost_eq(c.linear_damp, 1.4, 0.001)
	assert_almost_eq(c.angular_damp, 9.0, 0.001)

func test_unset_preset_damp_falls_back_to_crate_defaults() -> void:
	Settings.preset = DifficultyPreset.new()  # fields left at -1
	var c := _spawn_crate()
	assert_almost_eq(c.linear_damp, Crate.LINEAR_DAMP, 0.001)
	assert_almost_eq(c.angular_damp, Crate.ANGULAR_DAMP, 0.001)

func test_no_preset_at_all_uses_crate_defaults() -> void:
	Settings.preset = null
	var c := _spawn_crate()
	assert_almost_eq(c.linear_damp, Crate.LINEAR_DAMP, 0.001)
	assert_almost_eq(c.angular_damp, Crate.ANGULAR_DAMP, 0.001)
