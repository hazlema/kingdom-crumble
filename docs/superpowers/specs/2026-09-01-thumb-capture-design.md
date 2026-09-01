# Kingdom Crumble — Save-Time Thumbnail Capture Design

Owner-approved design, 2026-09-01. The editor becomes the only camera:
every save/save-as auto-captures a level thumbnail and embeds it in the
level json. Supersedes hand-made sibling screenshots (which remain a
supported fallback).

## 0. Owner decisions (binding)

- **Packaging = B:** base64 PNG embedded in the level json as a `"thumb"`
  field. Levels stay single-file; the only binary a level ever carries is
  its own portrait (backgrounds/decor/effects are curated ids by canon).
- **Target size:** 416×256 (13:8 — exactly 2× the card's 208×128 thumb
  region; renders 1:1 if the F8 UI-doubling happens).
- **Framing algorithm (owner-designed):** imaginary box around all the
  crates, padded to the magic aspect. Gotchas, owner-numbered:
  1. A naive box captures **black rows** (regions outside the painted
     background).
  2. Fix is **slide, not shrink** — there is ample sky; translate the
     box vertically until it is fully inside the background.
  3. A box wider than the magic size must **scale with aspect held** —
     the capture rect is always exactly 13:8 at variable world size; the
     downscale to 416×256 is uniform, so nothing distorts (wide levels
     render zoomed out).
- **The camera scrolls to the shot** (owner): capture never depends on
  where the editor view happens to be — the camera jumps to the computed
  box, snaps, and returns.
- Owner-acknowledged refinement: the box bottom anchors just below the
  ground line so every thumb shows a strip of grass — structures look
  planted, and the card grid reads consistently.

## 1. Framing math — `ThumbFraming` (pure, fully tested)

New `src/editor/thumb_framing.gd`, static only, no scene access — the
whole algorithm is computable from `layout.crates` and `EditorGrid`
constants, so it is deterministic and headless-testable.

`capture_rect(crates: Array) -> Rect2` in world coordinates:

1. **Content box:** union AABB over crate centers ± half a crate
   (32 × 31.5). Empty level → the box of an imaginary crate at cell
   (0, 0) (deterministic default framing).
2. **Pad:** 48 px left, right, and top. The bottom edge does NOT pad —
   it anchors at `FLOOR_Y + 32` (= 632, the grass strip).
3. **Grow to 13:8, dominant side wins (gotcha #3):**
   `h = max(content_h, content_w × 8/13, 256)`, `w = h × 13/8`, floored
   at 416×256 world px (min-zoom guard — a three-crate level is not a
   macro shot).
4. **Place:** centered horizontally on the content box, bottom at the
   grass anchor.
5. **Slide clamp (gotchas #1–2):** if the top edge rises past the
   background-safe limit (−1350), translate the whole box down —
   never resize. Grass is painted to y = 1200, so sliding down stays
   inside paint. With the current 8-row × 40-col grid the clamp can
   never fire; it guards future grid growth.

Horizontal needs no clamp: the background mirrors infinitely on x.

## 2. Capture — `ThumbCapture` (borrow the editor camera)

New `src/editor/thumb_capture.gd`. A SubViewport is the wrong tool here:
the background is a ParallaxBackground (a CanvasLayer), which a separate
viewport sharing the world would not render — black rows by construction.
Instead the capture borrows the editor's own viewport for one frame:

`grab(editor) -> String` (async; returns base64 PNG, or "" when capture
is impossible):

1. **Headless guard:** `DisplayServer.get_name() == "headless"` → return
   "" immediately (GUT runs headless; rendering is unavailable).
2. Freeze editor input (`set_process(false)`), hide `GridOverlay` and the
   `Ui` CanvasLayer, save camera state (position/zoom/limits), lift the
   limits so they cannot fight the framing.
3. Fit the camera to the rect: viewport canvas size is 1920×1080 (16:9,
   wider than 13:8), so fit by height — `zoom = 1080 / rect.h` uniform;
   position = rect center; `force_update_scroll()`.
4. Await rendered frames (`RenderingServer.frame_post_draw` twice —
   camera scroll applies on draw), then `get_viewport().get_texture()
   .get_image()`.
5. Crop: map the world rect through
   `get_final_transform() * get_canvas_transform()` to image pixels
   (robust to window size under canvas_items stretch), intersect with
   the image bounds, `get_region`.
6. `resize(416, 256, INTERPOLATE_LANCZOS)` → `save_png_to_buffer()` →
   `Marshalls.raw_to_base64()`.
7. Restore everything (camera, limits, visibility, processing) in all
   paths, then return.

**Wiring:** `_on_save` and `_on_save_as` await `ThumbCapture.grab(self)`
before `LevelStore.save_user`. A non-empty result replaces
`current.thumb`; an empty result (headless / failure) **preserves** the
existing thumb — a failed camera never wipes a good portrait. Ctrl+S
reaches the same path. The owner may see a one-frame camera flick at
save: that is the camera doing its job.

## 3. Format — `"thumb"` in the level json

- `LevelLayout` gains `@export var thumb := ""` (base64 PNG, "" = none).
- `LevelJson.serialize` writes `"thumb"` only when non-empty;
  `parse` reads it through `str(d.get("thumb", ""))`.
- `validate` (inert-data stance): key optional; when present it must be
  a String no longer than `MAX_THUMB_CHARS = 600_000` (~450 KB decoded —
  generous for a 416×256 PNG, hard wall for hostile blobs). Violations
  reject the level like any other bad field. Content is NOT decoded at
  validate time — decode failures are handled (silently, as no-thumb) at
  display time.

## 4. Display — LevelCard preference order

`LevelChain.entries()` adds `"thumb": layout.thumb` (the layout is
already loaded there). `LevelCard.setup` prefers, in order:

1. Embedded thumb: base64 → `Marshalls.base64_to_raw` →
   `Image.load_png_from_buffer` → texture. ANY failure (bad base64,
   not a PNG, empty) returns null silently — hostile or corrupt thumbs
   degrade to the next option, never crash.
2. Sibling `<stem>.png` (existing `_sibling_thumb`, unchanged — legacy
   and hand-authored levels keep working).
3. "NO IMAGE" panel (unchanged).

## 5. Out of scope

- Backfilling thumbs into shipped `res://levels/*.json` — the owner will
  resave levels through the editor (their stated test plan) and copy
  results over as they see fit.
- Star ratings, capture preview UI, re-capture button, thumbnails
  anywhere but the jump dialog.
- Removing the sibling-png convention (it stays as fallback).

## 6. Testing (GUT, headless)

- ThumbFraming (the bulk): exact 13:8 aspect for one crate / wide row /
  tall stack / full-grid extremes; 416×256 floor; bottom anchored at
  632; all crate boxes contained with margin; empty-level default;
  slide clamp translates without resizing (fabricated past-limit input).
- Format: thumb round-trips serialize→parse; absent key → "" and no
  `"thumb"` in output; non-string thumb rejected; oversize rejected at
  exactly the cap boundary.
- Capture: headless grab returns "" without error; saving with a loaded
  thumb and a failed (headless) capture preserves the thumb on disk.
- Card: embedded thumb (fabricated 4×4 PNG, real base64) shows in
  %Thumb and beats a sibling png; garbage base64 falls back to sibling /
  NO IMAGE; existing card tests stay green.
- Visual verdict (framing quality, flick acceptability) = owner, by
  resaving their existing levels — their stated test plan.
