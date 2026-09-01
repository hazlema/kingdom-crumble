# Kingdom Crumble — Polaroid Save Feedback Design

Owner-approved 2026-09-01 ("we will just add the picture frame thing. So
when it pops on screen it looks like we meant to do that"). Reframes the
save-capture camera flick as intentional showmanship: when the editor
takes the level portrait, the photo drops onto the screen in a Polaroid
frame, holds a beat, and fades.

## 0. Hard rules

- Editor-only presentation. No mechanics, no game-scene changes; the
  saved file is byte-identical to before this feature.
- Non-blocking: the popup ignores the mouse entirely — editing continues
  under it. It never gates or delays the save (fire-and-forget after the
  thumb is embedded).
- Headless-safe: in headless (tests), capture returns "" and the
  Polaroid simply never shows; showing it with a fabricated texture in
  tests works without rendering.
- A bad image input degrades to not-showing — never crashes.

## 1. Component — `Polaroid` (scenes/ui/polaroid.tscn + src/ui/polaroid.gd)

Classic instant-photo look: white frame (parchment-light), the captured
shot as the picture (208×128 — the card thumb region size), and a wide
bottom band carrying the level title as the handwritten-style caption
(Nunito, ink color). Subtle ink border for the pretty-pass panel language.

- API: `show_b64(b64: String, caption: String)` — decodes the base64 PNG
  internally (own trusted data, straight Marshalls + load_png_from_buffer;
  any failure = silently don't show). Also `show_shot(tex, caption)` for
  tests/direct use; `show_b64` wraps it.
- Animation (Tween, all durations as consts for testability): drops in
  from above with a tilt, settles with a small overshoot bounce
  (TRANS_BACK), holds ~1.4 s, fades ~0.5 s, hides. Tilt alternates sign
  on successive shows (deterministic — no randomness) so consecutive
  saves feel hand-tossed.
- Repeat-save safety: a new show kills the running tween and restarts
  cleanly.
- Placement: anchored lower-center of the screen, clear of the palette
  and hamburger.
- Shutter sound: owner-art auto-prefer slot — if
  `res://assets/sfx/shutter.ogg` exists it plays on show; absent = silent.
  Owner drops the file later, zero code changes.

## 2. Wiring

`level_editor.gd _capture_thumb`: after a successful capture embeds the
thumb, one added line shows the Polaroid with the fresh shot and
`current.title`. The Polaroid node instances under the editor's `Ui`
CanvasLayer (capture hides Ui during the shot and restores it before the
popup fires — no interaction).

## 3. Testing (GUT)

- Component: hidden initially; show_shot → visible with texture+caption;
  show_b64 with fabricated tiny PNG b64 → visible; garbage b64 → stays
  hidden, no errors; after drop+hold+fade durations elapse → hidden
  again; mouse_filter is IGNORE.
- Wiring: headless editor save (capture returns "") → Polaroid never
  becomes visible.
- Visual verdict (charm, timing, placement): owner, next resave.
