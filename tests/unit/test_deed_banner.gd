extends GutTest

# DeedBanner unit tests.
#
# DeedBanner is instantiated via preload so class_name ordering doesn't matter.
# Deeds is sandboxed to a scratch cfg/manifest so signals don't fire from
# real data during these tests.
#
# Choreography under test:
#   - DeedBanner.celebrate(entry) builds ribbon text exactly
#   - Multiple rapid unlocks queue FIFO (second fires after first completes)
#   - Banner defers behind an active hud toast (min-remaining+epsilon pattern)
#   - Missing/unloadable medallion image warns rather than crashing
#   - After complete run: banner freed or invisible (alpha near 0)
#   - Hud connects to Deeds.deed_unlocked in _ready, disconnects on tree_exit

const DeedBannerScript := preload("res://src/ui/deed_banner.gd")

const CFG_SCRATCH := "user://test_deed_banner_scratch.cfg"
const MAN_SCRATCH := "user://test_deed_banner_manifest.json"

var _orig_cfg_path: String
var _orig_manifest_path: String


func _write_scratch_manifest(entries: Array) -> void:
	var fa := FileAccess.open(MAN_SCRATCH, FileAccess.WRITE)
	fa.store_string(JSON.stringify(entries))
	fa.close()


func before_each() -> void:
	_orig_cfg_path = Deeds.cfg_path
	_orig_manifest_path = Deeds.manifest_path
	if FileAccess.file_exists(CFG_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_SCRATCH))
	if FileAccess.file_exists(MAN_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAN_SCRATCH))
	_write_scratch_manifest([])
	Deeds.cfg_path = CFG_SCRATCH
	Deeds.manifest_path = MAN_SCRATCH
	Deeds.reload()


func after_each() -> void:
	Deeds.cfg_path = _orig_cfg_path
	Deeds.manifest_path = _orig_manifest_path
	Deeds.reload()
	if FileAccess.file_exists(CFG_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_SCRATCH))
	if FileAccess.file_exists(MAN_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAN_SCRATCH))


func _make_entry(id: String = "test_deed", name_val: String = "Test Deed",
		solid: String = "missing-art.png") -> Dictionary:
	return {
		"id": id,
		"name": name_val,
		"text": "A test deed",
		"solid": solid,
		"ghost": "",
		"trigger": "flag:%s" % id,
		"secret": false,
	}


func _make_banner() -> Node:
	var b: Node = DeedBannerScript.new()
	add_child_autofree(b)
	await wait_frames(1)
	return b


# ---------------------------------------------------------------------------
# Test: DeedBanner has the expected interface
# ---------------------------------------------------------------------------
func test_banner_has_required_interface() -> void:
	var b := await _make_banner()
	assert_true(b.has_method("celebrate"), "DeedBanner has celebrate() method")
	assert_true("ribbon_text" in b, "DeedBanner exposes ribbon_text property")


# ---------------------------------------------------------------------------
# Test: ribbon text format is exactly "⚜ Deed Accomplished — {name} ⚜"
# ---------------------------------------------------------------------------
func test_ribbon_text_format() -> void:
	var b := await _make_banner()
	var entry := _make_entry("first_shot", "First Shot")
	b.celebrate(entry)
	await wait_frames(1)
	assert_eq(b.ribbon_text, "⚜ Deed Accomplished — First Shot ⚜",
		"ribbon text must match exact format")


# ---------------------------------------------------------------------------
# Test: ribbon text for another name
# ---------------------------------------------------------------------------
func test_ribbon_text_format_crate_smasher() -> void:
	var b := await _make_banner()
	var entry := _make_entry("crate_smasher", "Crate Smasher")
	b.celebrate(entry)
	await wait_frames(1)
	assert_eq(b.ribbon_text, "⚜ Deed Accomplished — Crate Smasher ⚜",
		"ribbon text uses exact name from entry")


# ---------------------------------------------------------------------------
# Test: missing/unloadable medallion art — banner still visible, ribbon shown
# ---------------------------------------------------------------------------
func test_missing_medallion_warns_not_crashes() -> void:
	var b := await _make_banner()
	var entry := _make_entry("missing_art", "Missing Art", "this-file-does-not-exist.png")
	b.celebrate(entry)
	await wait_frames(1)
	# Banner must be visible (ribbon label shown), even with missing art
	assert_true(b.visible, "banner visible even when art is missing")
	assert_eq(b.ribbon_text, "⚜ Deed Accomplished — Missing Art ⚜",
		"ribbon text shown even with missing art")


# ---------------------------------------------------------------------------
# Test: celebrate() with existing placeholder art loads without crash
# first-shot.png exists in achievements/ from the placeholder art drop
# ---------------------------------------------------------------------------
func test_celebrate_with_real_art() -> void:
	var b := await _make_banner()
	var entry := _make_entry("first_shot", "First Shot", "first-shot.png")
	b.celebrate(entry)
	await wait_frames(2)
	assert_eq(b.ribbon_text, "⚜ Deed Accomplished — First Shot ⚜",
		"ribbon correct with real art")
	assert_true(b.visible, "banner visible when art loads successfully")


