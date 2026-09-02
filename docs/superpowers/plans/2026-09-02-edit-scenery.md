# Edit Scenery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Levels embed custom images (`images` dict, hash keys) placed as living scenery (`overlays` via NarfDecor); the editor grows an EDIT SCENERY mode — themed FileDialog import with auto-downscale, drag/handles/inspector editing, transforms baked into the raster at save.

**Architecture:** Format first (thumb-field precedent, shared PNG-gate helper promoted out of LevelCard), then a pure `SceneryBuilder` used by game and editor alike, then the editor mode in three slices: panel/mode skeleton → import pipeline → selection/handles/inspector/bake.

**Tech Stack:** Godot 4.6.2, GDScript, GUT headless, NarfKit (NarfDecor).

## Global Constraints

- `$GODOT` = `/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64`; project `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble`. Import once after new files. Suite: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` — **216 green at start, only grows.**
- Spec (binding, owner-approved): `docs/superpowers/specs/2026-09-02-edit-scenery-design.md`. Canon: images ≤ 8 @ ≤ 600_000 b64 chars each, PNG-magic-gated, silent degrade; overlays ≤ 16, coordinate caps like crates, enum names validated against NarfDecor, unknown → skip with warning; keys = 8-hex content hashes; absent keys unwritten; scenery draws BEHIND gameplay; editor-owns-zero-gameplay (renderer shared); Godot FileDialog (never native).
- git add ONLY touched files (+ .uid). NEVER -A. `music/chill/old/` and `art/characters/skunk_parts/` are the owner's active work areas — never touch.
- Tabs; gdformat. Tests: gut_-prefixed user:// artifacts, cleaned immediately.
- Suite count arithmetic has drifted before — treat "expected" counts as approximate; report REAL numbers; green is the requirement.

## File Map

- Task 1 modify: `src/level/level_layout.gd`, `src/level/level_json.gd`, `src/ui/level_card.gd`; create: `tests/unit/test_scenery_format.gd`
- Task 2 create: `src/level/scenery_builder.gd`, `tests/unit/test_scenery_builder.gd`; modify: `src/level/level.gd` (one call), `src/editor/level_editor.gd` (one call in `_rebuild`)
- Task 3 create: `scenes/editor_scenery_panel.tscn`, `src/editor/scenery_panel.gd`, `tests/unit/test_scenery_mode.gd`; modify: `src/editor/editor_menu.gd`, `scenes/editor_menu.tscn`, `src/editor/level_editor.gd`
- Task 4 modify: `src/editor/scenery_panel.gd`, `src/editor/level_editor.gd`; extend `tests/unit/test_scenery_mode.gd`
- Task 5 create: `src/editor/scenery_gizmo.gd`; modify: `src/editor/level_editor.gd`, `scenes/editor.tscn`; extend `tests/unit/test_scenery_mode.gd`
- Task 6 create: `scenes/editor_piece_inspector.tscn`, `src/editor/piece_inspector.gd`; modify: `src/editor/level_editor.gd`; extend tests
- Task 7: verification sweep.

---

### Task 1: Format — images + overlays join the json

**Files:**
- Modify: `src/level/level_layout.gd`, `src/level/level_json.gd`, `src/ui/level_card.gd`
- Test: `tests/unit/test_scenery_format.gd` (create)

**Interfaces:**
- Produces: `LevelLayout.images: Dictionary` (String key → base64 String, default {}), `LevelLayout.overlays: Array[Dictionary]` (default []).
- `LevelJson` consts: `MAX_IMAGES := 8`, `MAX_IMAGE_CHARS := 600_000`, `MAX_OVERLAYS := 16`.
- `LevelJson.decode_png_b64(b64: String) -> Image` — THE shared gate (moves LevelCard's private length/alphabet/magic gates into LevelJson; returns null on ANY failure, silently). LevelCard `_embedded_thumb` now calls it (its `static var _b64_rx` and `PNG_MAGIC` move to LevelJson).
- `LevelJson.image_key(png_bytes: PackedByteArray) -> String` — first 8 hex of sha256.
- Validate rules (reject with specific message): `images` must be Dictionary, ≤ MAX_IMAGES, every key a String ≤ 16 chars, every value a String ≤ MAX_IMAGE_CHARS ("bad images" / "too many images" / "image too large"). `overlays` must be Array ≤ MAX_OVERLAYS ("bad overlays" / "too many overlays"); each entry a Dictionary with String `image`, numeric `x`/`y` within ±MAX_COORD ("bad overlay"). Behavior/pivot/speed/amplitude are NOT validate-rejected (unknown names skip at build time per spec).
- serialize writes both keys only when non-empty; parse reads with `{}`/`[]` defaults (duplicate() the dicts so layouts don't share references).

- [ ] **Step 1: failing tests** — create `tests/unit/test_scenery_format.gd`:

```gdscript
extends GutTest


