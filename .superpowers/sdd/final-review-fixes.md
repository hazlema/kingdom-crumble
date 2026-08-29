# Final-Review Fixes — 2026-08-29

Applied to branch `first-playable`. All 6 issues from the final review resolved.

---

## Issue 1 — CRITICAL: Invalid group syntax in scenes/level_01.tscn

**What:** `groups = ["crates"]` was written as a body property under Crate1/2/3. Godot 4 requires groups as a node-header attribute.

**Where:** `scenes/level_01.tscn` lines 37–47.

**Fix:** Changed each `[node name="CrateN" parent="." instance=...]` header to include `groups=["crates"]` directly. The body property line was removed.

**Commit:** `4076809`

---

## Issue 2 — IMPORTANT: Settle ignores the stone (src/level/level.gd)

**What:** `_all_sleeping()` only checked crates; the in-flight stone was never tracked, so settle could fire while the stone was still airborne.

**Where:** `src/level/level.gd` — `_on_fired()`, `_all_sleeping()`.

**Fix:** Added `var _active_stone: Stone`. In `_on_fired`, assigned `_active_stone = stone`. Added `_stone_is_done()` helper that returns true if the stone is freed/invalid, has `y > 2000` (fell off), or is sleeping. `_all_sleeping()` now returns false early if `_stone_is_done()` is false.

**Commit:** `6a607c9`

---

## Issue 3 — IMPORTANT: Lean banner overwritten in same frame (src/level/level.gd)

**What:** `_settle()` called `_award_leans()` without awaiting it, then immediately set CLEARED/FAILED banners, overwriting the just-displayed LEAN BONUS banner. The state-check guard in `_award_leans` was also fragile.

**Where:** `src/level/level.gd` — `_settle()`, `_award_leans()`.

**Fix:** `_settle()` now `await _award_leans()` before computing standing count and showing terminal banners. Inside `_award_leans`, `hud.clear_banner()` is called unconditionally after each 1.2s timer (terminal banners are set after the function returns, so nothing is overwritten). The state-check guard was removed.

**Commit:** `6a607c9` (same commit as Issue 2)

---

## Issue 4 — IMPORTANT: No aim feedback (trebuchet.tscn + trebuchet.gd)

**What:** No visual indicator for current aim angle or charge level.

**Where:** `scenes/trebuchet.tscn`, `src/gameplay/trebuchet.gd`.

**Fix:** Added `AimIndicator` (`Line2D`, width 6, gold `Color(1, 0.83, 0.29, 0.9)`) as child of Trebuchet at position `(0, -90)` (the LaunchPoint), with points `[(0,0), (90,0)]`. In `trebuchet.gd`, added `_process()` that rotates the indicator to `-aim_angle_deg` and stretches point[1].x from 90 to 150 as charge goes 0→1. Typed `indicator` as `Line2D` to avoid GDScript parse errors in the test harness.

**Commits:** `f50a090`, `7e98300` (type annotation fix landed in docs commit due to an amend accident — functionally correct)

---

## Issue 5 — Integration test for level_01.tscn (tests/unit/test_level_scene.gd)

**What:** No integration test verifying the scene's crate groups and required nodes.

**Where:** New file `tests/unit/test_level_scene.gd`.

**Fix:** Created two GUT tests:
- `test_level_01_crates_in_group`: loads level_01.tscn via `add_child_autofree`, asserts `get_nodes_in_group("crates").size() == 3`.
- `test_level_01_required_nodes_present`: asserts non-null `$Trebuchet`, `$CameraDirector`, `$Hud`.
Both call `Settings.load_tier("chill")` first.

**Commit:** `eb76971`

---

## Issue 6 — Plan doc correction (docs/superpowers/plans/2026-08-29-first-playable.md)

**What:** Task 10 .tscn listing used the invalid body-property `groups =` syntax.

**Where:** `docs/superpowers/plans/2026-08-29-first-playable.md` ~line 981.

**Fix:** Updated the three crate node entries to use `groups=["crates"]` as a header attribute. Added correction note: "(corrected: groups is a node-header attribute in Godot 4)".

**Commit:** `7e98300`

---

## Verification Results

### Full test suite

```
Totals
------
Scripts              10
Tests                27
Passing Tests        27
Asserts              71
Time              0.439s

---- All tests passed! ----
```

Command: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`

### Smoke-load

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
```

Command: `$GODOT --headless scenes/level_01.tscn --quit-after 120`
Result: No script errors, clean exit.
