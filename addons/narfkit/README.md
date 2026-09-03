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
  life: give it any texture, a behavior verb, a 9-point pivot anchor,
  and speed/movement dials. Windmill wheels turn, trees sway, boats
  bob, clouds drift, butterflies wander.

  Behavior verbs:
  - **SPIN** — continuous rotation (speed = rotations/sec).
  - **SWAY** — sine-swing around home rotation (movement = peak
    degrees, speed = oscillations/sec).
  - **BOB** — vertical sine-travel (movement = peak pixels, speed =
    oscillations/sec).
  - **DRIFT** — axis-locked ping-pong from placement (travel = max
    pixels either side, axis = HORIZONTAL or VERTICAL, speed =
    oscillations/sec). Good for clouds sliding left-right.
  - **WANDER** — random roam-circle glide (travel = roam radius in
    pixels, tilt = peak banking degrees while flying, speed controls
    hop duration). Flips to fly nose-first; always level at rest.
    Good for butterflies and birds.
- **NarfFlip** (`narf_flip.gd`) — the playing-card flip: scale.x
  through zero, texture swap at the edge-on apex, each flip slower
  than the last, always lands face-up. `play()` + `finished` signal.

## Citizenship policy

New generic components are born here. Existing game components migrate
opportunistically — next time one gets touched anyway, it moves in.
