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


func test_pivot_anchors_put_the_named_point_on_the_origin() -> void:
	var d := NarfDecor.new()
	var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	d.texture = ImageTexture.create_from_image(img)
	add_child_autofree(d)
	var expect := {
		NarfDecor.Pivot.TOP_LEFT: Vector2(0, 0),
		NarfDecor.Pivot.TOP_CENTER: Vector2(-20, 0),
		NarfDecor.Pivot.TOP_RIGHT: Vector2(-40, 0),
		NarfDecor.Pivot.CENTER_LEFT: Vector2(0, -10),
		NarfDecor.Pivot.CENTER: Vector2(-20, -10),
		NarfDecor.Pivot.CENTER_RIGHT: Vector2(-40, -10),
		NarfDecor.Pivot.LOWER_LEFT: Vector2(0, -20),
		NarfDecor.Pivot.LOWER_CENTER: Vector2(-20, -20),
		NarfDecor.Pivot.LOWER_RIGHT: Vector2(-40, -20),
	}
	for p in expect:
		d.pivot = p
		assert_eq(d.offset, expect[p], "pivot %d anchors correctly" % p)
	assert_false(d.centered, "pivot mode owns placement")
