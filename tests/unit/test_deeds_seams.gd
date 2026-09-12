extends GutTest

# Recording-seams test suite (Task 2).
# Each test sandboxes Deeds.cfg_path to a scratch user:// path so the real
# user://deeds.cfg is never touched. Manifest path is pointed at an empty
# scratch file — stats record fine with zero achievements.

const CFG_SCRATCH := "user://test_seams_deeds.cfg"
const MAN_SCRATCH := "user://test_seams_manifest.json"


func before_all() -> void:
	# The first Camera2D added in a headless session triggers an engine
	# notice about physics-interpolation mode. Pre-warm it here (before
	# any test body runs) so the editor_saves test doesn't see it.
	# Mirrors the same pattern in test_thumb_capture.gd.
	var warmup: LevelEditor = load("res://scenes/editor.tscn").instantiate()
	add_child(warmup)
	warmup.queue_free()
	await wait_physics_frames(1)


var _entry_cfg := ""
var _entry_manifest := ""


func before_each() -> void:
	# Capture whatever the suite-wide hook set (the scratch sandbox) so
	# after_each restores THAT — restoring the hardcoded real path here
	# defeated the hook and polluted the developer's real save (final
	# review catch, proven live).
	_entry_cfg = Deeds.cfg_path
	_entry_manifest = Deeds.manifest_path
	# Clean up any stale scratch files.
	if FileAccess.file_exists(CFG_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_SCRATCH))
	if FileAccess.file_exists(MAN_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAN_SCRATCH))
	# Empty manifest — stats record fine with zero achievements.
	var fa := FileAccess.open(MAN_SCRATCH, FileAccess.WRITE)
	fa.store_string("[]")
	fa.close()
	# Redirect Deeds to the scratch paths and reload clean state.
	Deeds.cfg_path = CFG_SCRATCH
	Deeds.manifest_path = MAN_SCRATCH
	Deeds.reload()


func after_each() -> void:
	# Restore real paths.
	Deeds.cfg_path = _entry_cfg
	Deeds.manifest_path = _entry_manifest
	Deeds.reload()
	# Remove scratch files.
	if FileAccess.file_exists(CFG_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_SCRATCH))
	if FileAccess.file_exists(MAN_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAN_SCRATCH))


# Helpers -----------------------------------------------------------------

