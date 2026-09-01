# Save-Time Thumbnail Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Editor save/save-as auto-captures a 416×256 level portrait (owner's crate-box framing algorithm), embeds it as a base64 `"thumb"` field in the level json, and the jump-dialog cards prefer it over the sibling png.

**Architecture:** Pure static `ThumbFraming` (all math, fully tested headless) + `ThumbCapture` that borrows the editor's own viewport for one frame (a SubViewport would drop the ParallaxBackground — CanvasLayers don't cross viewports). Format grows an optional validated `thumb` key; `LevelChain.entries()` carries it; `LevelCard` prefers it with the sibling png and NO IMAGE as unchanged fallbacks.

**Tech Stack:** Godot 4.6.2, GDScript, GUT headless.

## Global Constraints

- `$GODOT` = `/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64`; project `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble`. After creating new files run `$GODOT --headless --import .` once before tests.
- Suite: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` — **157 green at start, only grows.**
- Spec (binding): `docs/superpowers/specs/2026-09-01-thumb-capture-design.md`. Framing values are owner canon: 13:8 aspect, 416×256 floor, PAD 48, bottom anchor `FLOOR_Y + 32`, TOP_LIMIT −1350, slide-never-shrink.
- Capture failure NEVER wipes an existing thumb; hostile/corrupt thumbs NEVER crash (degrade to fallback).
- git add ONLY touched files (+ new `.uid` sidecars). NEVER `-A`. Note: `levels/demo.png` + its `.import` are the owner's untracked files — leave them alone.
- Tabs. gdformat style (double blank line between funcs).
- Headless test env may contain the owner's real `user://levels/` — tests use `gut_`-prefixed stems and clean up after themselves.

## File Map

- Task 1 create: `src/editor/thumb_framing.gd`, `tests/unit/test_thumb_framing.gd`
- Task 2 modify: `src/level/level_layout.gd`, `src/level/level_json.gd`, `tests/unit/test_level_json.gd`
- Task 3 create: `src/editor/thumb_capture.gd`, `tests/unit/test_thumb_capture.gd`; modify: `src/editor/level_editor.gd`
- Task 4 modify: `src/level/level_chain.gd`, `src/ui/level_card.gd`, `tests/unit/test_level_card.gd`
- Task 5: verification only.

---

### Task 1: ThumbFraming — the owner's algorithm as pure math

**Files:**
- Create: `src/editor/thumb_framing.gd`
- Test: `tests/unit/test_thumb_framing.gd` (create)

**Interfaces:**
- Produces: `ThumbFraming.capture_rect(crates: Array) -> Rect2` (world coords; crates entries are `{"x": float, "y": float, "type": String}` — same shape as `LevelLayout.crates`). Constants `OUTPUT` consumers rely on: `TOP_LIMIT`. Task 3 calls `capture_rect`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_thumb_framing.gd`:

```gdscript
extends GutTest

const EPS := 0.001


func _crate(cell: Vector2i) -> Dictionary:
	var w := EditorGrid.cell_to_world(cell)
	return {"x": w.x, "y": w.y, "type": "crate-wood"}


func _wide_row(n: int) -> Array:
	var out: Array = []
	for cx in n:
		out.append(_crate(Vector2i(cx, 0)))
	return out


func _aspect(r: Rect2) -> float:
	return r.size.x / r.size.y


func test_single_crate_gets_minimum_box() -> void:
	var r := ThumbFraming.capture_rect([_crate(Vector2i(0, 0))])
	assert_almost_eq(r.size.x, 416.0, EPS)
	assert_almost_eq(r.size.y, 256.0, EPS)


func test_aspect_is_always_13_8() -> void:
	var tall: Array = []
	for cy in 8:
		tall.append(_crate(Vector2i(0, cy)))
	for crates in [[_crate(Vector2i(2, 2))], _wide_row(30), tall]:
		var r := ThumbFraming.capture_rect(crates)
		assert_almost_eq(_aspect(r), 13.0 / 8.0, EPS)


func test_bottom_anchors_at_grass_strip() -> void:
	var r := ThumbFraming.capture_rect([_crate(Vector2i(0, 0))])
	assert_almost_eq(r.end.y, EditorGrid.FLOOR_Y + 32.0, EPS)


