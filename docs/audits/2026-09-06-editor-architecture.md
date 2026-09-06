# Level Editor Architecture Audit (2026-09-06)

Trigger: owner intuition ("the editor will need to be reworked") after
four review waves in two days caught the same class of state bug.
Auditor: read-only pass over the full editor subsystem, 348-test
baseline. Verdict: **CONFIRMED as a bounded input/selection-layer
problem — NOT a rewrite.**

## The evidence

- 22 mutable fields in one namespace on LevelEditor; edge detectors
  (_lmb_down/_rmb_down) SHARED across modes, so mode transitions must
  reset each other's state by hand.
- **18 call-sites** (close/open/_reopen_inspector) exist solely to keep
  PieceInspector aliased to a live dict — one unwritten invariant
  (inspector holds a raw reference INTO current.overlays/props; any
  dict REPLACEMENT orphans it) maintained manually everywhere.
- RMB pan-vs-menu disambiguator duplicated verbatim in both modes.
- All four review-wave bugs (drag_prop hygiene, close-site rounds ×2,
  rebuild key-stripping, Range.set_max signal injection) are instances
  of the SAME two invariants being re-implemented per feature.
- Stale comments in piece_inspector.gd:12-18 and level_editor.gd:379
  contradict post-8c02d4e behavior (verbs stay live through rebuilds).
- Latent pattern instance: scenery-mode over_ui doesn't guard the crate
  Info dialog (polled input, so window routing doesn't protect).

## Verified HEALTHY — do not touch

Pieces registry, PropBuilder/SceneryBuilder, LevelJson/LevelStore/
LevelLayout, EditorGrid, GridOverlay + SceneryGizmo (already passive
views), the polled-_process decision (documented Godot capture problem
— correct), the bake pipeline algorithms (just mislocated: ~450 lines
of image processing inside the interaction controller).

## The plan: Option A — five review-gated tasks (suite green after each)

1. **Extract the darkroom** — bake/image statics to
   src/editor/scenery_bake.gd. Pure move, zero behavior change,
   level_editor.gd drops to ~1,000 lines. Risk nil. Do regardless.
2. **Shared input services + GridTool** — EditorTool base
   (enter/exit/press/release/ghost/rmb hooks); crates+props stay ONE
   tool (they genuinely share the grid model); RMB disambiguator
   factored once; thin forwarders keep the 36 interaction tests
   untouched.
3. **SceneryTool** — _scenery_* quintet + gizmo driving move in;
   enter/exit hooks replace _enter/_exit_scenery; per-tool edge
   detectors kill the stale-input bug class.
4. **Selection/inspector authority** — one _sync_views() choke point
   owns open/close/re-point; 18 sites collapse to ~3. Kills the
   aliasing bug class. Highest value; do after 2-3.
5. **Registry hygiene** — dialog/panel lists become registries (closes
   the Info-dialog leak), stale comments fixed, %SceneryPanel
   reach-through encapsulated.

Do NOT: split crates from props, revisit polled input, touch the
healthy layers.

## Sequencing vs upcoming features

- Task 1: immediately (free).
- Tasks 2-4: BEFORE the trigger-link editor UI — link mode is a
  cross-mode modal sub-state, the current structure's worst case; as
  the first new Tool it becomes the abstraction's proof test instead.
- Toybox wave: fully independent (Pieces.scan seam + palette rework)
  — schedule freely, no ordering constraint.
- Do-nothing projection: ~3-4 review waves per feature indefinitely;
  gates have caught 100% so far but the rate is constant, not
  declining.

Contingency note: task 4's cost depends on the 23 scenery tests'
internals-coupling (not line-audited); budget half a task of shim work.
