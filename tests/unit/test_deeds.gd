extends GutTest

# Deeds autoload test suite.
# All tests sandbox via Deeds.cfg_path / Deeds.manifest_path seams.
# Fixture manifests are written to user:// scratch names.
# after_each restores both paths and calls Deeds.reload().

const CFG_SCRATCH := "user://test_deeds_scratch.cfg"
const MAN_SCRATCH := "user://test_deeds_manifest.json"

# Signal capture list — reset each test
var _signals: Array = []
# Bound callable so we can disconnect cleanly in after_each
var _signal_cb: Callable


func _on_deed_unlocked(id: String) -> void:
	_signals.append(id)


func _write_manifest(entries: Array) -> void:
	var fa := FileAccess.open(MAN_SCRATCH, FileAccess.WRITE)
	fa.store_string(JSON.stringify(entries))
	fa.close()


func before_each() -> void:
	# Remove any stale scratch files
	if FileAccess.file_exists(CFG_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_SCRATCH))
	if FileAccess.file_exists(MAN_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAN_SCRATCH))
	_signals = []
	# Point Deeds at scratch paths
	Deeds.cfg_path = CFG_SCRATCH
	Deeds.manifest_path = MAN_SCRATCH
	# Connect signal (fresh each test via method reference)
	_signal_cb = _on_deed_unlocked
	Deeds.deed_unlocked.connect(_signal_cb)


func after_each() -> void:
	# Disconnect signal before restoring state
	if Deeds.deed_unlocked.is_connected(_signal_cb):
		Deeds.deed_unlocked.disconnect(_signal_cb)
	# Restore defaults and clean up
	Deeds.cfg_path = "user://deeds.cfg"
	Deeds.manifest_path = "res://achievements/achievements.manifest"
	Deeds.reload()
	if FileAccess.file_exists(CFG_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_SCRATCH))
	if FileAccess.file_exists(MAN_SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAN_SCRATCH))


# ---------------------------------------------------------------------------
# test_manifest_loads_valid_entries_in_order
# 3 valid entries -> entries() size 3, same order as file
# ---------------------------------------------------------------------------
func test_manifest_loads_valid_entries_in_order() -> void:
	_write_manifest([
		{"id": "alpha", "name": "Alpha", "text": "First", "solid": "a.png", "ghost": "", "trigger": "flag:alpha", "secret": false},
		{"id": "beta",  "name": "Beta",  "text": "Second","solid": "b.png", "ghost": "", "trigger": "flag:beta",  "secret": false},
		{"id": "gamma", "name": "Gamma", "text": "Third", "solid": "g.png", "ghost": "", "trigger": "flag:gamma", "secret": false},
	])
	Deeds.reload()
	var e := Deeds.entries()
	assert_eq(e.size(), 3, "three valid entries load")
	assert_eq(e[0]["id"], "alpha")
	assert_eq(e[1]["id"], "beta")
	assert_eq(e[2]["id"], "gamma")


# ---------------------------------------------------------------------------
# test_malformed_entry_warns_and_skips
# bad id charset / missing trigger -> that entry absent, others load  # warns
# ---------------------------------------------------------------------------
func test_malformed_entry_warns_and_skips() -> void:
	_write_manifest([
		{"id": "good_one",   "name": "Good",   "text": "ok",  "solid": "g.png", "ghost": "", "trigger": "flag:good_one",   "secret": false},
		{"id": "BAD ID!",    "name": "Bad",    "text": "bad", "solid": "b.png", "ghost": "", "trigger": "flag:something",  "secret": false},
		{"id": "no_trigger", "name": "NoTrig", "text": "nt",  "solid": "n.png", "ghost": ""},
		{"id": "good_two",   "name": "Good2",  "text": "ok2", "solid": "g2.png","ghost": "", "trigger": "flag:good_two",   "secret": false},
	])
	Deeds.reload()
	var e := Deeds.entries()
	assert_eq(e.size(), 2, "only two valid entries survive")
	assert_eq(e[0]["id"], "good_one")
	assert_eq(e[1]["id"], "good_two")


