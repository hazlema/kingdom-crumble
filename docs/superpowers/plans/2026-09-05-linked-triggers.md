# Linked Triggers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crate-linked triggers — when a crate registers as hit, fire authored actions: show/hide named scenery overlays plus the existing effects library.

**Architecture:** Pure extension of the inert-data trigger system. Level JSON gains optional overlay `name`/`hidden` keys and `hit:X,Y` trigger events; builders attach lookup metadata at spawn; the level's existing knocked-once handler fires the actions. No editor changes — only round-trip preservation, which already holds.

**Tech Stack:** Godot 4.6.3 GDScript, GUT headless tests.

Spec: `docs/superpowers/specs/2026-09-05-linked-triggers-design.md`

## Global Constraints

- Godot binary for ALL commands: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **287 passing**, must stay green and grow):
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- **DEPLOY FREEZE: commit locally only. NO `git push`, NO web export, NO deploy.**
- Inert-data doctrine: wrong TYPE → named validation error; unknown NAME at runtime → `push_warning` + skip, never crash.
- Overlay name charset: `^[a-z0-9_-]{1,16}$`. Trigger event keys: `on_all_cleared` or `^hit:-?\d+,-?\d+$`. Action cap per event stays 16.
- One-shot firing comes from the existing knocked ledger — add NO new bookkeeping.
- GDScript traps: LevelLayout arrays are typed — `append` in tests, never assign a plain Array; GUT counts engine errors as failures; `parse()` strips underscore keys only (never `name`/`hidden`).

---

### Task 1: Format layer — validation and known actions

**Files:**
- Modify: `src/level/effects.gd` (is_known + name validator)
- Modify: `src/level/level_json.gd` (overlay name/hidden, trigger keys/actions)
- Modify: `src/level/level_layout.gd:22` (doc comment)
- Test: `tests/unit/test_linked_triggers.gd` (create)

**Interfaces:**
- Consumes: existing `Effects.is_known(id)`, `LevelJson.validate(d)`.
- Produces: `Effects.valid_name(n: String) -> bool`; `is_known` accepts `show:<name>`/`hide:<name>`; `validate` accepts/rejects the new keys with the exact error strings below. Tasks 2–3 rely on key names `name`, `hidden`, and event format `hit:%d,%d`.

- [ ] **Step 1: Write the failing tests** — create `tests/unit/test_linked_triggers.gd`:

```gdscript
extends GutTest

# Linked triggers (spec 2026-09-05): crate-hit events show/hide named
# scenery and fire effects. Format layer first.


func _base(extra: Dictionary = {}) -> Dictionary:
	var d := {"format": 1, "title": "t", "crates": [], "shots": 3}
	d.merge(extra, true)
	return d


func test_known_actions_learn_show_and_hide() -> void:
	assert_true(Effects.is_known("show:reward"))
	assert_true(Effects.is_known("hide:warning_1"))
	assert_false(Effects.is_known("show:"), "empty name refused")
	assert_false(Effects.is_known("show:Bad Name"), "charset enforced")
	assert_false(Effects.is_known("shwo:reward"), "typos stay unknown")


func test_overlay_name_and_hidden_validate() -> void:
	var ov := {"image": "abcd1234", "x": 0, "y": 0}
	var good := ov.duplicate()
	good["name"] = "sign-1"
	good["hidden"] = true
	assert_eq(LevelJson.validate(_base({"overlays": [good]})), "")
	var bad := ov.duplicate()
	bad["name"] = "Bad Name!"
	assert_eq(LevelJson.validate(_base({"overlays": [bad]})), "overlay 0: bad name")
	var dupe_a := ov.duplicate()
	dupe_a["name"] = "twin"
	var dupe_b := ov.duplicate()
	dupe_b["name"] = "twin"
	assert_eq(
		LevelJson.validate(_base({"overlays": [dupe_a, dupe_b]})),
		"overlay 1: duplicate name 'twin'"
	)
	var badh := ov.duplicate()
	badh["hidden"] = "yes"
	assert_eq(
		LevelJson.validate(_base({"overlays": [badh]})), "overlay 0: hidden must be true/false"
	)


func test_trigger_events_and_actions_validate() -> void:
	assert_eq(
		LevelJson.validate(_base({"triggers": {"hit:5,1": ["show:reward", "confetti"]}})), ""
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"hit:-3,7": ["hide:warning"]}})),
		"",
		"negative coords are legal"
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"on_crate": ["confetti"]}})),
		"trigger 'on_crate': unknown event"
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"hit:5,1": "confetti"}})),
		"trigger 'hit:5,1': actions must be a list"
	)
	assert_eq(
		LevelJson.validate(_base({"triggers": {"hit:5,1": ["shwo:reward"]}})),
		"trigger 'hit:5,1': bad action 'shwo:reward'"
	)
```

