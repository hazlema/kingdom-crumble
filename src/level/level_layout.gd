class_name LevelLayout
extends Resource

# In-memory level data. Persisted as JSON via LevelJson (spec 2026-09-01);
# the old .tres save format is retired.

@export var title := "Untitled"
@export var author := ""
@export var background := "meadow"
# Base64 PNG portrait captured by the editor at save ("" = none).
@export var thumb := ""
# Optional intro text shown when the level starts ("" = none). Plain
# String — text can charm, never act (sharing stays safe).
@export var intro := ""
@export var shots := 0  # 0 = difficulty preset decides
# Each entry: { "x": float, "y": float, "type": String }
@export var crates: Array[Dictionary] = []
# event name -> Array[String] of curated effect ids
@export var triggers := {}
# Embedded scenery art: content-hash key -> base64 PNG (spec 2026-09-02).
@export var images := {}
# Scenery placements: {image, x, y, behavior?, pivot?, speed?, amplitude?, axis?, travel?, tilt?}
@export var overlays: Array[Dictionary] = []