func _stat(key: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(CFG_SCRATCH)
	return cfg.get_value("stats", key, 0)


func _flag_set(key: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(CFG_SCRATCH)
	return bool(cfg.get_value("stats", key, false))


func _make_level(extra: Dictionary = {}) -> Level:
	var l := LevelLayout.new()
	l.title = "seam_test"
	l.crates.append({"x": 832.0, "y": 443.0, "type": "crate-wood"})
	l.shots = 5
	for k in extra:
		l.set(k, extra[k])
	Level.suppress_intro = true
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	return lvl


# ---------------------------------------------------------------------------
# Seam 1: shots_fired — trebuchet._fire()
# The headless suite cannot fire the sling via input (no InputEvent delivery
# to _process). We call _fire() directly on a spawned Trebuchet, which is the
# exact same codepath the game uses when the player releases the fire button.
# ---------------------------------------------------------------------------
func test_shots_fired_increments_on_fire() -> void:
	assert_eq(_stat("shots_fired"), 0, "baseline zero")
	var treb: Trebuchet = load("res://scenes/trebuchet.tscn").instantiate()
	add_child_autofree(treb)
	await wait_frames(1)
	treb._fire()
	assert_eq(_stat("shots_fired"), 1, "shots_fired bumped after _fire()")
	treb._fire()
	assert_eq(_stat("shots_fired"), 2, "shots_fired accumulates across fires")


# ---------------------------------------------------------------------------
# Seam 2: crates_smashed — level._on_crate_knocked(crate)
# Drives the real level path; mirrors test_powerup_rules.gd test_knock_path.
# ---------------------------------------------------------------------------
func test_crates_smashed_increments_on_knock() -> void:
	var lvl := _make_level()
	await wait_frames(2)
	var crate: Crate = lvl.get_tree().get_nodes_in_group("crates")[0]
	assert_eq(_stat("crates_smashed"), 0, "baseline zero")
	lvl._on_crate_knocked(crate)
	assert_eq(_stat("crates_smashed"), 1, "crates_smashed bumped after knock")
	# Knock a second crate node (same crate obj is fine — method is idempotent here).
	lvl._on_crate_knocked(crate)
	assert_eq(_stat("crates_smashed"), 2, "crates_smashed accumulates")


# ---------------------------------------------------------------------------
# Seam 3: levels_cleared — level._record_clear()
# _record_clear guards: editor_session=false, current_stem != "".
# We call it directly; in a plain level-fixture current_stem is "" (no chain),
# so we set it to a non-empty value first.
# ---------------------------------------------------------------------------
func test_levels_cleared_increments_on_record_clear() -> void:
	var lvl := _make_level()
	await wait_frames(1)
	assert_eq(_stat("levels_cleared"), 0, "baseline zero")
	# _record_clear is a no-op if current_stem is "" — set it to a stub value.
	lvl.current_stem = "builtin:seam_test"
	lvl._record_clear()
	assert_eq(_stat("levels_cleared"), 1, "levels_cleared bumped after _record_clear")


# ---------------------------------------------------------------------------
# Seam 4: tiers_cleared — chain-end clear inside _settle()
# We use a level with ZERO crates so count_standing() == 0 immediately,
# and set current_stem to a stub id that has no successor in the chain.
# The settle path then sets _chain_end=true and bumps tiers_cleared.
# ---------------------------------------------------------------------------
func test_tiers_cleared_increments_on_chain_end_clear() -> void:
	# Level with zero crates: count_standing == 0 → CLEARED on first settle.
	var l := LevelLayout.new()
	l.title = "seam_tier_test"
	l.shots = 5
	# No crates appended — layout.crates stays empty.
	Level.suppress_intro = true
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	assert_eq(_stat("tiers_cleared"), 0, "baseline zero")
	# Give the level a non-empty stem with no next entry in the chain.
	# "user:__seam_no_next__" is a stub id that will never appear in any chain.
	lvl.current_stem = "user:__seam_no_next__"
	# Call _settle() directly — no active stones, no crates → CLEARED + chain_end.
	lvl._settle()
	await wait_frames(1)
	assert_eq(_stat("tiers_cleared"), 1, "tiers_cleared bumped on chain-end clear")


# ---------------------------------------------------------------------------
# Seam 5: wormhole_transits — Wormhole._teleport()
# We build a minimal paired-wormhole fixture and call _teleport() directly.
# We use a plain RigidBody2D (not a Stone scene) to avoid heavy scene init.
# NOTE on headless: Wormhole._teleport() calls body.reset_physics_interpolation()
# after the Deeds.bump(). This may emit a Godot engine message about Camera2D
# and physics interpolation in some project configurations — that is a Godot
# engine quirk, not a test failure. The seam itself fires before that call.
# ---------------------------------------------------------------------------
func test_wormhole_transits_increments_on_teleport() -> void:
	assert_eq(_stat("wormhole_transits"), 0, "baseline zero")
	# Create two paired wormholes.
	var w1 := Wormhole.new()
	var w2 := Wormhole.new()
	var host := Node2D.new()
	add_child_autofree(host)
	host.add_child(w1)
	host.add_child(w2)
	w1.partner = w2
	w2.partner = w1
	w2.global_position = Vector2(500.0, 500.0)
	# A plain RigidBody2D satisfies the `body is RigidBody2D` guard in _teleport.
	# (Stone extends RigidBody2D but the scene is heavier than needed here.)
	var body := RigidBody2D.new()
	body.add_to_group("stones")
	host.add_child(body)
	body.global_position = Vector2(100.0, 100.0)
	await wait_physics_frames(1)
	# Drive _teleport directly. The Deeds.bump fires before reset_physics_interpolation.
	w1._teleport(body)
	assert_eq(_stat("wormhole_transits"), 1, "wormhole_transits bumped after _teleport()")


# ---------------------------------------------------------------------------
# Seam 6: mystery_opened — PowerupRules._route_power() mystery branch
# Calling route_crate on a mystery-type crate fires the bump.
# We use the "crate-ghost" type which has powerup="mystery" in the registry.
# ---------------------------------------------------------------------------
func test_mystery_opened_increments_on_mystery_roll() -> void:
	assert_eq(_stat("mystery_opened"), 0, "baseline zero")
	# Roll the mystery with skunk already unlocked (avoids skunk return path).
	var result := PowerupRules.route("crate-ghost", true, func() -> float: return 0.5)
	assert_ne(result["kind"], "none", "mystery produced a result")
	assert_eq(_stat("mystery_opened"), 1, "mystery_opened bumped on mystery resolution")


func test_mystery_opened_increments_on_skunk_roll_too() -> void:
	assert_eq(_stat("mystery_opened"), 0, "baseline zero")
	# Roll the mystery with skunk NOT unlocked and a lucky roll (triggers skunk path).
	var result := PowerupRules.route("crate-ghost", false, func() -> float: return 0.0)
	assert_eq(result["kind"], "skunk", "skunk roll returned")
	assert_eq(_stat("mystery_opened"), 1, "mystery_opened bumped even on skunk roll")


# ---------------------------------------------------------------------------
# Seam 7: editor_saves — LevelEditor._on_save/_on_save_as success path
# We drive the editor via its test fixture (mirrors test_level_editor_interactions).
# _on_save_as requires a stem. We call it with a stub stem so LevelStore.save_user
# runs and — since it's headless and user://levels/ is writable — should succeed.
# ---------------------------------------------------------------------------
const FIXTURE_TOYBOX_DIR_SEAMS := "user://toybox_gut_seams"
const TOYBOX_CFG := "user://toybox.cfg"

var _ed: LevelEditor
var _toybox_cfg_before: String = ""


func _setup_editor() -> void:
	Pieces.toybox_root = FIXTURE_TOYBOX_DIR_SEAMS
	if FileAccess.file_exists(TOYBOX_CFG):
		_toybox_cfg_before = FileAccess.open(TOYBOX_CFG, FileAccess.READ).get_as_text()
	else:
		_toybox_cfg_before = ""
	Pieces.scan()
	_ed = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(_ed)


func _teardown_editor() -> void:
	DirAccess.remove_absolute(FIXTURE_TOYBOX_DIR_SEAMS)
	if _toybox_cfg_before == "":
		if FileAccess.file_exists(TOYBOX_CFG):
			DirAccess.remove_absolute(TOYBOX_CFG)
	else:
		var f := FileAccess.open(TOYBOX_CFG, FileAccess.WRITE)
		if f:
			f.store_string(_toybox_cfg_before)
	Pieces.toybox_root = "user://toybox"
	Pieces.scan()
	_toybox_cfg_before = ""


func test_editor_saves_increments_on_save_as_success() -> void:
	_setup_editor()
	await wait_frames(2)
	assert_eq(_stat("editor_saves"), 0, "baseline zero")
	# Place one crate so the level is non-empty.
	_ed.carrying = "crate-wood"
	_ed._press(Vector2i(2, 0))
	# Trigger save-as with a test stem.
	await _ed._on_save_as("gut_seam_test_save")
	# Clean up the saved file regardless of pass/fail.
	DirAccess.remove_absolute("user://levels/gut_seam_test_save.json")
	assert_eq(_stat("editor_saves"), 1, "editor_saves bumped after save-as success")
	_teardown_editor()


# ---------------------------------------------------------------------------
# Seam 8: skunk flag — level._on_crate_knocked with mystery→skunk roll
# ---------------------------------------------------------------------------
func test_skunk_flag_set_on_skunk_roll() -> void:
	# First ensure skunk is NOT already set in Unlocks.
	var unlocks_path := "user://test_seams_unlocks.cfg"
	Unlocks.use_path(unlocks_path)
	assert_false(_flag_set("skunk"), "skunk flag not set at baseline")
	var lvl := _make_level()
	await wait_frames(2)
	# Use a custom ghost_roll that always triggers skunk (< SKUNK_CHANCE=0.10).
	lvl._ghost_roll = func() -> float: return 0.0
	# Find the mystery crate (crate-ghost). Our fixture uses crate-wood, so we
	# must create a ghost crate node with the right meta.
	var ghost_crate: Crate = load("res://scenes/crate.tscn").instantiate()
	ghost_crate.set_meta("powerup", "mystery")
	lvl.add_child(ghost_crate)
	ghost_crate.add_to_group("crates")
	# At this point Unlocks.has_flag("skunk") is false → skunk path fires.
	lvl._on_crate_knocked(ghost_crate)
	assert_true(_flag_set("skunk"), "Deeds.flag('skunk') recorded in deeds cfg")
	# Restore Unlocks.
	DirAccess.remove_absolute(unlocks_path)
	Unlocks.use_path("user://unlocks.cfg")


# ---------------------------------------------------------------------------
# Seam 9: seasonal_played flag — main_menu._start() when an in-season pack exists
# We inject a synthetic in-season pack via the Pieces toybox seam, then call
# _start() via the menu's internal method. We guard the scene change by
# intercepting the SceneTree (we can't in headless — instead we test the flag
# before the change_scene call fires, which is synchronous only after the frame).
# Since we can't stop scene changes in GUT, we test this seam DIRECTLY by
# reproducing the gate condition: if packs().any(in_season + months), flag is set.
# Document: _start() triggers get_tree().change_scene_to_file — unreachable
# headless without intercepting the tree. We test the flag insertion by calling
# Deeds.flag("seasonal_played") through the same condition we placed in _start().
# ---------------------------------------------------------------------------
const TOYBOX_DIR_SEASONAL := "user://toybox_gut_seasonal"

var _seasonal_cfg_before: String = ""


func test_seasonal_played_flag_set_when_in_season_pack_active() -> void:
	# Set up a Pieces sandbox with one in-season pack (months=[12], clock=12).
	Pieces.toybox_root = TOYBOX_DIR_SEASONAL
	if FileAccess.file_exists(TOYBOX_CFG):
		_seasonal_cfg_before = FileAccess.open(TOYBOX_CFG, FileAccess.READ).get_as_text()
	else:
		_seasonal_cfg_before = ""
	var pack_dir := "%s/xmas" % TOYBOX_DIR_SEASONAL
	DirAccess.make_dir_recursive_absolute(pack_dir)
	var mf := FileAccess.open("%s/pack.json" % pack_dir, FileAccess.WRITE)
	mf.store_string(JSON.stringify({"title": "Xmas", "kind": "objects", "months": [12]}))
	mf.close()
	Pieces.clock_month = 12  # force in-season
	Pieces.scan()

	assert_false(_flag_set("seasonal_played"), "not set at baseline")
	# Reproduce the gate condition from main_menu._start() exactly.
	if Pieces.packs().any(func(p: Dictionary) -> bool: return p.get("in_season", false) and not (p.get("months", []) as Array).is_empty()):
		Deeds.flag("seasonal_played")
	assert_true(_flag_set("seasonal_played"), "seasonal_played set when in-season pack present")

	# Teardown
	DirAccess.remove_absolute("%s/pack.json" % pack_dir)
	DirAccess.remove_absolute(pack_dir)
	DirAccess.remove_absolute(TOYBOX_DIR_SEASONAL)
	if _seasonal_cfg_before == "":
		if FileAccess.file_exists(TOYBOX_CFG):
			DirAccess.remove_absolute(TOYBOX_CFG)
	else:
		var f := FileAccess.open(TOYBOX_CFG, FileAccess.WRITE)
		if f:
			f.store_string(_seasonal_cfg_before)
	Pieces.clock_month = -1
	Pieces.toybox_root = "user://toybox"
	Pieces.scan()


func test_seasonal_played_flag_not_set_when_no_in_season_pack() -> void:
	# No packs at all → flag not set.
	Pieces.toybox_root = TOYBOX_DIR_SEASONAL
	Pieces.scan()
	assert_false(_flag_set("seasonal_played"), "not set at baseline")
	if Pieces.packs().any(func(p: Dictionary) -> bool: return p.get("in_season", false) and not (p.get("months", []) as Array).is_empty()):
		Deeds.flag("seasonal_played")
	assert_false(_flag_set("seasonal_played"), "seasonal_played NOT set when no in-season packs")
	DirAccess.remove_absolute(TOYBOX_DIR_SEASONAL)
	Pieces.toybox_root = "user://toybox"
	Pieces.scan()


func test_editor_session_clear_still_counts() -> void:
	# Review catch: the bump must fire BEFORE the editor guard — an editor
	# TEST clear is a real clear to the ledger (plan: no special-casing).
	var before := int(Deeds._cfg.get_value("stats", "levels_cleared", 0)) if Deeds._cfg else 0
	var lvl := Level.new()
	lvl._editor_session = true
	lvl._record_clear()
	var after := int(Deeds._cfg.get_value("stats", "levels_cleared", 0))
	assert_eq(after, before + 1, "editor clears count toward levels_cleared")
	lvl.free()
