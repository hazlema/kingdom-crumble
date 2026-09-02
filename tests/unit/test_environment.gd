extends GutTest

# The ground's feel is a tuned owner value — pin it so a scene edit
# can't silently deaden (or trampoline-ify) the world.


func test_ground_has_a_bounce_material() -> void:
	var env: Node2D = load("res://scenes/environment.tscn").instantiate()
	add_child_autofree(env)
	var mat: PhysicsMaterial = env.get_node("Ground").physics_material_override
	assert_not_null(mat, "ground carries a physics material")
	# Owner-decreed feel after the 0.75 trampoline experiment: ~0.2.
	assert_between(mat.bounce, 0.05, 0.3, "a LITTLE bounce — lively, not a trampoline")
