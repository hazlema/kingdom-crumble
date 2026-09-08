extends GutTest

# ---------------------------------------------------------------------------
# Toybox sandbox — mirrors test_toybox.gd conventions
# ---------------------------------------------------------------------------
const TOYBOX_DIR := "user://toybox_gut_pr"
const TOYBOX_CFG := "user://toybox.cfg"

var _cfg_before: String = ""
var _created_folders: Array[String] = []


func before_each() -> void:
	Pieces.toybox_root = TOYBOX_DIR
	if FileAccess.file_exists(TOYBOX_CFG):
		_cfg_before = FileAccess.open(TOYBOX_CFG, FileAccess.READ).get_as_text()
	else:
		_cfg_before = ""
	_created_folders.clear()
	Pieces.clock_month = -1


func after_each() -> void:
	get_tree().paused = false
	_nuke_toybox()
	if _cfg_before == "":
		if FileAccess.file_exists(TOYBOX_CFG):
			DirAccess.remove_absolute(TOYBOX_CFG)
	else:
		var f := FileAccess.open(TOYBOX_CFG, FileAccess.WRITE)
		if f:
			f.store_string(_cfg_before)
	Pieces.clock_month = -1
	Pieces.toybox_root = "user://toybox"
	Pieces.scan()


func _make_pack(folder: String, manifest: Dictionary, sidecars: Dictionary = {}) -> void:
	var pack_dir := "%s/%s" % [TOYBOX_DIR, folder]
	DirAccess.make_dir_recursive_absolute(pack_dir)
	_created_folders.append(folder)
	var mf := FileAccess.open("%s/pack.json" % pack_dir, FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest))
	mf.close()
	for basename: String in sidecars:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		img.save_png("%s/%s.png" % [pack_dir, basename])
		var sidecar_path := "%s/%s.json" % [pack_dir, basename]
		var sf := FileAccess.open(sidecar_path, FileAccess.WRITE)
		sf.store_string(JSON.stringify(sidecars[basename]))
		sf.close()


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


func _fixed(v: float) -> Callable:
	return func() -> float: return v


func test_type_routing() -> void:
	assert_eq(PowerupRules.route("crate-wood", false, _fixed(0.0))["kind"], "none")
	assert_eq(PowerupRules.route("crate-gold", false, _fixed(0.0))["kind"], "refund")
	var skull := PowerupRules.route("skull", false, _fixed(0.0))
	assert_eq(skull["kind"], "buff")
	assert_eq(skull["buff"], &"exploding")
	assert_eq(PowerupRules.route("crate-blue", false, _fixed(0.0))["buff"], &"multishot")
	assert_eq(PowerupRules.route("crate-green", false, _fixed(0.0))["buff"], &"super_bounce")
	assert_eq(PowerupRules.route("mystery-type", false, _fixed(0.0))["kind"], "none")


func test_ghost_rolls_skunk_only_when_locked_and_lucky() -> void:
	assert_eq(PowerupRules.route("crate-ghost", false, _fixed(0.0))["kind"], "skunk")
	assert_ne(PowerupRules.route("crate-ghost", true, _fixed(0.0))["kind"], "skunk")
	assert_ne(PowerupRules.route("crate-ghost", false, _fixed(0.9))["kind"], "skunk")


func test_ghost_pool_reaches_all_four() -> void:
	var kinds := {}
	for v in [0.13, 0.38, 0.63, 0.88]:
		var r := PowerupRules.route("crate-ghost", true, _fixed(v))
		var key: String = r["label"] if r.has("label") else r["kind"]
		kinds[key] = true
	assert_eq(kinds.size(), 4, "four distinct outcomes across the roll range")


func test_drain_one_charge_per_type() -> void:
	var q: Array[StringName] = [&"exploding", &"exploding", &"multishot"]
	var d := PowerupRules.drain(q)
	assert_true(d["consumed"].has(&"exploding"))
	assert_true(d["consumed"].has(&"multishot"))
	assert_eq(d["consumed"].size(), 2)
	assert_eq(d["remaining"], [&"exploding"] as Array[StringName])


func test_drain_empty() -> void:
	var d := PowerupRules.drain([] as Array[StringName])
	assert_eq(d["consumed"].size(), 0)
	assert_eq(d["remaining"].size(), 0)


# ---------------------------------------------------------------------------
# Audit 2026-09-08 — Finding 7: powerup snapshot at spawn
# ---------------------------------------------------------------------------