- [ ] **Step 2: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_linked_triggers.gd -gexit`
Expected: FAIL — `is_known("show:reward")` returns false; validate returns "" where errors are expected.

- [ ] **Step 3: Implement `src/level/effects.gd`** — replace `is_known` and add the validator (keep the existing body for confetti/sound):

```gdscript
# Overlay-name charset shared with LevelJson (single direction:
# level_json calls Effects, never the reverse — no circular statics).
static var _name_rx := RegEx.create_from_string("^[a-z0-9_-]{1,16}$")


static func valid_name(n: String) -> bool:
	return _name_rx.search(n) != null


static func is_known(id: String) -> bool:
	if id == "confetti":
		return true
	if id.begins_with("sound:"):
		var stem := id.trim_prefix("sound:")
		if stem.contains("/") or stem.contains("\\") or stem.contains(".."):
			return false
		return true
	# Linked-trigger actions (spec 2026-09-05): scenery show/hide by
	# overlay name. Whether the name EXISTS is runtime's warn-skip;
	# here we only vouch for the shape.
	if id.begins_with("show:") or id.begins_with("hide:"):
		return valid_name(id.split(":", true, 1)[1])
	return false
```

Note: `fire_all` needs no change — `show:`/`hide:` never reach it (the level routes them first, Task 3). If one ever does, the existing unknown-id warning is the correct degrade.

- [ ] **Step 4: Implement `src/level/level_json.gd`**

Add near the other compiled regexes (top of class):

```gdscript
# Linked-trigger event keys: on_all_cleared or hit:X,Y (ints, negatives ok).
static var _hit_rx := RegEx.create_from_string("^hit:-?\\d+,-?\\d+$")
```

Replace the trigger validation block:

```gdscript
	var _trig: Variant = d.get("triggers", {})
	if _trig is Dictionary:
		for _event in _trig:
			var _ekey := str(_event)
			if _ekey != "on_all_cleared" and _hit_rx.search(_ekey) == null:
				return "trigger '%s': unknown event" % _ekey
			var _ids: Variant = _trig[_event]
			if not _ids is Array:
				return "trigger '%s': actions must be a list" % _ekey
			if (_ids as Array).size() > 16:
				return "trigger '%s': too many effects (max 16)" % _ekey
			for _id in (_ids as Array):
				if not _id is String or not Effects.is_known(_id):
					return "trigger '%s': bad action '%s'" % [_ekey, str(_id)]
```

In the overlay loop, before the behavior/pivot checks, add (and declare `var _seen_names: Dictionary = {}` just before the loop):

```gdscript
		var _nm: Variant = (_entry as Dictionary).get("name", "")
		if not _nm is String:
			return "overlay %d: bad name" % oi
		if (_nm as String) != "":
			if not Effects.valid_name(_nm):
				return "overlay %d: bad name" % oi
			if _seen_names.has(_nm):
				return "overlay %d: duplicate name '%s'" % [oi, _nm]
			_seen_names[_nm] = true
		var _hd: Variant = (_entry as Dictionary).get("hidden", false)
		if not _hd is bool:
			return "overlay %d: hidden must be true/false" % oi
```

Update `src/level/level_layout.gd:22` comment to:

```gdscript
# Scenery placements: {image, x, y, name?, hidden?, behavior?, pivot?, speed?, amplitude?, axis?, travel?, tilt?}
```

- [ ] **Step 5: Run focused, then full suite**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_linked_triggers.gd -gexit` → PASS.
Run the full suite → expect **290 passing** (287 + 3), 0 failing. (Shipped levels revalidate under the stricter per-action check — they use only `confetti`/`sound:` ids and must stay green.)

- [ ] **Step 6: Commit (LOCAL ONLY — no push)**

```bash
git add src/level/effects.gd src/level/level_json.gd src/level/level_layout.gd tests/unit/test_linked_triggers.gd
git commit -m "feat: linked-trigger format — overlay name/hidden, hit:X,Y events, show/hide actions"
```

---

### Task 2: Spawn metadata — hidden pieces, named pieces, crate coords

**Files:**
- Modify: `src/level/scenery_builder.gd` (in the spawn loop, after `piece.position` is set)
- Modify: `src/level/level_builder.gd` (in `spawn_crates`, after `crate.position` is set)
- Test: `tests/unit/test_linked_triggers.gd` (append)

