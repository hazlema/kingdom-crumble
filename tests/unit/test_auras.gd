extends GutTest

# Task 1: Auras — ambient particle system on any piece.
# Tests: known table, attach, parse_sidecar, crate spawn, prop spawn.

const TOYBOX_DIR := "user://toybox_gut"
const TOYBOX_CFG := "user://toybox.cfg"

var _created_folders: Array[String] = []
var _cfg_before: String = ""


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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_pack(folder: String, manifest: Dictionary, pngs: Dictionary = {}, sidecars: Dictionary = {}) -> void:
	var pack_dir := "%s/%s" % [TOYBOX_DIR, folder]
	DirAccess.make_dir_recursive_absolute(pack_dir)
	_created_folders.append(folder)
	var mf := FileAccess.open("%s/pack.json" % pack_dir, FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest))
	mf.close()
	for basename: String in pngs:
		var img: Image = pngs[basename]
		img.save_png("%s/%s" % [pack_dir, basename])
	for basename: String in sidecars:
		var sc := FileAccess.open("%s/%s" % [pack_dir, basename], FileAccess.WRITE)
		sc.store_string(JSON.stringify(sidecars[basename]))
		sc.close()


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
# Tests — Auras.KNOWN and attach
# ---------------------------------------------------------------------------

func test_known_table_is_curated_v1() -> void:
	# Exactly ["embers", "mist", "smog-green", "sparkle"] when sorted.
	var keys := Auras.KNOWN.keys().duplicate()
	keys.sort()
	assert_eq(keys, ["embers", "mist", "smog-green", "sparkle"])


func test_attach_known_adds_capped_emitter() -> void:
	# attach("smog-green") → exactly one CPUParticles2D child,
	# emitting, local_coords == false, amount <= 12.
	var host := Node2D.new()
	add_child_autofree(host)
	Auras.attach(host, "smog-green")
	var particles := host.get_children().filter(func(c): return c is CPUParticles2D)
	assert_eq(particles.size(), 1, "exactly one CPUParticles2D child")
	var p: CPUParticles2D = particles[0]
	assert_true(p.emitting, "emitter is emitting")
	assert_false(p.local_coords, "local_coords == false")
	assert_lte(p.amount, 12, "amount capped at 12")


func test_attach_unknown_warns_and_adds_nothing() -> void:
	# attach("smog-purple") → zero children  # warns
	var host := Node2D.new()
	add_child_autofree(host)
	Auras.attach(host, "smog-purple")  # warns
	var particles := host.get_children().filter(func(c): return c is CPUParticles2D)
	assert_eq(particles.size(), 0, "unknown aura adds no children")


func test_attach_empty_is_silent_noop() -> void:
	# attach("") → zero children, NO warning (the every-piece default path)
	var host := Node2D.new()
	add_child_autofree(host)
	Auras.attach(host, "")
	var particles := host.get_children().filter(func(c): return c is CPUParticles2D)
	assert_eq(particles.size(), 0, "empty id is a silent no-op")


# ---------------------------------------------------------------------------
# Tests — parse_sidecar aura key
# ---------------------------------------------------------------------------

func test_parse_sidecar_aura_curated() -> void:
	# Known id accepted.
	var meta := Pieces.parse_sidecar("t", {"aura": "smog-green"})
	assert_eq(meta.get("aura", ""), "smog-green", "known aura passes through")

	# Unknown string warns and is omitted (or set to "").
	var meta_bad := Pieces.parse_sidecar("t", {"aura": "nonsense"})  # warns
	assert_eq(meta_bad.get("aura", ""), "", "unknown aura warns and is not stored")

	# Wrong type handled per parse_sidecar's existing style (warns + fallback).
	var meta_int := Pieces.parse_sidecar("t", {"aura": 7})  # warns
	assert_eq(meta_int.get("aura", ""), "", "non-string aura is treated as absent")


func test_parse_sidecar_aura_absent_defaults_empty() -> void:
	var meta := Pieces.parse_sidecar("t", {})
	assert_eq(meta.get("aura", ""), "", "absent aura defaults to empty string")


# ---------------------------------------------------------------------------
# Tests — integration: crate spawn carries the aura
# ---------------------------------------------------------------------------

func test_crate_spawn_attaches_aura() -> void:
	# Build a toybox pack with one crate piece that carries "embers" aura.
	# Verify: spawned crate has a CPUParticles2D child.
	# Verify: plain wood crate has none.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var sidecar := {"class": "crate", "aura": "embers"}
	_make_pack(
		"aura_pack",
		{"title": "Aura Pack", "kind": "objects"},
		{"aura-crate.png": img},
		{"aura-crate.json": sidecar}
	)
	Pieces.scan()

	# Spawn the aura crate through the REAL LevelBuilder path.
	var host := Node2D.new()
	add_child_autofree(host)
	var layout_aura := LevelLayout.new()
	layout_aura.crates = [{"x": 200.0, "y": 400.0, "type": "aura_pack:aura-crate"}]
	var tex_lookup := func(id: String) -> Texture2D: return Pieces.texture_for(id)
	var spawned_aura := LevelBuilder.spawn_crates(host, layout_aura, true, tex_lookup)
	assert_eq(spawned_aura.size(), 1, "aura crate spawned")
	var aura_crate: Crate = spawned_aura[0]
	var aura_particles := aura_crate.get_children().filter(func(c): return c is CPUParticles2D)
	assert_eq(aura_particles.size(), 1, "aura crate has a CPUParticles2D child")

	# Plain wood crate should have none.
	var layout_plain := LevelLayout.new()
	layout_plain.crates = [{"x": 300.0, "y": 400.0, "type": "crate-wood"}]
	var spawned_plain := LevelBuilder.spawn_crates(host, layout_plain, true, tex_lookup)
	assert_eq(spawned_plain.size(), 1, "plain crate spawned")
	var plain_crate: Crate = spawned_plain[0]
	var plain_particles := plain_crate.get_children().filter(func(c): return c is CPUParticles2D)
	assert_eq(plain_particles.size(), 0, "plain wood crate has no aura particles")


# ---------------------------------------------------------------------------
# Tests — integration: prop spawn carries the aura
# ---------------------------------------------------------------------------

func test_prop_spawn_attaches_aura() -> void:
	# Build a toybox pack with a static piece that carries "mist" aura.
	# Verify: spawned prop has a CPUParticles2D child (plus its NarfDecor sprite).
	var img := Image.create(64, 63, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	var sidecar := {"class": "static", "aura": "mist"}
	_make_pack(
		"aura_prop_pack",
		{"title": "Aura Prop Pack", "kind": "objects"},
		{"aura-block.png": img},
		{"aura-block.json": sidecar}
	)
	Pieces.scan()

	var host := Node2D.new()
	add_child_autofree(host)
	var layout := LevelLayout.new()
	var anchor := EditorGrid.cell_to_world(Vector2i(5, 0))
	layout.props = [{"id": "aura_prop_pack:aura-block", "x": anchor.x, "y": anchor.y}]
	var spawned := PropBuilder.spawn_props(host, layout)
	assert_eq(spawned.size(), 1, "aura prop spawned")
	var body: Node2D = spawned[0]
	var aura_particles := body.get_children().filter(func(c): return c is CPUParticles2D)
	assert_eq(aura_particles.size(), 1, "aura prop has a CPUParticles2D child")
