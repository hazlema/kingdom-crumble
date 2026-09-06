extends GutTest

# Task 1: Pack discovery — manifests, namespaced pieces, persistence, seasons.
# All fake packs are written under user://toybox/ and cleaned up in after_each.

const TOYBOX_DIR := "user://toybox"
const TOYBOX_CFG := "user://toybox.cfg"

var _created_folders: Array[String] = []
var _cfg_before: String = ""


func before_each() -> void:
	# Capture any existing toybox.cfg so we can restore it after_each.
	if FileAccess.file_exists(TOYBOX_CFG):
		_cfg_before = FileAccess.open(TOYBOX_CFG, FileAccess.READ).get_as_text()
	else:
		_cfg_before = ""
	_created_folders.clear()
	# Reset test-seam
	Pieces.clock_month = -1


func after_each() -> void:
	# Task 3 tests open the pause menu, which pauses the tree — unpause so
	# later physics tests (awaiting settle) don't hang forever.
	get_tree().paused = false
	_nuke_toybox()
	# Restore toybox.cfg exactly as it was
	if _cfg_before == "":
		if FileAccess.file_exists(TOYBOX_CFG):
			DirAccess.remove_absolute(TOYBOX_CFG)
	else:
		var f := FileAccess.open(TOYBOX_CFG, FileAccess.WRITE)
		if f:
			f.store_string(_cfg_before)
	Pieces.clock_month = -1
	Pieces.scan()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Write a pack under user://toybox/<folder>/ with a pack.json and optional PNGs.
## pngs: { "basename.png": Image }  — saved via save_png.
func _make_pack(folder: String, manifest: Dictionary, pngs: Dictionary = {}) -> void:
	var pack_dir := "%s/%s" % [TOYBOX_DIR, folder]
	DirAccess.make_dir_recursive_absolute(pack_dir)
	_created_folders.append(folder)
	# Write manifest
	var mf := FileAccess.open("%s/pack.json" % pack_dir, FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest))
	mf.close()
	# Write PNGs
	for basename: String in pngs:
		var img: Image = pngs[basename]
		img.save_png("%s/%s" % [pack_dir, basename])


