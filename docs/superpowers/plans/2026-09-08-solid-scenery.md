# Solid Scenery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scenery overlays gain `"solid": true` — the painted silhouette becomes collision. Owner draws a weapons-depot building in art software, imports it as scenery, ticks Solid, and stones land on the roofline. Spike-proven 2026-09-08 (stone rested at the exact predicted y on an alpha-derived surface; slopes roll stones realistically).

**Architecture:** Two tasks. (1) Format + spawn: `solid` bool in the overlay schema (validated, travel verbs refused), SceneryBuilder derives collision from the baked image's alpha (BitMap → opaque_to_polygons → CollisionPolygon2D on StaticBody2D), point-budget cap with graceful visual-only fallback, physics regression test porting the spike. (2) Editor: Solid checkbox in the full piece inspector with travel-verb interlock, docs.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **458 passing**) after each task: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`. GUT counts engine errors as failures.
- Commit locally per task; NO push.
- **The picture is the physics**: collision derives from the SPAWNED (baked) image via `BitMap.create_from_image_alpha(img, 0.5)` → `opaque_to_polygons(Rect2i(Vector2i.ZERO, img.get_size()), 2.0)`. Bake already flattens rotation/scale to pixels at save, and editor TEST bakes first (F3) — so spawn-time alpha always matches what the player sees. Never derive from pre-bake transforms.
- **Inert-data doctrine**: `solid` is a strict bool (wrong type = named validation error "overlay %d: solid must be true/false"); `solid: true` + travel verbs (DRIFT/WANDER) = named validation error "overlay %d: solid pieces cannot travel" (collision is static; the sprite-only verbs NONE/SPIN/SWAY/BOB stay legal under the existing amplitude cap, mirroring props).
- **Security/perf cap**: total polygon points per solid overlay ≤ 512. Over budget → retry `opaque_to_polygons` with epsilon 4.0, then 8.0; still over → `push_warning` naming the overlay and spawn it VISUAL-ONLY (never crash, never block the level). The spike measured a whole building at 7 points — this budget is generous.
- Solid bodies behave like the `static` piece class: StaticBody2D on the default layer (match PropBuilder's static setup — read it), deflects stones AND crates, never scored, invisible to triggers/powerups, joins group `"scenery_solid"`.
- Physics-test idioms: real physics needs `wait_physics_frames` (never wait_seconds under pause; headless _process outpaces 60Hz physics — terminate on physical conditions, not frame counts). See tests/unit/test_sleep_float.gd for the style.
- Save round-trip: `solid` survives serialize/parse; bake strips underscore keys only (verify `solid` untouched through SceneryBake).

---

### Task 1: Format + collision spawn + physics proof

**Files:**
- Modify: `src/level/level_json.gd` (overlay validation: solid bool gate + travel-verb refusal; parse preserves the key), `src/level/scenery_builder.gd` (spawn path derives collision for solid overlays)
- Test: `tests/unit/test_solid_scenery.gd` (new)

**Interfaces:**
- Produces: `SceneryBuilder.spawn(...)` — for overlays with `solid == true`, after the NarfDecor piece is created, builds a `StaticBody2D` sibling (child of the same parent) positioned so image-local polygon coords map exactly onto the sprite's world footprint (mind NarfDecor's pivot/centering — read `addons/narfkit/narf_decor.gd`; polygons from opaque_to_polygons are top-left-origin image space). Body gets meta `overlay_name` mirroring the sprite (for future tooling), group `"scenery_solid"`, one CollisionPolygon2D per returned polygon. Returns unchanged signature; solid bodies tracked so the editor's rebuild frees them with the pieces (read how _scenery_pieces teardown works and mirror it — no leaks on rebuild).
- Produces: static helper `SceneryBuilder.solid_polygons(img: Image) -> Array[PackedVector2Array]` — pure: alpha → polygons with the epsilon-escalation cap logic; returns `[]` (plus push_warning by the caller with the overlay name) when over budget. Unit-testable without physics.
- `show`/`hide` triggers on a solid overlay: visibility toggles the SPRITE only — the plan's call is collision follows visibility (hidden solid = no collision: toggle the body's `process_mode`/collision layer alongside, so a `show:` trigger can reveal a solid wall mid-level — that's a level-design feature, wire it through the existing `_set_scenery_visible` path in level.gd finding the body via group + overlay_name meta).

- [ ] **Step 1: Failing tests** (`tests/unit/test_solid_scenery.gd`):

```gdscript
func test_solid_validates_as_strict_bool() -> void:
	# solid: "yes" → "overlay 0: solid must be true/false"; solid: true → valid
func test_solid_refuses_travel_verbs() -> void:
	# solid: true + behavior DRIFT → named error; SWAY → valid
func test_solid_round_trips_and_survives_bake() -> void:
	# serialize→parse keeps solid; SceneryBake.bake leaves the key
func test_solid_polygons_from_alpha() -> void:
	# 200x150 image, opaque rect x40..160 y60..150 → 1 polygon, points >= 4,
	# all points within the rect bounds (+epsilon slack)
func test_solid_polygons_cap_falls_back() -> void:
	# pathological checkerboard image → [] after escalation (visual-only path)
func test_spawn_creates_static_body_aligned_to_sprite() -> void:
	# spawn layout with a solid overlay at a known position → exactly one
	# StaticBody2D in group scenery_solid; its polygon's world-space bbox
	# matches the sprite's world rect within 3px
func test_stone_rests_on_painted_roof() -> void:
	# THE SPIKE AS A PIN: flat-topped painted building via the real
	# SceneryBuilder spawn; drop a RigidBody2D stone above it; a control
	# stone beside it; await physics until the control has fallen well past;
	# assert the roof stone rests at surface-minus-radius (±2px) with ~zero velocity
func test_hidden_solid_has_no_collision() -> void:
	# overlay solid+hidden spawns with collision disabled; _set_scenery_visible
	# show → collision enabled (drive via the level or directly per wiring)
```

