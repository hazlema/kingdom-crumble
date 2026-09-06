# Animatable Props Design

Owner idea (2026-09-06): props opt into the SAME animation system as
scenery — a sidecar `animatable: true` unlocks per-placement NarfDecor
verbs and dials, edited with the piece inspector level authors already
know. Supersedes the wormhole spin-dial (never built). First
application of the sidecar-first standing rule (pieces-design,
2026-09-06): abilities live in sidecars, mechanics stay baked.

## 1. Sidecar: `animatable` (any prop class)

| Key | Type | Rule | Default |
|---|---|---|---|
| `animatable` | bool | strict bool (the `hidden` lesson); non-bool → named warning + false | false |

- Wave 1 ships it on the four wormhole/tramp entries? NO — owner call:
  `wormhole-blue` and `wormhole-orange` gain `"animatable": true`;
  statics and trampolines stay non-animatable until a level needs it
  (flipping them on later is a one-line sidecar edit, zero code).
- A non-animatable prop placed before this feature: unchanged. A prop
  whose sidecar later turns animatable: existing placements simply
  have no animation keys → NONE (static), as today.

## 2. Level format: per-placement animation keys on props entries

`props` entries gain the same optional keys overlays carry, minus the
travel verbs:

```json
{ "id": "wormhole-blue", "x": 1024, "y": 443,
  "behavior": "SPIN", "speed": 0.6 }
```

| Key | Type | Rule | Default |
|---|---|---|---|
| `behavior` | String | curated: `NONE`, `SPIN`, `SWAY`, `BOB` | `NONE` |
| `speed` | number | clamped 0.0–2.0 (scenery convention) | verb-sensible (SPIN 0.6) |
| `amplitude` | number | clamped 0–12 px (TIGHT — see §4) | 6 |

- Validation (inert doctrine, named errors): unknown `behavior` →
  `"prop %d: bad behavior"`; non-number speed/amplitude →
  `"prop %d: bad dial"`. Keys on a NON-animatable piece are not a
  validation error — they parse, and spawn ignores them with a named
  `push_warning` (an author may flip animatable off later; the level
  must still load).
- `DRIFT`/`WANDER` are NOT valid for props (they travel — a warp zone
  or collision box that appears to roam would lie to the player's
  aim). Listing them → `"prop %d: bad behavior"`.
- serialize/parse round-trip the keys verbatim (they are plain keys,
  not underscore-prefixed edit state).

## 3. Runtime: sprite-only animation, physics glued to the grid

- The prop's Area2D/StaticBody2D and its collision NEVER move or
  rotate. Only the child Sprite2D animates. The warp zone, the wall,
  the bounce surface — all exactly where the grid says.
- PropBuilder reads the placement keys (when the entry is animatable)
  and configures the sprite's animation. Implementation shape: a small
  `PropAnimator` helper (or reuse of NarfDecor math on the sprite —
  implementer's choice at plan time, but the VERB SEMANTICS must match
  scenery: SPIN = continuous rotation at `speed` rad/s; SWAY = rotation
  oscillation; BOB = vertical position oscillation of the sprite around
  its offset, amplitude in px).
- Wormhole's built-in `_process` spin (SPIN_RAD_PER_SEC const) is
  RETIRED — replaced by the data path. **Default-behavior decision
  (owner to confirm): placements with no animation keys are NONE
  (static).** Still portals become the zero-effort case; spin is a
  deliberate per-placement choice in the inspector. No shipped level
  contains wormholes yet, so nothing regresses — but this inverts
  today's always-spinning default. (A class-level default-verb sidecar
  key was considered and rejected as YAGNI.)
- The arrival whoosh's gulp pulse tweens the sprite's SCALE — compose
  with animation (scale pulse + rotation coexist; BOB's offset tween
  and the pulse touch different properties).

## 4. Amplitude cap: 12 px

SWAY/BOB visuals must stay honest about where the piece physically is.
12 px keeps the art within ~20% of a cell — readable wobble, no lying.
(Scenery's cap is 60; props are gameplay objects, hence the tight
clamp in §2. The clamp lives in level_json validation AND is re-applied
at spawn — belt for hand-edits, suspenders for packs.)

## 5. Editor: the scenery inspector, pointed at props

- Selecting an animatable prop (click, crate mode) opens the existing
  `%PieceInspector` in a reduced mode: verb dropdown (NONE/SPIN/SWAY/
  BOB only), speed + amplitude sliders (amplitude max 12). Pivot/axis/
  travel/tilt controls hidden.
- The inspector writes to the prop's `current.props` entry (mirror of
  how it writes overlay dicts) and pokes the live sprite for instant
  preview.
- Selecting a NON-animatable prop or a crate: inspector stays closed
  (today's behavior).
- Deselect/delete/mode-change closes it. Drag-move keeps the entry's
  animation keys (move rewrites x/y only — the Task-1 `_move_prop`
  entry rewrite must PRESERVE unknown keys: copy the dict and update
  x/y instead of rebuilding `{id, x, y}` — this is a required fix to
  the just-shipped code).
- TEST and the game render identically (PropBuilder is the one path).

## 6. Testing (GUT)

- Sidecar: animatable strict-bool (true/1/absent), warning on non-bool.
- Validation: behavior matrix (SPIN ok, WANDER rejected, junk
  rejected), dial clamps, keys-on-non-animatable parse fine.
- Spawn: SPIN placement rotates the sprite, body rotation stays 0 and
  collision position unchanged after N frames; NONE placement fully
  static; keys on non-animatable prop → warn + static; amplitude
  clamped at spawn.
- Editor: inspector opens for animatable prop only; writes land in
  current.props; drag-move preserves animation keys (regression pin on
  the §5 fix); serialize round-trips.
- Whoosh coexistence: gulp pulse on an animated sprite ends at scale 1.

## Out of scope

Travel verbs for props, per-prop pivot/axis, animating collision,
class-level default verbs, retrofitting statics/tramps' sidecars
(one-line edits whenever a level wants them).
