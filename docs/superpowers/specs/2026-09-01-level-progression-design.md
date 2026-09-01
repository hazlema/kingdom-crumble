# Kingdom Crumble — Level Progression & Jump Dialog Design

Owner-approved design, 2026-09-01.

## 0. Canon decisions (owner)

- **The chain**: built-in levels sorted alphabetically by stem, then user
  levels sorted alphabetically by stem. Clear the previous level to unlock
  the next. NO manifest — `campaign.json` is deleted (owner simplification,
  2026-09-01): the owner controls built-in order via naming, and since the
  UI displays titles, stems are free to be ordering keys (`10_meadow` shows
  as "Meadow Meltdown"). Caveat: renaming a stem orphans its checkmark.
- **Per-tier progression** ("make it so"): chill/heartpumper/hardcore each
  track their own completion — `chill/pineapple` and `hardcore/pineapple`
  are separate achievements. Adds a longevity dimension.
- **Keys are bare stems** (owner call over namespacing, eyes open): a user
  level sharing a built-in's stem shares its checkmark. Benign in a solo
  game; migrate to namespaced keys if/when level sharing ships.
- **Deletion-resilient**: progress is keyed by name; deleting a level leaves
  its entry harmless, re-adding restores its checkmark. The Pineapple rule:
  a new level inserted alphabetically between cleared levels is playable iff
  its predecessor is cleared.
- **Level select is IN-GAME**: no new screen. Pause/gear menu entry
  "Jump to Level" + keybind **L**. Bare-bones popup panel now; the owner
  stylizes later (KingdomDialog family).
- **Editor TEST runs never log completion** ("testing is just testing —
  no cheaters"), same law as the skunk exclusion.
- **Entry point**: main-menu tier buttons launch that tier's next uncleared
  level (all cleared → last level; nothing cleared → first built-in).
- **End of chain**: victory-flavored banner, ENTER → main menu. Fanfare
  animation hooks later.

## 1. LevelChain — pure ordering/unlock logic

`src/level/level_chain.gd`, `class_name LevelChain extends RefCounted`,
static, no scene access. Built fresh on every use — nothing cached, so
folder changes are instantly reflected.

- `static func entries() -> Array[Dictionary]` — ordered chain:
  `[{ "stem": String, "path": String, "title": String }]`.
  Built-ins first (`LevelStore.list_builtin()`, alphabetical by stem —
  NEW function replacing `campaign()`, same directory-listing shape as
  `list_user()`; `campaign()` and `levels/campaign.json` are deleted),
  then `LevelStore.list_user()` alphabetical. Unloadable files are
  skipped with a `push_warning` (a broken user file must not break the
  chain). Titles read from the parsed layout.
- `static func is_unlocked(chain: Array, index: int, tier: String) -> bool`
  — index 0 always; else `Progress.is_cleared(tier, chain[i-1].stem)`.
- `static func frontier(chain: Array, tier: String) -> int` — index of the
  first entry not cleared in this tier; `chain.size() - 1` when everything
  is cleared; 0 for an empty log.
- `static func next_index_after(chain: Array, stem: String) -> int` —
  index of the entry after the named one, or -1 at the end.
- Pure helpers take the chain array as a parameter → unit-testable with
  fabricated chains (no files needed).

## 2. Progress — the per-tier completion log

`src/settings/progress.gd`, autoload `Progress` (register after Unlocks in
project.godot). ConfigFile at `user://progress.cfg`, twin of the Unlocks
store. Sections = tier names, keys = stems, value `true`.

- `mark_cleared(tier: String, stem: String)` — saves immediately.
- `is_cleared(tier: String, stem: String) -> bool` — default false.
- `use_path(p: String)` — test hook, same pattern as Unlocks.
- Flags only, never code.

## 3. Entry — tier buttons resume the frontier

`src/ui/main_menu.gd`: each tier button, after `Settings.load_tier`, builds
the chain, finds `frontier(chain, tier)`, sets
`Level.next_layout_path = chain[frontier].path`, changes to level.tscn.
Empty chain → path stays "" (Level's DEFAULT_LAYOUT + invalid-level dialog
already handle the pathological cases).

## 4. LevelJumpDialog — the bare-bones picker

`src/ui/level_jump_dialog.gd` + `scenes/ui/level_jump_dialog.tscn`.
Deliberately plain (owner stylizes later): a themed PanelContainer popup,
title "LEVELS", ScrollContainer + VBox of one Button per chain entry.

- `signal level_picked(path: String)`
- `func open(tier: String) -> void` — rebuilds the list every open:
  button text `"✓  Title"` when cleared in this tier, plain `"Title"` when
  unlocked-uncleared, `"🔒  Title"` + `disabled = true` when locked.
  Current level highlighted (button `flat = false` vs others — minimal).
- Esc closes (popup default). Not modal-paused: opened FROM the pause menu
  the tree is already paused; opened via **L** it pauses nothing (quick
  glance + jump).
- Picking emits `level_picked` and hides.

## 5. Level integration

`src/level/level.gd`:

- Instance var `current_stem: String` — derived in `_ready` from the loaded
  path's basename (empty for editor-session layouts, which have no path).
- **L key** (new InputMap action `jump_levels`, KEY_L, added in
  GameInput.BINDINGS) and a new pause-menu entry "Jump to Level" both open
  the dialog with the current tier. Editor TEST sessions do NOT show the
  pause entry and ignore L (no chain inside a sandbox).
- `level_picked(path)` → `Level.next_layout_path = path` →
  `reload_current_scene()` (buffs do NOT carry on a jump — carry is a
  victory reward, jumping is navigation; pending buffs drop like a restart).
- CLEARED (`_settle`, non-editor): `Progress.mark_cleared(Settings.tier,
  current_stem)` when `current_stem != ""`.
- CLEARED + ENTER (non-editor): `next_index_after` → found: set
  `next_layout_path` to it, `carry_buffs = pending`, reload. Not found
  (end of chain): the banner already said so — ENTER goes to main menu.
- Banner at CLEARED: end-of-chain shows `"KINGDOM CONQUERED!"` /
  `"press ENTER for the throne room"` (→ main menu); otherwise the
  existing crumbled banner with `"press ENTER for the next level"`.
- FAILED unchanged (retry same). Editor sessions unchanged (banner→editor).

## 6. Out of scope

- Visual design of the dialog (owner mockups; KingdomDialog later).
- Victory fanfare animation (hook: the conquered banner).
- Per-tier trophy flair (gold checkmarks etc. — trophy shelf).
- Level sharing / namespaced progress keys (documented migration path).

## 7. Testing (GUT)

- LevelChain: ordering (campaign order + alpha user), Pineapple insertion
  (new level between cleared ones unlocked iff predecessor cleared),
  frontier (empty log → 0; partial; all cleared → last), next_index_after
  (middle, end), broken-file skip.
- Progress: round-trip temp file, per-tier isolation (chill ≠ hardcore),
  absent file = nothing cleared.
- Dialog: open(tier) builds correct button states (✓/plain/🔒 disabled),
  level_picked emits path, rebuild-on-open reflects a changed folder.
- Level: clearing writes the right tier+stem; editor session does not;
  ENTER advances to next path; end-of-chain goes to menu; jump drops buffs.
- Shipped-levels test guards chain inputs; its campaign-manifest test is
  replaced by a list_builtin() coverage test (every listed built-in loads).