func test_wide_level_grows_height_uniformly() -> void:
	var r := ThumbFraming.capture_rect(_wide_row(30))
	assert_gt(r.size.x, 1920.0)
	assert_almost_eq(r.size.y, r.size.x * 8.0 / 13.0, EPS)


func test_all_crate_centers_inside() -> void:
	var crates: Array = []
	for cx in 12:
		crates.append(_crate(Vector2i(cx, cx % 8)))
	var r := ThumbFraming.capture_rect(crates)
	for c in crates:
		assert_true(r.has_point(Vector2(c["x"], c["y"])), "crate center inside rect")


func test_empty_level_is_deterministic_min_box() -> void:
	var r := ThumbFraming.capture_rect([])
	assert_almost_eq(r.size.x, 416.0, EPS)
	assert_almost_eq(r.size.y, 256.0, EPS)
	assert_almost_eq(r.end.y, 632.0, EPS)


func test_top_limit_slides_without_resize() -> void:
	# Fabricated sky-high crate (unreachable via the 8-row grid) — the
	# clamp must translate the box down, never resize it.
	var crates: Array = [{"x": 1000.0, "y": -2000.0, "type": "crate-wood"}]
	var r := ThumbFraming.capture_rect(crates)
	assert_true(r.position.y >= ThumbFraming.TOP_LIMIT - EPS, "top clamped to limit")
	assert_almost_eq(_aspect(r), 13.0 / 8.0, EPS)
```

- [ ] **Step 2: Run selected — FAIL (ThumbFraming not declared):**
`$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_thumb_framing -gexit`

- [ ] **Step 3: Implement**

Create `src/editor/thumb_framing.gd`:

```gdscript
class_name ThumbFraming
extends RefCounted

# Owner's framing algorithm (thumb-capture spec §1): box the crates,
# pad, grow to 13:8 with the dominant side winning, anchor the bottom
# at the grass strip, slide (never shrink) if the top would leave the
# painted background. Pure math — deterministic from level data alone,
# so every thumbnail is framed identically regardless of editor view.

const ASPECT_W := 13.0
const ASPECT_H := 8.0
const MIN_W := 416.0
const MIN_H := 256.0
const PAD := 48.0
const GRASS_STRIP := 32.0  # bottom edge sits this far below FLOOR_Y
const TOP_LIMIT := -1350.0  # background stays painted above this y
const HALF_CRATE := Vector2(32.0, 31.5)


static func capture_rect(crates: Array) -> Rect2:
	var content := _content_box(crates)
	var bottom := EditorGrid.FLOOR_Y + GRASS_STRIP
	var content_w := content.size.x + PAD * 2.0
	var content_h := bottom - (content.position.y - PAD)
	var h := maxf(maxf(content_h, content_w * ASPECT_H / ASPECT_W), MIN_H)
	var w := h * ASPECT_W / ASPECT_H
	var top := bottom - h
	if top < TOP_LIMIT:
		top = TOP_LIMIT  # slide down, never shrink (owner gotcha #2)
	var center_x := content.get_center().x
	return Rect2(center_x - w / 2.0, top, w, h)


static func _content_box(crates: Array) -> Rect2:
	if crates.is_empty():
		var origin := EditorGrid.cell_to_world(Vector2i(0, 0))
		return Rect2(origin - HALF_CRATE, HALF_CRATE * 2.0)
	var box := Rect2(Vector2(crates[0]["x"], crates[0]["y"]), Vector2.ZERO)
	for c in crates:
		box = box.expand(Vector2(c["x"], c["y"]))
	return box.grow_individual(HALF_CRATE.x, HALF_CRATE.y, HALF_CRATE.x, HALF_CRATE.y)
```

- [ ] **Step 4: Import, then selected tests PASS; FULL suite green (157 + 8 = 165 expected).**

- [ ] **Step 5: Commit**

```bash
git add src/editor/thumb_framing.gd src/editor/thumb_framing.gd.uid tests/unit/test_thumb_framing.gd tests/unit/test_thumb_framing.gd.uid
git commit -m "feat: ThumbFraming — the owner's crate-box algorithm as pure math"
```

---

### Task 2: `"thumb"` joins the level format

**Files:**
- Modify: `src/level/level_layout.gd`, `src/level/level_json.gd`
- Test: `tests/unit/test_level_json.gd` (extend)

**Interfaces:**
- Produces: `LevelLayout.thumb: String` ("" = none); `LevelJson.MAX_THUMB_CHARS := 600_000`; serialize writes `"thumb"` only when non-empty; parse populates `thumb`; validate rejects non-String and > cap. Tasks 3–4 rely on `layout.thumb`.

- [ ] **Step 1: Write the failing tests** — append to `tests/unit/test_level_json.gd` (match its existing style):

```gdscript
func test_thumb_round_trips() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	l.thumb = "aGVsbG8="
	var parsed := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(parsed)
	assert_eq(parsed.thumb, "aGVsbG8=")


