# NarfDecor DRIFT + WANDER Design

Two new behavior verbs for NarfKit's living scenery, reachable from both
hand-built scenes and the in-game level editor: **DRIFT** (clouds gliding
back and forth) and **WANDER** (butterflies roaming a meadow). Plus one
usability rename: the "Amplitude" dial becomes **Movement**.

Owner decisions (2026-09-03): range = ± distance from placement; motion
eases at the edges (sine); one DRIFT verb + axis dial (not two verbs);
WANDER flips to face travel and banks with a degree-dial tilt; no rest
pauses (dropped — add later if wanted); amplitude display name → Movement
("Speed" was floated but collides with the existing rate dial).

## 1. NarfDecor component (`addons/narfkit/narf_decor.gd`)

### Enum additions

```gdscript
enum Behavior { NONE, SPIN, SWAY, BOB, DRIFT, WANDER }
enum DriftAxis { HORIZONTAL, VERTICAL }
```

Existing values keep their ordinals — saved scenes are untouched.

### Export dials

| Dial | Range | Used by | Meaning |
|---|---|---|---|
| `behavior` | enum | all | what the piece does with its time |
| `pivot` | 9-point enum | all | unchanged |
| `speed` | 0–10 | all | SPIN: rev/s · SWAY/BOB/DRIFT: oscillations/s · WANDER: hops/s |
| `movement` | 0–180 | SWAY, BOB | **renamed from `amplitude`** — SWAY: peak tilt °, BOB: peak travel px |
| `axis` | H/V | DRIFT | which way the piece slides |
| `travel` | 0–2000 px | DRIFT, WANDER | DRIFT: ± range from placement · WANDER: roam radius |
| `tilt` | 0–45° | WANDER | peak banking angle while flying |

The `amplitude → movement` rename is a true property rename (var, code,
tests). No .tscn in the repo stores `amplitude`, so nothing migrates.
The level-JSON field keeps the name `amplitude` for save compatibility
(see §3) — one comment at the builder assignment notes the mapping.

### Motion math (all in `_process`, no Tweens — deterministic, testable)

`_home_y` grows into `_home_pos: Vector2` captured in `_ready()`
(BOB switches to `_home_pos.y`, same behavior).

**DRIFT** — sine glide centered on placement, easing at both edges:

```gdscript
var axis_vec := Vector2.RIGHT if axis == DriftAxis.HORIZONTAL else Vector2.DOWN
position = _home_pos + axis_vec * travel * sin(_t * speed * TAU)
```

**WANDER** — hop loop. Each hop:

1. Pick a uniform random target inside the roam circle:
   `_home_pos + Vector2.from_angle(_rng.randf() * TAU) * travel * sqrt(_rng.randf())`
2. Glide from hop start to target over `1.0 / max(speed, 0.01)` seconds
   with smoothstep easing (`q = p * p * (3.0 - 2.0 * p)`), so short hops
   amble and long hops hustle — butterfly-like.
3. On arrival, immediately pick the next target.

While flying:
- `flip_h = target.x < hop_start.x` — flies nose-first (art assumed to
  face right; doc comment says flip the PNG if it doesn't).
- Banking: `rotation = _home_rotation + hsign * deg_to_rad(tilt) * sin(p * PI)`
  where `hsign` is +1 flying right, −1 flying left. `sin(p * PI)` is zero
  at both endpoints — always level at rest.

Randomness comes from a per-node `_rng := RandomNumberGenerator.new()`;
tests set `_rng.seed` for reproducibility. `Engine.is_editor_hint()`
early-out stays — no motion (or RNG churn) in the Godot editor.

## 2. In-game editor (`src/editor/piece_inspector.gd` + its scene)

- `BEHAVIOR_NAMES` gains `"DRIFT"` and `"WANDER"` (order matches enum).
- The Amplitude slider's **displayed label** becomes **MOVEMENT** (scene
  text change; node names and overlay keys stay).
- New controls, following existing inspector patterns (write the overlay
  dict as source of truth, poke the live piece, no motion preview):
  - **Axis**: two radio-style toggle buttons `H` / `V` (same style as
    the behavior/pivot controls). Default H.
  - **Travel**: HSlider 0–2000, step 1, default 120.
  - **Tilt**: HSlider 0–45, step 0.5, default 8.
- All dials stay always-visible, like speed/movement today.

## 3. Level JSON (`src/level/level_json.gd`, `src/level/level_layout.gd`, `src/level/scenery_builder.gd`)

Three new **optional** overlay fields — `FORMAT` unchanged, every old
level (including web IndexedDB saves) loads exactly as before:

```json
{ "image": "...", "x": 0, "y": 0,
  "behavior": "DRIFT", "pivot": "CENTER",
  "speed": 0.25, "amplitude": 6.0,
  "axis": "HORIZONTAL", "travel": 120.0, "tilt": 8.0 }
```

- `level_json.gd` validation (same split as today — wrong TYPE rejects
  here, unknown NAME is the builder's skip-with-warning department):
  `axis` must be String; `travel` and `tilt` must be float or int.
- `scenery_builder.gd` maps and clamps:
  - `axis` name → `DriftAxis` via enum keys (unknown → warning + skip
    entry, same as behavior/pivot handling).
  - `piece.travel = clampf(float(entry.get("travel", 120.0)), 0.0, 2000.0)`
  - `piece.tilt = clampf(float(entry.get("tilt", 8.0)), 0.0, 45.0)`
  - JSON `amplitude` → `piece.movement` (field name kept for compat).
- `level_layout.gd` doc comment gains the new optional keys.

## 4. Testing (GUT, headless)

`tests/unit/test_narf_decor.gd` — drive `_process(dt)` by hand:
- DRIFT horizontal: x stays within home ± travel, y never changes;
  vertical: mirror.
- WANDER (seeded RNG): position never leaves the roam circle over many
  simulated seconds; `flip_h` matches heading; |rotation offset| ≤ tilt
  and returns to level (≈ home rotation) at each hop boundary.
- `movement` rename: existing SWAY/BOB tests updated to the new name.

Existing suites for level_json validation, scenery format round-trip,
and scenery_builder get cases for the three new fields (valid, missing →
defaults, wrong type → "bad overlay", unknown axis name → skip+warning).

`addons/narfkit/README.md` documents both verbs and the rename.

## Out of scope

Rest pauses for WANDER, diagonal DRIFT, per-behavior Inspector property
hiding (`_validate_property`), and any editor-asset additions (clouds /
butterfly art ship separately through the normal assets pipeline).
