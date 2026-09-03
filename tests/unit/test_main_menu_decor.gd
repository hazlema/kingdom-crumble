extends GutTest


func test_windmill_wheel_spins_on_the_menu() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	# The wheel moved under the owner's animated "menu" wrapper (intro).
	var wheel: NarfDecor = menu.get_node("menu/WindmillWheel")
	assert_not_null(wheel.texture, "rotor art loaded")
	assert_eq(wheel.behavior, NarfDecor.Behavior.SPIN)
	assert_eq(wheel.pivot, NarfDecor.Pivot.CENTER)
	var r0 := wheel.rotation
	await wait_seconds(0.3)
	assert_gt(wheel.rotation, r0, "the kingdom's first moving scenery turns")
