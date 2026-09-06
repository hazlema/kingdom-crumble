# Wormholes Design

Paired portals for Kingdom Crumble: a stone enters one, exits the
other, velocity untouched. Rides the Pieces system (see
2026-09-05-pieces-design.md) as the first Area2D class. Owner decisions
(2026-09-06): stones only now with the crate door open for later;
preserve velocity exactly; pairing by id ("colors"), two colors in V1.

## 1. Class `wormhole` (baked code; sidecar selects/tunes)

- New curated class beside `crate|static|trampoline` in
  `Pieces.CLASSES`. Existing sidecar keys apply (`cells`, `tip`);
  `tilt`/`bounce` are ignored for this class (no new keys in V1).
- Spawned as **Area2D** (not StaticBody2D): a detection zone, not a
  wall. Crates and stones pass through it physically; only the
  teleport logic reacts, and only to stones.
- `PropBuilder.spawn_one` return type widens `StaticBody2D` → `Node2D`
  (portals are Areas). Callers already treat results as nodes; the
  typed arrays update accordingly.
- Sprite gets a slow idle spin (class-level constant, e.g. 0.6 rad/s)
  for free juice; owner art replaces the placeholder PNGs freely.

## 2. Pairing: the id IS the pair

- Rule: any wormhole-class id placed **exactly twice** in a level
  auto-links those two portals bidirectionally.
- Placed once, or 3+ times → named `push_warning` at spawn
  ("wormhole '<id>': needs exactly 2, found N — inert") and ALL
  portals of that id stay inert scenery (spawned, visible, spinning,
  non-functional). Inert-data doctrine: never crash, level still
  plays.
- V1 ships two ids: `wormhole-blue`, `wormhole-orange` → up to two
  independent pairs per level. More colors later = PNG + sidecar drop,
  zero code.
- NO level-format change: wormholes are ordinary `props` entries
  (`{id, x, y}`). No pair field, no editor linking UI.
- Linking pass: after `spawn_props`, group spawned wormhole bodies by
  `prop_id` meta; wire pairs (each portal holds a reference to its
  partner). Lives in the wormhole class/builder, not in level.gd.

## 3. Teleport semantics

- Trigger: `body_entered` with `body is Stone` (the codebase idiom —
  crate.gd gates the same way; crates and everything else ignored in
  V1). The teleport helper itself takes any RigidBody2D so a future
  sidecar flag can admit crates without rebuild.
- Effect (deferred to physics-safe time): stone's `global_position` :=
  partner portal's center; `linear_velocity` unchanged;
  `reset_physics_interpolation()` after the move (camera-teleport
  lesson — no one-frame smear).
- **Arrival immunity, not timers:** on arrival the stone is added to
  the partner portal's `_arrivals` set; that portal ignores it until
  `body_exited` removes it. Framerate-proof, no oscillation even with
  adjacent portals.
- Effects hook (nice-to-have, in scope if trivial): reuse
  `Effects.fire_all(["sound:..."], ...)`-style sound later — V1 ships
  silent; owner may drop a warp ogg into the auto-resolve slot when
  the class learns a sound (future).

## 4. Shape & art

- Sidecar: `{"class": "wormhole", "cells": [1, 2], "tip": "..."}` —
  a 64×126 vertical portal, a hittable target. Resizable by editing
  the sidecar (registry clamps 1–4 apply).
- Area collision: rectangle matching the footprint (same sizing rule
  as static shapes).
- Placeholder art: generated swirly ovals (blue/orange) at 64×126;
  ids and sidecars stay when the owner replaces the PNGs.

## 5. Editor

- Zero new UI: class `wormhole` joins the OBSTACLES palette section;
  grid placement/delete/footprint-ghost identical to trampolines.
  (A dedicated "GADGETS" section waits until there are 2+ dynamic
  pieces.)
- The editor does not enforce the exactly-two rule (placement stays
  dumb); the rule is a spawn-time behavior. TEST from the editor
  exercises the real linking pass.

## 6. Testing (GUT)

- Pair links: layout with two `wormhole-blue` props + a stone body
  pushed into portal A → stone relocates to portal B's center with
  velocity preserved (exact vector compare).
- Odd counts inert: one portal (and three portals) → warning fires,
  stone passes through unteleported.
- No oscillation: stone arriving at B is ignored by B until it exits
  once; adjacent-portal layout doesn't ping-pong.
- Crates don't teleport: crate body entering a portal stays put.
- Registry: wormhole sidecars parse (class accepted, cells honored).
- Props format untouched: existing round-trip tests already cover
  wormhole entries (they're plain ids).

## Out of scope (doors left open)

Crate transit (future sidecar flag), portal sounds/particles beyond
idle spin, exit-aiming "cannon" variants, GADGETS palette section,
editor pair-validation hints.