**Interfaces:**
- Consumes: overlay keys `name`/`hidden` (Task 1 validated them).
- Produces: scenery pieces carry `set_meta("overlay_name", String)` and spawn `visible = false` when hidden; crates carry `set_meta("json_coords", Vector2i(int(x), int(y)))`. Task 3 reads both metas.

- [ ] **Step 1: Write the failing tests** — append to `tests/unit/test_linked_triggers.gd`:

```gdscript
func _tiny_b64() -> String:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func _layout_with_named_scenery() -> LevelLayout:
	var l := LevelLayout.new()
	l.title = "linked"
	var b64 := _tiny_b64()
	var key := LevelJson.image_key(Marshalls.base64_to_raw(b64))
	l.images[key] = b64
	l.overlays.append({"image": key, "x": 10, "y": 20, "name": "warning"})
	l.overlays.append({"image": key, "x": 30, "y": 40, "name": "reward", "hidden": true})
	return l


func test_builder_spawns_hidden_and_named_pieces() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var pieces := SceneryBuilder.spawn(host, _layout_with_named_scenery())
	assert_eq(pieces.size(), 2)
	assert_true(pieces[0].visible, "unhidden piece shows")
	assert_eq(pieces[0].get_meta("overlay_name"), "warning")
	assert_false(pieces[1].visible, "hidden piece waits for its show")
	assert_eq(pieces[1].get_meta("overlay_name"), "reward")


func test_crates_carry_their_json_coords() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var l := LevelLayout.new()
	l.title = "coords"
	l.crates.append({"x": 320.0, "y": 512, "type": "crate-wood"})
	var crates := LevelBuilder.spawn_crates(host, l, true, func(_id: String) -> Texture2D: return null)
	assert_eq(crates.size(), 1)
	assert_eq(crates[0].get_meta("json_coords"), Vector2i(320, 512), "float x still keys as int")
```

- [ ] **Step 2: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_linked_triggers.gd -gexit`
Expected: the two new tests FAIL on missing meta / visible-not-false.

- [ ] **Step 3: Implement `src/level/scenery_builder.gd`** — in the spawn loop, directly after `piece.position = Vector2(...)`:

```gdscript
		# Linked triggers: hidden pieces wait for a show: action; named
		# pieces are addressable by triggers.
		if (entry as Dictionary).get("hidden", false):
			piece.visible = false
		var _nm: String = str((entry as Dictionary).get("name", ""))
		if _nm != "":
			piece.set_meta("overlay_name", _nm)
```

- [ ] **Step 4: Implement `src/level/level_builder.gd`** — in `spawn_crates`, directly after `crate.position = Vector2(c["x"], c["y"])`:

```gdscript
		# Linked triggers key crates by their authored coordinates.
		crate.set_meta("json_coords", Vector2i(int(c["x"]), int(c["y"])))
```

- [ ] **Step 5: Run focused, then full suite**

Focused file → PASS. Full suite → expect **292 passing**, 0 failing.

- [ ] **Step 6: Commit (LOCAL ONLY — no push)**

```bash
git add src/level/scenery_builder.gd src/level/level_builder.gd tests/unit/test_linked_triggers.gd
git commit -m "feat: linked-trigger spawn metadata — hidden/named pieces, crate json_coords"
```

---

### Task 3: Runtime firing + round-trip proof

**Files:**
- Modify: `src/level/level.gd` (`_on_crate_knocked` + two new helpers)
- Test: `tests/unit/test_linked_triggers.gd` (append)

**Interfaces:**
- Consumes: `overlay_name` / `json_coords` metas (Task 2), `Effects.fire_all(ids, host, at)` (existing), `layout.triggers` Dictionary.
- Produces: gameplay behavior only — no new public API.

- [ ] **Step 1: Write the failing tests** — append to `tests/unit/test_linked_triggers.gd`:

```gdscript
func test_knocked_crate_fires_its_linked_trigger() -> void:
	var l := _layout_with_named_scenery()
	l.crates.append({"x": 5, "y": 1, "type": "crate-wood"})
	l.crates.append({"x": 7, "y": 1, "type": "crate-wood"})
	l.triggers = {"hit:5,1": ["hide:warning", "show:reward", "confetti"]}
	l.shots = 3
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	var warning: Node = null
	var reward: Node = null
	for p in lvl.get_tree().get_nodes_in_group("scenery"):
		if p.get_meta("overlay_name", "") == "warning":
			warning = p
		elif p.get_meta("overlay_name", "") == "reward":
			reward = p
	assert_not_null(warning)
	assert_true(warning.visible, "warning starts shown")
	assert_false(reward.visible, "reward starts hidden")
	var linked: Crate = null
	var unlinked: Crate = null
	for c in lvl.get_tree().get_nodes_in_group("crates"):
		if c.get_meta("json_coords") == Vector2i(5, 1):
			linked = c
		else:
			unlinked = c
	# Unlinked crate first: nothing changes.
	lvl._on_crate_knocked(unlinked)
	assert_true(warning.visible, "unlinked knock leaves scenery alone")
	# Linked crate: the whole list fires.
	var before := lvl.get_child_count()
	lvl._on_crate_knocked(linked)
	assert_false(warning.visible, "hide:warning landed")
	assert_true(reward.visible, "show:reward landed")
	assert_gt(lvl.get_child_count(), before, "confetti particles spawned on the level")