func _tiny_png_b64() -> String:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func _base(d := {}) -> Dictionary:
	var out := {"format": 1, "title": "T", "crates": []}
	out.merge(d)
	return out


func test_scenery_round_trips() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	var b64 := _tiny_png_b64()
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	l.images = {key: b64}
	l.overlays = [{"image": key, "x": 500.0, "y": 100.0, "behavior": "SPIN", "speed": 0.1}]
	var parsed := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(parsed)
	assert_eq(parsed.images[key], b64)
	assert_eq(parsed.overlays[0]["image"], key)
	assert_eq(str(parsed.overlays[0]["behavior"]), "SPIN")


func test_absent_scenery_unwritten() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	var s := LevelJson.serialize(l)
	assert_false(s.contains("images"))
	assert_false(s.contains("overlays"))
	assert_eq(LevelJson.parse(s).images.size(), 0)
	assert_eq(LevelJson.parse(s).overlays.size(), 0)


func test_image_key_is_8_hex_and_deterministic() -> void:
	var bytes := Marshalls.base64_to_raw(_tiny_png_b64())
	var k := LevelJson.image_key(bytes)
	assert_eq(k.length(), 8)
	assert_eq(k, LevelJson.image_key(bytes), "same bytes, same key")


func test_caps_and_shapes_rejected() -> void:
	assert_ne(LevelJson.validate(_base({"images": []})), "", "images must be a dict")
	assert_ne(LevelJson.validate(_base({"overlays": {}})), "", "overlays must be an array")
	var many := {}
	for i in LevelJson.MAX_IMAGES + 1:
		many["k%d" % i] = "aaaa"
	assert_ne(LevelJson.validate(_base({"images": many})), "")
	var big := {"k": "a".repeat(LevelJson.MAX_IMAGE_CHARS + 4)}
	assert_ne(LevelJson.validate(_base({"images": big})), "")
	var lots := []
	for i in LevelJson.MAX_OVERLAYS + 1:
		lots.append({"image": "k", "x": 0, "y": 0})
	assert_ne(LevelJson.validate(_base({"overlays": lots})), "")
	assert_ne(
		LevelJson.validate(_base({"overlays": [{"image": 7, "x": 0, "y": 0}]})), "", "bad entry"
	)
	assert_eq(
		LevelJson.validate(
			_base({"images": {"k": "aaaa"}, "overlays": [{"image": "k", "x": 1.0, "y": 2.0}]})
		),
		"",
		"well-shaped scenery passes"
	)


func test_decode_gate_is_shared_and_silent() -> void:
	assert_null(LevelJson.decode_png_b64(""))
	assert_null(LevelJson.decode_png_b64("abc"), "bad length")
	assert_null(LevelJson.decode_png_b64("YWJjZGFiY2Q="), "not png")
	assert_not_null(LevelJson.decode_png_b64(_tiny_png_b64()))