func test_absent_thumb_stays_empty_and_unwritten() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	var s := LevelJson.serialize(l)
	assert_false(s.contains("thumb"), "empty thumb is not serialized")
	assert_eq(LevelJson.parse(s).thumb, "")


func test_non_string_thumb_rejected() -> void:
	var d := {"format": 1, "title": "T", "crates": [], "thumb": 7}
	assert_ne(LevelJson.validate(d), "")


func test_thumb_cap_is_exact() -> void:
	var at_cap := {
		"format": 1, "title": "T", "crates": [], "thumb": "a".repeat(LevelJson.MAX_THUMB_CHARS)
	}
	assert_eq(LevelJson.validate(at_cap), "")
	var over := {
		"format": 1,
		"title": "T",
		"crates": [],
		"thumb": "a".repeat(LevelJson.MAX_THUMB_CHARS + 1),
	}
	assert_ne(LevelJson.validate(over), "")
```

(If `parse` takes the parsed Dictionary rather than a String in this codebase, adapt the round-trip test to the actual signature — read the existing tests first and follow them.)

- [ ] **Step 2: Run selected — FAIL:** `-gselect=test_level_json`

- [ ] **Step 3: Implement** in `src/level/level_json.gd`:

Add near the other consts: `const MAX_THUMB_CHARS := 600_000  # ~450 KB decoded — a 416x256 PNG fits many times over`

In `validate()`, after the triggers block, before the final `return ""`:

```gdscript
	var _thumb: Variant = d.get("thumb", "")
	if not _thumb is String:
		return "bad thumb"
	if (_thumb as String).length() > MAX_THUMB_CHARS:
		return "thumb too large"
```

In `parse()`, next to the other optional-field reads (author/background/shots): `out.thumb = str(d.get("thumb", ""))`

In `serialize()`, mirroring the author block:

```gdscript
	if layout.thumb != "":
		d["thumb"] = layout.thumb
```

In `src/level/level_layout.gd`, after `background`:

```gdscript
# Base64 PNG portrait captured by the editor at save ("" = none).
@export var thumb := ""
```

- [ ] **Step 4: Selected PASS; FULL suite green (165 + 4 = 169 expected).**

- [ ] **Step 5: Commit**

```bash
git add src/level/level_layout.gd src/level/level_json.gd tests/unit/test_level_json.gd
git commit -m "feat: level json learns an optional validated base64 thumb field"
```

---

### Task 3: ThumbCapture + save wiring

**Files:**
- Create: `src/editor/thumb_capture.gd`
- Modify: `src/editor/level_editor.gd` (only `_on_save`, `_on_save_as`, plus one new helper)
- Test: `tests/unit/test_thumb_capture.gd` (create)

**Interfaces:**
- Consumes: `ThumbFraming.capture_rect` (Task 1), `LevelLayout.thumb` (Task 2).
- Produces: `ThumbCapture.grab(editor: LevelEditor) -> String` (async — call with `await`; base64 PNG or "" when capture is impossible). `_on_save`/`_on_save_as` become coroutines.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_thumb_capture.gd`:

```gdscript
extends GutTest

# GUT runs headless: capture must decline gracefully, and a failed
# capture must never wipe a previously loaded thumb (spec §2).


func _editor() -> LevelEditor:
	var e: LevelEditor = load("res://scenes/editor.tscn").instantiate()
	add_child_autofree(e)
	return e


func test_grab_returns_empty_headless() -> void:
	var shot: String = await ThumbCapture.grab(_editor())
	assert_eq(shot, "")


func test_save_preserves_existing_thumb_when_capture_fails() -> void:
	var editor := _editor()
	editor.current.title = "Thumb Keeper"
	editor.current.thumb = "aGVsbG8="
	await editor._on_save_as("gut_thumb_keeper")
	var loaded := LevelStore.load_level("user://levels/gut_thumb_keeper.json")
	assert_not_null(loaded)
	assert_eq(loaded.thumb, "aGVsbG8=")
	DirAccess.remove_absolute("user://levels/gut_thumb_keeper.json")
