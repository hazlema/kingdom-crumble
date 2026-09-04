extends GutTest

# NarfKit citizen #3: party in a node. Kit rule -- zero host-game refs.


func test_pop_emits_a_one_shot_burst() -> void:
	var c := NarfConfetti.new()
	c.pieces = 42
	add_child_autofree(c)
	c.pop()
	assert_true(c.emitting, "the party is on")
	assert_true(c.one_shot, "and it ends on its own")
	assert_eq(c.amount, 42, "pieces dial wired to amount")


func test_burst_is_fire_and_forget() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var c := NarfConfetti.burst(host, Vector2(123, 45), 30)
	assert_eq(c.get_parent(), host, "lands on the host")
	assert_eq(c.position, Vector2(123, 45), "at the asked spot")
	assert_true(c.emitting, "already celebrating")


func test_gravity_pulls_the_party_downward() -> void:
	var c := NarfConfetti.new()
	add_child_autofree(c)
	assert_gt(c.gravity.y, 0.0, "confetti falls, as confetti must")
	assert_gt(c.lifetime, 2.0, "long enough to cross a 1080 screen")
