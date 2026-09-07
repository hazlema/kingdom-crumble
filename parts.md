# Parts — the Pieces System

Everything placeable in Kingdom Crumble is a **piece**: one PNG plus an
optional JSON sidecar in `pieces/`. Drop a PNG in, it's a plain crate.
Add a sidecar, it becomes whatever the sidecar says. No code.

**The standing rule (sidecar-first):** nothing per-piece is hardcoded.
Sidecars *select and tune* from curated sets and clamped ranges; the
mechanics behind those choices live in code (`class`es and `powerup`s
are baked — new ones ship in game updates, sometimes dormant, then
become sidecar-pickable forever). This is also the security stance:
a shared level or a future DLC pack can only ever pick powers you
built — it can never script.

Bad data never crashes: a wrong **type** in a level file is a named
validation error at load; an unknown **name** (piece id, overlay name,
powerup) warns in the log and is skipped at spawn. Malformed sidecars
warn and either clamp or fall back to a plain crate.

---

## Image rules (read this before making art)

**One PNG per piece. No spritesheets.** Animation is NarfDecor's job
(see *Animatable*, below) — a piece image is a single still.

**Native pixels are world pixels.** Prop sprites draw at the PNG's
exact size — nothing rescales them. If the art doesn't match the
footprint, the picture and the physics disagree on where the object
is. The grid cell is **64 px wide × 63 px tall**, so:

> **image size = cells.x × 64 wide, cells.y × 63 tall**

| Footprint | Image size | Shipped examples |
|---|---|---|
| 1×1 | 64 × 63 | `block-stone.png`, `tramp-left/right.png` |
| 2×1 | 128 × 63 | `tramp-flat.png` |
| 1×2 | 64 × 126 | `wormhole-blue/orange.png` |

Crates are the one exception: their art rides the crate scene's Skin
sprite (also unscaled), and the shipped faces are **64 × 64** — match
that for new crate skins.

Other art notes:

- Transparency is fine (the wormholes and tramps use it); keep the
  visual mass inside the footprint so hits feel honest.
- Generate big, then downscale with Lanczos to the exact display size
  — in-engine downscale looks crunchy (established art doctrine).
- After adding a PNG, run a headless import once
  (`godot --headless --import`) or open the editor, so Godot registers
  it.

---

## The classes

### `crate` — the game layer (default)

Physics body (RigidBody2D) that the whole game is about: **scored**
(counts toward clearing), knockable, a valid `hit:X,Y` linked-trigger
target, and the only class that can carry a `powerup`. No sidecar at
all = a plain 1×1 crate.

### `static` — immutable geometry

StaticBody2D. Deflects stones and crates, can't be destroyed, never
scored, invisible to triggers and powerups. Pure level architecture:
walls, shelves, funnels, shields.

### `trampoline` — bouncy geometry

StaticBody2D with a bouncy physics material. `bounce` is the
restitution dial (owner-blessed feel: **1.5**; lower = mushy crash
pad, higher = violent). `tilt` bakes the ramp direction into the
collision shape — this is why the three tramps are three separate
pieces rather than one rotatable one: grid placement stays
axis-aligned and the bounce direction is always readable.

- `tilt: 0` — flat, bounces straight up
- `tilt: -45` — launches up-and-**left**
- `tilt: 45` — launches up-and-**right**

*(The angled tramps are owner art, 1×1, and the lean now matches the
physics — verified against the collision polygons 2026-09-06.)*

### `wormhole` — paired portals

Area2D (a detection zone, not a wall — things pass through it
physically). Rules:

- **The id is the pair.** Place the *same* wormhole piece exactly
  twice in a level and the two link automatically. Once, or three or
  more times → a warning at spawn and they sit as inert scenery. Want
  two independent pairs? Use two colors. More colors = more PNG+JSON
  drops.
- **Stones only** warp (crates pass through; crate transit is a
  reserved future flag).
- **Speed is preserved; direction rides the exit portal's sprite
  rotation.** A still portal is a through-window (out exactly as you
  came in). A SPIN-animated portal is a sweeping launcher — arrival
  timing decides the exit line. SWAY wobbles the exit within a cone.
  The swirl you see IS the aim: honest by construction.
