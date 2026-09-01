# Kingdom Crumble — Pretty Pass Design (UI chrome only)

Owner-approved design, 2026-09-01. Presentation ONLY — zero mechanics
changes.

## 0. Binding references and hard rules

- **Comps (binding, exact values):** `art/mockups/Game UI Styles.html` —
  inline styles carry the paddings/gaps/radii/tracking/font sizes to copy
  literally. `art/mockups/palette.json` = colors and rules (already applied
  to `resources/ui/kingdom_theme.tres`). Fonts already wired: Lilita One
  (display), Nunito 800 (body), IBM Plex Mono 500 (meta labels — used for
  the first time this pass).
- **SCOPE WALL (owner paranoia clause, binding):** UI chrome only — HUD
  stat card, MENU, FIRE, jump dialog, pause menu, theme. NOTHING in the
  game world changes: backgrounds, crates, catapult, stones, physics,
  particles, shaders, level content. Final verification grep-checks that
  no gameplay/world file changed beyond UI wiring in level.gd/hud.gd.
- **No new mechanics.** Stars are NOT rendered (no data exists). Chapters
  are NOT implemented (header shows real counts only). Thumbnails come
  from files if present — no capture pipeline this pass.
- Style-guide law: "FIRE is the only fully saturated element on screen."

## 1. Approach — hybrid transcription

Global styles remain in `kingdom_theme.tres`. Composed components become
dedicated scenes transcribed 1:1 from the comp HTML:

- `scenes/ui/stat_card.tscn` + `src/ui/stat_card.gd` (new)
- `scenes/ui/level_card.tscn` + `src/ui/level_card.gd` (new)
- Restyle in place: `scenes/ui/level_jump_dialog.tscn`, `scenes/hud.tscn`
  (FIRE/MENU), pause menu inherits theme.

Gradients (FIRE red top→bottom, brass button faces) are built with
`GradientTexture2D` inside `StyleBoxTexture` resources — no shaders.

## 2. StatCard — the unified HUD panel

Replaces the HUD's scattered top-left elements (StatBar/PowerBar icon,
StonesRow, CratesRow, BuffRow all retire from hud.tscn).

Layout per comp: parchment panel; header row = title (Lilita One) +
"LVL n" chip (IBM Plex Mono, 9px, .16em tracking, ink-muted — n = the
level's position in the current chain, derived live via LevelChain, and
absent when the level isn't in the chain e.g. editor TEST); dashed
separators (ink-muted dashes); STONES row and CRATES row (emoji-style
icon 17px, mono meta label, Lilita One value 20px); PWR row (mono label +
brass-fill bar); fourth dashed section = queued buff icons (32px icons,
existing crate textures), hidden entirely while the queue is empty.
Body padding 11px 14px, row gaps 9px, in-row gaps 10px — from the comp.

**API stability rule:** `Hud.set_shots/set_crates/set_power/set_buffs`
and `hud.toast` keep their exact signatures; internally they forward to
the StatCard. Level title feeds the card header (toast remains for the
transient announcement). NO call-site changes in level.gd beyond what
wiring requires.

## 3. FIRE and MENU buttons

- FIRE: comp red gradient (fire-top #c9553a → fire-bottom #a13a24),
  Lilita One label, depth look (light inner top edge, dark drop bottom
  edge per rules.button-depth approximated with StyleBoxTexture +
  borders), pill radius, bottom-right, ≥48px touch target. **Dynamic
  icon** (pure display of the existing pending_buffs queue): stone icon
  by default; skull when exploding queued; green crate when super_bounce;
  gold sheen icon (crate-gold texture) when 2+ enchant types queued.
  Existing press/release wiring (action_press/release "fire") unchanged.
- MENU: brass pill (brass-light→brass-dark gradient face), ☰ + "MENU"
  in Lilita One, replaces the gear button. Same menu_pressed signal.

## 4. Level cards + jump dialog restyle

`LevelJumpDialog` becomes a card grid (3 columns, comp spacing) inside
the parchment dialog; title "LEVELS" (Lilita One) + right-aligned header
"N OF M CLEARED" (IBM Plex Mono meta style; counts = cleared/total in
the current tier's chain — real data, no chapter prefix).

Each `LevelCard`:
- Thumb region: loads the level's sibling image `<stem>.png` (same dir
  as the level json — works for res:// builtins and user:// levels).
  Missing → parchment inset panel with "NO IMAGE" (mono meta style).
  **Reserved convention (owner): every level MAY ship as two files,
  json + png; a future save-time capture pipeline writes the png; cards
  need no changes when it arrives.**
- Title row: state icon + title (Nunito 800). Cleared = ✓ on success
  green chip; unlocked-uncleared = plain; locked = padlock, greyed thumb
  (desaturated modulate), card disabled.
- Current level: "NOW" badge (danger red, top-left of thumb) + danger
  ring border around the card.
- Signals unchanged: clicking an unlocked card emits level_picked(path).
- Close: red circular X floating on the dialog's top-right corner
  (replaces the bottom Close button); Esc behavior unchanged.
- Star region: NOT rendered this pass (no data); card layout tolerates
  its future addition (comp shows top-right of thumb).

Scroll behavior: grid scrolls vertically when cards exceed the dialog.

## 5. Out of scope (explicit)

- Star mechanics/data, chapter grouping, thumbnail capture pipeline.
- Any world/gameplay change (scope wall).
- Editor-specific dialogs beyond what the theme already restyles.
- Victory fanfare, KingdomDialog generalization (this pass builds the
  pieces those will later reuse).

## 6. Testing (GUT)

- StatCard: set_shots/set_crates/set_power reflect in card labels/bar;
  buff section hidden when queue empty, one icon per charge when not;
  LVL chip shows chain position for a chain level and hides for a
  pathless (editor) layout.
- LevelCard: png-sibling found → texture used; missing → NO IMAGE panel
  visible; locked card disabled + greyed; NOW badge only on the current
  stem.
- Jump dialog: header reads "N OF M CLEARED" with correct counts; grid
  builds one card per chain entry; level_picked still emits; X closes.
- Hud API: existing suites keep passing unmodified (signature stability
  is the regression net).
- Scope wall verification: git diff shows no changes under
  src/gameplay/, src/level/ (except hud-wiring lines in level.gd if
  any), scenes/ world scenes, art/ (except mockups), assets/.