## Remove every folder created by _make_pack and clean up any cfg keys they touched.
func _nuke_toybox() -> void:
	for folder in _created_folders:
		var pack_dir := "%s/%s" % [TOYBOX_DIR, folder]
		var dir := DirAccess.open(pack_dir)
		if dir:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while fname != "":
				if not dir.current_is_dir():
					dir.remove(fname)
				fname = dir.get_next()
			dir.list_dir_end()
		DirAccess.remove_absolute(pack_dir)
	_created_folders.clear()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_object_pack_pieces_register_namespaced() -> void:
	var img := Image.create(64, 63, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	_make_pack("testpack", {"title": "Test Pack", "kind": "objects"}, {"mini-block.png": img})
	Pieces.scan()
	var e := Pieces.entry("testpack:mini-block")
	assert_false(e.is_empty(), "namespaced piece registered")
	assert_eq(e["class"], "crate", "default class for no-sidecar pack piece is 'crate'")
	assert_not_null(e.get("texture"), "texture non-null")


func test_bad_manifest_ignores_pack_with_warning() -> void:
	# kind "banana" is unknown → pack ignored (warns)
	_make_pack("badpack", {"title": "Bad", "kind": "banana"})
	Pieces.scan()
	var found := false
	for p in Pieces.packs():
		if p["folder"] == "badpack":
			found = true
	assert_false(found, "unknown-kind pack absent from packs()")
	var e := Pieces.entry("badpack:anything")
	assert_true(e.is_empty(), "no pieces from bad-kind pack")


func test_disabled_pack_contributes_nothing() -> void:
	var img := Image.create(64, 63, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	_make_pack("testpack", {"title": "Test Pack", "kind": "objects"}, {"mini-block.png": img})
	Pieces.scan()
	# Confirm it's there first
	assert_false(Pieces.entry("testpack:mini-block").is_empty(), "piece present after scan")
	# Disable
	Pieces.set_pack_enabled("testpack", false)
	assert_true(Pieces.entry("testpack:mini-block").is_empty(), "piece absent when pack disabled")
	# Check packs() reflects disabled state
	var found_disabled := false
	for p in Pieces.packs():
		if p["folder"] == "testpack" and not p["enabled"]:
			found_disabled = true
	assert_true(found_disabled, "packs() shows enabled=false")
	# Re-enable
	Pieces.set_pack_enabled("testpack", true)
	assert_false(Pieces.entry("testpack:mini-block").is_empty(), "re-enable restores piece")


func test_season_math_and_gating() -> void:
	# in_season with explicit months
	Pieces.clock_month = 11
	assert_true(Pieces.in_season([11]), "month 11 is in season when clock=11")
	assert_true(Pieces.in_season([11, 12]), "months [11,12]; clock=11 → in season")
	Pieces.clock_month = 3
	assert_false(Pieces.in_season([11]), "month 11 not in season when clock=3")
	# empty months = always in season
	assert_true(Pieces.in_season([]), "empty months = always in season")
	Pieces.clock_month = 7
	assert_true(Pieces.in_season([]), "empty months = in season even with clock=7")


func test_junk_png_warns_and_skips_piece() -> void:
	# Write garbage bytes as a .png — the magic gate must block it before load_png_from_buffer
	var pack_dir := "%s/junkpack" % TOYBOX_DIR
	DirAccess.make_dir_recursive_absolute(pack_dir)
	_created_folders.append("junkpack")
	# Write manifest
	var mf := FileAccess.open("%s/pack.json" % pack_dir, FileAccess.WRITE)
	mf.store_string(JSON.stringify({"title": "Junk", "kind": "objects"}))
	mf.close()
	# Write junk bytes (definitely not a PNG)
	var jf := FileAccess.open("%s/junk-piece.png" % pack_dir, FileAccess.WRITE)
	jf.store_buffer(PackedByteArray([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD]))
	jf.close()
	# Scan should NOT produce engine errors (magic gate blocks junk before load_png_from_buffer)
	Pieces.scan()
	assert_true(Pieces.entry("junkpack:junk-piece").is_empty(), "junk PNG skipped — no piece registered")


func test_web_absent_toybox_is_silent() -> void:
	# Simulates the web/absent-dir case: DirAccess.open failing = silent empty list.
	# Remove toybox dir first to ensure we test the absent-dir path (not empty-dir).
	if DirAccess.dir_exists_absolute(TOYBOX_DIR):
		DirAccess.remove_absolute(TOYBOX_DIR)
	# Verify scan() produces no engine errors and packs() returns an Array (not null/crash).
	# (GUT counts engine errors as failures automatically.)
	Pieces.scan()
	var result: Array = Pieces.packs()
	assert_true(result is Array, "packs() returns Array even when toybox absent")
	# No packs created by this test → nothing from us in the list
	for p in result:
		assert_ne(p.get("folder", ""), "", "any pack has a non-empty folder")


# ---------------------------------------------------------------------------
# Task 2 Tests: Theme resolution
# ---------------------------------------------------------------------------

func test_theme_reskins_base_id() -> void:
	# Build a correctly-sized theme PNG for "crate-wood" (64x64, distinctive red pixel at 0,0)
	# First scan to get the baked texture's size
	Pieces.scan()
	var baked_tex := Pieces.texture_for("crate-wood")
	assert_not_null(baked_tex, "baked crate-wood must exist for this test")
	var baked_w: int = baked_tex.get_width()
	var baked_h: int = baked_tex.get_height()
	# Make a theme image matching baked dimensions but with a distinctive pixel
	var theme_img := Image.create(baked_w, baked_h, false, Image.FORMAT_RGBA8)
	theme_img.fill(Color(0.5, 0.1, 0.9, 1.0))  # distinctive purple — unlikely to match baked
	_make_pack("wintertest", {"title": "Winter Test", "kind": "theme", "months": []}, {"crate-wood.png": theme_img})
	# Scan so the pack appears in _packs, then set active
	Pieces.scan()
	Pieces.set_active_theme("wintertest")
	# texture_for should now return the themed texture
	var themed_tex := Pieces.texture_for("crate-wood")
	assert_not_null(themed_tex, "themed texture non-null")
	assert_ne(themed_tex, baked_tex, "themed texture differs from baked")
	# entry()'s texture should match themed too
	var e := Pieces.entry("crate-wood")
	assert_eq(e.get("texture"), themed_tex, "entry() texture matches themed texture")
	# PIN TEST: by_class() entries carry the themed texture
	var palette_entries := Pieces.by_class("crate")
	var found_themed := false
	for pe in palette_entries:
		if pe["id"] == "crate-wood":
			assert_eq(pe["texture"], Pieces.texture_for("crate-wood"), "by_class() entries carry the themed texture")
			found_themed = true
	assert_true(found_themed, "crate-wood present in by_class results")


func test_theme_dimension_mismatch_falls_back() -> void:
	# A 32x32 PNG when baked is a different size → dimension mismatch → warn, fall back to baked  # warns
	Pieces.scan()
	var baked_tex := Pieces.texture_for("crate-wood")
	assert_not_null(baked_tex, "baked crate-wood must exist for this test")
	# Build a mismatched theme: use 32x32 (baked is unlikely to be 32x32 — verify)
	var baked_w: int = baked_tex.get_width()
	var baked_h: int = baked_tex.get_height()
	# Force a size that differs
	var bad_w := 32 if baked_w != 32 else 16
	var bad_h := 32 if baked_h != 32 else 16
	var mismatch_img := Image.create(bad_w, bad_h, false, Image.FORMAT_RGBA8)
	mismatch_img.fill(Color.RED)
	_make_pack("badtheme", {"title": "Bad Theme", "kind": "theme", "months": []}, {"crate-wood.png": mismatch_img})
	# Scan so the pack appears in _packs, then set active
	Pieces.scan()
	Pieces.set_active_theme("badtheme")
	var tex := Pieces.texture_for("crate-wood")
	assert_eq(tex, baked_tex, "dimension mismatch falls back to baked texture")


func test_out_of_season_theme_reverts_at_scan() -> void:
	# months [11], clock_month = 3 → out of season. Write active directly to cfg to bypass setter guard.  # warns
	_make_pack("autumntest", {"title": "Autumn Test", "kind": "theme", "months": [11]}, {})
	# Write cfg directly to bypass set_active_theme's in-season guard
	var cfg := ConfigFile.new()
	cfg.load("user://toybox.cfg")
	cfg.set_value("theme", "active", "autumntest")
	cfg.save("user://toybox.cfg")
	Pieces.clock_month = 3
	Pieces.scan()
	assert_eq(Pieces.active_theme(), "", "out-of-season theme reverts to Default at scan")


func test_default_theme_is_bakeware() -> void:
	# With "" active theme, texture_for returns the identical baked texture object
	Pieces.scan()
	# Ensure no theme is active
	Pieces.set_active_theme("")
	var tex_default := Pieces.texture_for("crate-wood")
	var e := Pieces.entry("crate-wood")
	var tex_entry: Texture2D = e.get("texture")
	var baked_tex: Texture2D = load("res://pieces/crate-wood.png")
	assert_not_null(tex_default, "texture_for returns non-null for default theme")
	assert_eq(tex_default, baked_tex, "default theme: texture_for returns baked texture")
	assert_eq(tex_entry, baked_tex, "default theme: entry() texture is baked texture")


func test_hostile_ihdr_blocked_before_decode() -> void:
	# PIN TEST: Write a file with valid 8-byte PNG magic + hostile IHDR (20000x20000)
	# → assert piece absent, warning fired, no giant allocation.
	# Confirms IHDR pre-check gate fires before load_png_from_buffer.
	var pack_dir := "%s/hostile_pack" % TOYBOX_DIR
	DirAccess.make_dir_recursive_absolute(pack_dir)
	_created_folders.append("hostile_pack")
	# Write manifest
	var mf := FileAccess.open("%s/pack.json" % pack_dir, FileAccess.WRITE)
	mf.store_string(JSON.stringify({"title": "Hostile", "kind": "objects"}))
	mf.close()
	# Craft hostile PNG: valid magic + IHDR with 20000x20000 claim + junk body
	var hostile := PackedByteArray()
	hostile.append_array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])  # PNG magic
	# IHDR chunk: width 20000 (0x4E20), height 20000, rest is standard fields
	hostile.append_array([0x00, 0x00, 0x00, 0x0D])  # chunk length (IHDR = 13 bytes)
	hostile.append_array([0x49, 0x48, 0x44, 0x52])  # "IHDR"
	hostile.append_array([0x00, 0x00, 0x4E, 0x20])  # width = 20000
	hostile.append_array([0x00, 0x00, 0x4E, 0x20])  # height = 20000
	hostile.append_array([0x08, 0x02, 0x00, 0x00, 0x00])  # bit depth, color, compression, filter, interlace
	hostile.append_array([0x12, 0x34, 0x56, 0x78])  # fake CRC
	# Junk body
	for i in range(1000):
		hostile.append(0xFF)
	var hf := FileAccess.open("%s/hostile.png" % pack_dir, FileAccess.WRITE)
	hf.store_buffer(hostile)
	hf.close()
	# Scan should block hostile before decode, warn, and complete fast
	var start := Time.get_ticks_msec()
	Pieces.scan()
	var elapsed := Time.get_ticks_msec() - start
	# Verify piece absent (IHDR gate blocked it)
	assert_true(Pieces.entry("hostile_pack:hostile").is_empty(), "hostile piece blocked by IHDR gate")
	# Verify fast completion (< 500ms confirms no giant allocation/decode)
	assert_true(elapsed < 500, "scan completes fast (no allocation on hostile IHDR)")


