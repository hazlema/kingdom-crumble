# Kingdom Crumble — Powerup System Design

Owner-approved design, 2026-08-31. Supersedes the old random-on-gold idea
from the original web game.

## 0. Canon

| Crate | Powerup | Timing |
|---|---|---|
| Wood | none | — |
| Gold | Free Shot | instant: `shots_left += 1` |
| Skull | Exploding Shot | enchants next shot |
| Blue | Multi-shot | enchants next shot |
| Green | Super Bounce | enchants next shot |
| Ghost | Mystery | rolls one of the four above at collection |

Rules of the system:

- **One collection law.** A crate is collected the moment it is knocked out —
  the same line scoring uses (`Crate.is_standing()` false: tilt > 45° or
  displaced ≥ `KNOCKED_OUT_DISTANCE` 48px from `home`). Cause is irrelevant:
  direct hit, falling neighbor, explosion shove. No graze-harvesting.
- **"Collected" means the buff, never the crate.** Crates are NEVER removed
  from the world by this system — a collected crate remains as rubble like
  any knocked-out crate. (Owner-confirmed 2026-08-31.)
- **All buffs enchant the NEXT shot** (gold's instant refund is the one
  exception — it is economy, not ammunition).
- **Buffs stack and combine.** The next shot consumes one queued charge of
  each buff type; duplicate charges stay queued for later shots. Distinct
  types co-apply: bounce + explode = detonates on EVERY contact including
  ground, then keeps going. Multi + anything = every stone in the volley
  carries it.
- **Buffs are consumed on fire, hit or miss.** Wasting a stacked shot is
  intended drama.
- **Chaining is a feature.** A buffed shot that knocks out more powerup
  crates enchants the shot after it. Combo trains are deliberate.
- **Carry-through on victory only.** Unspent buffs ride into the next level
  when the level is CLEARED. Restart, failure, quit, or back-to-editor
  discards them with the attempt.

## 1. Collection — crate self-reporting

`src/gameplay/crate.gd`:

