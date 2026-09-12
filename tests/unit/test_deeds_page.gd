extends GutTest

# DeedsPage unit tests.
#
# Tests cover:
#   - Page builds one slot per manifest entry in order
#   - Locked slot shows ghost texture + "?" name suffix
#   - Secret locked slot shows "???"
#   - Unlock signal causes slot to refresh (name clears "?")
#   - ghost_of() saturation pin (< 0.05 average saturation)
#   - Manifest validates through Deeds: exactly the two intentional
#     unknown-stat teasers (windmill_whiz, dragon_tamer) warn on first evaluate.

const DeedsPageScript := preload("res://src/ui/deeds_page.gd")

const CFG_SCRATCH := "user://test_deeds_page_scratch.cfg"
const MAN_SCRATCH := "user://test_deeds_page_manifest.json"

var _orig_cfg_path: String
var _orig_manifest_path: String


func _write_manifest(entries: Array) -> void:
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
	Deeds.cfg_path = CFG_SCRATCH
	Deeds.manifest_path = MAN_SCRATCH


func after_each() -> void:
	Deeds.cfg_path = _orig_cfg_path
	Deeds.manifest_path = _orig_manifest_path
	Deeds.reload()
	if FileAccess.file_exists(CFG_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_SCRATCH))
	if FileAccess.file_exists(MAN_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAN_SCRATCH))


func _make_page() -> Node:
	var page: Node = DeedsPageScript.new()
	add_child_autofree(page)
	await wait_frames(1)
	return page


# ---------------------------------------------------------------------------
# Helper: find all slot buttons inside the page's grid
# ---------------------------------------------------------------------------
func _find_slots(page: Node) -> Array:
	var grid := _find_grid(page)
	if grid == null:
		return []
	var slots: Array = []
	for child in grid.get_children():
		if child is Button:
			slots.append(child)
	return slots


func _find_grid(page: Node) -> GridContainer:
	# Structure-agnostic: the popup rebuild moved the grid under the
	# painted panel — find it by name wherever it lives.
	return page.find_child("Grid", true, false) as GridContainer


func _find_label_in_slot(slot: Button) -> Label:
	for child in slot.get_children():
		if child is VBoxContainer:
			for grandchild in child.get_children():
				if grandchild is Label:
					return grandchild as Label
	return null


func _find_plaque(page: Node) -> Label:
	# Structure-agnostic after the popup rebuild.
	return page.find_child("Plaque", true, false) as Label


# ---------------------------------------------------------------------------
# Test: page builds exactly one slot per manifest entry in order
# ---------------------------------------------------------------------------
func test_page_builds_one_slot_per_entry() -> void:
	_write_manifest([
		{"id": "alpha", "name": "Alpha", "text": "First", "solid": "first-shot.png", "ghost": "", "trigger": "flag:alpha", "secret": false},
		{"id": "beta",  "name": "Beta",  "text": "Second","solid": "first-shot.png", "ghost": "", "trigger": "flag:beta",  "secret": false},
		{"id": "gamma", "name": "Gamma", "text": "Third", "solid": "first-shot.png", "ghost": "", "trigger": "flag:gamma", "secret": false},
	])
	Deeds.reload()

	var page := await _make_page()
	var slots := _find_slots(page)
	assert_eq(slots.size(), 3, "page has one slot per manifest entry")

	# Slots are named Slot_{id}
	assert_eq(slots[0].name, "Slot_alpha")
	assert_eq(slots[1].name, "Slot_beta")
	assert_eq(slots[2].name, "Slot_gamma")


# ---------------------------------------------------------------------------
# Test: locked (non-secret) slot shows name + "?" suffix in ribbon
# ---------------------------------------------------------------------------
func test_locked_slot_shows_name_with_question_suffix() -> void:
	_write_manifest([
		{"id": "my_deed", "name": "My Deed", "text": "Cool deed", "solid": "first-shot.png", "ghost": "", "trigger": "flag:my_deed", "secret": false},
	])
	Deeds.reload()

	var page := await _make_page()
	var slots := _find_slots(page)
	assert_eq(slots.size(), 1)
	var lbl: Label = _find_label_in_slot(slots[0])
	assert_not_null(lbl, "slot has name label")
	assert_eq(lbl.text, "My Deed ?", "locked non-secret shows name + '?'")


# ---------------------------------------------------------------------------
# Test: secret locked slot shows "???"
# ---------------------------------------------------------------------------
func test_secret_locked_slot_shows_triple_question() -> void:
	_write_manifest([
		{"id": "secret_deed", "name": "Hidden Name", "text": "Secret text", "solid": "first-shot.png", "ghost": "", "trigger": "flag:secret_deed", "secret": true},
	])
	Deeds.reload()

	var page := await _make_page()
	var slots := _find_slots(page)
	assert_eq(slots.size(), 1)
	var lbl: Label = _find_label_in_slot(slots[0])
	assert_not_null(lbl, "slot has name label")
	assert_eq(lbl.text, "???", "secret locked slot shows '???'")