- A stone can't instantly re-enter the portal it just exited (arrival
  immunity), so adjacent portals never ping-pong.
- Arrivals fire a **whoosh**: a particle burst auto-tinted from the
  portal's own art (any future color gets matching juice for free)
  plus a "gulp" pulse on the sprite.

---

## Sidecar reference (per-piece, in `pieces/<id>.json`)

| Key | Type | Values / clamp | Default | Applies to |
|---|---|---|---|---|
| `class` | String | `crate` \| `static` \| `trampoline` \| `wormhole` | `crate` | all |
| `cells` | [int, int] | each 1–4 | `[1, 1]` | all (footprint: x → right, y → up) |
| `tip` | String | ≤ 200 chars | the id | all (palette tooltip) |
| `powerup` | String | `free_shot` \| `exploding` \| `multishot` \| `super_bounce` \| `mystery` | none | crate |
| `tilt` | int | `-45` \| `0` \| `45` | `0` | trampoline |
| `bounce` | float | 0.5–2.0 | `1.5` | trampoline |
| `animatable` | bool | strict `true` only | `false` | any prop (see below) |

Unknown keys are ignored (forward compatibility). Unknown `class` or
`powerup` values warn and degrade safely. `mystery` is the ghost-crate
roll: a random power, with the skunk-unlock chance baked into it.

## Per-placement keys (in the level file's `props` entries)

A placed prop is `{"id": "...", "x": ..., "y": ...}` in the level
JSON's `props` array (`x`,`y` = the anchor cell's center — the
leftmost, bottom-most cell of the footprint, exactly as the editor
writes them; bare ints, no `.0`). If the piece's sidecar says
`animatable: true`, each placement may also carry:

| Key | Type | Values / clamp | Default |
|---|---|---|---|
| `behavior` | String | `NONE` \| `SPIN` \| `SWAY` \| `BOB` | `NONE` (still) |
| `speed` | number | 0.0–2.0 | verb-sensible |
| `amplitude` | number | 0–12 px | 6 |

