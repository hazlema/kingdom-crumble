extends GutTest

# NarfKit citizen #2: the playing-card flip. Must always land showing
# the front, swap faces at each edge-on apex, and slow per flip.


func _flipper(flips: int) -> NarfFlip:
	var f := NarfFlip.new()
	var front := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	front.fill(Color.RED)
	var back := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	back.fill(Color.BLUE)
	f.front_texture = ImageTexture.create_from_image(front)
	f.back_texture = ImageTexture.create_from_image(back)
	f.texture = f.front_texture
	f.flips = flips
	f.first_flip_time = 0.08
	f.slowdown = 1.2
	add_child_autofree(f)
	return f


func test_lands_on_front_odd_flips() -> void:
	var f := _flipper(3)
	watch_signals(f)
	f.play()
	await wait_for_signal(f.finished, 3.0)
	assert_signal_emitted(f, "finished")
	assert_eq(f.texture, f.front_texture, "3 flips end face-up")
	assert_almost_eq(f.scale.x, 1.0, 0.01, "fully unfolded")


func test_lands_on_front_even_flips() -> void:
	var f := _flipper(4)
	f.play()
	await wait_for_signal(f.finished, 3.0)
	assert_eq(f.texture, f.front_texture, "4 flips also end face-up")


func test_shows_the_back_mid_performance() -> void:
	var f := _flipper(3)
	f.play()
	var saw_back := false
	for i in 60:
		await wait_process_frames(1)
		if f.texture == f.back_texture:
			saw_back = true
			break
	assert_true(saw_back, "the card's back appears during the turn")