# ---------------------------------------------------------------------------
# Task 3 Tests: Pause menu Toybox section
# ---------------------------------------------------------------------------

const MONTHS := ["", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]


func _pause_menu() -> PauseMenu:
	var pm: PauseMenu = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(pm)
	return pm


func test_toybox_section_hidden_without_packs() -> void:
	# No packs written → section must be absent or invisible
	Pieces.scan()
	var pm := _pause_menu()
	pm.open()
	var section := pm.get_node_or_null("Center/Panel/Margin/Items/ToyboxSection")
	if section != null:
		assert_false(section.visible, "ToyboxSection invisible when packs() is empty")
	else:
		pass  # absent is also acceptable


func test_object_pack_checkbox_toggles_enabled() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	_make_pack("ui_obj_pack", {"title": "My Objects", "kind": "objects"}, {"block.png": img})
	Pieces.scan()
	var pm := _pause_menu()
	pm.open()
	var section: Node = pm.get_node("Center/Panel/Margin/Items/ToyboxSection")
	assert_not_null(section, "ToyboxSection present when packs exist")
	assert_true(section.visible, "ToyboxSection visible when packs exist")
	# Find the CheckBox for ui_obj_pack
	var cb: CheckBox = null
	for child in section.get_children():
		if child is CheckBox and child.text == "My Objects":
			cb = child
			break
	assert_not_null(cb, "CheckBox with title 'My Objects' found in ToyboxSection")
	assert_true(cb.button_pressed, "CheckBox pressed=true because pack starts enabled")
	# Simulate toggle off — should call set_pack_enabled
	cb.button_pressed = false
	cb.toggled.emit(false)
	# After toggle, Pieces must reflect disabled (set_pack_enabled persists+rescans)
	var found_disabled := false
	for p in Pieces.packs():
		if p["folder"] == "ui_obj_pack" and not p["enabled"]:
			found_disabled = true
	assert_true(found_disabled, "toggling checkbox calls set_pack_enabled(folder, false)")


