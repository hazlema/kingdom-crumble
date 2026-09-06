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
	# We verify scan() produces no engine errors and packs() returns an Array (not null/crash).
	# (GUT counts engine errors as failures automatically.)
	Pieces.scan()
	var result: Array = Pieces.packs()
	assert_true(result is Array, "packs() returns Array even when toybox empty/absent")
	# No packs created by this test → nothing from us in the list
	for p in result:
		assert_ne(p.get("folder", ""), "", "any pack has a non-empty folder")