```

- [ ] **Step 2: Run selected — FAIL (ThumbCapture not declared):** `-gselect=test_thumb_capture`

- [ ] **Step 3: Implement**

Create `src/editor/thumb_capture.gd`:

```gdscript
class_name ThumbCapture
extends RefCounted

# Save-time portrait (thumb-capture spec §2). Borrows the editor's own
# viewport for one frame — a separate SubViewport would not render the
# ParallaxBackground (CanvasLayers don't cross viewports), baking in
# exactly the black rows the framing algorithm exists to avoid.

const OUT_W := 416
const OUT_H := 256


static func grab(editor: LevelEditor) -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var vp := editor.get_viewport()
	var cam: Camera2D = editor.get_node("Camera")
	var overlay: Node2D = editor.get_node("GridOverlay")
	var ui: CanvasLayer = editor.get_node("Ui")
	var rect := ThumbFraming.capture_rect(editor.current.crates)

	editor.set_process(false)
	var was_overlay := overlay.visible
	var was_ui := ui.visible
	var saved_pos := cam.position
	var saved_zoom := cam.zoom
	var saved_limits := [cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom]
	overlay.visible = false
	ui.visible = false
	cam.limit_left = -10000000
	cam.limit_top = -10000000
	cam.limit_right = 10000000
	cam.limit_bottom = 10000000
	# Viewport (16:9) is wider than the 13:8 rect — fit by height.
	var view_scale := vp.get_visible_rect().size.y / rect.size.y
	cam.zoom = Vector2(view_scale, view_scale)
	cam.position = rect.get_center()
	cam.force_update_scroll()

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var b64 := ""
	if img != null:
		# World -> rendered-image pixels, robust to window size under
		# the canvas_items stretch mode.
		var xf := vp.get_final_transform() * vp.get_canvas_transform()
		var tl := (xf * rect.position).round()
		var br := (xf * rect.end).round()
		var crop := Rect2i(Vector2i(tl), Vector2i(br - tl)).intersection(
			Rect2i(Vector2i.ZERO, img.get_size())
		)
		if crop.size.x > 0 and crop.size.y > 0:
			img = img.get_region(crop)
			img.resize(OUT_W, OUT_H, Image.INTERPOLATE_LANCZOS)
			b64 = Marshalls.raw_to_base64(img.save_png_to_buffer())

	cam.position = saved_pos
	cam.zoom = saved_zoom
	cam.limit_left = saved_limits[0]
	cam.limit_top = saved_limits[1]
	cam.limit_right = saved_limits[2]
	cam.limit_bottom = saved_limits[3]
	overlay.visible = was_overlay
	ui.visible = was_ui
	editor.set_process(true)
	return b64
```

In `src/editor/level_editor.gd`, REPLACE `_on_save` and `_on_save_as` with:

```gdscript
func _on_save() -> void:
	if save_path == "":
		menu.open_save_as()
		return
	var stem := save_path.get_file().get_basename()
	await _capture_thumb()
	LevelStore.save_user(current, stem)


func _on_save_as(stem: String) -> void:
	if current.title == "Untitled":
		current.title = stem
	await _capture_thumb()
	save_path = LevelStore.save_user(current, stem)


# A failed camera (headless, render hiccup) never wipes a good portrait.
func _capture_thumb() -> void:
	var shot: String = await ThumbCapture.grab(self)
	if shot != "":
		current.thumb = shot