## Audit reproduction: spawn a pack crate with powerup:free_shot, disable the
## pack mid-"level", then route the ALREADY-SPAWNED crate → still "refund".
## The crate's metadata snapshot (set at spawn) must override the now-empty registry.
func test_spawned_crate_powerup_survives_pack_disable() -> void:
	# Set up a pack with a free_shot piece
	_make_pack("snappack", {"title": "Snap Pack", "kind": "objects"},
		{"snap-crate": {"class": "crate", "powerup": "free_shot"}})
	Pieces.scan()
	assert_false(Pieces.entry("snappack:snap-crate").is_empty(), "piece registered before disable")

	# Spawn the crate — LevelBuilder.spawn_crates must call crate.set_meta("powerup", ...)
	var host := Node2D.new()
	add_child_autofree(host)
	var layout := LevelLayout.new()
	layout.crates.append({"x": 100.0, "y": 100.0, "type": "snappack:snap-crate"})
	var spawned := LevelBuilder.spawn_crates(
		host, layout, true, func(_id: String) -> Texture2D: return null
	)
	assert_eq(spawned.size(), 1, "one crate spawned")
	var crate := spawned[0]
	assert_true(crate.has_meta("powerup"), "crate has 'powerup' meta set at spawn")
	assert_eq(str(crate.get_meta("powerup")), "free_shot", "snapshot value is free_shot")

	# Now route via the crate node — PowerupRules.route_crate must consult meta first
	var result_before := PowerupRules.route_crate(crate, false, _fixed(0.5))
	assert_eq(result_before["kind"], "refund", "free_shot routes to refund before disable")

	# Disable the pack mid-level (simulates pause menu toggle)
	Pieces.set_pack_enabled("snappack", false)
	assert_true(Pieces.entry("snappack:snap-crate").is_empty(), "entry gone after disable")

	# Route the SAME already-spawned crate → must still refund (snapshot)
	var result_after := PowerupRules.route_crate(crate, false, _fixed(0.5))
	assert_eq(result_after["kind"], "refund",
		"spawned crate still refunds after pack disabled — snapshot intact")


## A freshly spawned crate AFTER rescan follows the new (disabled) registry.
func test_newly_spawned_crate_after_disable_has_no_powerup() -> void:
	_make_pack("snappack2", {"title": "Snap2", "kind": "objects"},
		{"snap2-crate": {"class": "crate", "powerup": "free_shot"}})
	Pieces.scan()

	# Disable immediately — piece leaves registry
	Pieces.set_pack_enabled("snappack2", false)
	assert_true(Pieces.entry("snappack2:snap2-crate").is_empty(), "entry gone")

	# Spawn a new crate using the disabled type
	var host := Node2D.new()
	add_child_autofree(host)
	var layout := LevelLayout.new()
	layout.crates.append({"x": 50.0, "y": 50.0, "type": "snappack2:snap2-crate"})
	var spawned := LevelBuilder.spawn_crates(
		host, layout, true, func(_id: String) -> Texture2D: return null
	)
	assert_eq(spawned.size(), 1, "one crate spawned even for disabled type")
	var crate := spawned[0]
	# Snapshot should be empty because entry() returned {} at spawn time
	assert_true(crate.has_meta("powerup"), "powerup meta always set at spawn")
	assert_eq(str(crate.get_meta("powerup")), "", "no powerup when disabled at spawn time")

	# Route via crate → should be none
	var result := PowerupRules.route_crate(crate, false, _fixed(0.5))
	assert_eq(result["kind"], "none", "newly spawned crate after disable routes to none")


## route() (type_id string) still works for callers without a crate node (compat).
func test_route_string_api_compat_still_works() -> void:
	# The original string route() must remain callable and correct for baked types
	assert_eq(PowerupRules.route("crate-gold", false, _fixed(0.0))["kind"], "refund")


## The call-site pin the first pass lacked: the fix is only real if the
## GAMEPLAY knock path uses the snapshot. Drive level.gd's actual
## _on_crate_knocked with a pack crate, disable the pack mid-level, and
## watch the refund land in shots_left — through the game, not the API.
func test_knock_path_uses_snapshot_after_pack_disable() -> void:
	_make_pack("livepack", {"title": "Live Pack", "kind": "objects"},
		{"live-crate": {"class": "crate", "powerup": "free_shot"}})
	Pieces.scan()
	var layout := LevelLayout.new()
	layout.title = "snapshot_gate"
	layout.crates.append({"x": 832.0, "y": 443.0, "type": "livepack:live-crate"})
	layout.shots = 3
	Level.next_layout = layout
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	var crate: Crate = lvl.get_tree().get_nodes_in_group("crates")[0]
	Pieces.set_pack_enabled("livepack", false)  # mid-level toggle
	var shots_before: int = lvl.shots_left
	lvl._on_crate_knocked(crate)
	assert_eq(lvl.shots_left, shots_before + 1,
		"gold-style refund fired from the spawn-time snapshot, not the gutted registry")
