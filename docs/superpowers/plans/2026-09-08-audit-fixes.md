# Audit 2026-09-08 Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear all 8 findings of docs/audit-2026-09-08.md (1×P1 + 7×P2) with the audit's own regression checks as new pins.

**Architecture:** Four tasks by subsystem: (1) the scenery-bake pair — post-rotation budget enforcement + pivot-true placement; (2) the document-preservation pair — loading never mutates (missing-pack props retained, snapped triggers migrated); (3) editor/registry admission — file-dialog registration + pack-id validation; (4) lifetime & budgets — powerup snapshot-at-spawn + pre-read size caps.

**Tech Stack:** Godot 4.6.3, GDScript, GUT headless.

## Global Constraints

- Godot binary: `/home/frosty/Dev/godot/bin/godot`
- Full suite (baseline **423 passing**) after every task: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`. GUT counts engine errors as failures.
- Commit locally per task; NO push (owner pushes/deploys).
- The audit is the spec: **docs/audit-2026-09-08.md** — each finding's "Fix" and "Regression check" paragraphs are binding. Read your finding's section in full.
- Decoded-image budgets (existing, from LevelJson): ≤ 1024 per side, ≤ 1_048_576 pixels. Never `load()` on user://; never let hostile bytes reach a decoder ungated.
- Test hygiene: headless shares the REAL user:// — sandbox via `Pieces.toybox_root` (pattern in tests/unit/test_toybox.gd) and capture-restore any cfg touched; new PNG fixtures via Image.create/save_png; typed arrays on LevelLayout: append, don't assign.
- Editor doctrine: selection is one fact (`ed.selection`, views via `_sync_views`); dialogs register with `ed.register_popup()`; bad data warns-and-skips, never crashes; the editor must never silently mutate a loaded document (this audit's theme).
- Trigger keys: `hit:%d,%d` — `LevelEditor.crate_trigger_key` is the ONLY format site.

---

### Task 1: Scenery bake — budget-gated rotation + pivot-true placement (findings 1 P1 + 2)

**Files:**
- Modify: `src/editor/scenery_bake.gd` (both fixes), `src/editor/level_editor.gd` only if the skip-surfacing message needs wording
- Test: `tests/unit/test_scenery_bake.gd` (append; read its existing fixtures/idioms first)

**Interfaces:**
- Finding 1: the bake step gains a decoded-budget check on the ROTATED result (width > 1024 or height > 1024 or w*h > 1_048_576) BEFORE the old blob/edit keys are consumed → the piece joins the EXISTING cap-skip path (same skipped counter the editor already surfaces as "N scenery change(s) hit the image limit"; original blob + underscore edit keys retained so nothing is lost and the user can undo/adjust). Do NOT silently downscale.
- Finding 2: baking a rotation must keep the piece where the live preview showed it. The live preview rotates around the selected 9-pivot (NarfDecor pivot table — read `addons/narfkit/narf_decor.gd` pivot offsets); the bake rotates pixels about the image center. Compensate the stored overlay x/y: `new_center = pivot_world + Rot(theta) * (old_center - pivot_world)`; write the compensated coords with the baked image. The pivot NAME stays (it re-anchors to the same named position of the new bounds).
- Audit reproduction numbers are the acceptance tests: (a) 800×800 flat-color art rotated 45° → bake SKIPS (blob unchanged, edit keys intact, skip counter +1), level still parses and the piece still renders from the old blob; (b) 64×64 at (1000,400), LOWER_CENTER pivot, 90° → post-bake world center equals the live preview's center (audit: (1032,400)), NOT (1000,368).

- [ ] **Step 1:** Failing tests reproducing both audit cases (use SceneryBake statics directly + a layout fixture; flat-color Image.create art compresses exactly as the audit describes).
- [ ] **Step 2:** RED focused; implement; GREEN focused.
- [ ] **Step 3:** FULL suite ≥ 423. Commit: `fix: bake respects decode budgets and pivots — audit 2026-09-08 findings 1+2`

---

### Task 2: Loading never mutates the document (findings 3 + 4)

**Files:**
- Modify: `src/editor/level_editor.gd` (`_rebuild` prop filtering ~582-607, load snap ~568-578), possibly `src/editor/tools/grid_tool.gd` (placeholder interactions)
- Test: `tests/unit/test_level_editor_interactions.gd` (append)

**Interfaces:**
- Finding 3: `_rebuild()` STOPS writing the filtered prop array back into `current.props`. Unavailable-pack props stay in the document verbatim and round-trip through save. In the canvas they spawn as a PLACEHOLDER: a dim 1×1 gray box (Sprite2D or ColorRect-textured piece) at the prop's cell, occupying that cell in `ed.occupancy` (so nothing is placed on top), selectable and DELETE-able (explicit author removal = the only way they leave the document), draggable not required. Placeholder carries the prop dict reference so delete removes the right entry.
- Finding 4: the load-time crate snap gains trigger-key migration: build old→new coordinate mapping while snapping, then rewrite `current.triggers` keys via `crate_trigger_key`. Collisions (two source keys snapping to one cell): MERGE the action lists in source order, dedup, cap 16 (drop overflow with a push_warning naming the key).
- Audit numbers as tests: (a) doc with props `[{"id":"missing:wall", ...}]`, pack absent → after `_rebuild`, `current.props.size() == 1` STILL, placeholder occupies the cell, save round-trips the prop, DELETE removes it; (b) crate at (833,443) with `hit:833,443: [confetti]` → after load, triggers has `hit:832,443` (snapped) and not the old key; merged-collision case pinned.

- [ ] **Step 1:** Failing tests (both audit reproductions + save round-trip + delete path). **Step 2:** RED → implement → GREEN. **Step 3:** FULL suite. Commit: `fix: loading preserves the document — missing-pack placeholders + trigger snap migration (audit 3+4)`

---

### Task 3: Admission control — file dialog registry + pack id validation (findings 5 + 6)

**Files:**
- Modify: `src/editor/scenery_panel.gd` (register `_file_dialog`), `src/editor/level_editor.gd` (if a registration hook is needed), `src/level/pieces.gd` (basename validation in `_scan_object_pack`)
- Test: `tests/unit/test_level_editor_interactions.gd` + `tests/unit/test_toybox.gd` (append)

**Interfaces:**
- Finding 5: the scenery panel's FileDialog joins the central blocking registry (`ed.register_popup(...)` — it is a Window). Opening it must also end any pending canvas gesture (call the tools' `reset_input_state()` / clear scenery drag state — read how mode switches do it). Test: dialog visible → `ed.over_ui_at(any world point)` is true.
- Finding 6: object-pack piece BASENAMES validate against the savable charset before admission: lowercase `a-z0-9_-`, and total namespaced id (`folder:basename`) ≤ 64 chars (the LevelJson prop-id contract). Violations push_warning naming the file and are skipped — never offered in the palette. NO silent normalization. Share the constraint: expose the basename rule beside the existing `_folder_rx` in pieces.gd with a comment tying it to `LevelJson._prop_id_rx`.
- Tests: (a) audit's `auditpack/Wall.png` case → not registered, warning; lowercase sibling registers; (b) an overlong basename skipped; (c) dialog-registration probe per audit reproduction (visible dialog → over_ui_at true at a far-away point).

- [ ] Steps: failing tests → RED → implement → GREEN → FULL suite. Commit: `fix: file dialog blocks input, packs admit only savable ids (audit 5+6)`

---

### Task 4: Lifetime & budgets — powerup snapshot + pre-read caps (findings 7 + 8)

**Files:**
- Modify: `src/level/level_builder.gd` (snapshot), `src/level/powerup_rules.gd` (read snapshot), `src/level/level_store.gd`, `src/level/pieces.gd`, `src/editor/level_editor.gd` (web upload JS size check ~475-486)
- Test: `tests/unit/test_powerups.gd` or the file containing PowerupRules routing tests (read to find it) + `tests/unit/test_toybox.gd` + `tests/unit/test_audit_fixes.gd` (append where each fits; follow each file's idioms)

**Interfaces:**
- Finding 7: crates SNAPSHOT their gameplay metadata at spawn: `crate.set_meta("powerup", entry.get("powerup",""))` beside the existing spawn-time registry resolution; `PowerupRules.route` consults the crate's meta when present, falling back to the registry ONLY for crates without the meta (compat with any non-builder spawn path). Mid-level `set_pack_enabled` then cannot change a live crate's reward. Test = the audit reproduction: spawn pack crate with free_shot → disable pack → routing that CRATE still returns the refund; a NEWLY spawned crate after rescan honors the new registry.
- Finding 8: size checks BEFORE full reads, via `FileAccess.open` + `get_length()` (or `FileAccess.get_size`): (a) level documents: new `LevelJson.MAX_FILE_BYTES = 8_000_000` (comfortably above thumb 600k + 8×600k images + json slack; document the arithmetic in a comment) enforced in LevelStore load AND LevelChain scanning AND editor Folder-load path; (b) pack manifest + sidecars: the existing 64KB cap checked pre-read; (c) user PNGs (toybox art + theme art): encoded-size cap `2_000_000` bytes pre-read; (d) web upload: check `file.size` in the JS bridge before readAsText, same 8MB budget, oversize → the existing LoadError dialog with a named reason. Oversize anything → named warning/error, zero full-file allocation.
- Tests: oversized fixture files (write junk of cap+1 bytes) rejected with warnings and — where observable — without a parse attempt (e.g. junk content after the cap would have errored the parser; assert no engine error). Valid max-adjacent files still load.

- [ ] Steps: failing tests → RED → implement → GREEN → FULL suite. Commit: `fix: powerups snapshot at spawn, size caps precede reads (audit 7+8)`

---

## Riders (logged, not in scope)

- ObjectDB leak / "2 resources still in use" at exit — unresolved diagnostic per the audit; pre-existing.
- 12 deprecated API uses reported by GUT.
- Desktop visual walkthrough items (thumbnails headless, browser/PWA validation) — owner's polish pass covers the human half.
