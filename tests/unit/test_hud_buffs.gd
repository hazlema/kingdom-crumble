extends GutTest


func _hud() -> Node:
	var h: Node = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(h)
	return h


func test_set_buffs_draws_one_icon_per_charge() -> void:
	var h := _hud()
	h.set_buffs([&"exploding", &"exploding", &"multishot"] as Array[StringName])
	await wait_frames(1)
	assert_eq(h.get_node("%StatCard/%BuffRow").get_child_count(), 3)


func test_set_crates_shows_standing_over_total() -> void:
	var h := _hud()
	h.set_crates(12, 15)
	assert_eq(h.get_node("%StatCard/%CratesValue").text, "12/15")
	assert_not_null(h.get_node("%StatCard/%CrateIcon").texture, "icon assigned on first update")


func test_set_buffs_empty_clears_row() -> void:
	var h := _hud()
	h.set_buffs([&"multishot"] as Array[StringName])
	await wait_frames(1)
	h.set_buffs([] as Array[StringName])
	await wait_frames(2)
	var live := 0
	for c in h.get_node("%StatCard/%BuffRow").get_children():
		if not c.is_queued_for_deletion():
			live += 1
	assert_eq(live, 0)


func test_crates_row_hold_bridges_the_check_action() -> void:
	# Playtester ask: "which boxes are left to hit" had no touch path.
	# Press-and-hold on the CRATES row now drives the same "check" action
	# as holding H; slide-off or focus loss releases it.
	var h := _hud()
	await wait_frames(1)
	var card: StatCard = h.get_node("%StatCard")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	card._on_crates_row_input(press)
	assert_true(Input.is_action_pressed("check"), "hold = H down")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card._on_crates_row_input(release)
	assert_false(Input.is_action_pressed("check"), "let go = H up")


# ---------------------------------------------------------------------------
# Banner sequencing — a real banner waits for an active display: toast
# (same control; they replace, not stack — the winner-winner bug).
# ---------------------------------------------------------------------------

func test_banner_waits_for_active_toast() -> void:
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	hud.toast("Winner winner chicken dinner")
	hud.banner("KINGDOM CRUMBLED!", "press ENTER")
	assert_eq(hud.get_node("%Banner").text, "Winner winner chicken dinner", "toast keeps the slot")
	assert_false(hud.get_node("%BannerSub").visible, "banner not applied yet")
	await wait_seconds(hud.TOAST_SECS + 0.4)
	assert_eq(hud.get_node("%Banner").text, "KINGDOM CRUMBLED!", "banner lands after the toast beat")
	assert_true(hud.get_node("%BannerSub").visible)


func test_banner_immediate_without_toast() -> void:
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	hud.banner("OUT OF STONES", "press ENTER")
	assert_eq(hud.get_node("%Banner").text, "OUT OF STONES", "no toast, no wait")


func test_late_toast_never_steals_a_real_banner() -> void:
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	hud.banner("KINGDOM CRUMBLED!", "press ENTER")
	hud.toast("too late")
	assert_eq(hud.get_node("%Banner").text, "KINGDOM CRUMBLED!", "banner outranks a late toast")
