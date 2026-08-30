# Kingdom Crumble — In-Game Level Editor Design

**Date:** 2026-09-01
**Status:** Approved design, pre-implementation
**Goal:** Players (and the owner) build, save, load, test, and share levels
from inside the game. Shared levels are safe, single-file, future-proof.

## 1. Level file format (JSON)

Levels are single JSON files, extension `.json`, schema versioned.

```json
{
  "format": 1,
  "title": "Falling",
  "author": "frosty",
  "background": "meadow",
  "shots": 4,
  "crates": [
    { "x": 1400, "y": 572, "type": "crate-wood" },
    { "x": 1400, "y": 516, "type": "crate-wood" },
    { "x": 1400, "y": 460, "type": "crate-gold" }
  ],
  "triggers": {
    "on_all_cleared": ["confetti", "sound:fanfare"]
  }
}
```

Rules:
- `format` is mandatory; loader rejects files with a newer major format
  than it knows. Unknown fields are ignored (old game loads new files).
- `shots: 0` (or absent) = difficulty preset decides.
- `type` = asset filename stem from the editor asset registry.
- `triggers` maps event names to lists of **curated effect ids** — data,
  never code. v1 implements `confetti` and `sound:*` on `on_all_cleared`.
- Reserved for v2: `background_file` (custom local background image;
  requires a bundling story before shareable).
- **Security stance:** JSON is inert. Lua and shared `.tres` were
  explicitly rejected: both make shared levels executable code from
  strangers. The creative-scripting itch is served by growing the
  curated trigger/effect library instead.
- Loader validates hard: malformed JSON, missing fields, unknown asset
  types, out-of-bounds positions → friendly error, never a crash, never
  a partial load.

Locations:
- Built-ins: `res://levels/*.json`; campaign order from
  `res://levels/campaign.json` (an ordered list of filename stems, e.g.
  `["demo", "escape", "falling"]`). Files carry real names — no numeric
  prefixes. Display names always come from `title` inside the file.
- Player levels: `user://levels/*.json`, listed by name; no manifest.
- Sharing v1 = file copy ("Open Levels Folder" button in the editor).
- Migration: existing `levels/meadow.tres` converts to `demo.json` (or
  similar); the `LevelLayout` .tres save format retires. `LevelLayout`
  remains as the in-memory data class, constructed from parsed JSON.

## 2. Editor asset registry (folder = behavior)

```
assets/editor/
  crates/
    crate-wood.png     # placeable physics crate
    crate-wood.txt     # optional palette tooltip: "A standard crate"
    crate-gold.png
    crate-gold.txt     # "A golden (bonus) crate"
    ...
```

- The folder an image lives in defines its behavior. v1 ships only
  `crates/` (all existing crate variants moved/split here as single
  images). Future folders (`critters/`, `decor/`) plug in without
  format changes.
- Optional `<name>.txt` sidecar = human description shown as the
  palette tooltip. Missing sidecar = filename shown.
- Registry scans these folders at startup and exposes:
  id (filename stem), texture, behavior (folder), description.
- Adding a placeable asset = dropping a PNG (and optionally a .txt)
  into a folder. No manifest, no code.

## 3. Editor scene — composition over duplication

**Hard rule: the editor owns zero gameplay code.** It instances the
same `background.tscn`, `crate.tscn`, and trebuchet scene the game
uses, and spawns/clears layouts through a shared `LevelBuilder` used by
the real level scene too. Gameplay changes propagate to the editor
automatically because the editor is displaying the same scenes. The
only editor-owned code is editing UX (palette, grid, selection,
dialogs, file I/O). Any temptation to copy gameplay logic into the
editor means that logic should move into a shared scene/class.

- Entry: main menu gains an **EDITOR** button.
- The editor scene shows the normal world (background, grass,
  trebuchet for context) with an empty field.
- Physics is not simulated while editing (crates are display-only
  previews; the same crate scene with physics disabled via the
  builder's edit flag).

## 4. Grid & placement

- 64px cells (crate-sized): stacks align by construction.
- Buildable zone: from `min_build_x` (a safety margin right of the
  catapult, tunable constant, initial ~600 world px) to the level's
  right bound; floor to a max height. Faint grid lines drawn over the
  buildable zone only.
- Place: drag from palette into the world — ghost preview snaps to
  cells; illegal cell (occupied / outside zone) tints red and refuses.
- Select: left-click a placed item (gold outline).
- Move: drag a selected item to another cell.
- Delete: DELETE key removes the selection. (Right-click stays camera
  pan; the existing RMB-drag scouting works in the editor too.)
- No undo in v1. Clear (with confirm) is the big hammer.

## 5. Hamburger menu (editor)

Save · Save As · Load (lists `user://levels/` only) · Clear ·
Open Levels Folder · Exit to Menu.
Save dialog: title text field; filename = sanitized title. Save
overwrites its own file silently after first save.

## 6. Test loop

- **TEST** button: hands the in-memory layout to the real game scene
  (no save required), plays honestly (physics, shots, win/lose).
- While testing, the pause menu shows **Back to Editor**, returning to
  the exact editing state (layout kept in memory across the round trip).
- Win/lose banners work normally; advancing returns to the editor
  instead of reloading.

## 7. Backgrounds

- Hamburger → Background: pick from built-in scene ids (v1: `meadow`;
  more as palettes/scenes are added). Stored as the id string.
- v2 (reserved): local image file via `background_file`.

## 8. Triggers / effects (v1 slice)

- Effect library: `confetti` (particle burst), `sound:<name>` (from a
  small approved list). Event: `on_all_cleared`.
- The game's level scene reads `triggers` and fires effects; unknown
  effect ids are ignored with a warning.
- The editor does NOT need trigger-editing UI in v1 (hand-editable in
  JSON); UI comes when the library grows.

## 9. Testing

- Unit: JSON serialize/parse round-trip; validation rejects malformed/
  hostile input (missing fields, wrong types, absurd values); registry
  scan on a fixture folder; grid math (world↔cell, zone bounds);
  campaign manifest ordering; LevelBuilder spawns N crates with types.
- Manual: full editor session — place/move/delete/save/load/test/clear.

## 10. Explicitly out of scope (v1)

Undo, trigger-editing UI, custom background images, critter/decor
palettes, online sharing/workshop, mobile touch editing polish,
per-crate attribute editing beyond type.
