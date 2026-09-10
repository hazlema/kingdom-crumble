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
| `aura` | String | `smog` \| `mist` \| `sparkle` \| `embers` | none | crate + any prop |
| `aura_color` | String | strict `#RRGGBB` (retints the verb; alpha stays baked) | verb default | anything with an `aura` |
| `tilt` | int | `-45` \| `0` \| `45` | `0` | trampoline |
| `bounce` | float | 0.5–2.0 | `1.5` | trampoline |
| `animatable` | bool | strict `true` only | `false` | any prop (see below) |

Unknown keys are ignored (forward compatibility). Unknown `class` or
`powerup` values warn and degrade safely. `mystery` is the ghost-crate
roll: a random power, with the skunk-unlock chance baked into it.

### Auras

**Auras** are ambient cosmetic particles that drift from a piece — purely
visual, zero gameplay effect. Each aura id maps to a baked CPUParticles2D
configuration inside `Auras` (`src/level/auras.gd`). The four curated ids:

- **`embers`** — slow upward orange sparks, campfire feel
- **`mist`** — soft blue-white wisps, cool and quiet
- **`smog`** — sooty haze, subtle menace (default dark olive-charcoal — green smoke vanishes against the meadow; recolor via `aura_color`)
- **`sparkle`** — bright yellow glitter, celebratory

Auras are applied at spawn (both crates and props). Unknown or non-String
values warn and are silently ignored — a missing aura is always a no-op,
never a crash. `aura_color` recolors any verb — `"aura": "smog"` plus
`"aura_color": "#7ec8ff"` is blue ghost-smoke; a bad color warns and
falls back to the verb's default, and the tint can never change the
baked alpha (content recolors, never opacifies). New aura ids require
a code change (adding an entry to
`Auras.KNOWN`) and can never be scripted from content alone.

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
editor → **Info** → **Copy Key** to get it clipboard-ready. The full
action vocabulary (editor dialog or hand-written): `show:<name>`,
`hide:<name>`, `confetti`, `sound:<stem>`, `smoke` /
`smoke:#RRGGBB` (the hit crate starts smoldering), and
`display:<message>` / `display:<secs>:<message>` (HUD toast, ≤ 80
chars, seconds from 3/10/20/30; other leading tokens are just message
text). The editor keeps keys honest for you: moving a crate moves its
trigger, deleting a crate deletes it.

---

## Scenery overlays

Scenery is freeform painted art (imported PNGs) placed outside the prop
grid. Each overlay is positioned by the editor and saved in the level's
`overlays` array. Three optional flags control collision, rendering order,
and the peek mechanic:

### Solid

Tick **Solid** to turn the painted silhouette into real collision.
The engine derives a collision polygon directly from the baked image's
alpha channel (`BitMap.create_from_image_alpha` → `opaque_to_polygons`).
**The picture is the physics**: what the player sees is what they can
stand on, no separate collision shape needed.

Image guidance:

- **Keep art ≤ 1024 px on the long edge.** The polygon tracer runs
  at spawn time; large images slow loading and produce over-detailed
  edges. The art pipeline downcaps on import anyway.
- **Transparency is passage.** A gap in the image (alpha = 0) is a hole
  the stone will fall through. Paint the roofline solid if you want
  stones to rest on it; leave gaps intentional if you want a gate.
- **Travel verbs (DRIFT/WANDER) are refused on solid overlays.**
  Collision is a `StaticBody2D` — it cannot move. The inspector
  disables the DRIFT/WANDER items in the behavior dropdown while Solid
  is checked, and resets any active travel verb to NONE when you first
  check the box.
- **Point-budget cap:** the tracer allows up to 512 polygon points per
  overlay. Over budget, the engine retries at higher epsilon values
  (simplifying the outline); if still over budget it logs a warning
  and spawns the overlay visual-only (never crashes, never blocks the
  level). The budget is generous — the spike measured a whole building
  silhouette at 7 points.
- **Hidden solid pieces spawn with collision disabled.** A `show:`
  trigger that reveals the piece also re-enables the body, so a
  secret wall can appear mid-level as a design feature.

Solid overlays join group `"scenery_solid"` and behave like the
`static` piece class: they deflect stones and crates, are never scored,
and are invisible to triggers and powerups.

### Auto-peek

Tick **Peek** to give the overlay the second object property: *fade
out when a shot comes near*. When any stone flies within ~120 px of
the piece, its alpha tweens down to 0.35 over ~0.2 s, then back to 1.0
when the shot is gone. The fade is pure feedback — it tells the player
"this thing isn't solid" without them having to test-fire at it.