func test_unknown_scenery_name_warns_but_never_crashes() -> void:
	var l := _layout_with_named_scenery()
	l.crates.append({"x": 5, "y": 1, "type": "crate-wood"})
	l.triggers = {"hit:5,1": ["show:no_such_sign"]}
	l.shots = 3
	Level.next_layout = l
	var lvl: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_frames(2)
	var crate: Crate = lvl.get_tree().get_nodes_in_group("crates")[0]
	lvl._set_scenery_visible("no_such_sign", true)  # direct: warning path
	lvl._fire_crate_triggers(crate)  # full path: still no crash
	pass_test("warn-and-skip held")


func test_round_trip_preserves_linked_trigger_keys() -> void:
	var l := _layout_with_named_scenery()
	l.crates.append({"x": 5, "y": 1, "type": "crate-wood"})
	l.triggers = {"hit:5,1": ["hide:warning", "show:reward"]}
	l.shots = 1
	var back := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(back, "serialized linked level reloads: %s" % LevelJson.last_error)
	assert_eq(back.overlays[0].get("name", ""), "warning")
	assert_eq(back.overlays[1].get("hidden", false), true)
	assert_true(back.triggers.has("hit:5,1"), "trigger entry survives")
```

Note on the warn test: GUT fails tests on unexpected ENGINE errors, not
`push_warning` — warnings are the designed degrade and safe to emit.

- [ ] **Step 2: Run to verify failure**

Run: `/home/frosty/Dev/godot/bin/godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_linked_triggers.gd -gexit`
Expected: FAIL — `_fire_crate_triggers` / `_set_scenery_visible` don't exist; visibility never changes.

- [ ] **Step 3: Implement `src/level/level.gd`**

At the top of `_on_crate_knocked` (first line of the body):

```gdscript
	_fire_crate_triggers(crate)
```

New helpers, placed directly after `_on_crate_knocked`:

```gdscript
# Linked triggers (spec 2026-09-05): a crate registering as hit fires
# its authored actions — scenery show/hide by name, everything else
# through the effects library. One-shot for free: the knocked ledger
# already guarantees this handler runs once per crate, ever.
func _fire_crate_triggers(crate: Crate) -> void:
	if not crate.has_meta("json_coords"):
		return
	var jc: Vector2i = crate.get_meta("json_coords")
	var key := "hit:%d,%d" % [jc.x, jc.y]
	if not layout.triggers.has(key):
		return
	var effect_ids: Array = []
	for id in layout.triggers[key]:
		var s := str(id)
		if s.begins_with("show:") or s.begins_with("hide:"):
			_set_scenery_visible(s.split(":", true, 1)[1], s.begins_with("show:"))
		else:
			effect_ids.append(s)
	if not effect_ids.is_empty():
		Effects.fire_all(effect_ids, self, crate.global_position)


func _set_scenery_visible(overlay_name: String, on: bool) -> void:
	for piece in get_tree().get_nodes_in_group("scenery"):
		if piece.get_meta("overlay_name", "") == overlay_name:
			piece.visible = on
			return
	push_warning("Trigger references unknown scenery '%s'" % overlay_name)
```

- [ ] **Step 4: Run focused, then full suite**

Focused file → PASS (5 total in file... 8 counting Tasks 1–2). Full suite → expect **295 passing**, 0 failing.

- [ ] **Step 5: Commit (LOCAL ONLY — no push)**

```bash
git add src/level/level.gd tests/unit/test_linked_triggers.gd
git commit -m "feat: linked triggers fire — knocked crates show/hide scenery and launch effects"
```