- New one-shot signal `knocked_out(crate: Crate)`.
- In `_physics_process`, an uncollected, unfrozen crate that first fails
  `is_standing()` sets `_collected = true` and emits. Frozen crates (the
  editor's preview spawns) never emit — the editor keeps owning zero
  gameplay code (level-editor spec §3 hard rule).
- Emission is once per crate per level instance, ever.

`src/level/level.gd` connects each crate's signal at spawn
(`LevelBuilder.spawn_crates` return array) and routes by `type_id`:

- `crate-wood` → nothing.
- `crate-gold` → `shots_left += 1`, `hud.set_shots`, floaty text
  "+Free Shot".
- `skull` → queue `&"exploding"`, floaty "+Exploding Shot".
- `crate-blue` → queue `&"multishot"`, floaty "+Multi-shot".
- `crate-green` → queue `&"super_bounce"`, floaty "+Super Bounce".
- `crate-ghost` → mystery roll (§4), then handle the result exactly as if
  that crate had been the rolled type (floaty text announces the result).

Floaty text = `HitTextEffect` (`src/effects/HitTextEffect.tscn`), spawned on
a HUD-side CanvasLayer at the crate's canvas position
(`get_viewport_transform() * crate.global_position` — Control in screen
space, world anchor).

## 2. Buff queue and firing

- `Level` instance var `pending_buffs: Array[StringName]` — plain array,
  duplicates allowed (two skulls queued = two `exploding` charges).
- **Stacking rule for duplicates:** on fire, ONE charge of each buff type is
  consumed for that shot; remaining duplicates stay queued for later shots.
  (Two skulls = this shot explodes and the next one still can.) Distinct
  types all apply together to the same shot.
- `_on_fired(velocity)` drains: `multishot` charge present → launch 3 stones,
  velocities fanned by a small drift (base, base rotated ±~2.5°, matching
  the old version's "drifted apart a hair" feel); `exploding` /
  `super_bounce` charges set the corresponding flag on every stone launched.
- All launched stones join the existing flight bookkeeping: `_active_stone`
  becomes an array (`_active_stones`); `_stone_is_done()` and camera follow
  use the first/lead stone; settle waits for all.

## 3. Stone enchantments

`src/gameplay/stone.gd`:

- `var exploding := false`, `var super_bounce := false` — set by Level
  before/at launch.
- **Super bounce:** when set, apply a high-restitution
  `PhysicsMaterial` (bounce ≈ 0.75, tunable const). Natural decay — each
  bounce is lower and slower until the stone rests. No counters. Inherits
  the crates' speed-gated impact system: early bounces wallop, late bounces
  tickle.
- **Exploding:** `contact_monitor` on; on first `body_entered` → `_boom()`.
  - `_boom()`: radial impulse to every RigidBody2D within `BOOM_RADIUS`
    (≈ 180px, tunable) — impulse magnitude scales with the stone's speed at
    detonation and falls off with distance. Boom visual: reuse the
    CPUParticles2D pattern from `Effects._confetti` with fire/smoke colors +
    optional `sound:boom` when the owner drops a boom.ogg in assets/sfx.
  - Without `super_bounce`: the stone frees itself in the blast (one boom).
  - With `super_bounce`: the stone survives and booms again on EVERY
    subsequent contact (ground included) until it comes to rest — a skipping
    cluster bomb with naturally shrinking booms.
- Displacement scoring judges all blast damage. No special kill logic.

## 4. Ghost roll, skunk event, unlocks

- Roll at collection time, inside Level's ghost handler:
  - If skunk NOT yet unlocked: `SKUNK_CHANCE` (1/8, tunable) → skunk event;
    else equal roll of the four powerups.
  - If skunk already unlocked: always equal roll of the four (§0 pool A).
- **Skunk event (once ever per player):**
  - `Unlocks.set_flag("skunk")` persists immediately.
  - `RareUnlockFrame` ceremony plays: gold picture frame centered on
    screen, title "Rare Unlock", the skunk spritesheet animation
    (`art/characters/skunk-sprites.png`) playing inside the frame via
    AnimatedSprite2D/AnimationPlayer. Dismisses itself after the animation
    (a few seconds); gameplay continues (tree not paused — it's a fanfare,
    not a modal).
  - The ghost crate that released the skunk grants no powerup — the skunk
    IS the payout.
- **Skunk in-level behavior: TBD, deliberately out of scope.** This spec
  only opens the cage and remembers it. A future spec gives the skunk a job
  in subsequent levels.

New units:

- `src/settings/unlocks.gd` — `Unlocks` autoload; ConfigFile at
  `user://unlocks.cfg`; `has_flag(name) -> bool`, `set_flag(name)` (saves
  on write). The game's first save-data. Never stores code, only flags.
- `src/ui/rare_unlock_frame.gd` + `scenes/ui/rare_unlock_frame.tscn` —
  reusable ceremony: `show_unlock(title: String, frames: SpriteFrames,
  anim: StringName)`. Skunk is the first customer; future rare unlocks
  reuse it.

## 5. Carry-through and reset

- New static on Level: `static var carry_buffs: Array[StringName] = []`,
  same consume-and-clear discipline as `next_layout` (read into instance
  state in `_ready`, static cleared immediately).
- Set ONLY on the CLEARED advance path (and TEST-mode return is unaffected:
  back-to-editor discards buffs — editor sessions get no carry).
- Restart re-arm path does NOT carry buffs (restarting resets the attempt).
- Quit consumes-and-clears in the next `_ready` like all Level statics.

## 6. HUD buff indicator

- `Hud` gains a small `HBoxContainer` buff row near the stones row: one
  32px icon per queued buff, textures = the editor crate PNGs
  (`EditorAssets.texture_for` — blue crate icon means multishot; the color
  language is the crate language). Gold never appears (instant). Ghost
  never appears (it resolves to a real buff at collection).
- `hud.set_buffs(buffs: Array[StringName])` redraws the row; Level calls it
  on every queue change and after firing (row clears as charges consume).

## 7. Editor touchpoints

Code: none. The editor spawns frozen crates; frozen crates never emit
`knocked_out`. Content only: rewrite the `.txt` sidecars in
`assets/editor/crates/` to describe real behaviors (e.g. gold: "Knock it
out for a free shot"). Palette tooltips update themselves.

## 8. Testing (GUT, headless)

- Crate: `knocked_out` emits exactly once when displaced past the line;
  never when frozen; never while standing.
- Level routing: gold bumps shots + HUD; skull/blue/green queue; duplicates
  queue as charges; one charge per type consumed per shot; distinct types
  co-apply.
- Ghost: with a stubbed RNG, all four outcomes reachable; skunk event only
  when flag unset; sets flag; subsequent rolls exclude skunk.
- Unlocks: flag round-trips through a temp ConfigFile path; absent file =
  no flags.
- Stone: exploding stone displaces neighbors within radius (headless
  physics, settle-lab style); super_bounce stone bounces (post-ground-hit
  upward velocity); bounce+explode stone survives its first boom.
- Carry statics: consume-and-clear (set → new Level instance reads and
  clears; restart path does not carry).
- Multi-shot: 3 stones spawned, velocities distinct.
- Tier lab re-run (informal): difficulty ladder still monotonic with
  powerups present.

## 9. Out of scope

- Skunk's in-level behavior in subsequent levels (future spec).
- Crate damage states from explosions (owner's future idea: exploded-on
  crates become singed, or vaporize — "but not today").
- New curated Effects ids for level authors (boom visual is internal).
- Powerup crates in campaign level files beyond what the owner authors.
- Any editor code changes.
