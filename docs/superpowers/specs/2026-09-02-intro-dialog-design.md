# Kingdom Crumble — Level Intro Dialog Design

Owner-directed 2026-09-02 ("we need to add the text dialog key to the
json... a control to display the message everytime the level starts...
an Info icon after the level name that will re pop the message"). Levels
learn to talk: optional intro text, shown at every level start,
re-openable from the HUD.

## 0. Hard rules

- **Inert data:** the intro is a plain String — text can charm, never
  act. Validation caps length; no markup, no ids, no paths. Levels stay
  safe to share.
- Shown EVERY level start (owner explicit) — including restarts and
  editor TEST sessions (the author must be able to proof their text; no
  completion logging is involved, so the no-cheaters rule is untouched).
- Zero behavior change for levels without an intro: no key in the json,
  no dialog, no info icon.

## 1. Format — `"intro"` in the level json

- `LevelLayout.intro := ""` (plain text, "" = none).
- `LevelJson`: serialize writes `"intro"` only when non-empty; parse
  reads via `str(d.get("intro", ""))`; validate — optional; when present
  must be a String no longer than `MAX_INTRO_CHARS = 600` (a hearty
  paragraph; hard wall for blobs) else reject ("intro too long" /
  "bad intro"). Same shape as the thumb field's rules.

## 2. Presentation — `IntroDialog` (scenes/ui/intro_dialog.tscn)

Parchment panel, centered, theme-styled like the jump dialog family:
level title header (Lilita One), message body (Nunito, autowrap,
max width ~560px), and a "TAP TO CONTINUE" meta footer (IBM Plex Mono,
ink-muted). API: `open(title: String, text: String)`; signal `closed`.

- Pauses the tree while visible (`process_mode = ALWAYS` on itself);
  unpauses on dismiss. The pause guards against firing through the
  dialog; the HUD's existing stuck-fire releases already handle pause
  transitions.
- Dismiss on ANY of: click/tap anywhere, `ui_accept`, `fire` (SPACE),
  `menu` (Esc) — Esc closes the intro, it does not open the pause menu
  while the intro is up.
- Re-openable at will: opening again with the same text is the info
  icon's whole job.

## 3. Level wiring

- `Level` shows the dialog once the level is presented (same timing
  family as the title toast) when `layout.intro != ""` — every start,
  every restart, TEST included.
- HUD/StatCard: an info icon Button after the title in the card header
  (owner's screenshot: title row, next to the LVL chip). Visible only
  when the level has an intro. Pressing re-opens the dialog. Plumbing:
  `hud.set_level_info` gains the intro presence + a `hud.info_pressed`
  signal (or callback) the Level connects to reopen.
- Icon art: `res://art/assets/ui/info.png` — generated via the owner's
  OpenArt (authorized), brass roundel matching the key/padlock set,
  ~20px display in the header row.

## 4. Editor authoring

- `EditorMenu` hamburger gains an "INTRO…" entry opening a small dialog:
  TextEdit (prefilled with `current.intro`), SAVE and CLEAR buttons.
  SAVE writes `current.intro`; CLEAR empties it. Plain Godot dialog
  styled by the theme, following the menu's existing save-as/load dialog
  patterns.
- Round-trips through save/load like any layout field. TEST sessions
  carry it (so authors proof the text in place).

## 5. Out of scope

- KingdomDialog generalization (this builds another future customer for
  it, not the component itself), typewriter effects, per-page text,
  portraits, localization.

## 6. Testing (GUT)

- Format: intro round-trips; absent key → "" and unwritten; non-string
  rejected; cap boundary exact (600 passes, 601 fails).
- IntroDialog: hidden initially; open() shows, pauses, sets title+text;
  dismiss via ui_accept unpauses, emits closed, hides; reopen works.
- Level: layout with intro → dialog visible after start; without → not;
  restart shows again (fresh scene = fresh show covers it).
- StatCard: info icon visible only with intro; pressing emits the
  reopen signal.
- Editor: INTRO dialog saves text into `current.intro`; save/load
  round-trip preserves it; CLEAR empties.
- Scope: no gameplay/world changes beyond the Level wiring block.
