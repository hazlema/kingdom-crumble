# Trigger Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author crate-hit triggers in the editor — right-click a crate → Add Trigger… → a dialog lists named scenery targets (with canvas flash), an action catalog with per-action params, and existing-action removal. No more VS Code round-trips for tutorial levels (the owner's stated pain).

**Architecture:** One task. A new `TriggerDialog` component (scene + script) driven by a small action-descriptor catalog (each action declares its param controls — extensible for future parameterized effects); the crate context menu gains an entry; the editor gains a transient `flash_overlay()` highlight (documented cosmetic exception, NOT selection). Writes `current.triggers` through the existing format — validators/round-trip untouched.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **393 passing**): `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`. GUT counts engine errors as failures.
- **DEPLOY FREEZE: commit locally only. NO push/export/deploy.** (Owner may lift it today — irrelevant to this task; never push.)
- **Trigger format is FROZEN — the editor learns to WRITE it, the format does not change.** Key `"hit:X,Y"` with the crate's exact ints (`%d` formatting — never zero-padded); value = Array of action Strings; ≤ 16 actions per list (LevelJson cap); actions: `show:<name>`, `hide:<name>`, `confetti`, `sound:<stem>`. Overlay names validate via `Effects.valid_name` (`^[a-z0-9_-]{1,16}$`).
- **Selection doctrine:** selection is one fact; views render it; view writers live in `_sync_views` + documented exceptions. The canvas flash is a NEW documented exception: a transient modulate pulse on a scenery piece (tween, self-terminating, never touches `ed.selection`, never survives a rebuild). Comment it as such at the definition.
- Editor doctrine: dialogs register via `ed.register_popup()` / live under the menu's `any_dialog_open()` so click-veto and the bare-letter keybind guard work automatically. kingdom_theme styles inherit.
- Sound stems for the dropdown: scan `res://assets/sfx/*.ogg` at dialog-open; STRIP export-suffix disguises `.import`/`.remap` when listing (the MusicDirector lesson — exported builds list disguised names).
- Only NAMED overlays are targetable. Unnamed overlays appear as a single footer note ("N unnamed piece(s) — name them to target them"), not as rows.
- Duplicate action strings in one list are silently deduped at Add (a duplicate `sound:boom` would double-fire).
- Headless tests: UI tests follow the pause-menu/test-toybox idioms (instantiate scene, drive methods, assert child structure; unpause in after_each if anything pauses).

---

### Task 1: TriggerDialog component + crate-menu wiring + canvas flash

**Files:**
- Create: `src/editor/trigger_dialog.gd` (+ scene, or fully programmatic — match how PieceInspector/pause-menu sections are built; read them first)
- Modify: `src/editor/tools/grid_tool.gd` (crate context menu gains "Add Trigger…"), `src/editor/level_editor.gd` (flash_overlay + dialog registration/wiring), `parts.md` (editor-behavior bullet: right-click crate → Add Trigger)
- Test: `tests/unit/test_trigger_dialog.gd` (new)

**Interfaces:**
- Produces `TriggerDialog` with:
  - `const ACTIONS` — the descriptor catalog, data-driven so future parameterized effects are one entry: `[{id:"show", label:"Show", param:"overlay"}, {id:"hide", label:"Hide", param:"overlay"}, {id:"confetti", label:"Confetti", param:"none"}, {id:"sound", label:"Sound", param:"stem"}]`
  - `open(trigger_key: String, layout: LevelLayout)` — populates: existing actions for that key (each with a remove ✕), action OptionButton from ACTIONS, and a param area REBUILT per selected action: `overlay` param → ItemList of named overlays (text `name` + ` (hidden)` badge when hidden; row select → emits `flash_requested(overlay_idx)`); `stem` param → OptionButton of sfx stems; `none` → empty. Footer label with the unnamed-overlay count when > 0.
  - Add button → composes the action string, validates (overlay param: a row must be selected; stem param: a stem picked), dedupes, enforces the 16 cap with a visible warning label (not a crash), writes into `layout.triggers[trigger_key]` (creating key/array; REMOVE the key when the last action is removed — no empty arrays in saved files).
  - Signal `flash_requested(overlay_idx: int)`.
- Produces on `LevelEditor`: `flash_overlay(idx: int)` — 3-pulse modulate tween (~0.6s total) on the live piece via `_piece_for_overlay`, self-cleaning (kill prior flash tween on re-entry; restore modulate exactly), no-op for invalid idx or missing piece. Documented as the transient-cosmetic view exception (see Global Constraints).
- Consumes: the crate context menu in `grid_tool.gd` (the Info menu — read its structure; add "Add Trigger…" beside Info, same guard rules), the crate's json coords meta for the `hit:X,Y` key (the SAME `%d` formatting the Info dialog's Copy Key uses — share the key-building code, do not duplicate the formatting).

- [ ] **Step 1: Failing tests** (`tests/unit/test_trigger_dialog.gd`) — cover at minimum:

```gdscript
func test_catalog_covers_current_action_vocabulary() -> void:
	# ids exactly ["confetti", "hide", "show", "sound"] sorted — catalog drift breaks authoring silently
func test_open_lists_named_overlays_with_hidden_badge() -> void:
	# layout with overlays [{name:"sign1"}, {name:"door", hidden:true}, {no name}]
	# → 2 rows ("sign1", "door (hidden)"), footer mentions 1 unnamed
func test_add_show_action_writes_trigger() -> void:
	# pick show + sign1 row + Add → layout.triggers["hit:4,0"] == ["show:sign1"]
func test_add_sound_action_uses_stem_param() -> void:
	# pick sound + a stem + Add → appends "sound:<stem>"
func test_duplicate_action_deduped_and_cap_enforced() -> void:
	# adding same action twice → one copy; filling to 16 → 17th refused with warning label visible, array stays 16
func test_remove_action_deletes_and_empty_key_vanishes() -> void:
	# remove sole action → layout.triggers has NO "hit:4,0" key
func test_row_select_emits_flash_with_overlay_index() -> void:
	# selecting the "door (hidden)" row emits flash_requested with THAT overlay's index in layout.overlays (not the row index — unnamed overlays skew them)
func test_flash_overlay_restores_modulate_and_survives_bad_idx() -> void:
	# ed.flash_overlay on a real piece: modulate returns to original after the tween (use await); flash_overlay(99) and flash mid-flash → no error
```

- [ ] **Step 2: RED** — focused `-gtest=res://tests/unit/test_trigger_dialog.gd`.
- [ ] **Step 3: Implement** per Interfaces. Read `grid_tool.gd`'s Info menu, `piece_inspector.gd`, and the pause-menu Toybox section FIRST — match their construction idioms; reuse the Info menu's key formatting.
- [ ] **Step 4: Focused green, then FULL suite = 393 + new, zero failures.**
- [ ] **Step 5: parts.md** — one bullet in Editor behavior: right-click a crate → **Add Trigger…** (named scenery + actions, params per action; the dialog is why overlays want names).
- [ ] **Step 6: Commit** — `git commit -m "feat: trigger dialog — author crate-hit triggers in the editor"`
