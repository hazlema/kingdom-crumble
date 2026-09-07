extends GutTest

# Tests for the TriggerDialog component (src/editor/trigger_dialog.gd).
# The dialog is programmatically built (no .tscn), registered via
# ed.add_child + ed.register_popup, and uses ed.current for layout data.
#
# Flash test: uses the editor scene + a real scenery piece, so it must
# be an integration-style test in this file.

var ed: LevelEditor
var dlg: TriggerDialog


func before_each() -> void:
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed)
	dlg = TriggerDialog.new(ed)
	ed.add_child(dlg)
	ed.register_popup(dlg)


# ---------------------------------------------------------------------------
# Catalog integrity
# ---------------------------------------------------------------------------

func test_catalog_covers_current_action_vocabulary() -> void:
	# ids exactly ["confetti", "hide", "show", "sound"] sorted — catalog drift breaks authoring silently
	var ids: Array[String] = []
	for entry in TriggerDialog.ACTIONS:
		ids.append(entry["id"])
	ids.sort()
	assert_eq(ids, ["confetti", "hide", "show", "sound"])


# ---------------------------------------------------------------------------
# open() populates overlays correctly
# ---------------------------------------------------------------------------

func test_open_lists_named_overlays_with_hidden_badge() -> void:
	# layout with overlays [{name:"sign1"}, {name:"door", hidden:true}, {no name}]
	# → 2 rows ("sign1", "door (hidden)"), footer mentions 1 unnamed
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	ed.current.images[key] = b64
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0, "name": "sign1"})
	ed.current.overlays.append({"image": key, "x": 10.0, "y": 0.0, "name": "door", "hidden": true})
	ed.current.overlays.append({"image": key, "x": 20.0, "y": 0.0})  # no name
	dlg.open("hit:0,0", ed.current)
	# Named-overlay list has exactly 2 rows
	var overlay_list: ItemList = dlg.get_overlay_list()
	assert_eq(overlay_list.item_count, 2, "2 named overlays shown")
	assert_eq(overlay_list.get_item_text(0), "sign1")
	assert_eq(overlay_list.get_item_text(1), "door (hidden)")
	# Footer mentions the 1 unnamed overlay
	var footer: Label = dlg.get_footer_label()
	assert_true(
		str(footer.text).contains("1"),
		"footer mentions 1 unnamed overlay, got: %s" % footer.text
	)


# ---------------------------------------------------------------------------
# Add action: show
# ---------------------------------------------------------------------------

func test_add_show_action_writes_trigger() -> void:
	# pick show + sign1 row + Add → layout.triggers["hit:4,0"] == ["show:sign1"]
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.GREEN)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	ed.current.images[key] = b64
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0, "name": "sign1"})
	dlg.open("hit:4,0", ed.current)
	# Select "show" in the action option button
	dlg.set_action_by_id("show")
	# Select overlay row 0 ("sign1")
	dlg.get_overlay_list().select(0)
	dlg.add_action()
	assert_true(ed.current.triggers.has("hit:4,0"), "trigger key created")
	assert_eq(ed.current.triggers["hit:4,0"], ["show:sign1"])


# ---------------------------------------------------------------------------
# Add action: sound
# ---------------------------------------------------------------------------

func test_add_sound_action_uses_stem_param() -> void:
	# pick sound + a stem + Add → appends "sound:<stem>"
	dlg.open("hit:2,1", ed.current)
	dlg.set_action_by_id("sound")
	# Select the first stem in the option button (index 0)
	dlg.get_stem_option().selected = 0
	dlg.add_action()
	assert_true(ed.current.triggers.has("hit:2,1"), "trigger key created")
	var actions: Array = ed.current.triggers["hit:2,1"]
	assert_eq(actions.size(), 1)
	assert_true(
		String(actions[0]).begins_with("sound:"),
		"action begins with 'sound:', got: %s" % actions[0]
	)


# ---------------------------------------------------------------------------
# Duplicate dedup + cap enforcement
# ---------------------------------------------------------------------------