```

- [ ] **Step 4: Import, selected PASS; FULL suite green (169 + 2 = 171 expected). Existing editor-interaction tests must stay green — the save signatures didn't change, they just became coroutines.**

- [ ] **Step 5: Commit**

```bash
git add src/editor/thumb_capture.gd src/editor/thumb_capture.gd.uid src/editor/level_editor.gd tests/unit/test_thumb_capture.gd tests/unit/test_thumb_capture.gd.uid
git commit -m "feat: the editor is the only camera — save captures a framed thumb"
```

---

### Task 4: Cards prefer the embedded thumb

**Files:**
- Modify: `src/level/level_chain.gd`, `src/ui/level_card.gd`
- Test: `tests/unit/test_level_card.gd` (extend; read its existing helpers first and match style)

**Interfaces:**
- Consumes: `LevelLayout.thumb` (Task 2).
- Produces: chain entries gain `"thumb": String`; `LevelCard` preference order = embedded thumb → sibling png → NO IMAGE.

- [ ] **Step 1: Write the failing tests** — append to `tests/unit/test_level_card.gd`, reusing its existing card-construction helper:

```gdscript
func _tiny_png_b64() -> String:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func test_embedded_thumb_shows() -> void:
	var card := _card()
	var entry := {
		"path": "user://levels/gut_no_such.json",
		"stem": "gut_no_such",
		"title": "T",
		"thumb": _tiny_png_b64(),
	}
	card.setup(entry, false, true, false)
	assert_true(card.get_node("%Thumb").visible)
	assert_not_null(card.get_node("%Thumb").texture)
	assert_false(card.get_node("%NoImage").visible)


func test_garbage_thumb_degrades_to_no_image() -> void:
	var card := _card()
	var entry := {
		"path": "user://levels/gut_no_such.json",
		"stem": "gut_no_such",
		"title": "T",
		"thumb": "!!!not/base64@@@",
	}
	card.setup(entry, false, true, false)
	assert_false(card.get_node("%Thumb").visible)
	assert_true(card.get_node("%NoImage").visible)


func test_embedded_thumb_beats_sibling_png() -> void:
	var sibling := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	sibling.fill(Color.BLUE)
	DirAccess.make_dir_recursive_absolute("user://levels")
	sibling.save_png("user://levels/gut_pref.png")
	var card := _card()
	var entry := {
		"path": "user://levels/gut_pref.json",
		"stem": "gut_pref",
		"title": "T",
		"thumb": _tiny_png_b64(),
	}
	card.setup(entry, false, true, false)
	var tex: Texture2D = card.get_node("%Thumb").texture
	assert_eq(tex.get_width(), 4, "embedded (4px) wins over sibling png (8px)")
	DirAccess.remove_absolute("user://levels/gut_pref.png")
```

(If the file's card helper has a different name, use that. If `setup` is called with entries lacking `"thumb"` elsewhere in the suite, `entry.get("thumb", "")` in the implementation keeps them green.)

- [ ] **Step 2: Run selected — FAIL:** `-gselect=test_level_card`

- [ ] **Step 3: Implement**

In `src/level/level_chain.gd` `entries()`, add `"thumb": layout.thumb,` to the appended dictionary (after `"title"`).

In `src/ui/level_card.gd`:

REPLACE the two thumb lines in `setup()`:

```gdscript
	var tex := _embedded_thumb(entry.get("thumb", ""))
	if tex == null:
		tex = _sibling_thumb(entry["path"])
```

(keeping the `%Thumb.visible = tex != null` block that follows), ADD after `_sibling_thumb`:

```gdscript
# Hostile or corrupt blobs degrade silently to the sibling/NO IMAGE
# fallbacks — a bad thumb can disappoint, never crash (spec §4).
func _embedded_thumb(b64: String) -> Texture2D:
	if b64 == "":
		return null
	var buf := Marshalls.base64_to_raw(b64)
	if buf.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(buf) != OK:
		return null
	return ImageTexture.create_from_image(img)
```

and UPDATE the class header comment (it still says "a future capture pipeline needs no changes here" — the pipeline arrived): describe the preference order embedded thumb → sibling `<stem>.png` → NO IMAGE.

- [ ] **Step 4: Selected PASS; FULL suite green (171 + 3 = 174 expected).**

- [ ] **Step 5: Commit**

```bash
git add src/level/level_chain.gd src/ui/level_card.gd tests/unit/test_level_card.gd
git commit -m "feat: level cards prefer the embedded thumb, sibling png stays as fallback"
```

---

### Task 5: Verification sweep

- [ ] Full suite twice: green both runs (174 expected).
- [ ] `git diff main --stat` — ONLY the File Map files (+ .uid sidecars + docs). No world/gameplay files beyond the two named editor-save functions and helper in level_editor.gd.
- [ ] Grep confirms: `capture_rect` called only from ThumbCapture and tests; `ThumbCapture.grab` called only from level_editor.gd `_capture_thumb` and tests.
- [ ] Confirm `levels/demo.png` still untracked and unmodified.
- [ ] No commit for this task; report findings.
