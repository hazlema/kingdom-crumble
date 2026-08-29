# Kingdom Crumble — Design

**Date:** 2026-08-29
**Status:** Approved design, pre-implementation
**Predecessor:** the three.js/cannon-es web game in this repo (frozen as v1 — "good enough," no further feature work)

## Concept

**Kingdom Crumble** — a 2D indie artillery/destruction game in the Angry
Birds lineage: launch stones from a trebuchet, topple crate structures,
charm the player. Target the orphaned Angry Birds audience with better
music, richer personality, and physics rewards no one else offers.

Name notes: "Castle Crasher" was rejected (collides with The Behemoth's
*Castle Crashers*). Nearest neighbor to the chosen name is *Thy Kingdom
Crumble* (small 2019 Steam platformer) — different genre and low
profile, judged acceptable; run a trademark search before any real
store launch.

**Pillars: super fun, pretty (animation eye-candy / design), challenging.**

## Engine & Platforms

- **Godot 4**, 2D. Chosen over Odin/raylib because the owner's time
  should go to art, music, and level design — not engine plumbing.
  Godot supplies Skeleton2D cutout animation, audio buses, particles,
  UI, tweens, and web export.
- Physics: Godot built-in 2D physics first; if crate stacking feels
  mushy, switch to the Rapier physics plugin (known community fix).
- Exports: **HTML5 (Netlify, keeps the current distribution + mobile
  reach)** and native desktop.

## The Hook Stack (what makes it "not a normal game")

### 1. Music is difficulty
The main menu offers three vibes instead of easy/medium/hard:

| Menu choice | Music pool | Difficulty preset |
|---|---|---|
| Chill | `music/chill/` | generous shots, simple structures, forgiving physics |
| Heart-Pumper | `music/heartpumper/` | tighter shots, taller structures |
| Hardcore | `music/hardcore/` | minimal shots, complex structures, stubborn physics |

Depth level: **vibe + preset** (music selects playlist and difficulty
knobs; gameplay itself is not beat-synced — explicitly decided against
music-reactive and rhythm-hybrid variants).

Crates themselves **never move on their own** at any tier — difficulty
comes from structure design and physics tuning, not moving targets.
(A moving *platform* under a structure is a v2 idea at most.)

### Difficulty presets as Resources
Tier tuning lives in a custom `DifficultyPreset` Resource
(`extends Resource` with `@export` vars), one `.tres` per tier:

```gdscript
# difficulty_preset.gd
class_name DifficultyPreset extends Resource
@export var crate_natural_bounce := 0.6   # chill 0.6 → hardcore 0.3
@export var impact_force := 3.0           # chill 3.0 → hardcore 1.0
@export var shots_per_level := 5
# ...grows as tuning needs emerge
```

The menu choice loads the matching `.tres` into a global autoload
(`Settings`), so every system reads `Settings.preset.impact_force`.
Values are editable with inspector sliders and hot-tweakable at
runtime. Per-level overrides, if ever needed, are just another
`DifficultyPreset` resource assigned on the level scene.

### 2. Lean bonus
When a shot leaves a crate *leaning* against another (tilted roughly
15°–75° off vertical and in contact with another crate after physics
settles), a powerup pops out. Each formed lean pays **once** — track
paid-out crate pairs. Rewards near-misses and emergent physics instead
of punishing them.

### 3. Progressive elements (the retention engine)
Level 1 is pure basics — trebuchet, crates, nothing else. Every few
levels a **new element** enters and stays in the rotation, so the game
keeps surprising (the Cut the Rope / Angry Birds onboarding model).
Candidate element pool, in rough introduction order:

- **Roaming critters** (skunk, chicken) — optional bonus targets;
  hitting one grants a powerup + signature eye-candy burst (feathers /
  stink cloud). Simple path-walk AI with a 2-frame waddle.
- **The Frog King** 🐸👑 — a recurring cameo (roughly every couple of
  levels once introduced): a crowned frog with scepter and cloak
  appears somewhere in the scene. Hitting him "does something" —
  deliberately mysterious, effects can vary (jackpot powerup, confetti
  storm, maybe an occasional royal curse). Players should trade rumors
  about him. Character already comped.
- **Obstacles** — terrain and props that block or redirect shots.
- **Water** — hazard pools / splashdown physics.
- **Weather** — rain and snow (visual + light physics flavor).
- **Wind** — promoted from the v2 bucket into the element pool; enters
  late as the aim-skill multiplier.

Elements are introduced by level design, not difficulty tier — all
tiers meet the same elements; the preset tunes how punishing they are.

### 4. Living world
Painted panorama backgrounds (reuse the v1 21:9 art pipeline) sliced
into parallax layers, animated procedurally: drifting clouds as sprites,
flickering windows via shader or two-still crossfade (frame-exact — the
control the v1 video backgrounds never had), ambient birds. No video
files, no sprite-sheet megaframes.

## Presentation

- Flat-stylized 2D art language (the "indie" mockup direction).
- Main character: cartoon soldier kid (already comped, exploded into
  parts) rigged with **Skeleton2D** — fire cycle, idle bounce,
  celebrate. Owner wants the rigging learning experience.
- Juice budget: screen shake, crate splinters, dust puffs, feather
  bursts, slow-mo on the final crate of a level.

## Camera System (one Camera2D, three modes)

1. **Aim view** — anchored framing the trebuchet and near field.
2. **Follow-cam** — auto-engages at launch, chases the projectile with
   zoom; returns to aim view after impact resolves.
3. **Free scout** — drag / arrow-pan / touch-drag anywhere between
   shots to survey off-screen targets; snaps back to aim view when the
   player touches aim controls. Levels are designed wider than one
   screen, so this is required, not optional.

## Core Loop

Aim (angle + power) → fire → follow-cam flight → destruction resolves →
lean check → powerup awards → next shot. Clear the required structures
to advance. Powerups persist to the next shot (v1's `nextShot` modifier
pattern carries over conceptually).

## Scope Guardrail

**First playable:** one level, one music tier (chill), the kid +
trebuchet rigged and firing, flat-color placeholder art, all three
camera modes. No elements yet — level 1 is pure basics by design.
Prove fun/pretty/challenging on one screen before building content
breadth. First element (a critter) arrives with the first level batch.

**Explicitly v2 (wanted, not now):** multiple ammo types, the rich HUD
from the 2.5D mockup (round counter, opponent panels), PvP, level
editor, moving platforms under structures (crates themselves never
self-move even then). Water/weather/wind graduated into the
progressive-element pool above.

## Asset Pipeline Notes

- Stills: owner generates on OpenAI directly (conserves OpenArt
  credits); OpenArt (cheap models ~8 credits) for quick mockups.
- Panoramas: 21:9; parallax slicing replaces the v1 horizon-pinning
  system, so the 45%-horizon rule no longer constrains composition.
- Character sheets: generate assembled + exploded-parts views on
  transparent backgrounds for Skeleton2D cutting.