```

- [ ] **Step 2: run selected — FAIL:** `-gselect=test_scenery_format`
- [ ] **Step 3: implement.** LevelLayout: add after `intro`:

```gdscript
# Embedded scenery art: content-hash key -> base64 PNG (spec 2026-09-02).
@export var images := {}
# Scenery placements: {image, x, y, behavior?, pivot?, speed?, amplitude?}
@export var overlays: Array[Dictionary] = []
```

LevelJson: add consts; `image_key` uses `HashingContext` (HASH_SHA256) over the bytes, hex-encode, `substr(0, 8)`. Move LevelCard's `_b64_rx` static + magic-gate body into `static func decode_png_b64(b64: String) -> Image` (return the decoded Image or null; every failure silent). Validate/parse/serialize per Interfaces — mirror the thumb/intro blocks; parse assigns `l.images = (data.get("images", {}) as Dictionary).duplicate()` and rebuilds overlays as typed `Array[Dictionary]` from `data.get("overlays", [])` entries. LevelCard `_embedded_thumb` shrinks to: decode via `LevelJson.decode_png_b64`, wrap in ImageTexture, null-safe.

- [ ] **Step 4: selected PASS; FULL suite green (~221). LevelCard tests must stay green — the gate moved, behavior identical.**
- [ ] **Step 5: commit** `feat: levels carry scenery — hashed embedded images + overlay entries, shared png gate`

---

### Task 2: SceneryBuilder — one renderer for game and editor

**Files:**
- Create: `src/level/scenery_builder.gd`
- Test: `tests/unit/test_scenery_builder.gd` (create)
- Modify: `src/level/level.gd` (one call after `_spawn_crates()`), `src/editor/level_editor.gd` (one call in `_rebuild`)

**Interfaces:**
- Produces: `SceneryBuilder.spawn(parent: Node, layout: LevelLayout) -> Array[NarfDecor]` — decodes each image once (via `LevelJson.decode_png_b64`), spawns one NarfDecor per overlay entry with: texture, `position = Vector2(x, y)`, behavior/pivot mapped by NAME through `NarfDecor.Behavior.keys()` / `NarfDecor.Pivot.keys()` (unknown name → `push_warning` + skip the entry entirely; missing/broken image → skip), speed/amplitude clamped to the export ranges (0–10, 0–180), `z_index = -1` and `show_behind_parent` unnecessary — instead: caller adds them FIRST so tree order draws them behind gameplay; spawn() also sets `add_to_group("scenery")`.

- [ ] **Step 1: failing tests** — create `tests/unit/test_scenery_builder.gd`:

```gdscript
extends GutTest


func _layout_with(overlays: Array) -> LevelLayout:
	var l := LevelLayout.new()
	l.title = "T"
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.GREEN)
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	l.images = {"abcd1234": b64}
	for o in overlays:
		l.overlays.append(o)
	return l


func test_spawns_living_pieces() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := _layout_with(
		[
			{
				"image": "abcd1234",
				"x": 500.0,
				"y": 200.0,
				"behavior": "SPIN",
				"pivot": "CENTER",
				"speed": 0.5,
			}
		]
	)
	var pieces := SceneryBuilder.spawn(host, l)
	assert_eq(pieces.size(), 1)
	assert_eq(pieces[0].position, Vector2(500, 200))
	assert_eq(pieces[0].behavior, NarfDecor.Behavior.SPIN)
	assert_eq(pieces[0].pivot, NarfDecor.Pivot.CENTER)
	assert_almost_eq(pieces[0].speed, 0.5, 0.001)
	assert_not_null(pieces[0].texture)


func test_defaults_and_hostiles_skip_cleanly() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := _layout_with(
		[
			{"image": "abcd1234", "x": 1.0, "y": 2.0},
			{"image": "missing", "x": 0.0, "y": 0.0},
			{"image": "abcd1234", "x": 0.0, "y": 0.0, "behavior": "EXPLODE"},
			{"image": "abcd1234", "x": 0.0, "y": 0.0, "behavior": "BOB", "speed": 999.0},
		]
	)
	l.images["broken"] = "!!!"
	var pieces := SceneryBuilder.spawn(host, l)
	assert_eq(pieces.size(), 2, "plain + clamped spawn; missing image + unknown verb skip")
	assert_eq(pieces[0].behavior, NarfDecor.Behavior.NONE, "no verb = statue")
	assert_almost_eq(pieces[1].speed, 10.0, 0.001, "speed clamps to the dial range")