# ---------------------------------------------------------------------------
# test_count_trigger_unlocks_at_threshold
# trigger count:crates_smashed>=3; bump x2 -> locked; 3rd bump -> unlocked + signal
# ---------------------------------------------------------------------------
func test_count_trigger_unlocks_at_threshold() -> void:
	_write_manifest([
		{"id": "crate_smasher", "name": "Crate Smasher", "text": "Smash!", "solid": "cs.png", "ghost": "", "trigger": "count:crates_smashed>=3", "secret": false},
	])
	Deeds.reload()

	Deeds.bump("crates_smashed")
	assert_false(Deeds.is_unlocked("crate_smasher"), "not yet unlocked at 1")
	assert_eq(_signals.size(), 0)

	Deeds.bump("crates_smashed")
	assert_false(Deeds.is_unlocked("crate_smasher"), "not yet unlocked at 2")
	assert_eq(_signals.size(), 0)

	Deeds.bump("crates_smashed")
	assert_true(Deeds.is_unlocked("crate_smasher"), "unlocked at 3")
	assert_eq(_signals.size(), 1, "signal fired exactly once")
	assert_eq(_signals[0], "crate_smasher")


# ---------------------------------------------------------------------------
# test_flag_trigger
# flag:skunk -> is_unlocked after Deeds.flag("skunk")
# ---------------------------------------------------------------------------
func test_flag_trigger() -> void:
	_write_manifest([
		{"id": "skunks_ally", "name": "Skunk's Ally", "text": "Met the skunk", "solid": "sk.png", "ghost": "", "trigger": "flag:skunk", "secret": false},
	])
	Deeds.reload()

	assert_false(Deeds.is_unlocked("skunks_ally"), "not yet unlocked")
	Deeds.flag("skunk")
	assert_true(Deeds.is_unlocked("skunks_ally"), "unlocked after flag")
	assert_eq(_signals.size(), 1)
	assert_eq(_signals[0], "skunks_ally")


# ---------------------------------------------------------------------------
# test_meta_unlocked_trigger
# unlocked:a,b unlocks only when BOTH a and b unlocked;
# fires in same write as the last dependency
# ---------------------------------------------------------------------------
func test_meta_unlocked_trigger() -> void:
	_write_manifest([
		{"id": "a", "name": "A", "text": "deed a", "solid": "a.png", "ghost": "", "trigger": "flag:a_done", "secret": false},
		{"id": "b", "name": "B", "text": "deed b", "solid": "b.png", "ghost": "", "trigger": "flag:b_done", "secret": false},
		{"id": "meta", "name": "Meta", "text": "both", "solid": "m.png", "ghost": "", "trigger": "unlocked:a,b", "secret": false},
	])
	Deeds.reload()

	Deeds.flag("a_done")
	assert_true(Deeds.is_unlocked("a"), "a unlocked")
	assert_false(Deeds.is_unlocked("meta"), "meta still needs b")

	Deeds.flag("b_done")
	assert_true(Deeds.is_unlocked("b"), "b unlocked")
	assert_true(Deeds.is_unlocked("meta"), "meta unlocked when both deps met")

	# meta should fire in same write as b (in manifest order: a, b, meta)
	assert_true("meta" in _signals, "meta signal fired")
	var b_idx := _signals.find("b")
	var meta_idx := _signals.find("meta")
	assert_true(b_idx >= 0 and meta_idx >= 0, "both signals present")
	assert_true(meta_idx > b_idx, "meta fires after b in same write")


# ---------------------------------------------------------------------------
# test_unlocked_cycle_disabled
# a requires unlocked:b, b requires unlocked:a -> both disabled  # warns
# ---------------------------------------------------------------------------
func test_unlocked_cycle_disabled() -> void:
	_write_manifest([
		{"id": "cyc_a", "name": "A", "text": "a", "solid": "a.png", "ghost": "", "trigger": "unlocked:cyc_b", "secret": false},
		{"id": "cyc_b", "name": "B", "text": "b", "solid": "b.png", "ghost": "", "trigger": "unlocked:cyc_a", "secret": false},
	])
	Deeds.reload()
	# Both should be absent from entries() — disabled by cycle detection
	var e := Deeds.entries()
	var ids := e.map(func(d: Dictionary) -> String: return d["id"])
	assert_false("cyc_a" in ids, "cyc_a disabled due to cycle")
	assert_false("cyc_b" in ids, "cyc_b disabled due to cycle")