# ---------------------------------------------------------------------------
# Test: unlocked slot shows plain name (no "?")
# ---------------------------------------------------------------------------
func test_unlocked_slot_shows_plain_name() -> void:
	_write_manifest([
		{"id": "done_deed", "name": "Done Deed", "text": "I did it", "solid": "first-shot.png", "ghost": "", "trigger": "flag:done_deed", "secret": false},
	])
	Deeds.reload()
	Deeds.flag("done_deed")  # unlock it

	var page := await _make_page()
	var slots := _find_slots(page)
	assert_eq(slots.size(), 1)
	var lbl: Label = _find_label_in_slot(slots[0])
	assert_not_null(lbl)
	assert_eq(lbl.text, "Done Deed", "unlocked slot shows plain name without '?'")


# ---------------------------------------------------------------------------
# Test: clicking unlocked slot → plaque shows deed text
# ---------------------------------------------------------------------------
func test_click_unlocked_shows_deed_text() -> void:
	_write_manifest([
		{"id": "click_deed", "name": "Click Deed", "text": "You clicked it!", "solid": "first-shot.png", "ghost": "", "trigger": "flag:click_deed", "secret": false},
	])
	Deeds.reload()
	Deeds.flag("click_deed")

	var page := await _make_page()
	var slots := _find_slots(page)
	assert_eq(slots.size(), 1)
	# Simulate click
	slots[0].emit_signal("pressed")
	await wait_frames(1)

	var plaque: Label = _find_plaque(page)
	assert_not_null(plaque, "plaque label found")
	assert_eq(plaque.text, "You clicked it!", "unlocked click shows deed text")


# ---------------------------------------------------------------------------
# Test: clicking locked slot → plaque shows "Not yet discovered…"
# ---------------------------------------------------------------------------
func test_click_locked_shows_not_discovered() -> void:
	_write_manifest([
		{"id": "locked_deed", "name": "Locked Deed", "text": "Secret text here", "solid": "first-shot.png", "ghost": "", "trigger": "flag:locked_deed", "secret": false},
	])
	Deeds.reload()

	var page := await _make_page()
	var slots := _find_slots(page)
	assert_eq(slots.size(), 1)
	slots[0].emit_signal("pressed")
	await wait_frames(1)

	var plaque: Label = _find_plaque(page)
	assert_not_null(plaque)
	assert_eq(plaque.text, "Not yet discovered…", "locked click shows 'Not yet discovered…'")


# ---------------------------------------------------------------------------
# Test: deed_unlocked signal live-refreshes slot label
# ---------------------------------------------------------------------------
func test_deed_unlocked_signal_refreshes_slot() -> void:
	_write_manifest([
		{"id": "live_deed", "name": "Live Deed", "text": "Live unlock", "solid": "first-shot.png", "ghost": "", "trigger": "flag:live_deed", "secret": false},
	])
	Deeds.reload()

	var page := await _make_page()
	var slots := _find_slots(page)
	assert_eq(slots.size(), 1)

	# Before unlock: "?" suffix
	var lbl: Label = _find_label_in_slot(slots[0])
	assert_eq(lbl.text, "Live Deed ?", "starts locked with '?'")

	# Unlock — this fires deed_unlocked which calls _refresh_slots
	Deeds.flag("live_deed")
	await wait_frames(2)

	# Re-find label (it's the same node, text was updated in-place)
	assert_eq(lbl.text, "Live Deed", "slot refreshed to plain name after unlock")


# ---------------------------------------------------------------------------
# Test: ghost_of() saturation pin — average saturation of result < 0.05
# ---------------------------------------------------------------------------
func test_ghost_of_saturation_pin() -> void:
	# Use a real 256x256 medallion from the achievements folder
	var tex: Texture2D = load("res://achievements/first-shot.png")
	if tex == null:
		pending("first-shot.png not loaded — skip saturation test")
		return

	var ghost: Texture2D = DeedsPageScript.ghost_of(tex)
	assert_not_null(ghost, "ghost_of() returns a texture")

	var img: Image = ghost.get_image()
	assert_not_null(img)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	# Sample pixels for saturation check (32x32 grid)
	var w := img.get_width()
	var h := img.get_height()
	var total_sat := 0.0
	var sample_count := 0
	var step_x: int = max(1, w / 32)
	var step_y: int = max(1, h / 32)
	for y in range(0, h, step_y):
		for x in range(0, w, step_x):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.05:  # skip transparent pixels
				# Compute HSV saturation manually: S = (max - min) / max
				var r: float = c.r
				var g: float = c.g
				var b: float = c.b
				var cmax: float = max(r, max(g, b))
				var cmin: float = min(r, min(g, b))
				var sat: float = 0.0
				if cmax > 0.0:
					sat = (cmax - cmin) / cmax
				total_sat += sat
				sample_count += 1

	if sample_count == 0:
		pending("all pixels transparent — skip saturation test")
		return

	var avg_sat: float = total_sat / float(sample_count)
	assert_true(avg_sat < 0.05,
		"ghost_of() average saturation %.4f must be < 0.05" % avg_sat)


