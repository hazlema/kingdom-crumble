# Linked Triggers Design

Crate-linked triggers: when a specific crate registers as hit, fire a
list of actions — show/hide named scenery overlays plus anything from
the existing effects library. Hand-authored JSON for built-in levels;
NO editor UI (the editor must merely round-trip the new keys intact).

Owner decisions (2026-09-05): actions = show/hide + full effects
library; event = the crate's existing "registered as hit" moment
(leaves standing state — direct shot or chain collision, one-shot,
dead-stays-dead); crates referenced by their JSON x,y; overlays
referenced by a new optional `name`; editor authoring deferred.

## 1. Level JSON additions (`src/level/level_json.gd`, `level_layout.gd`)

### Overlay keys (both optional)

| Key | Type | Meaning |
|---|---|---|
| `name` | String | Author handle for triggers. 1–16 chars, `a-z0-9_-` (lowercase), unique among overlays in the file. |
| `hidden` | bool | Spawn invisible; a `show:` action reveals it. Default false. |

### Trigger event keys

The existing `triggers` dictionary gains per-crate events beside
`on_all_cleared`:

```json
"triggers": {
  "on_all_cleared": ["confetti"],
  "hit:5,1": ["hide:warning", "show:reward", "confetti", "sound:tada"]
}
```

- Event key format: `hit:X,Y` where X and Y are the linked crate's
  `x` and `y` exactly as integers (`"hit:%d,%d"`). Matching is against
  `int(crate.x), int(crate.y)`.
- Action ids: the existing curated set (`confetti`, `sound:<stem>`)
  plus two new families — `show:<name>` and `hide:<name>`.
- The existing 16-actions-per-event cap applies unchanged.

### Validation (inert-data doctrine: wrong TYPE rejects with a named
error; unknown NAME warns and skips at runtime)

- `name`: must be String, 1–16 chars, chars in `a-z0-9_-`, unique →
  errors "overlay N: bad name" / "overlay N: duplicate name '<n>'".
- `hidden`: must be bool → "overlay N: hidden must be true/false".
- Trigger keys must be `on_all_cleared` or match `hit:<int>,<int>` →
  "trigger '<key>': unknown event". Values must be Arrays of Strings
  (existing shape).
- `show:`/`hide:` action payloads must satisfy the same name charset →
  "trigger '<key>': bad action '<id>'". Whether the name EXISTS is a
  runtime warn-skip, not a validation error (an editor delete may
  orphan a reference; the level must still load).
- `Effects.is_known` learns `show:`/`hide:` prefixes so intro/effect
  count validation keeps one source of truth.

## 2. Spawning (`src/level/scenery_builder.gd`, `level_builder.gd`)

- SceneryBuilder: a piece whose overlay has `hidden: true` spawns with
  `visible = false`. Pieces with a `name` get
  `set_meta("overlay_name", name)`.
- LevelBuilder: each spawned crate gets
  `set_meta("json_coords", Vector2i(int(x), int(y)))` so the level can
  form its event key without re-deriving from physics positions.

## 3. Runtime firing (`src/level/level.gd`)

- `_on_crate_knocked(crate)` (existing, fires once per crate via the
  dead-stays-dead ledger) additionally:
  1. Reads `json_coords` meta → key `"hit:%d,%d"`.
  2. If `layout.triggers` has the key, iterate its actions:
     - `show:<name>` / `hide:<name>`: find the scenery piece whose
       `overlay_name` meta matches; set `visible` true/false. Unknown
       name → `push_warning`, continue.
     - anything else → collect and pass to `Effects.fire_all` at the
       crate's global position (unknown ids already warn there).
- One-shot is inherited from the knocked ledger — no new bookkeeping.
- TEST from the editor exercises triggers identically (same level
  scene, same layout).

## 4. Editor round-trip (no editor changes expected; verify only)

- `serialize()` writes overlays verbatim minus underscore keys →
  `name`/`hidden` survive; `triggers` passes through untouched.
- Scenery bake rekeys `image` only → `name`/`hidden` survive.
- Deleting a named overlay in the editor may orphan `show:`/`hide:`
  references: loads fine, warns at fire time (accepted).
- parse() strips underscore keys only — `name`/`hidden` are normal
  keys and untouched.

## 5. Testing (GUT)

- Validation: good file passes; bad name charset / duplicate names /
  bad hidden type / malformed `hit:` key / bad action id each return
  their named error.
- Builder: `hidden` overlay spawns invisible; named piece carries the
  meta; crate carries `json_coords`.
- Level runtime (synthetic layout): knock the linked crate → hidden
  piece becomes visible, shown piece hides, effect actions reach
  Effects (confetti node appears); unknown name warns without crash;
  a second knock of a different unlinked crate fires nothing.
- Round-trip: serialize→parse preserves `name`, `hidden`, and `hit:`
  trigger entries.

## Out of scope

Editor UI for linking (future "link" option in the scenery/context
menus), non-crate events, overlay swap actions, per-hit repeatable
triggers.
