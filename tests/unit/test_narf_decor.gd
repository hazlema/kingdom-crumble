extends GutTest

# NarfKit's founding citizen: living scenery. Kit rule — no host-game
# references; everything through exports.


func _piece(b: NarfDecor.Behavior) -> NarfDecor:
	var d := NarfDecor.new()
	d.behavior = b
	d.speed = 1.0
	d.amplitude = 10.0
	add_child_autofree(d)
	return d


func test_spin_turns_continuously() -> void:
	var d := _piece(NarfDecor.Behavior.SPIN)
	var r0 := d.rotation
	await wait_seconds(0.3)
	assert_gt(d.rotation, r0, "the wheel turns")


func test_sway_oscillates_around_home() -> void:
	var d := _piece(NarfDecor.Behavior.SWAY)
	d.rotation = 0.5
	d._home_rotation = 0.5
	await wait_seconds(0.3)
	assert_between(d.rotation, 0.5 - deg_to_rad(10.5), 0.5 + deg_to_rad(10.5), "tilts near home")


func test_bob_moves_vertically_within_amplitude() -> void:
	var d := _piece(NarfDecor.Behavior.BOB)
	await wait_seconds(0.3)
	assert_between(d.position.y, -10.5, 10.5, "bobs around home")


func test_none_sits_perfectly_still() -> void:
	var d := _piece(NarfDecor.Behavior.NONE)
	d.rotation = 1.0
	await wait_seconds(0.2)
	assert_eq(d.rotation, 1.0)