func test_no_scenery_no_nodes() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var before := host.get_child_count()
	SceneryBuilder.spawn(host, LevelLayout.new())
	assert_eq(host.get_child_count(), before)
```

- [ ] **Step 2: FAIL:** `-gselect=test_scenery_builder`
- [ ] **Step 3: implement** `src/level/scenery_builder.gd` (class_name SceneryBuilder extends RefCounted; static spawn per Interfaces; decode each distinct image once into a local `Dictionary` cache of ImageTexture). Wiring: in `level.gd` `_ready`, call `SceneryBuilder.spawn(self, layout)` IMMEDIATELY BEFORE `_spawn_crates()` (tree order = scenery behind crates; find the actual call site and match the local layout variable). In `level_editor.gd` `_rebuild`, after clearing spawned crates ALSO free the previous `get_tree().get_nodes_in_group("scenery")` children it owns, then `SceneryBuilder.spawn(self, current)` BEFORE the crate spawn so editing previews match the game.
- [ ] **Step 4: selected PASS; FULL suite green. Levels without scenery: zero new nodes (pinned).**
- [ ] **Step 5: commit** `feat: SceneryBuilder — one shared renderer breathes life into level scenery`

---

### Task 3: EDIT SCENERY mode — button, panel swap, crate guard

**Files:**
- Create: `scenes/editor_scenery_panel.tscn`, `src/editor/scenery_panel.gd`
- Modify: `src/editor/editor_menu.gd` + `scenes/editor_menu.tscn` (background dropdown → EDIT SCENERY button), `src/editor/level_editor.gd`, `scenes/editor.tscn` (instance the panel, hidden)
- Test: `tests/unit/test_scenery_mode.gd` (create)

**Interfaces:**
- EditorMenu: the existing background-picker UI moves OUT of the hamburger; hamburger gains an "EDIT SCENERY" entry emitting `signal scenery_requested`. (READ editor_menu.gd/tscn first; whatever nodes/signals implement `background_picked` migrate into the new panel — keep the signal name.)
- Produces: `SceneryPanel` (PanelContainer, hidden by default, positioned where the crate palette sits — READ how Palette is laid out in editor.tscn and mirror it): contains the migrated background picker, an `ADD IMAGE` button (`signal add_image_requested` — wired in Task 4), a `%Pieces` ItemList (thumbnails, populated in Task 4+), and a DONE button (`signal done`). Emits `background_picked(id)` upward exactly as the menu used to.
- LevelEditor: `enum Mode { CRATES, SCENERY }`, `var mode := Mode.CRATES`. `menu.scenery_requested` → `_enter_scenery()`; panel `done` → `_exit_scenery()`. Enter: hide Palette, show SceneryPanel, `overlay.visible = false` (grid), dim crates (`for c in _spawned: c.modulate.a = 0.8` — restore 1.0 on exit), mode = SCENERY. The crate interaction block in `_process` (the `_press`/`_release`/`_update_ghost` section) is guarded: `if mode == Mode.CRATES:` — scenery mode skips it entirely. Esc in scenery mode = DONE (extend `_unhandled_input`'s menu-action branch: scenery mode → `_exit_scenery()` before the carrying check).
- `background_picked` re-wired from the panel (the editor's existing `_on_background_picked` stays).

- [ ] **Step 1: failing tests** — create `tests/unit/test_scenery_mode.gd`:

```gdscript
extends GutTest

var ed: LevelEditor


func before_each() -> void:
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(ed)