Sprite-only: the collision (and a wormhole's warp zone) never moves —
the tight amplitude cap keeps the picture honest about where the
object really is. Travel verbs (DRIFT/WANDER) are scenery-only and
rejected for props. In the editor, selecting an animatable prop opens
the piece inspector in a reduced mode with exactly these dials.

Crates live in the separate `crates` array (`{"x", "y", "type"}`) and
are additionally the targets of linked triggers: the trigger key is
`"hit:X,Y"` with the crate's exact ints — right-click a crate in the
editor → **Info** → **Copy Key** to get it clipboard-ready.

---

## Editor behavior

- Palette sections are fed by class: CRATES, then OBSTACLES (statics,
  tramps, wormholes).
- Everything places on the grid. Multi-cell pieces need their whole
  footprint free; the ghost preview spans it (green = fits, red = no).
- **Select** any cell of a piece — the ring wraps the whole footprint.
  **Drag** moves the whole piece (grab any cell). **DELETE** removes
  it. Right-click a **crate** for Info/Copy-Key.
- Selection is one fact; the views (ring, inspector, gizmo) render it.
  Loading/clearing a level always deselects.
- TEST runs the real game spawners — what you test is what ships.

---

## For coders: the API surface

**`Pieces`** (static registry, `src/level/pieces.gd`) — scans
`res://pieces/` recursively at boot:

- `scan()` — repopulate the cache
- `entries() -> Array[Dictionary]` — all pieces, sorted by id
- `by_class(cls) -> Array[Dictionary]` — palette feeds
- `entry(id) -> Dictionary` — `{id, texture, class, cells: Vector2i,
  tilt, bounce, tip, powerup, animatable}`; `{}` if unknown
- `texture_for(id) -> Texture2D` — the single texture authority
  (HUD, palette, spawners all route here); null if unknown
- `parse_sidecar(id, raw) -> Dictionary` — pure, clamped; `{}` = skip

**`PropBuilder`** (`src/level/prop_builder.gd`):

- `spawn_props(parent, layout) -> Array[Node2D]` — spawns every
  `props` entry and links wormhole pairs (the one production path;
  game and editor-TEST both use it)
- `spawn_one(parent, prop) -> Node2D` — StaticBody2D or Wormhole;
  null + warning on unknown ids; bodies join group `"props"` and
  carry meta `prop_id` + `anchor_cell`
- `footprint_center(anchor_world, cells) -> Vector2`

**`Wormhole`** (`src/level/wormhole.gd`, Area2D): `partner`,
`link_pairs(nodes)` (the exactly-two rule), `play_arrival_fx(v)`,
arrival-immunity internals. Teleports write through
`PhysicsServer2D.body_set_state` — never node properties from a
`body_entered` callback (the flush overwrites them; hard-won lesson).

**`PowerupRules.route(type_id, ...)`** reads the registry's `powerup`
key — there is no id table.

**Adding a mechanic** (the dormant-class pattern): new class in code →
add it to `Pieces.CLASSES` + a spawn branch + its curated keys with
clamps → from then on, every variant is a PNG + JSON drop. Candidates
on the roadmap: mortar (sticks-to-neighbors), and whatever the next
brain fart demands.

## Related docs

- `docs/superpowers/specs/2026-09-05-pieces-design.md` — the system
  spec, including wave 2 (user packs in `user://toybox/`, seasonal
  reskin themes) and the sidecar-first standing rule
- `docs/superpowers/specs/2026-09-06-wormholes-design.md`,
  `2026-09-06-animatable-props-design.md` — class deep-dives
- `docs/audits/2026-09-06-editor-architecture.md` — why the editor is
  shaped the way it is

---

## The Toybox — content packs

Packs are folders players drop into `user://toybox/` (desktop builds;
web pack import is future work). Each pack is:

```
user://toybox/thanksgiving/
├── pack.json          ← the manifest (required)
├── turkey-crate.png   ← pieces (object packs)
├── turkey-crate.json
└── ...
```

### The manifest (`pack.json`)

| Key | Type | Rule |
|---|---|---|
| `title` | String | shown in the Toybox menu; ≤ 60 chars |
| `kind` | String | `objects` or `theme` |
| `months` | [int] | 1–12; absent/empty = available all year |

Folder names: lowercase `a-z0-9_-`, ≤ 32 chars. A bad manifest, bad
folder name, or oversized manifest (> 64 KB) makes the pack warn and
sit out — nothing crashes, ever. Pack images pass the same hardened
gates as everything else (PNG signature, pre-decode dimension caps),
so a broken or hostile file is just a warning in the log.

### Object packs (`kind: objects`) — NEW pieces

PNG + sidecar pairs, exactly like `pieces/` (same schema, same image
rules — see above). Their ids are namespaced by the folder:
`thanksgiving:turkey-crate`. That means packs can never collide with
built-in pieces or with each other. Pack crates can carry `powerup`,
pack pieces can be `animatable` — the full sidecar vocabulary works.

Players toggle each object pack with a checkbox in the **Toybox**
section of the pause menu (default: on). Disabling a pack removes its
pieces from the palette; a level that uses them still loads — props
from a disabled pack are skipped with a warning; crates from a
disabled pack spawn as plain wood crates (still scored, level stays
winnable) with a warning.

### Theme packs (`kind: theme`) — reskin the base game

No sidecars: just PNGs **named for the built-in ids they replace**
(`crate-wood.png`, `tramp-flat.png`, `wormhole-blue.png`...). While a
theme is active, every level — built-in, yours, anyone's — wears the
new art. Physics, scoring, and triggers are untouched by construction:
themes change pixels, nothing else.

Rules:

- **Dimensions must match the base art exactly** (native pixels are
  world pixels — a mis-sized reskin would lie about physics). Wrong
  size → warning, that one image falls back to the built-in.
- **One theme at a time** — a radio choice in the Toybox menu
  ("Default" always available). No merge rules needed, ever.
- **Seasons**: give the manifest `"months": [11]` and the theme is
  only *selectable* in November — the menu shows it grayed with
  "returns in November" the rest of the year, and an active theme
  auto-reverts to Default when its season ends. (The clock is the
  local system clock. Time-travelers welcome.)

### Where the switches live

Pause menu → **TOYBOX** (the section only appears when packs are
installed). Changes apply on the next level load or editor open.
Persistence: `user://toybox.cfg` — delete it to reset all pack
settings to defaults.