# ---------------------------------------------------------------------------
# Test: ghost_of() returns null gracefully for null input
# ---------------------------------------------------------------------------
func test_ghost_of_null_input() -> void:
	var result: Texture2D = DeedsPageScript.ghost_of(null)
	assert_null(result, "ghost_of(null) returns null without crash")


# ---------------------------------------------------------------------------
# Test: shipped manifest loads all entries (10 wave-1 + 9 slinger scroll-testers)
# ---------------------------------------------------------------------------
func test_shipped_manifest_entry_count() -> void:
	Deeds.cfg_path = CFG_SCRATCH
	Deeds.manifest_path = "res://achievements/achievements.manifest"
	Deeds.reload()

	var entries: Array = Deeds.entries()
	assert_eq(entries.size(), 19, "shipped manifest loads all 19 entries")


# ---------------------------------------------------------------------------
# Test: shipped manifest — exactly two unknown-stat warns on first evaluate.
#       windmill_whiz (windmill_rides) and dragon_tamer (dragons_tamed).
#       Warns fire on first evaluate (post-review amendment), so bump a real
#       stat to trigger _evaluate(), then check Deeds._warned_stats.
# ---------------------------------------------------------------------------
func test_shipped_manifest_exactly_two_unknown_stat_teaser_warns() -> void:
	Deeds.cfg_path = CFG_SCRATCH
	Deeds.manifest_path = "res://achievements/achievements.manifest"
	Deeds.reload()

	# Pre-seed ALL known wave-1 stats so they exist in the cfg.
	# This means the only count: stats that are NOT in the cfg after this
	# are the two intentional unknown-stat teaser entries (windmill_rides,
	# dragons_tamed). The flag: and already-bumped stats won't warn.
	# We must call bump/flag WITHOUT triggering warns first — use the cfg
	# directly before reload, so _warned_stats is fresh.
	Deeds.bump("shots_fired")
	Deeds.bump("crates_smashed")
	Deeds.bump("levels_cleared")
	Deeds.bump("wormhole_transits")
	Deeds.bump("tiers_cleared")
	Deeds.bump("mystery_opened")
	Deeds.bump("editor_saves")
	Deeds.flag("skunk")

	# After all the bumps above, _warned_stats will contain whatever was
	# unknown at the time of each bump's evaluate call. On a fresh cfg,
	# the first bump (shots_fired) warns about all count: stats not yet
	# in the cfg. We need to reset and replay cleanly.
	# Strategy: reload from the now-populated cfg, then do ONE bump of
	# a real stat to trigger evaluate. Now all known stats are in cfg;
	# only windmill_rides and dragons_tamed are absent.
	Deeds.reload()

	# Now bump one real stat to force a fresh evaluate pass.
	# _warned_stats is empty after reload().
	Deeds.bump("shots_fired")

	# _warned_stats is a Dictionary of stat_name -> true for unknown stats.
	var warned: Dictionary = Deeds._warned_stats
	assert_true(warned.has("windmill_rides"),
		"windmill_rides flagged as unknown stat (windmill_whiz tease)")
	assert_true(warned.has("dragons_tamed"),
		"dragons_tamed flagged as unknown stat (dragon_tamer tease)")
	assert_eq(warned.size(), 2,
		"exactly two unknown-stat warns: windmill_rides and dragons_tamed")


func test_menu_buttons_actually_flow_vertically() -> void:
	# Owner screenshot catch: zero-min-size children stacked all seven
	# buttons at one spot (only Quit visible on top of the pile). Pin the
	# flow: each button sits strictly below the previous, ~88px pitch.
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	await wait_frames(2)
	var box: VBoxContainer = menu.get_node("menu/Options")
	var prev_y := -INF
	var ys: Array[float] = []
	for child in box.get_children():
		var c := child as Control
		if not c.visible:
			continue  # hidden buttons (Fullscreen on desktop) aren't positioned
		var gy := c.global_position.y
		assert_gt(gy, prev_y, "%s sits below the previous button" % c.name)
		prev_y = gy
		ys.append(gy)
	if ys.size() >= 2:
		assert_almost_eq(ys[1] - ys[0], 88.0, 4.0, "the original 88px pitch is reproduced")


func test_deeds_hotkey_action_registered() -> void:
	assert_true(InputMap.has_action("deeds"), "the in-game deeds action exists")


func test_toggle_deeds_opens_and_closes_popup_on_level() -> void:
	var l := LevelLayout.new()
	l.title = "hotkey"
	l.crates.append({"x": 832.0, "y": 443.0, "type": "crate-wood"})
	l.shots = 3
	Level.suppress_intro = true
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	lvl._toggle_deeds()
	await wait_frames(1)
	assert_not_null(lvl.hud.get_node_or_null("DeedsPopup"), "T opens the parchment over the hud")
	lvl._toggle_deeds()
	await wait_frames(2)
	assert_null(lvl.hud.get_node_or_null("DeedsPopup"), "T again closes it")