func test_scenery_mode_blocks_crate_placement() -> void:
	ed._enter_scenery()
	ed.carrying = "crate-wood"
	ed._press(Vector2i(2, 0))
	assert_eq(ed.current.crates.size(), 1, "_press itself still works when called")
	ed.current.crates.clear()
	ed._rebuild()
	# the real guard is the polling gate: simulate a frame's decision
	assert_eq(ed.mode, LevelEditor.Mode.SCENERY)
	ed._exit_scenery()
	assert_eq(ed.mode, LevelEditor.Mode.CRATES)


func test_panel_swaps_with_mode() -> void:
	ed._enter_scenery()
	assert_false(ed.palette.visible)
	assert_true(ed.get_node("%SceneryPanel").visible)
	assert_false(ed.overlay.visible, "grid rests during scenery work")
	ed._exit_scenery()
	assert_true(ed.palette.visible)
	assert_false(ed.get_node("%SceneryPanel").visible)
	assert_true(ed.overlay.visible)


func test_background_picker_still_reaches_the_layout() -> void:
	ed._enter_scenery()
	ed.get_node("%SceneryPanel").background_picked.emit("meadow")
	assert_eq(ed.current.background, "meadow")
```

(Plus: since the polling guard can't be driven headless via real mouse, add the direct pin — read `_process`'s guard structure and assert via a one-frame await that placing input is not consumed in scenery mode if feasible; otherwise the mode-flag assertions above + reviewer eyes carry it.)

- [ ] **Step 2: FAIL** → **Step 3: implement per Interfaces** (READ editor_menu.gd, editor.tscn, editor_palette.tscn first; mirror existing panel styling — theme covers most of it). `_mouse_over_ui` must also treat the SceneryPanel rect as UI.
- [ ] **Step 4: selected + FULL green.**
- [ ] **Step 5: commit** `feat: EDIT SCENERY mode — panel swap, crate guard, background picker finds its true home`

---

### Task 4: ADD IMAGE — themed FileDialog + import pipeline

**Files:**
- Modify: `src/editor/scenery_panel.gd`, `src/editor/level_editor.gd`
- Test: extend `tests/unit/test_scenery_mode.gd`

**Interfaces:**
- SceneryPanel owns a `FileDialog` child (`use_native_dialog = false`, FILE_MODE_OPEN_FILE, access FILESYSTEM, filters `*.png,*.jpg,*.jpeg,*.webp`), opened by ADD IMAGE; on file selected emits `image_chosen(path: String)`.
- LevelEditor: `_on_image_chosen(path)` → `import_scenery_image(img: Image) -> String` (separated pure-ish for tests): downscale so `max(w, h) <= 512` (LANCZOS, keep aspect); `save_png_to_buffer`; while b64 length > `LevelJson.MAX_IMAGE_CHARS`: halve the long edge and re-encode; key = `LevelJson.image_key(bytes)`; if images.size() >= MAX_IMAGES and key not already present → toast/beep + return "" (no import); `current.images[key] = b64` (dedup free — same key overwrites identically). Then `_on_image_chosen` appends overlay `{image: key, x: <screen center in world coords via camera>, y: ..., }`, `_rebuild_scenery()`, selects the new piece (selection lands fully in Task 5 — for now store `selected_overlay := current.overlays.size() - 1`). `%Pieces` list refreshes: one entry per overlay, thumbnail = decoded texture, no text.

- [ ] **Step 1: failing tests** — append:

```gdscript
func test_import_downscales_caps_and_dedupes() -> void:
	var big := Image.create(2048, 1024, false, Image.FORMAT_RGBA8)
	big.fill(Color.BLUE)
	var key := ed.import_scenery_image(big)
	assert_ne(key, "")
	var stored: String = ed.current.images[key]
	var decoded := LevelJson.decode_png_b64(stored)
	assert_lte(maxi(decoded.get_width(), decoded.get_height()), 512, "long edge capped")
	assert_lte(stored.length(), LevelJson.MAX_IMAGE_CHARS)
	var key2 := ed.import_scenery_image(big)
	assert_eq(key2, key, "same pixels, same key")
	assert_eq(ed.current.images.size(), 1, "dedup stores one blob")


