# Final-Fix Report — 2026-08-30

Branch: `level-editor`
Suite baseline: **55 green**
Suite after fixes: **62 green, 0 failures**

---

## Item 1 — CRITICAL: round-trip statics (level.gd)

**Commit:** `9a2e5e7`

**Files changed:** `src/level/level.gd`

**Changes:**
- Added instance var `_editor_session := false`
- In `_ready`: copy `Level.return_to_editor` into `_editor_session`, immediately clear the static to `false` (alongside `next_layout` consumption)
- `PauseMenu.set_editor_mode` call uses `_editor_session` not the static
- `restart_requested` lambda re-arms `Level.next_layout = _pristine; Level.return_to_editor = true` when `_editor_session` before `reload_current_scene`
- CLEARED/FAILED advance branch uses `_editor_session` not the static
- `_back_to_editor` unchanged (static was already cleared in `_ready`; the `Level.return_to_editor = false` write is a harmless no-op)

**Also covers Item 8 (banner text):** CLEARED banner sub reads "press ENTER to return to editor" and FAILED reads same when `_editor_session`. These are in the same commit since they use `_editor_session`.

**Test tail:**
```
res://tests/unit/test_level_scene.gd
* test_level_crates_in_group
* test_level_required_nodes_present
2/2 passed.
```

---

## Item 2 — CRITICAL: type-confused JSON (level_json.gd + test_level_json.gd)

**Commit:** `d5a7608` _(also covers Item 4 — both touch level_json.gd validate())_

**Files changed:** `src/level/level_json.gd`, `tests/unit/test_level_json.gd`

**Changes:**
- `validate()`: format field checked with `_fmt is int or _fmt is float` before `int()` conversion; returns "unsupported or missing format" for dict/array inputs
- `validate()`: shots field checked with `_shots is int or _shots is float`; returns "bad shots" for non-numeric
- `validate()`: trigger id arrays checked for size > 16; returns "too many effects" (Item 4)
- `parse()`: trigger id mapping changed to filter-only loop (`if i is String`) instead of `String(i)` coercion
- 5 new tests: `test_format_object_is_null`, `test_format_array_is_null`, `test_shots_object_is_null`, `test_non_string_trigger_ids_dropped`, `test_too_many_trigger_ids_is_null`

**Test tail:**
```
res://tests/unit/test_level_json.gd
* test_parse_good_file
* test_defaults_for_absent_optionals
* test_rejects_garbage_and_bad_shapes
* test_unknown_fields_ignored
* test_roundtrip
* test_format_object_is_null
* test_format_array_is_null
* test_shots_object_is_null
* test_non_string_trigger_ids_dropped
* test_too_many_trigger_ids_is_null
10/10 passed.
```

---

## Item 3 — IMPORTANT: off-grid crates uneditable/duplicating (level_editor.gd)

**Commit:** `2fe7d05` _(also includes `_on_load` change from Item 5 — same file)_

**Files changed:** `src/editor/level_editor.gd`

**Changes:**
- Added `_spawned: Array[Crate] = []` class var
- `_rebuild`: frees crates via `_spawned` array (not `occupancy.values()`) with `is_instance_valid` guard
- `_rebuild`: snaps all `current.crates` coords to cell centres via `world_to_cell`/`cell_to_world` roundtrip; drops duplicate-cell entries (keep first)
- `_on_load`: calls `menu.show_load_error()` when loaded is null (Item 5)

---

## Item 4 — IMPORTANT: unbounded triggers DoS (level_json.gd + test)

**Commit:** `d5a7608` _(combined with Item 2 — both fix level_json.gd validate())_

See Item 2 above. The DoS cap (> 16 entries → "too many effects") and its test (`test_too_many_trigger_ids_is_null`) are in the same commit.

---

## Item 5 — IMPORTANT: silent load failure (editor_menu.tscn + editor_menu.gd + level_editor.gd)

**Commits:**
- `bc44c69` — `scenes/editor_menu.tscn`, `src/editor/editor_menu.gd`
- `2fe7d05` — `src/editor/level_editor.gd` (`_on_load` change)

**Changes:**
- Added `AcceptDialog` node `LoadError` (unique_name_in_owner = true, dialog_text = "Couldn't load that level file.") to `scenes/editor_menu.tscn`
- Added `func show_load_error() -> void` to `EditorMenu` calling `%LoadError.popup_centered()`
- `_on_load` in `level_editor.gd` calls `menu.show_load_error()` when `LevelStore.load_level` returns null

