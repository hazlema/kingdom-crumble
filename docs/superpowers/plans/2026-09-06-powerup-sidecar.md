# Powerup Sidecar Key Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crates declare their powerup in data: sidecars gain an optional `powerup` key from the curated set; `PowerupRules.route()` consults the Pieces registry instead of its hardcoded id match — so a pack crate can grant any baked power with zero code.

**Architecture:** `Pieces.parse_sidecar` validates/stores `powerup`; `PowerupRules.route` matches on the entry's power (not the id string); the six shipped sidecars gain their keys; the ghost's skunk-roll logic lives behind the `mystery` value. Mini-design approved in conversation 2026-09-06.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **332 passing**): `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **DEPLOY FREEZE: commit locally only. NO push/export/deploy.**
- Curated powerup set: `free_shot`, `exploding`, `multishot`, `super_bounce`, `mystery`. Unknown value → named `push_warning` + treated as absent (plain crate). Sidecars select-and-tune, never define.
- Behavior must be BIT-IDENTICAL for the six shipped crates: gold=free_shot, skull=exploding, blue=multishot, green=super_bounce, ghost=mystery (skunk 10% roll preserved exactly), wood=none. Existing powerup tests are the regression net — they must pass unmodified.
- GUT counts engine errors as failures; typed arrays append in tests.

---

### Task 1: `powerup` sidecar key + registry-driven routing

**Files:**
- Modify: `src/level/pieces.gd` (parse_sidecar + POWERUPS const), `src/level/powerup_rules.gd` (route), `pieces/crate-gold.json`, `pieces/skull.json`, `pieces/crate-blue.json`, `pieces/crate-green.json`, `pieces/crate-ghost.json` (crate-wood gets NO key)
- Test: `tests/unit/test_pieces.gd` (append)

**Interfaces:**
- Consumes: `Pieces.entry(id)` (lazy-scans), current `PowerupRules.route(type_id: String, skunk_unlocked: bool, roll: Callable) -> Dictionary` (signature unchanged — callers untouched).
- Produces: entry dicts carry `powerup: String` ("" = none).

- [ ] **Step 1: Write the failing tests** (append to `tests/unit/test_pieces.gd`)

```gdscript
func test_parse_sidecar_powerup_curated_set() -> void:
	assert_eq(Pieces.parse_sidecar("t", {"powerup": "multishot"})["powerup"], "multishot")
	assert_eq(Pieces.parse_sidecar("t", {})["powerup"], "", "absent = plain crate")
	assert_eq(
		Pieces.parse_sidecar("t", {"powerup": "laser_eyes"})["powerup"],
		"",
		"unknown power warns and downgrades to plain"
	)  # warns (GUT-safe)


func test_shipped_crates_route_identically_through_registry() -> void:
	var no_roll := func() -> float: return 0.99
	assert_eq(PowerupRules.route("crate-gold", true, no_roll)["kind"], "refund")
	assert_eq(PowerupRules.route("skull", true, no_roll)["buff"], &"exploding")
	assert_eq(PowerupRules.route("crate-blue", true, no_roll)["buff"], &"multishot")
	assert_eq(PowerupRules.route("crate-green", true, no_roll)["buff"], &"super_bounce")
	assert_eq(PowerupRules.route("crate-wood", true, no_roll)["kind"], "none")
	assert_eq(PowerupRules.route("no-such-crate", true, no_roll)["kind"], "none")
	# ghost mystery: skunk roll preserved (roll below chance, skunk locked)
	var low_roll := func() -> float: return 0.01
	assert_eq(PowerupRules.route("crate-ghost", false, low_roll)["kind"], "skunk")
	# ghost mystery: pool pick when skunk unlocked
	var r := PowerupRules.route("crate-ghost", true, no_roll)
	assert_true(r["kind"] in ["refund", "buff"], "mystery rolls the pool")
```

- [ ] **Step 2: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_pieces.gd -gexit`
Expected: FAIL — `powerup` key absent from parse_sidecar output.

- [ ] **Step 3: Implement — pieces.gd**

Const beside CLASSES:

```gdscript
const POWERUPS := ["free_shot", "exploding", "multishot", "super_bounce", "mystery"]
```

In `parse_sidecar`, before the return, add:

```gdscript
	var power := str(raw.get("powerup", ""))
	if power != "" and power not in POWERUPS:
		push_warning("Pieces: %s has unknown powerup '%s' — plain crate" % [id, power])
		power = ""
```

and add `"powerup": power` to the returned dictionary.

- [ ] **Step 4: Implement — powerup_rules.gd**

Replace `route`'s body (signature unchanged; SKUNK_CHANCE/POOL/BUFF_LABELS stay):

```gdscript
static func route(type_id: String, skunk_unlocked: bool, roll: Callable) -> Dictionary:
	var power := str(Pieces.entry(type_id).get("powerup", ""))
	match power:
		"free_shot":
			return {"kind": "refund", "label": "+Free Shot"}
		"exploding", "multishot", "super_bounce":
			var buff := StringName(power)
			return {"kind": "buff", "buff": buff, "label": BUFF_LABELS[buff]}
		"mystery":
			if not skunk_unlocked and roll.call() < SKUNK_CHANCE:
				return {"kind": "skunk"}
			var pick: StringName = POOL[clampi(int(roll.call() * POOL.size()), 0, POOL.size() - 1)]
			if pick == &"free_shot":
				return {"kind": "refund", "label": "+Free Shot"}
			return {"kind": "buff", "buff": pick, "label": BUFF_LABELS[pick]}
	return {"kind": "none"}
```

Update the class doc comment: routing now reads the registry; ids no longer hardcoded.

- [ ] **Step 5: Add the keys to the five shipped sidecars**

Each existing json gains one key (crate-wood untouched): crate-gold `"powerup": "free_shot"`; skull `"powerup": "exploding"`; crate-blue `"powerup": "multishot"`; crate-green `"powerup": "super_bounce"`; crate-ghost `"powerup": "mystery"`.

- [ ] **Step 6: Verify**

Focused green; then FULL suite — the existing powerup tests (test_powerups*/route coverage) are the regression net and must pass UNMODIFIED. Expected: **334 passing** (332 + 2).

- [ ] **Step 7: Commit**

```bash
git add src/level/pieces.gd src/level/powerup_rules.gd pieces/*.json tests/unit/test_pieces.gd
git commit -m "feat: crates declare powerups in data — route() reads the registry, hardcoded id match dies"
```
