# Level Intro Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Levels carry an optional `"intro"` text key; an IntroDialog shows it at every level start (restarts and TEST included); a brass info icon in the StatCard header re-pops it; the editor hamburger authors it.

**Architecture:** Format first (LevelLayout + LevelJson, thumb-field twin), then a self-contained IntroDialog scene (pauses while visible), then Level/HUD wiring, then editor authoring. Icon art is pre-generated at `art/assets/ui/info.png` (committed before Task 1).

**Tech Stack:** Godot 4.6.2, GDScript, GUT headless.

## Global Constraints

- `$GODOT` = `/home/frosty/Dev/godot/bin/Godot_v4.6.2-stable_linux.x86_64`; project `/home/frosty/Dev/godot/v4.6/Kingdom-Crumble`. `$GODOT --headless --import .` once after creating files. Suite: `$GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` — **188 green at start, only grows.**
- Spec (binding): `docs/superpowers/specs/2026-09-02-intro-dialog-design.md`. Inert-data rule: intro is a plain String, cap `MAX_INTRO_CHARS = 600`, reject violations.
- Shown EVERY start incl. editor TEST; levels without intro see ZERO change (no dialog, no icon).
- Theme: fonts art/fonts/ (Lilita One display, project-theme Nunito body, IBMPlexMono-Medium meta); palette ink #4b3b2a, ink-muted #8f7047, parchment-light #fffaf0.
- git add ONLY touched files (+ .uid). NEVER -A. `music/chill/old/` is the owner's untracked archive — leave it.
- Tabs; gdformat (double blank line between funcs). Tests: gut_-prefixed user:// stems, cleaned up immediately.

## File Map

- Task 1 modify: `src/level/level_layout.gd`, `src/level/level_json.gd`, `tests/unit/test_level_json.gd`
- Task 2 create: `src/ui/intro_dialog.gd`, `scenes/ui/intro_dialog.tscn`, `tests/unit/test_intro_dialog.gd`
- Task 3 modify: `scenes/level.tscn`, `src/level/level.gd` (wiring block), `src/ui/hud.gd`, `src/ui/stat_card.gd`, `scenes/ui/stat_card.tscn`, `tests/unit/test_stat_card.gd`
- Task 4 modify: `src/editor/editor_menu.gd`, `scenes/editor_menu.tscn` (or its dialog pattern), `tests/unit/test_level_editor_interactions.gd`
- Task 5: verification only.

---

### Task 1: `"intro"` joins the level format

**Files:**
- Modify: `src/level/level_layout.gd`, `src/level/level_json.gd`
- Test: `tests/unit/test_level_json.gd` (extend — READ it first, match style; it already has the thumb tests to twin)

**Interfaces:**
- Produces: `LevelLayout.intro: String` ("" = none); `LevelJson.MAX_INTRO_CHARS := 600`; serialize writes `"intro"` only when non-empty; parse populates; validate rejects non-String / over-cap.

- [ ] **Step 1: Write the failing tests** — append to `tests/unit/test_level_json.gd`:

```gdscript
func test_intro_round_trips() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	l.intro = "Hold to charge, release to FIRE!"
	var parsed := LevelJson.parse(LevelJson.serialize(l))
	assert_not_null(parsed)
	assert_eq(parsed.intro, "Hold to charge, release to FIRE!")


func test_absent_intro_stays_empty_and_unwritten() -> void:
	var l := LevelLayout.new()
	l.title = "T"
	var s := LevelJson.serialize(l)
	assert_false(s.contains("intro"), "empty intro is not serialized")
	assert_eq(LevelJson.parse(s).intro, "")


func test_non_string_intro_rejected() -> void:
	var d := {"format": 1, "title": "T", "crates": [], "intro": 7}
	assert_ne(LevelJson.validate(d), "")


func test_intro_cap_is_exact() -> void:
	var at_cap := {
		"format": 1, "title": "T", "crates": [], "intro": "a".repeat(LevelJson.MAX_INTRO_CHARS)
	}
	assert_eq(LevelJson.validate(at_cap), "")
	var over := {
		"format": 1,
		"title": "T",
		"crates": [],
		"intro": "a".repeat(LevelJson.MAX_INTRO_CHARS + 1),
	}
	assert_ne(LevelJson.validate(over), "")
```

- [ ] **Step 2: Run selected — FAIL:** `-gselect=test_level_json`

- [ ] **Step 3: Implement** — twin of the thumb field, in `src/level/level_json.gd`:

Near the other consts: `const MAX_INTRO_CHARS := 600  # a hearty paragraph; hard wall for blobs`