func test_import_refuses_a_ninth_image() -> void:
	for i in LevelJson.MAX_IMAGES:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(float(i) / 8.0, 0.2, 0.3))
		assert_ne(ed.import_scenery_image(img), "")
	var extra := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	extra.fill(Color.WHITE)
	assert_eq(ed.import_scenery_image(extra), "", "the ninth image is politely declined")
	assert_eq(ed.current.images.size(), LevelJson.MAX_IMAGES)
```

(GUT note: use `assert_lte`/`assert_lt` per what the suite already uses — check a neighboring test file.)

- [ ] **Steps 2–4: FAIL → implement → selected + FULL green.**
- [ ] **Step 5: commit** `feat: ADD IMAGE — any picture on disk becomes level scenery, capped, hashed, deduped`

---

### Task 5: Selection, drag, handles, bake-at-save

**Files:**
- Create: `src/editor/scenery_gizmo.gd` (draw-only Node2D, GridOverlay's sibling in spirit)
- Modify: `src/editor/level_editor.gd`, `scenes/editor.tscn` (add SceneryGizmo node above world, below Ui)
- Test: extend `tests/unit/test_scenery_mode.gd`

**Interfaces:**
- Editor keeps `_scenery_pieces: Array[NarfDecor]` (from `_rebuild_scenery()`; index-aligned with `current.overlays`) plus per-piece EDIT-TIME transform fields stored IN the overlay dicts while editing: `_rot` (radians), `_scale` (float), `_flip_h`/`_flip_v` (bool) — underscore-prefixed keys are edit-session state, applied to the live NarfDecor for preview, and CONSUMED at save by the bake (never serialized: serialize must strip keys starting with "_" from overlay dicts — add that line + a format test in this task).
- Scenery-mode pointer polling (new block in `_process`, mirroring the crate block's structure): press picks the topmost piece whose rect contains the world mouse (Sprite2D `get_rect()` transformed); drag moves it (updates overlay x/y + node position); handles: the gizmo draws a rect outline + 4 corner squares (resize, aspect-locked: drag changes `_scale`) + one rotate lollipop above (drag changes `_rot`); hit-testing the handles happens in editor code with world-space distance checks (handle radius ~10px / cam zoom).
- Right-click on a selected piece: minimal PopupMenu — Flip H, Flip V, Delete (delete removes overlay + piece; image blob stays unless unreferenced: if no overlay references its key anymore, drop it from `current.images` too).
- **Bake at save:** in `_capture_thumb`'s caller path (`_on_save`/`_on_save_as`) BEFORE capture: `_bake_scenery()` — for each overlay with `_rot`/`_scale`/`_flip` state: decode its image, apply flip_x/flip_y, `rotate`/resize via Image ops (rotation: use a canvas — compute the rotated bounding box, blit through a Transform2D by nearest/bilinear sampling loop OR use the documented approach: `Image` lacks arbitrary rotate, so bake via a SubViewport is NOT allowed headless — implement a small pure-GDScript inverse-mapping rotate (sample source with bilinear) — it's ~20 lines, test-pinned below), re-encode + re-key (content changed → new hash; update every overlay sharing the OLD key only if they carry identical bake state — otherwise the baked copy gets its own key; simplest correct rule: bake produces a NEW key per overlay that had edits, and unreferenced old keys are dropped), strip the `_` keys, zero the piece's live transform.
- Keyboard: Delete key deletes the selected piece in scenery mode (guard the existing crate-delete branch by mode).

- [ ] **Step 1: failing tests** — append (representative; the implementer writes these FIRST):

```gdscript
func test_bake_rotates_pixels_and_strips_edit_keys() -> void:
	var img := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 100.0, "y": 100.0, "_rot": PI / 2})
	ed._bake_scenery()
	var o: Dictionary = ed.current.overlays[-1]
	assert_false(o.has("_rot"), "edit-state keys consumed")
	var baked := LevelJson.decode_png_b64(ed.current.images[o["image"]])
	assert_eq(baked.get_width(), 4, "90-degree bake swaps dimensions")
	assert_eq(baked.get_height(), 8)


