# Kingdom Crumble — Edit Scenery Design (DRAFT for owner review)

Drafted 2026-09-02 night from the owner's design session (windmill →
NarfDecor → format sketch → mode flow → "EDIT SCENERY" naming). Items
marked **[OWNER-PROPOSED]** are the owner's own decisions; items marked
**[DEFAULT — veto me]** are my fills for the gaps.

## 0. The one constitutional amendment (needs explicit blessing)

**Levels may embed CUSTOM IMAGES** (base64 PNG), amending the original
"curated ids only" decor rule. Rationale: the rule predates the thumb
pipeline, which built the exact safety machinery (byte caps, PNG magic
gate, decode-failure = silent degrade). Pixels are inert like text.
Result: a level file is a complete cartridge — crates, intro, portrait,
scenery art — sharable as one file, Crate-Store ready.
**→ Owner must say "make it so" on this line specifically.**

## 1. Format [OWNER-PROPOSED, sharpened to named keys]

```json
"images": { "a3f29c01": "<base64 png>" },
"overlays": [
  { "image": "a3f29c01", "x": 1344, "y": 260, "behavior": "SPIN",
    "pivot": "CENTER", "speed": 0.1 }
]
```

- Image keys are AUTO-GENERATED at import [OWNER-PROPOSED: no user
  text entry] — first 8 hex chars of the PNG bytes' SHA-256, so
  re-importing identical art dedupes to one stored blob for free. The
  key is invisible plumbing; the editor's placed-pieces list shows
  thumbnails, never names.
- `images`: dict key → base64 PNG. Caps: ≤ 8 entries, each ≤
  MAX_THUMB_CHARS-style byte cap (600k chars), PNG magic-gated at
  display, silent degrade on bad data. Multiple overlays may share one
  image.
- `overlays`: array of entries. Required: `image` (must name an entry
  in `images`), `x`, `y` (coordinate caps like crates). Optional:
  `behavior` (NONE default; names checked against NarfDecor.Behavior),
  `pivot` (CENTER default; NarfDecor.Pivot names), `speed`,
  `amplitude` (clamped to NarfDecor's export ranges). Unknown names →
  entry skipped with warning, never a crash. Cap: ≤ 16 overlays.
- Both keys optional; absent = zero change, unwritten on serialize
  (thumb/intro precedent exactly).

## 2. Renderer

`LevelBuilder` (or a sibling `SceneryBuilder`) spawns one `NarfDecor`
per overlay entry at level start — game AND editor preview use the
same code (editor-owns-zero-gameplay rule). Z-order: all scenery draws
**behind gameplay** (above backdrop, below crates/trebuchet)
**[DEFAULT — veto me: per-piece front/back toggle is deferred to V2]**.
Textures decode once per level load; decode failures render nothing.

## 3. Editor — the EDIT SCENERY mode [OWNER-PROPOSED]

- Hamburger: background dropdown is REPLACED by an **EDIT SCENERY**
  button (background picker moves into the scenery panel).
- Pressing it swaps the crate palette panel for the **scenery panel**:
  background picker, **ADD IMAGE** button, list of placed pieces,
  **DONE** pinned at bottom. DONE (or Esc) restores the crate palette.
- Mode guard: while in scenery mode, crate polling is disabled by a
  mode flag (the polled-input architecture makes this a one-line
  guard); crates stay drawn, dimmed to ~80% modulate; grid overlay
  hidden.
- ADD IMAGE → Godot's own FileDialog, NOT the native one
  [OWNER-PROPOSED: themeable — it inherits kingdom_theme (parchment
  skin) and has a typeable path bar; the native dialog is unskinnable].
  Any image on disk → imported:
  auto-downscaled to ≤ 512 px long edge **[DEFAULT — veto me]**,
  PNG-encoded, byte-cap enforced (further downscale until it fits),
  placed at screen center, selected.
- Selection & handles [OWNER-PROPOSED: handles primary]: click a piece
  to select; drag body to move; corner handles resize
  (aspect-locked **[DEFAULT — veto me]**); a rotate handle above the
  piece. Right-click context menu: Flip H, Flip V, Delete
  **[DEFAULT: also Send Backward/Bring Forward within scenery]**.
- **Piece inspector** (small floating panel while selected): behavior
  dropdown (None/Spin/Sway/Bob), the 9-point pivot grid, speed +
  amplitude sliders. Live preview: the piece animates in the editor
  while selected **[DEFAULT — veto me]**.
- SAVE bakes move/resize/rotate/flip into the raster (edit-time
  transforms become pixels; base64 re-encoded) [OWNER-PROPOSED].
  Accepted cost: edits after reload resample baked pixels.
  Position/behavior/pivot/speed stay as json fields (runtime needs
  them). Thumb capture naturally includes scenery.

## 4. Out of scope (V2+)

Per-piece z-order toggle, decor in the curated registry
(assets/editor/decor — embedded images cover V1), parallax-attached
scenery, WebP encoding, animated multi-frame scenery.

## 5. Testing (GUT)

- Format: images/overlays round-trip; absent keys unwritten; every cap
  boundary exact (count, bytes, coords); unknown behavior/pivot/image
  names skip cleanly; hostile blobs (bad b64, non-PNG, magic-prefixed
  corrupt) degrade silently through a full store round-trip.
- Renderer: level with overlays spawns NarfDecor children with mapped
  properties; level without = zero new nodes; broken image = piece
  absent, level plays.
- Editor: mode flag blocks crate placement while scenery mode active;
  ADD IMAGE import path caps size (fabricated big image); save bakes
  a rotation (pixel-compare fabricated case) and round-trips.
- Owner eyes: handle feel, inspector layout, dim level, import UX.