- [ ] **Step 2: RED** focused. **Step 3: implement.** **Step 4: focused green; FULL suite = 458 + new.**
- [ ] **Step 5: Commit** `feat: solid scenery — the painted silhouette is the collision`

---

### Task 2: Foreground layer + auto-peek (owner-approved 2026-09-08 — "auto-peek for all users, it's 2026")

**Files:**
- Modify: `src/level/level_json.gd` (two new overlay bools), `src/level/scenery_builder.gd` (front-layer spawn), `src/level/level.gd` (peek watcher), possibly `scenes/level.tscn` (front container node)
- Test: `tests/unit/test_solid_scenery.gd` (append) or a new `test_front_scenery.gd` — implementer's call, follow suite idioms

**Interfaces:**
- Format: overlay gains `"front": true` (strict bool, default absent/back — mirrors `hidden`/`solid` gates verbatim) and `"peek": true` (strict bool; REQUIRES front — `peek` without `front` = named validation error "overlay %d: peek requires front", the aura_color-requires-aura precedent). Both round-trip; bake leaves them.
- Rendering: front overlays spawn into a container ABOVE gameplay (crates/stones/props) and BELOW the HUD. Read the level scene's z/tree structure first; add a dedicated front-scenery parent. Editor canvas mirrors the split so the preview is honest (front pieces draw over placed crates in edit mode too — read _rebuild_scenery z handling).
- Auto-peek: for each front+peek piece, when any node in groups "stones" or "crates" (standing crates — use the same standing test count_standing uses if cheap, else all crates) has its center inside the piece's world rect → tween the piece's modulate alpha to 0.65 over ~0.2s; when clear again → back to 1.0. Poll on a ~0.1s timer or physics process in level.gd (gameplay-side only; the editor never peeks). Tween per-piece, kill-on-retarget (the flash_overlay hygiene pattern). Cosmetic only — never touches visibility/collision/selection.
- Solid×front is legal (collision is layer-independent); solid+peek fades the picture while the wall stays real — fine, the fade is a reveal, not a lie about physics.

- [ ] **Step 1: failing tests**: strict-bool gates for front/peek; peek-requires-front error; front piece spawns under the front container (assert parent/order) in game spawn; peek fade — spawn front+peek piece with known rect, place a stone inside the rect, run the watcher tick, assert modulate.a tweens toward 0.65 (await the tween; physical-condition termination); stone leaves → returns to 1.0; round-trip + bake-survival pins.
- [ ] **Step 2-4:** RED → implement → focused + FULL green (baseline = post-Task-1 count).
- [ ] **Step 5: Commit** `feat: foreground scenery + auto-peek — the roof fades when the action goes behind it`

---

### Task 3: Editor checkboxes + docs

**Files:**
- Modify: `src/editor/piece_inspector.gd` (Solid + Front + Peek CheckBoxes, full mode only), `src/editor/level_editor.gd` only if wiring requires, `parts.md` (scenery section: Solid — what it does, the ≤1024px guidance, gaps/transparency, travel-verb rule, point-budget fallback; Front/Peek — layering + auto-peek behavior, why-not-mouseover touch note)
- Test: `tests/unit/test_solid_scenery.gd` (append) or the inspector's existing test home (read where inspector tests live and follow)

**Interfaces:**
- Produces: full-mode inspector shows "Solid", "Front", and "Peek" CheckBoxes bound to their overlay keys (absent = unchecked; unchecking ERASES the key — keep saved files minimal). Peek's checkbox is enabled only while Front is checked (unchecking Front also erases peek — the validator would reject the orphan). Interlock: while Solid is checked, the behavior dropdown's DRIFT/WANDER entries are disabled (`set_item_disabled`); if the overlay already has a travel verb when Solid is checked, behavior resets to NONE (and the live piece updates through the existing verb-change path — mind the `_updating` guard idiom, see the radio-helpers battle scar in this file's history).
- Editor edit-canvas spawns NO collision (canvas draws pictures; only TEST/game spawn bodies) — confirm the checkbox doesn't accidentally trigger body spawns in edit mode.
- Reduced mode (animatable props) does NOT show the checkbox (solid is a scenery concept).

- [ ] **Step 1: failing inspector tests** (checkbox writes/erases key; travel interlock resets + disables; reduced mode hides). **Step 2-4: RED → implement → focused + FULL green.**
- [ ] **Step 5: Commit** `feat: Solid checkbox — paint a building, tick a box, get a wall`

---

## Riders (log, not in scope)

- Selection-ring tint for solid pieces (owner taste question, unanswered — cosmetic).
- Physics material dials on solid scenery (bounce — "trampoline walls") — future sidecar-style extension.
- Moving solid scenery = the moving-platforms seed, explicitly separate.