func test_serialize_never_leaks_edit_state() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	l.images = {"aaaa1111": "x"}
	l.overlays = [{"image": "aaaa1111", "x": 0.0, "y": 0.0, "_rot": 1.0}]
	assert_false(LevelJson.serialize(l).contains("_rot"))


func test_delete_drops_orphaned_image() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.YELLOW)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	ed.selected_overlay = ed.current.overlays.size() - 1
	ed._delete_selected_piece()
	assert_false(ed.current.images.has(key), "unreferenced blob leaves with its piece")
```

- [ ] **Steps 2–4: FAIL → implement → selected + FULL green.** The pointer/handle FEEL is owner-verified later; tests pin the data model (pick math may be exercised directly via `_pick_piece(world_pos)` if exposed).
- [ ] **Step 5: commit** `feat: scenery pieces live in your hands — select, drag, handles, and transforms bake to pixels at save`

---

### Task 6: The piece inspector

**Files:**
- Create: `scenes/editor_piece_inspector.tscn`, `src/editor/piece_inspector.gd`
- Modify: `src/editor/level_editor.gd`, `scenes/editor.tscn` (instance under Ui, hidden)
- Test: extend `tests/unit/test_scenery_mode.gd`

**Interfaces:**
- `PieceInspector` (PanelContainer, theme-styled): behavior OptionButton (None/Spin/Sway/Bob), a 3×3 GridContainer of toggle buttons for pivot (radio-style), speed HSlider (0–2, step 0.01 — display range; stored raw), amplitude HSlider (0–60). `open(overlay: Dictionary)` populates; edits write straight into the overlay dict AND re-apply to the live piece (editor passes a refresh callback or the piece reference via `bind(piece)`). Signal-free where possible: the dict is shared by reference — mutating it + poking the NarfDecor's exports live-previews.
- Editor: piece selected → inspector opens docked near the panel; deselect/exit → hides.

- [ ] **Step 1: failing tests** (representative):

```gdscript
func test_inspector_writes_through_to_overlay_and_piece() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.CYAN)
	var key := ed.import_scenery_image(img)
	ed.current.overlays.append({"image": key, "x": 0.0, "y": 0.0})
	ed._rebuild_scenery()
	var insp: PieceInspector = ed.get_node("%PieceInspector")
	insp.open(ed.current.overlays[-1], ed._scenery_pieces[-1])
	insp.set_behavior_by_name("SPIN")
	insp.set_speed(0.4)
	assert_eq(str(ed.current.overlays[-1]["behavior"]), "SPIN")
	assert_eq(ed._scenery_pieces[-1].behavior, NarfDecor.Behavior.SPIN)
	assert_almost_eq(ed._scenery_pieces[-1].speed, 0.4, 0.001)
```

(Expose small setter methods — `set_behavior_by_name`, `set_speed` — used by both the UI signals and the tests; the UI wiring routes through them.)

- [ ] **Steps 2–4: FAIL → implement → green.**
- [ ] **Step 5: commit** `feat: the piece inspector — every scenery sprite gets its verb, pivot, and dials`

---

### Task 7: Verification sweep

- [ ] Full suite twice, real counts reported, green both.
- [ ] Scope: `git diff main --stat` matches the File Map (+ docs/uids).
- [ ] End-to-end script check (headless): build a layout via `import_scenery_image` + overlay + `_bake_scenery` + `LevelStore.save_user` round-trip → `SceneryBuilder.spawn` in a fresh host renders the piece. Confirm a NO-scenery level's json is byte-identical in the scenery keys (absent).
- [ ] Grep: `decode_png_b64` is the ONLY b64→Image path (level_card's private gates gone); native FileDialog never enabled (`use_native_dialog` false/absent).
- [ ] Report findings; no commit.