In `validate()`, directly after the thumb block:

```gdscript
	var _intro: Variant = d.get("intro", "")
	if not _intro is String:
		return "bad intro"
	if (_intro as String).length() > MAX_INTRO_CHARS:
		return "intro too long"
```

In `parse()`, next to the other optional reads: `l.intro = str(data.get("intro", ""))` (match the local variable name the function actually uses).

In `serialize()`, mirroring the thumb block:

```gdscript
	if layout.intro != "":
		d["intro"] = layout.intro
```

In `src/level/level_layout.gd`, after `thumb`:

```gdscript
# Optional intro text shown when the level starts ("" = none). Plain
# String — text can charm, never act (sharing stays safe).
@export var intro := ""
```

- [ ] **Step 4: Selected PASS; FULL suite green (188 + 4 = 192 expected).**

- [ ] **Step 5: Commit**

```bash
git add src/level/level_layout.gd src/level/level_json.gd tests/unit/test_level_json.gd
git commit -m "feat: levels learn to talk — optional validated intro text in the json"
```

---

### Task 2: IntroDialog component

**Files:**
- Create: `src/ui/intro_dialog.gd`, `scenes/ui/intro_dialog.tscn`
- Test: `tests/unit/test_intro_dialog.gd` (create)

**Interfaces:**
- Produces: `IntroDialog` (Control) — `open(title: String, text: String)`, signal `closed`. Pauses the tree while visible, unpauses on dismiss. Task 3 instances it in level.tscn as `%IntroDialog`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_intro_dialog.gd`:

```gdscript
extends GutTest


func _dialog() -> IntroDialog:
	var d: IntroDialog = load("res://scenes/ui/intro_dialog.tscn").instantiate()
	add_child_autofree(d)
	return d


func after_each() -> void:
	get_tree().paused = false


func test_hidden_initially() -> void:
	assert_false(_dialog().visible)


func test_open_shows_pauses_and_fills() -> void:
	var d := _dialog()
	d.open("THE MEADOW", "Aim for the base!")
	assert_true(d.visible)
	assert_true(get_tree().paused, "world holds its breath while the level speaks")
	assert_eq(d.get_node("%Title").text, "THE MEADOW")
	assert_eq(d.get_node("%Body").text, "Aim for the base!")


func test_accept_dismisses_unpauses_and_signals() -> void:
	var d := _dialog()
	watch_signals(d)
	d.open("T", "hello")
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	d._input(ev)
	assert_false(d.visible)
	assert_false(get_tree().paused)
	assert_signal_emitted(d, "closed")


func test_reopens_after_dismiss() -> void:
	var d := _dialog()
	d.open("T", "hello")
	d.dismiss()
	d.open("T", "hello again")
	assert_true(d.visible)
	assert_eq(d.get_node("%Body").text, "hello again")
```

- [ ] **Step 2: Run selected — FAIL (IntroDialog not declared):** `-gselect=test_intro_dialog`

- [ ] **Step 3: Implement**

Create `src/ui/intro_dialog.gd`:

```gdscript
class_name IntroDialog
extends Control

# The level speaks (intro-dialog spec §2): optional level text shown at
# every start and re-popped from the HUD's info icon. Pauses the world
# while open; any tap or key dismisses.

signal closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open(title: String, text: String) -> void:
	%Title.text = title
	%Body.text = text
	visible = true
	get_tree().paused = true


func dismiss() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var tap := event is InputEventMouseButton and event.pressed
	var key := (
		event.is_action_pressed("ui_accept")
		or event.is_action_pressed("fire")
		or event.is_action_pressed("menu")
	)
	if tap or key:
		get_viewport().set_input_as_handled()
		dismiss()
```

Create `scenes/ui/intro_dialog.tscn` — full-rect Control root (`visible = false`), dim scrim (ColorRect, `Color(0.16, 0.12, 0.08, 0.45)`, full rect, mouse_filter stop), CenterContainer holding a PanelContainer (parchment-light #fffaf0 StyleBoxFlat: 3px ink-muted border at 45% alpha, corner radius 12, content margins 28/22/28/18, `custom_minimum_size = Vector2(480, 0)` and max width via the body label's `custom_minimum_size = Vector2(560, 0)` + autowrap) containing a VBox (separation 12):
- `%Title` Label — Lilita One (ext_resource `res://art/fonts/LilitaOne-Regular.ttf`), size 28, ink #4b3b2a, centered.
- `DashedLine` separator (script `res://src/ui/dashed_line.gd`, `custom_minimum_size = Vector2(0, 10)`) — the StatCard's own separator style.
- `%Body` Label — project-theme body font, size 18, ink, `autowrap_mode = 3`, `custom_minimum_size = Vector2(520, 0)`, centered.
- Footer Label — IBM Plex Mono Medium (ext_resource), size 11, ink-muted #8f7047, text `TAP TO CONTINUE`, centered.

