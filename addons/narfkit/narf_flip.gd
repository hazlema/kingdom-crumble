class_name NarfFlip
extends Sprite2D

# NarfKit: the playing-card flip. Animates scale.x through zero and
# swaps the texture at the edge-on apex — the classic 2D fake-3D turn
# (the founder invented it independently once; now it lives here).
# Successive flips slow like a settling card and it ALWAYS lands
# showing the front.
#
# Kit rules: zero host-game dependencies.

signal finished

## The face shown when the flipping ends.
@export var front_texture: Texture2D
## The reverse side (card back). Falls back to the front if empty.
@export var back_texture: Texture2D
## Half-turns to perform (3 = back, front, back... always ends front).
@export_range(1, 12) var flips := 3
## Seconds for the first (fastest) flip.
@export_range(0.05, 2.0, 0.01) var first_flip_time := 0.22
## Each successive flip takes this much longer — the settling feel.
@export_range(1.0, 3.0, 0.05) var slowdown := 1.45

var _tween: Tween


func play() -> void:
	if front_texture == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var back := back_texture if back_texture != null else front_texture
	scale.x = absf(scale.x)
	var base := scale.x
	_tween = create_tween()
	var dur := first_flip_time
	for i in flips:
		# Which face shows AFTER this flip's apex: count back from the
		# end — the final segment must reveal the front.
		var face := front_texture if (flips - 1 - i) % 2 == 0 else back
		_tween.tween_property(self, "scale:x", 0.0, dur / 2.0).set_trans(Tween.TRANS_SINE)
		_tween.tween_callback(_swap.bind(face))
		(
			_tween
			. tween_property(self, "scale:x", base, dur / 2.0)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		dur *= slowdown
	_tween.tween_callback(func() -> void: finished.emit())


func _swap(face: Texture2D) -> void:
	texture = face
