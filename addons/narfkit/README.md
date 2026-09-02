# NarfKit 🐭

Reusable game components. Copy this folder into any Godot 4 project's
`addons/` and everything works — no activation, no editor plugin, no
host-game dependencies.

## The founding rule

A NarfKit component may not reference the host game: no autoloads, no
`res://` paths outside `addons/narfkit/`, no host themes. Everything a
component needs arrives through exported properties or sensible
defaults. If a component needs the host's blessing, it isn't kit
material yet.

## Citizens

- **NarfDecor** (`narf_decor.gd`) — a Sprite2D that brings scenery to
  life: give it any texture, a behavior verb (SPIN, SWAY, BOB), a
  9-point pivot anchor, and speed/amplitude dials. Windmill wheels
  turn, trees sway, boats bob.
- **NarfFlip** (`narf_flip.gd`) — the playing-card flip: scale.x
  through zero, texture swap at the edge-on apex, each flip slower
  than the last, always lands face-up. `play()` + `finished` signal.

## Citizenship policy

New generic components are born here. Existing game components migrate
opportunistically — next time one gets touched anyway, it moves in.