- [ ] **Step 4: Import, selected PASS; FULL suite green (192 + 4 = 196 expected).**

- [ ] **Step 5: Commit**

```bash
git add src/ui/intro_dialog.gd src/ui/intro_dialog.gd.uid scenes/ui/intro_dialog.tscn tests/unit/test_intro_dialog.gd tests/unit/test_intro_dialog.gd.uid
git commit -m "feat: IntroDialog — parchment panel that pauses the world to speak"
```

---

### Task 3: Level + HUD wiring (the icon re-pops the speech)

**Files:**
- Modify: `scenes/level.tscn` (instance IntroDialog), `src/level/level.gd` (wiring), `src/ui/hud.gd`, `src/ui/stat_card.gd`, `scenes/ui/stat_card.tscn`
- Test: `tests/unit/test_stat_card.gd` (extend), `tests/unit/test_intro_dialog.gd` (one integration test appended)

**Interfaces:**
- Consumes: `IntroDialog.open/closed` (Task 2), `LevelLayout.intro` (Task 1). Icon asset already committed: `res://art/assets/ui/info.png`.
- Produces: `StatCard.set_info(has_intro: bool)` + signal `info_pressed`; `Hud.set_level_info(title, number, has_intro := false)` (default keeps every existing call site compiling) + `Hud.info_pressed` signal; Level shows the dialog at start and on info press.

- [ ] **Step 1: Failing tests** — append to `tests/unit/test_stat_card.gd` (READ it first, reuse its `_card()` helper):

```gdscript
func test_info_icon_only_when_level_has_intro() -> void:
	var c := _card()
	c.set_info(false)
	assert_false(c.get_node("%InfoBtn").visible)
	c.set_info(true)
	assert_true(c.get_node("%InfoBtn").visible)


func test_info_press_signals() -> void:
	var c := _card()
	watch_signals(c)
	c.set_info(true)
	c.get_node("%InfoBtn").pressed.emit()
	assert_signal_emitted(c, "info_pressed")
```

And append to `tests/unit/test_intro_dialog.gd` (integration through the real level scene — follow the style of existing level tests if any exist for setup; keep it minimal):

```gdscript
func test_level_with_intro_speaks_at_start() -> void:
	Level.next_layout = LevelLayout.new()
	Level.next_layout.title = "Talky"
	Level.next_layout.intro = "Welcome!"
	Level.next_layout.crates = [
		{"x": 800.0, "y": 569.0, "type": "crate-wood"},
	]
	var lvl: Node = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(lvl)
	await wait_seconds(1.0)
	assert_true(lvl.get_node("%IntroDialog").visible, "the level speaks at start")
	lvl.get_node("%IntroDialog").dismiss()
```

