# Deeds of the Kingdom — Achievements Design

**Owner-approved direction (2026-09-12).** Single-player, local-only achievement
system with zero scoring: event-tied unlocks displayed as an illuminated
parchment page of round medallions ("Deeds of the Kingdom" — concept art:
`assets/tmp/trophy-concepts/concept-3-medallions.png`, the chosen vibe).
Earned medallions are full-color paintings; unearned ones are pencil-sketch
ghosts. Adding an achievement is a content act, not a code act: paint a
medallion, drop the PNG(s), add one manifest entry.

## Core separation (the owner's architecture)

1. **The game only writes.** Gameplay code records events through a tiny
   API — it never knows what achievements exist.
2. **One class reads.** The `Deeds` autoload is the only reader of the
   persisted file and the only evaluator of triggers. Public surface:
   `is_unlocked(id) -> bool`, plus a `deed_unlocked(id)` signal for juice.
3. **Content is a manifest.** `res://achievements/achievements.manifest`
   lists every achievement **in display order** (the deeds page is a
   curated document — order is first-class, which is why this is one
   manifest and not per-file sidecars like `pieces/`).

## Files

```
res://achievements/
  achievements.manifest        ← one JSON array, display order
  first-shot.png               ← solid medallion art
  first-shot-ghost.png         ← optional; auto-desaturated fallback
  ...
user://deeds.cfg               ← [stats] counters/flags + [celebrated] ids
```

`user://deeds.cfg` joins `VersionGate.WIPE_FILES` (wiped on version change
in testing builds only, like progress/unlocks).

## Manifest entry

```json
{ "id": "crate_smasher",
  "name": "Crate Smasher",
  "text": "Clear your first level",
  "solid": "crate-smasher.png",
  "ghost": "crate-smasher-ghost.png",
  "trigger": "count:levels_cleared>=1",
  "secret": false }
```

- `id` — savable charset `^[a-z0-9_-]{1,32}$`, unique. `name` — ribbon
  label. `text` — plaque description (shown when unlocked; locked shows
  the name with the concept art's "?" styling).
- `ghost` optional → auto-generate by desaturating `solid` (artist can
  override with hand-drawn ghosts).
- `secret: true` → locked entry shows "???" for the name too (the
  mystery slots from the concept).
- Inert-data doctrine: a malformed entry warns (naming the id/index) and
  is skipped; the rest of the page loads. Unknown keys ignored. Unknown
  stat names in triggers = the trigger simply never fires (warn once at
  load) — a future-content tease costs nothing.

## Trigger vocabulary (curated — sidecar-first doctrine)

A trigger is ONE clause. Content selects and combines; only code defines
what is recordable. V1 clauses:

| Clause | Meaning |
|---|---|
| `count:<stat>>=N` | recorded counter reached N |
| `flag:<name>` | recorded flag is set |
| `unlocked:<id,id,...>` | ALL listed achievements unlocked (meta-deeds — the owner's `1,4,7` example) |

No expressions, no scripting, no OR (rider if ever needed). `unlocked:`
must not be self-referential or cyclic — load-time validation warns and
disables the entry on a cycle.

## Recording API (the game-side seams)

`Deeds.bump(stat: String)` / `Deeds.flag(name: String)` — one-liners
placed at existing events. After every write, `Deeds` re-evaluates,
diffs against `[celebrated]`, appends newly-earned ids, and emits
`deed_unlocked(id)` — this is what makes the banner LIVE, not lazy.

Wave-1 stats (seams that already exist — no new plumbing):

| Stat | Seam |
|---|---|
| `shots_fired` | trebuchet fire path |
| `levels_cleared` | `_record_clear` |
| `tiers_cleared` | chain-end clear |
| `wormhole_transits` | wormhole teleport |
| `mystery_opened` | ghost-crate powerup roll |
| `editor_saves` | editor `_on_save` first success |
| `skunk` (flag) | existing unlock — Skunk's Ally is grandfathered |
| `seasonal_played` (flag) | seasonal month main-menu play |

Feat-stats needing new detection (bank as wave 2): tramp-bounce-kill
(High Bouncer as a kill feat), one-shot clear, boom-chain count.

## The banner (the owner wants it REALLY cool)

On `deed_unlocked`: the actual medallion art stamps onto the screen
center-top with a scale-punch (big → settle), gold ribbon beneath —
"⚜ Deed Accomplished — Crate Smasher ⚜" — confetti burst, dedicated
sound stem (`deed.ogg`, art dept to supply). Holds ~2.5s, tucks away.
Queues politely behind/after the existing toast/banner choreography
(same `_banner_seq` discipline; multiple unlocks queue in order).
Cosmetic only; never blocks input.

## The deeds page

Main-menu button → full-screen parchment page in the concept-3 style:
carved wood frame, illuminated header, grid of medallions in manifest
order (ribbon label under each). Unlocked = solid art + gold ring;
locked = ghost art + grey sketch ring + "?"-styled name. Tap/hover a
medallion → plaque text (unlocked) or a shrug (locked, secret stays
"???"). Scrolls when entries exceed a page. Uses kingdom_theme.

## Critters (relationship, not scope)

Critters are the prestige tier displayed with special treatment later
(concept-2 "My Kingdom" room is the banked hub idea). V1 ships the
deeds page only; Skunk's Ally medallion represents the skunk for now.
Critter unlock plumbing = its own future design.

## Art department order sheet 🎨

- Per achievement: **solid medallion** PNG, 256×256, round composition,
  transparent corners (displayed ~128). Ghost optional.
- The **page dressing**: parchment + frame + header banner (one big
  background image is fine — same pipeline as scenery).
- **Banner ribbon** art (or theme-drawn if preferred).
- **`deed.ogg`** unlock sound.
- Wave-1 roster (owner-approved name seeds): First Shot, Crate Smasher,
  High Bouncer*, Warp Master, Skunk's Ally, Kingdom Defender, Lucky
  Shot, Master Builder — plus ghost-only teasers Windmill Whiz? and
  Dragon Tamer? (secret, trigger on stats that don't exist yet — free
  foreshadowing, costs nothing by design).
  (*High Bouncer v1 trigger can be `count:tramp_bounces>=1` only if a
  cheap bounce seam exists; otherwise it waits for wave 2's feat
  detection.)

## Security / doctrine recap

Built-in content only in v1 (`res://achievements/`). Toybox packs
shipping deeds = rider (would need namespacing + the same curated
vocabulary — nothing in this design blocks it). No scripting anywhere:
triggers select from baked clauses over baked stats. Decode budgets and
pre-read caps per the existing image-loading rules.

## Riders

- Wave-2 feat detection (bank-shot, one-shot clear, boom-chain).
- Critter hub page (concept-2) + critter unlock plumbing.
- Toybox packs shipping achievements.
- OR-composition in triggers (only if a real deed needs it).
