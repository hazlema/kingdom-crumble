extends GutTest

const SCENE := "res://src/effects/HitTextEffect.tscn"


func test_text_set_before_add_child_survives_and_applies() -> void:
	var fx: HitTextEffect = load(SCENE).instantiate()
	fx.text = "+Explosive Shot"
	add_child(fx)
	assert_eq(fx.get_node("ColorRect/Label").text, "+Explosive Shot")
	assert_gt(fx.get_node("ColorRect").size.x, 33.0, "panel should grow to fit long text")


func test_floats_up_fades_and_frees_itself() -> void:
	var fx: HitTextEffect = load(SCENE).instantiate()
	fx.position = Vector2(100, 200)
	add_child(fx)
	await wait_seconds(0.5)
	assert_lt(fx.position.y, 200.0, "should drift upward")
	assert_lt(fx.modulate.a, 1.0, "should be fading")
	await wait_seconds(1.0)
	assert_false(is_instance_valid(fx), "should free itself when done")