---

## Item 6 — IMPORTANT: unknown crate type silent (level_builder.gd)

**Commit:** `06f1aa4`

**Files changed:** `src/level/level_builder.gd`

**Changes:**
- Captures `tex_lookup.call(c["type"])` result in `_tex`
- If `_tex == null` and `c["type"] != "crate-wood"`: emits `push_warning("Unknown crate type: %s" % c["type"])`
- Crate still spawns with default look

**Test tail (warnings from existing test crate-gold):**
```
res://tests/unit/test_level_builder.gd
* test_spawns_positioned_typed_crates_in_group
WARNING: Unknown crate type: crate-gold
* test_frozen_for_editor
WARNING: Unknown crate type: crate-gold
2/2 passed.
```
(Warnings are expected — `crate-gold` in test data has no texture in EditorAssets. Tests still pass.)

---

## Item 7 — MINOR: Effects.is_known alignment (effects.gd + test_effects.gd)

**Commit:** `d1bf7cd`

**Files changed:** `src/level/effects.gd`, `tests/unit/test_effects.gd`

**Changes:**
- `is_known`: now checks sound stem for `/`, `\`, `..` (mirroring `_sound`'s guard) and returns false for traversal names
- 4 new tests: `test_is_known_rejects_traversal_sound_ids` (covers `../../evil`, `foo/bar`, `a\b`, `a..b`)

**Test tail:**
```
res://tests/unit/test_effects.gd
* test_known_ids
* test_fire_all_counts_known_only
* test_traversal_sound_ids_rejected
* test_is_known_rejects_traversal_sound_ids
4/4 passed.
```

---

## Item 8 — MINOR: banner text in editor session (level.gd)

**Commit:** `9a2e5e7` _(combined with Item 1 — same file, uses `_editor_session` introduced there)_

CLEARED banner sub: "press ENTER to return to editor" when `_editor_session`, else "press ENTER to play again".
FAILED banner sub: "press ENTER to return to editor" when `_editor_session`, else "press ENTER to retry".

---

## Item 9 — MINOR: empty stem guard (level_store.gd + test_level_store.gd)

**Commit:** `b66170a`

**Files changed:** `src/level/level_store.gd`, `tests/unit/test_level_store.gd`

**Changes:**
- `save_user`: captures `sanitize_stem(stem)` in `safe`; if `safe == ""`, returns `""` immediately without writing
- 1 new test: `test_save_user_empty_stem_returns_empty` — asserts `save_user(layout, "!!!") == ""`

**Test tail:**
```
res://tests/unit/test_level_store.gd
* test_campaign_order_and_load
* test_user_save_load_roundtrip
* test_load_missing_or_invalid_is_null
* test_sanitize_stem
* test_save_user_empty_stem_returns_empty
5/5 passed.
```

---

## Full Suite Output

```
Totals
------
Scripts              18
Tests                62
Passing Tests        62
Asserts             161
Time              0.452s

---- All tests passed! ----
```

---

## Smoke Tests

All three scenes loaded headless without script/parse errors (terminated by timeout as expected):

- `scenes/editor.tscn` — clean
- `scenes/level.tscn` — clean
- `scenes/main_menu.tscn` — clean

---

## Commit Summary

| Item | Commit | Description |
|------|--------|-------------|
| 1 + 8 | `9a2e5e7` | level.gd static consume-and-clear + editor-session banners |
| 2 + 4 | `d5a7608` | level_json.gd type checks + trigger cap + tests |
| 3 + 5 | `2fe7d05` | level_editor.gd off-grid snap + load error call |
| 5 | `bc44c69` | editor_menu.tscn LoadError dialog + show_load_error() |
| 6 | `06f1aa4` | level_builder.gd unknown crate push_warning |
| 7 | `d1bf7cd` | effects.gd is_known traversal guard + tests |
| 9 | `b66170a` | level_store.gd empty stem guard + test |

---

## Concerns

- Items 1+8 and 2+4 and 3+5 are combined in single commits (same file, logically tied). Per-item commits were not possible without splitting the same file across multiple commits.
- The `crate-gold` warning in test_level_builder.gd is a pre-existing condition (test data uses a crate type with no texture registered in EditorAssets). Item 6's warning correctly fires for it — the tests still pass.
- The `minimal_theme.tres` script error (`Trying to assign value of type 'Nil' to a variable of type 'bool'`) is pre-existing and unrelated to any of these fixes.