Draw order is fixed and simple: background scenery, then peek pieces,
then crates, then stones, then the HUD. Peek pieces sit above plain
backdrops but **below the crates and stones — the goal is never
obscured** by scenery, faded or not.

Solid and Peek combine naturally: a solid depot with a peek awning is
a real wall wherever it's painted, and the awning advertises its
passable parts by fading as your shot arrives.

**Why not a mouseover?** On touch devices there is no hover; peek is
driven by shot proximity so it works identically on all platforms
without any input.

The fade is cosmetic only — it never touches collision, visibility
triggers, or selection.

---

## Editor behavior

- Palette sections are fed by class: CRATES, then OBSTACLES (statics,
  tramps, wormholes).
- Everything places on the grid. Multi-cell pieces need their whole
  footprint free; the ghost preview spans it (green = fits, red = no).
  **Hold Shift while placing to stamp multiples** without re-picking
  from the palette.
- Imported scenery gets an automatic **name** from its filename
  (sanitized, deduped: `sign`, `sign2`...) — right-click the piece →
  **Copy Name** for a clipboard-ready `show:`/`hide:` trigger target.
- In scenery mode: **arrows** nudge the selected piece 1 px (Shift =
  10 px), **hold Ctrl while dragging** to snap its top-left corner onto
  the crate-cell lattice (press **G** to see the grid you're snapping
  to), and corner-resize grows from the piece's **upper-left** like an
  art tool — the top-left corner stays pinned while the image scales.
- **Select** any cell of a piece — the ring wraps the whole footprint.
  **Drag** moves the whole piece (grab any cell). **DELETE** removes
  it. Right-click a **crate** for Info/Copy-Key.
- Right-click a **crate** → **Add Trigger…** opens the trigger dialog:
  pick named scenery overlays as `show:`/`hide:` targets, `confetti`,
  `smoke` (the hit crate starts smoldering — color picker tints it),
  `display:` (a short on-screen message, ≤ 80 chars, with a duration
  dropdown: 3/10/20/30 s — tutorial beats; saved as
  `display:<secs>:<message>`, bare `display:<message>` = 3 s),
  or a `sound:` stem. Each action is parameterized per type; up to 16
  actions per crate. This is why overlays want names — anonymous
  overlays don't appear in the picker.
- Selecting a scenery piece (full mode) opens the piece inspector with
  Behavior, Pivot, Speed, Movement, Axis, Travel, Tilt dials plus the
  **Solid** and **Peek** checkboxes — the two object properties. In
  reduced (prop) mode the scenery flags are hidden — they are scenery
  concepts. Checking **Solid** disables DRIFT/WANDER in the behavior
  dropdown and resets any active travel verb to NONE. The checkboxes
  only write the overlay dict; collision bodies are spawned by the
  game/TEST path, not the editor canvas.
- Selection is one fact; the views (ring, inspector, gizmo) render it.
  Loading/clearing a level always deselects.
- TEST runs the real game spawners — what you test is what ships.
- Keys: **S** save, **A** save as, **T** test, **C** toggle scenery,
  **M** next soundtrack album (chill → hardcore → heartpumper),
  **DELETE** remove selection, **Esc** leave scenery / drop carried
  piece (Ctrl+S / Ctrl+T also work on desktop; browsers keep those).

---

## For coders: the API surface

**`Pieces`** (static registry, `src/level/pieces.gd`) — scans
`res://pieces/` recursively at boot:

- `scan()` — repopulate the cache
- `entries() -> Array[Dictionary]` — all pieces, sorted by id
- `by_class(cls) -> Array[Dictionary]` — palette feeds
- `entry(id) -> Dictionary` — `{id, texture, class, cells: Vector2i,
  tilt, bounce, tip, powerup, aura, animatable}`; `{}` if unknown
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
pack pieces can be `animatable`, and pack pieces of any class can carry
`aura` — the full sidecar vocabulary works.

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

---

## Versioning & testing builds

Project Settings hold two dials (Project → Project Settings):

- **Application → Config → Version** — the build's version string.
- **Application → Config → Testing Reset** — the tester checkbox. While CHECKED, a
  version change wipes `progress.cfg` and `unlocks.cfg` on first boot
  so every test build starts fresh. UNCHECK it for real releases —
  players keep their progress across updates. Fresh installs are never
  wiped either way, and levels/settings are untouched.