(Adapt the Level static handoff to how `_on_test` actually passes layouts — `Level.next_layout` is the existing pattern; check level.gd's consume-and-clear discipline and mirror a TEST session so no progress is logged: set `Level.return_to_editor = true` as `_on_test` does, and reset any statics you set at test end.)

- [ ] **Step 2: Run selected — FAIL:** `-gselect=test_stat_card` and `-gselect=test_intro_dialog`

- [ ] **Step 3: Implement**

`scenes/ui/stat_card.tscn`: in the header row after `%Title`, add `%InfoBtn` — a flat Button (`visible = false`, `custom_minimum_size = Vector2(22, 22)`, flat = true, icon `res://art/assets/ui/info.png`, `expand_icon = true`, tooltip_text "Level info").

`src/ui/stat_card.gd`:

```gdscript
signal info_pressed
```

wire in `_ready` (create `_ready` if absent):

```gdscript
func _ready() -> void:
	%InfoBtn.pressed.connect(func() -> void: info_pressed.emit())
```

and add:

```gdscript
func set_info(has_intro: bool) -> void:
	%InfoBtn.visible = has_intro
```

`src/ui/hud.gd`: add `signal info_pressed`; extend `set_level_info(title: String, number: int, has_intro := false)` to also call `%StatCard.set_info(has_intro)`; in `_ready`, connect `%StatCard.info_pressed` → re-emit `info_pressed`.

`scenes/level.tscn`: instance `res://scenes/ui/intro_dialog.tscn` as `%IntroDialog` (unique_name_in_owner) at the END of the scene's UI layer (find where JumpDialog lives and follow — same layer, after it).

`src/level/level.gd`: in the existing set_level_info wiring block, pass `layout.intro != ""` as the third argument; connect `hud.info_pressed` → `_show_intro`; call `_show_intro()` at the same moment the title toast fires (find the toast call — same timing family) guarded by `if layout.intro != "": ...`. Add:

```gdscript
func _show_intro() -> void:
	if layout.intro != "":
		%IntroDialog.open(layout.title, layout.intro)
```

(Use the actual layout variable name level.gd uses. TEST sessions show it too — no editor_session guard here, by spec.)

- [ ] **Step 4: Selected PASS; FULL suite green (196 + 3 = 199 expected). Existing set_level_info call sites keep compiling via the default arg.**

- [ ] **Step 5: Commit**

```bash
git add scenes/level.tscn src/level/level.gd src/ui/hud.gd src/ui/stat_card.gd scenes/ui/stat_card.tscn tests/unit/test_stat_card.gd tests/unit/test_intro_dialog.gd
git commit -m "feat: the level speaks at start — intro dialog wired, info icon re-pops it"
```

---

### Task 4: Editor authoring — the INTRO… entry

**Files:**
- Modify: `src/editor/editor_menu.gd`, `scenes/editor_menu.tscn`, `src/editor/level_editor.gd` (one signal connection + handler)
- Test: `tests/unit/test_level_editor_interactions.gd` (extend)

**Interfaces:**
- Consumes: `LevelLayout.intro` (Task 1).
- Produces: EditorMenu emits `intro_edited(text: String)`; LevelEditor stores it into `current.intro`.

- [ ] **Step 1: Failing test** — append to `tests/unit/test_level_editor_interactions.gd` (uses its existing `ed` fixture):

```gdscript
func test_intro_edit_lands_in_the_layout() -> void:
	ed.menu.intro_edited.emit("Aim for the base of the tower!")
	assert_eq(ed.current.intro, "Aim for the base of the tower!")
	ed.menu.intro_edited.emit("")
	assert_eq(ed.current.intro, "", "clearing empties the field")
```

- [ ] **Step 2: Run selected — FAIL (no signal intro_edited):** `-gselect=test_level_editor_interactions`

- [ ] **Step 3: Implement**

READ `src/editor/editor_menu.gd` + `scenes/editor_menu.tscn` FIRST and follow their existing dialog pattern exactly (they already do save-as/load/clear-confirm dialogs — mirror one):

- `editor_menu.gd`: add `signal intro_edited(text: String)`; add an "INTRO…" item to the hamburger list wherever the other entries are declared; add `open_intro(current_text: String)` that shows a dialog holding a TextEdit (prefilled) + SAVE + CLEAR buttons. SAVE → `intro_edited.emit(textedit.text.strip_edges())`; CLEAR → `intro_edited.emit("")`. Cap input: `if text.length() > LevelJson.MAX_INTRO_CHARS: text = text.substr(0, LevelJson.MAX_INTRO_CHARS)` before emitting.
- The hamburger's INTRO entry needs the current text to prefill — either the menu asks via a callback or LevelEditor passes it when opening; follow whichever direction the existing entries use (e.g. how Save As gets its stem), keeping the pattern consistent.
- `level_editor.gd` `_ready` wiring block: `menu.intro_edited.connect(func(t: String) -> void: current.intro = t)` (match the existing connect style; a named `_on_intro_edited` is fine too if neighbors do that).
- Ensure `any_dialog_open()` (used by the input-polling guard) also covers the new dialog — follow how the other dialogs register.

- [ ] **Step 4: Selected PASS; FULL suite green (199 + 1 = 200 expected).**

- [ ] **Step 5: Commit**

```bash
git add src/editor/editor_menu.gd scenes/editor_menu.tscn src/editor/level_editor.gd tests/unit/test_level_editor_interactions.gd
git commit -m "feat: editor authors the intro — INTRO... in the hamburger, capped and round-tripping"
```

---

### Task 5: Verification sweep

- [ ] Full suite twice — green both (200 expected).
- [ ] `git diff main --stat` — only File Map files + the icon + docs.
- [ ] Grep: `IntroDialog` instanced only in level.tscn + tests; `MAX_INTRO_CHARS` referenced from validate + editor cap + tests.
- [ ] Confirm a level WITHOUT intro: no `"intro"` key written, `%InfoBtn` hidden, no dialog (covered by tests; spot-check the serialize output of a bare layout).
- [ ] No commit; report findings.