# ---------------------------------------------------------------------------
# Test: after full animation run, banner alpha reaches 0 and visible=false
# (physical-condition guard — punch 0.25s + hold 2.5s + fade 0.3s = ~3.05s)
# We wait 6 seconds (same budget as test_rare_unlock_frame) then assert.
# ---------------------------------------------------------------------------
func test_banner_frees_or_fades_after_run() -> void:
	var b := await _make_banner()
	var entry := _make_entry("fade_test", "Fade Test")
	b.celebrate(entry)
	# Generous wait: 6s >> 3.05s tween total (mirrors test_rare_unlock_frame pattern)
	await wait_seconds(6.0)
	# After tween: visible=false and modulate.a is 0 (tween target) or b is freed
	assert_true(not is_instance_valid(b) or not b.visible,
		"banner invisible or freed after animation completes")
	if is_instance_valid(b):
		assert_almost_eq(b.modulate.a, 0.0, 0.1,
			"banner alpha near 0 after tween")


# ---------------------------------------------------------------------------
# Test: deed_completed signal fires with the deed id after animation
# ---------------------------------------------------------------------------
func test_deed_completed_signal_fires() -> void:
	var b := await _make_banner()
	var completed: Array[String] = []
	if b.has_signal("deed_completed"):
		b.deed_completed.connect(func(id: String) -> void: completed.append(id))
	else:
		pending("DeedBanner.deed_completed signal not found")
		return

	var entry := _make_entry("signal_test", "Signal Test")
	b.celebrate(entry)
	# Wait for animation (~3.05s) with generous budget
	await wait_seconds(6.0)
	assert_eq(completed.size(), 1, "deed_completed fires once")
	assert_eq(completed[0], "signal_test", "deed_completed carries the deed id")


# ---------------------------------------------------------------------------
# Test: two rapid celebrate() calls execute FIFO via deed_completed order
# ---------------------------------------------------------------------------
func test_queue_fifo_order() -> void:
	var b := await _make_banner()
	var log: Array[String] = []

	if not b.has_signal("deed_completed"):
		pending("DeedBanner.deed_completed signal not found — skip fifo test")
		return

	b.deed_completed.connect(func(id: String) -> void: log.append(id))

	var e1 := _make_entry("deed_alpha", "Alpha")
	var e2 := _make_entry("deed_beta", "Beta")
	b.celebrate(e1)
	b.celebrate(e2)

	# Wait enough for both to complete (2 × ~3.05s + slop = ~7s)
	# Using a generous straight wait like test_rare_unlock_frame
	await wait_seconds(8.0)

	assert_eq(log.size(), 2, "both deeds completed")
	assert_eq(log[0], "deed_alpha", "alpha completes first (FIFO)")
	assert_eq(log[1], "deed_beta", "beta completes second (FIFO)")


# ---------------------------------------------------------------------------
# Test: hud connects Deeds.deed_unlocked in _ready, disconnects on tree_exit
# ---------------------------------------------------------------------------
func test_hud_connects_and_disconnects_deeds_signal() -> void:
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	await wait_frames(1)

	# After _ready: Deeds.deed_unlocked must have a connection to the hud
	var connected_before := false
	for conn in Deeds.deed_unlocked.get_connections():
		if conn["callable"].get_object() == hud:
			connected_before = true
			break
	assert_true(connected_before, "hud connects to Deeds.deed_unlocked in _ready")

	# Remove from tree: tree_exiting fires, should disconnect
	hud.get_parent().remove_child(hud)
	await wait_frames(1)
	var connected_after := false
	for conn in Deeds.deed_unlocked.get_connections():
		if conn["callable"].get_object() == hud:
			connected_after = true
			break
	assert_false(connected_after, "hud disconnects from Deeds.deed_unlocked on tree_exit")
	hud.queue_free()


# ---------------------------------------------------------------------------
# Test: deed banner defers when hud has an active toast
# ---------------------------------------------------------------------------
func test_defer_behind_active_hud_toast() -> void:
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	await wait_frames(1)

	# Activate a toast (sets _toast_until ~1.8s from now)
	hud.toast("Level Start!")

	# Queue a deed banner immediately after — should not show yet
	var entry := _make_entry("defer_deed", "Defer Deed")
	hud._queue_deed_banner(entry)

	# Immediately: deed banner should not be active yet
	await wait_frames(2)
	assert_false(hud._deed_banner_active(),
		"deed banner defers behind an active toast")

	# After the toast clears: deed banner should appear
	# Toast = 1.8s + 0.15s defer epsilon = ~2.0s; then banner animates
	await wait_seconds(hud.TOAST_SECS + 0.5)
	assert_true(hud._deed_banner_active(),
		"deed banner shows after toast beat clears")
