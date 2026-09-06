# Pieces Design — one registry for everything placeable

Owner problem (2026-09-05): "there really are not that many ways to
arrange crates to keep it interesting." Solution: a unified game-object
registry that (wave 1) adds static obstacles — immutable blocks and
trampolines — and (wave 2) supports drop-in content packs: additive
object packs and seasonal reskin themes ("all your levels become Turkey
levels in November").

Doctrine carried forward from levels: **data selects and tunes, never
defines.** Mechanics (behavior classes) are baked code shipped in game
updates; packs and sidecars pick from and parameterize the curated set.
Wrong TYPE in a level file → named validation error. Unknown NAME at
spawn → `push_warning` + skip, never crash.

## 1. Registry (`Pieces`, replaces `EditorAssets`)

One class scans two roots with identical rules and becomes the single
texture/metadata authority for everything placeable:

| Root | Contents | Id form |
|---|---|---|
| `res://pieces/` | baked content (crates migrate here; blocks + tramps born here) | bare: `crate-wood`, `tramp-left` |
| `user://toybox/<pack>/` | one folder per pack (wave 2) | namespaced: `thanksgiving:turkey-crate` |

- Subfolders under either root are purely organizational; recursive
  scan; the object's **class comes from its sidecar, not its folder**
  (supersedes folder-is-behavior).
- Scan happens at editor/game boot (same moment `EditorAssets.scan`
  runs today). No hot-reload, no pack manager beyond §5.
- Entry shape: `{id, texture, class, cells, params, tip, pack}` where
  `pack == ""` for baked.
- Namespacing is the level-stem lesson applied on day one: baked ids
  are bare, pack ids are always `<folder>:<basename>`, so packs cannot
  collide with baked content or each other (two folders cannot share a
  name on one filesystem).

## 2. Object format: one PNG + optional JSON sidecar

`tramp-left.png` + `tramp-left.json`:

```json
{
  "class": "trampoline",
  "cells": [2, 1],
  "tilt": -45,
  "bounce": 1.5,
  "tip": "Launches stones up and to the left"
}
```

| Key | Type | Rule | Default |
|---|---|---|---|
| `class` | String | one of `crate`, `static`, `trampoline` | `crate` |
| `cells` | Array of 2 ints | each clamped 1–4 | `[1, 1]` |
| `tilt` | int | trampoline only; curated set `-45, 0, 45` | `0` |
| `bounce` | float | trampoline only; clamped 0.5–2.0 | `1.5` |
| `tip` | String | palette tooltip; length capped 200 | id |

- **No sidecar → plain 1×1 crate.** Every existing palette PNG stays
  valid with zero edits.
- Sidecar hygiene (asset metadata, not level data, so the object —
  not the game — is the blast radius): unknown `class` or malformed
  JSON → named `push_warning`, object skipped; out-of-range numbers →
  clamped; unknown keys → ignored (forward compatibility).
- Pack PNGs pass the existing decode gates (PNG magic bytes, dimension
  caps from `decode_png_b64`'s budget) before becoming textures.
- Single image only. No spritesheets in this system (user authors
  should never need our sheet layout); if an object ever needs
  animation frames, the sidecar may grow an optional `frames` key —
  future, not built. Animated scenery remains NarfDecor's department.

## 3. Behavior classes (baked code, wave 1 set)

- **`crate`** — exactly today's crate (RigidBody2D, scored, powerup
  behaviors keyed on id, `hit:` trigger targets). Only its texture
  source changes: served by the registry instead of the spritesheet.
- **`static`** — StaticBody2D, rectangle collision = footprint
  (cells × 64 px), deflects stones and crates, indestructible,
  unscored, invisible to triggers/powerups.
- **`trampoline`** — StaticBody2D like `static`, plus a
  PhysicsMaterial with the sidecar's `bounce` as restitution. Three
  baked entries ship: `tramp-flat` (2×1, bounces up), `tramp-left` /
  `tramp-right` (±45°, redirect for bank shots). Tilt is baked into
  the collision shape and art per entry — grid placement stays
  axis-aligned, no runtime rotation math. Restitution interacts with
  the stone's speed-gated bounce; final `bounce` values are an owner
  feel-tuning pass, the clamp range is the guardrail.

New mechanics (turkey cannon, cages, mortar joints) are **new classes
in a game update first**, sidecar-selectable forever after. Classes may
ship dormant — code in the update, content in a later pack.

## 4. Level JSON: new `props` array

```json
"props": [ {"id": "tramp-left", "x": 1024, "y": 569} ]
```

- `crates` is untouched — same ids, same scoring, same triggers, full
  save compatibility.
- Validation (inert-data, named errors): `props` must be an Array →
  `"props must be a list"`; each entry a Dictionary with String `id`
  (charset `a-z0-9_:-`, 1–64 chars) and numeric `x`/`y` →
  `"prop N: bad id"` / `"prop N: bad coords"`; count capped at 64 →
  `"too many props"`.
- Spawn: unknown/disabled id → `push_warning` + skip (a level using a
  missing pack still plays; the prop just doesn't spawn).
- `x`,`y` = world coords of the **anchor cell's center** (the
  leftmost, bottom-most cell of the footprint), formed exactly like
  crate coords via
  `cell_to_world`, so hand-editing follows the same rules the Info
  menu teaches. Props are NOT `hit:` trigger targets (nothing to
  knock).
- Scoring/win: `count_standing`, powerups, and triggers see only
  crates. Props are geometry.

## 5. Packs (wave 2)

A pack = `user://toybox/<folder>/` containing `pack.json` +
content. Two kinds, declared by manifest:

```json
{ "title": "Thanksgiving Pack", "kind": "theme", "months": [11] }
```

| Key | Type | Rule |
|---|---|---|
| `title` | String | display name; capped 60 |
| `kind` | String | `objects` or `theme` |
| `months` | Array of ints | 1–12; empty/absent = always available |

- **Object packs** (`kind: objects`): additive placeables — PNGs +
  sidecars exactly like baked content, ids namespaced. Settings shows
  a **checkbox** per pack (default ON, persisted
  `packs/<folder>=true` in settings.cfg). Disabled → palette hides
  it; already-authored levels warn-skip those props at spawn.
- **Theme packs** (`kind: theme`): reskins — PNGs **named for the base
  ids they replace** (`crate-wood.png`, `stone.png`); no sidecars
  (art only, zero behavior change). Settings shows a **radio**: at
  most ONE active theme, "Default" always listed
  (`packs/active_theme=<folder>` or absent). Texture resolution:
  active theme's art if present for that id, else baked — the
  auto-prefer pattern (`skunk_frames.tres` precedent). Because only
  art changes, every existing level "becomes a turkey level" with
  physics, scoring, and triggers bit-identical. No conflict policy
  needed: one theme at a time, by construction.
- **Seasonal gating** (`months`): gates *selectability*, never
  playback. Out-of-season packs appear in settings grayed with
  "returns in <month>"; an active theme whose season ends reverts to
  Default at next boot. Clock = local system time (time-travel by
  clock change is fine for a cozy single-player game).
- Discovery is automatic (dropping the folder IS the install; "Toybox" is also the player-facing name for the settings Packs section); the
  settings Packs section is the kill-switch, not the enabler.
- Manifest hygiene: malformed `pack.json` or unknown `kind` → named
  warning, pack ignored.
- **Web caveat:** browsers cannot drop folders into `user://`; pack
  loading is desktop-first. Web pack import (zip via the JS bridge,
  like level upload) is future work.

## 6. Editor (wave 1)

- Palette grows a second section — CRATES / OBSTACLES — fed by class
  (crates in the first, static+trampoline in the second). Pack objects
  (wave 2) join their class's section.
- All placement stays on the crate grid. Multi-cell objects occupy
  every footprint cell (occupancy maps all cells → the piece): ghost
  preview spans the footprint, placement requires all cells free and
  in-zone, drag-move moves the whole footprint, delete frees all
  cells.
- Right-click Info stays crate-only in wave 1 (props aren't trigger
  targets; extending Info to props is future polish).
- TEST spawns props through the same builder as the game.

## 7. The gutting (wave 1, no legacy path survives)

- `EditorAssets` deleted; every caller (palette, editor spawn, game
  spawn, `texture_for`) repoints to `Pieces`.
- Baked crate PNGs move `assets/editor/crates/` → `res://pieces/`
  (`.txt` tooltips become `tip` sidecars or stay default).
- The in-game crate spritesheet retires to kc-old-assets: each crate
  face becomes its own PNG (mechanical darkroom slice, owner blesses
  results). One texture authority.
- Export filter check: `pieces/` must be included in all presets
  (dynamic scan = invisible to dependency tracing — the music-folder
  lesson).

## 8. Testing (GUT)

- Registry: sidecar parse/clamp/skip table (bad class, bad cells,
  clamped bounce, missing sidecar = crate); namespacing of a fake
  user pack; theme texture override + fallback (wave 2).
- Level JSON: props validation matrix (bad id charset, bad coords,
  cap, non-array), serialize→parse round-trip preserving props.
- Builders: static spawns with footprint collision; trampoline
  restitution set from sidecar; unknown prop id warn-skips; props
  absent from `count_standing`.
- Editor: multi-cell occupancy (place/blocked/move/delete), palette
  sections populated by class.
- Migration pins: every baked crate id resolves to a texture through
  `Pieces`; shipped levels still load and spawn identical crate
  counts.

## 9. Future (spec'd, not built)

Pack-shipped levels (`<pack>/levels/*.json` joining the chain like
user levels); dormant classes lighting up via packs; web zip pack
import; Info menu on props; optional `frames` animation key; mortar
joint class; weapon/ammo skins via themes; reskin support for object
ids beyond the base set.

## Out of scope

Free placement, runtime rotation, pack management beyond the settings
toggles, hot-reload, servers/online anything.

## Standing rule (owner, 2026-09-06): sidecar-first

No per-piece stat or ability is hardcoded. Everything a piece IS —
class, cells, bounce, tilt, spin, powerup, animatable, whatever comes
next — lives in its sidecar as a curated id or a clamped number. Code
ships the curated sets, the clamps, and the mechanics behind the ids
(new mechanics may ship dormant); sidecars pick and tune. The powerup
migration (2026-09-06) retired the last hardcoded per-piece table.