func test_theme_dropdown_lists_and_disables_out_of_season() -> void:
	# Create an in-season theme pack (months=[]) and an out-of-season one (months=[11], clock=3)
	_make_pack("theme_in", {"title": "Summer Theme", "kind": "theme", "months": []}, {})
	_make_pack("theme_out", {"title": "Winter Theme", "kind": "theme", "months": [11]}, {})
	Pieces.clock_month = 3  # not November → theme_out is out of season
	Pieces.scan()
	var pm := _pause_menu()
	pm.open()
	var section: Node = pm.get_node("Center/Panel/Margin/Items/ToyboxSection")
	assert_not_null(section, "ToyboxSection present")
	# Find the OptionButton
	var ob: OptionButton = null
	for child in section.get_children():
		if child is OptionButton:
			ob = child
			break
	# OptionButton may be inside a HBoxContainer child
	if ob == null:
		for child in section.get_children():
			if child is HBoxContainer:
				for subchild in child.get_children():
					if subchild is OptionButton:
						ob = subchild
						break
	assert_not_null(ob, "OptionButton (theme picker) found in ToyboxSection")
	# Must have at least 3 items: "Default", "Summer Theme", "Winter Theme (returns in November)"
	assert_gte(ob.item_count, 3, "OptionButton has Default + 2 theme items")
	# Find Winter Theme item and check disabled + text
	var winter_idx := -1
	for i in ob.item_count:
		if "Winter Theme" in ob.get_item_text(i):
			winter_idx = i
			break
	assert_ne(winter_idx, -1, "Winter Theme item found in OptionButton")
	assert_true(ob.is_item_disabled(winter_idx), "out-of-season theme item is disabled")
	assert_true("returns in " + MONTHS[11] in ob.get_item_text(winter_idx),
		"disabled item text contains 'returns in November'")