# ---------------------------------------------------------------------------
# test_signal_fires_once_ever
# unlock, then bump the stat again / reload -> no second deed_unlocked
# ---------------------------------------------------------------------------
func test_signal_fires_once_ever() -> void:
	_write_manifest([
		{"id": "one_shot", "name": "One Shot", "text": "once", "solid": "o.png", "ghost": "", "trigger": "count:shots_fired>=1", "secret": false},
	])
	Deeds.reload()

	Deeds.bump("shots_fired")
	assert_eq(_signals.size(), 1, "signal fired once on unlock")

	# Bump again — should not re-fire
	Deeds.bump("shots_fired")
	assert_eq(_signals.size(), 1, "no second signal after extra bump")

	# Reload from same cfg — should not re-fire
	Deeds.reload()
	assert_eq(_signals.size(), 1, "no signal on reload when already celebrated")


# ---------------------------------------------------------------------------
# test_cfg_round_trip
# bump/flag, new Deeds load from same cfg -> stats and celebrated persist
# ---------------------------------------------------------------------------
func test_cfg_round_trip() -> void:
	_write_manifest([
		{"id": "round_trip", "name": "Round Trip", "text": "persist", "solid": "r.png", "ghost": "", "trigger": "count:rt_stat>=2", "secret": false},
	])
	Deeds.reload()

	Deeds.bump("rt_stat")
	Deeds.bump("rt_stat")
	assert_true(Deeds.is_unlocked("round_trip"), "unlocked after 2 bumps")

	# Reload simulates a new session reading the same cfg
	Deeds.reload()
	assert_true(Deeds.is_unlocked("round_trip"), "still unlocked after reload — celebrated persists")


# ---------------------------------------------------------------------------
# test_unknown_stat_in_trigger_never_fires
# trigger count:windmills>=1 with no such stat recorded -> stays locked, no crash
# warns once at load
# ---------------------------------------------------------------------------
func test_unknown_stat_in_trigger_never_fires() -> void:
	_write_manifest([
		{"id": "windmill_whiz", "name": "Windmill Whiz", "text": "secret", "solid": "w.png", "ghost": "", "trigger": "count:windmill_rides>=1", "secret": true},
	])
	Deeds.reload()

	# Should load fine (unknown stat = warn once, but entry is valid)
	var e := Deeds.entries()
	assert_eq(e.size(), 1, "entry loaded despite unknown stat")
	assert_false(Deeds.is_unlocked("windmill_whiz"), "never fires without the stat")

	# Bump an unrelated stat — still not unlocked
	Deeds.bump("crates_smashed")
	assert_false(Deeds.is_unlocked("windmill_whiz"), "stays locked, no crash")


# ---------------------------------------------------------------------------
# test_version_gate_wipes_deeds_cfg
# VersionGate.apply with testing+version-change with deeds.cfg present -> file gone
# (mirror test_version_gate.gd style)
# ---------------------------------------------------------------------------
func test_version_gate_wipes_deeds_cfg() -> void:
	const DIR := "user://vgate_deeds_gut"
	const STAMP := DIR + "/version.cfg"
	var deeds_cfg := DIR + "/deeds.cfg"
	var files: Array[String] = [deeds_cfg]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

	# Create a fake deeds.cfg
	var fa := FileAccess.open(deeds_cfg, FileAccess.WRITE)
	fa.store_string("[stats]\ncrates_smashed=5\n")
	fa.close()

	# First apply: stamps 1.0
	VersionGate.apply("1.0", true, files, STAMP)
	assert_true(FileAccess.file_exists(deeds_cfg), "file present before version change")

	# Second apply: version changes -> wipe
	var wiped := VersionGate.apply("1.1", true, files, STAMP)
	assert_true(wiped, "version gate wiped on change")
	assert_false(FileAccess.file_exists(deeds_cfg), "deeds.cfg wiped by version gate")

	# Cleanup
	if FileAccess.file_exists(STAMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STAMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_negative_threshold_rejected() -> void:
	# Review catch: count:x>=-1 is always-true — an authoring bug, skipped.
	_write_manifest([{"id": "oops", "name": "Oops", "text": "t",
		"solid": "x.png", "trigger": "count:shots_fired>=-1"}])
	Deeds.reload()
	assert_eq(Deeds.entries().size(), 0, "negative threshold entry is skipped at load")