func test_duplicate_action_deduped_and_cap_enforced() -> void:
	# adding same action twice → one copy; filling to 16 → 17th refused with
	# warning label visible, array stays 16
	dlg.open("hit:0,0", ed.current)
	dlg.set_action_by_id("confetti")
	dlg.add_action()
	dlg.add_action()  # duplicate
	assert_eq((ed.current.triggers.get("hit:0,0", []) as Array).size(), 1, "deduped to 1")

	# Fill to 16 using variations on sound: stems
	var stems: Array[String] = dlg.get_all_stems()
	# Use confetti + show: + hide: + sound:stem variants (need 16 unique actions)
	# First we already have "confetti" (1). Build 15 more unique sound: variants
	# using fake stem names directly in the trigger (bypass add_action for speed).
	var trig: Array = ed.current.triggers["hit:0,0"]
	for i in range(15):
		trig.append("sound:stem%d" % i)
	# trig is 16 now; attempt to add one more via add_action
	dlg.open("hit:0,0", ed.current)
	dlg.set_action_by_id("confetti")
	dlg.add_action()  # confetti already present → deduped, still 16
	# Try adding a brand-new unique action that doesn't exist yet
	# Manually push to 16 unique items then try to add a 17th
	ed.current.triggers["hit:0,0"] = []
	for i in range(16):
		ed.current.triggers["hit:0,0"].append("sound:stem%d" % i)
	dlg.open("hit:0,0", ed.current)
	dlg.set_action_by_id("confetti")
	dlg.add_action()  # 17th: must be refused
	assert_eq(
		(ed.current.triggers["hit:0,0"] as Array).size(),
		16,
		"cap enforced: array stays at 16"
	)
	var warn: Label = dlg.get_warning_label()
	assert_true(warn.visible, "warning label visible when cap hit")


# ---------------------------------------------------------------------------
# Remove action — key vanishes on last removal
# ---------------------------------------------------------------------------

func test_remove_action_deletes_and_empty_key_vanishes() -> void:
	# remove sole action → layout.triggers has NO "hit:4,0" key
	dlg.open("hit:4,0", ed.current)
	dlg.set_action_by_id("confetti")
	dlg.add_action()
	assert_true(ed.current.triggers.has("hit:4,0"), "trigger exists before remove")
	# Remove the first (and only) action
	dlg.remove_action(0)
	assert_false(
		ed.current.triggers.has("hit:4,0"),
		"trigger key removed when last action deleted"
	)


# ---------------------------------------------------------------------------
# Row select → flash_requested signal with correct overlay INDEX
# ---------------------------------------------------------------------------

func test_row_select_emits_flash_with_overlay_index() -> void:
	# overlays: [{name:"sign1"}, {name:"door", hidden:true}, {no name}]
	# "door" is index 1 in layout.overlays (not row index — unnamed skews them)
	# Row 1 in the ItemList is "door (hidden)" → must emit flash_requested(1)
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	ed.current.images[key] = b64
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0, "name": "sign1"})
	ed.current.overlays.append({"image": key, "x": 10.0, "y": 0.0, "name": "door", "hidden": true})
	ed.current.overlays.append({"image": key, "x": 20.0, "y": 0.0})  # no name, index 2
	dlg.open("hit:0,0", ed.current)
	watch_signals(dlg)
	# Simulate selecting row 1 ("door (hidden)" — overlay index 1)
	dlg.get_overlay_list().select(1)
	dlg._on_overlay_row_selected(1)
	assert_signal_emitted_with_parameters(dlg, "flash_requested", [1])


# ---------------------------------------------------------------------------
# flash_overlay: restores modulate; survives bad idx and mid-flash re-entry
# ---------------------------------------------------------------------------

func test_flash_overlay_restores_modulate_and_survives_bad_idx() -> void:
	# Build a real scenery piece at overlay index 0
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	ed.current.images[key] = b64
	ed.current.overlays.append({"image": key, "x": 200.0, "y": 200.0, "name": "flashtest"})
	ed._rebuild_scenery()
	# Verify we have a piece
	var piece: NarfDecor = ed._piece_for_overlay(0)
	assert_not_null(piece, "piece must exist for flash test")
	var orig_mod := piece.modulate

	# Verify bad idx is a no-op (no error)
	ed.flash_overlay(99)
	ed.flash_overlay(-1)

	# Start a flash, then call mid-flash (should kill prior tween gracefully)
	ed.flash_overlay(0)
	ed.flash_overlay(0)  # mid-flash re-entry

	# Wait long enough for the tween to complete (~0.8s)
	await wait_seconds(0.9)

	# Modulate must be restored to original
	assert_almost_eq(piece.modulate.r, orig_mod.r, 0.01, "red restored")
	assert_almost_eq(piece.modulate.g, orig_mod.g, 0.01, "green restored")
	assert_almost_eq(piece.modulate.b, orig_mod.b, 0.01, "blue restored")
	assert_almost_eq(piece.modulate.a, orig_mod.a, 0.01, "alpha restored")
