class_name RareUnlockFrame
extends Control

# Gold-framed "Rare Unlock" ceremony (spec §4). Reusable: hand it any
# SpriteFrames. The skunk is its first customer. Not modal — gameplay
# continues behind it.
#
# When the owner's portrait pair exists (photo-front/photo-back), the
# ceremony upgrades itself to the NarfFlip card reveal — flip, flip,
# flip... skunk (owner design: "use narf to spin him in the frame").

const SKUNK_SHEET := "res://assets/characters/skunk/skunk-spritesheet.png"
const PHOTO_FRONT := "res://assets/characters/skunk/photo-front.png"
const PHOTO_BACK := "res://assets/characters/skunk/photo-back.png"
const LINGER := 4.0


static func skunk_frames() -> SpriteFrames:
	if ResourceLoader.exists("res://resources/skunk_frames.tres"):
		return load("res://resources/skunk_frames.tres")
	# The sheet is a 3x3 pose grid (walk / dizzy / hearts). Derived
	# fallback animates the walk row; the owner's .tres wins when it
	# exists.
	var tex: Texture2D = load(SKUNK_SHEET)
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 6.0)
	frames.set_animation_loop(&"default", true)
	var fw := tex.get_width() / 3.0
	var fh := tex.get_height() / 3.0
	for i in 3:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(&"default", at)
	return frames


func show_unlock(title: String, frames: SpriteFrames) -> void:
	%Title.text = title
	if ResourceLoader.exists(PHOTO_FRONT) and ResourceLoader.exists(PHOTO_BACK):
		_show_flip_reveal()
	else:
		%Anim.sprite_frames = frames
		var first: Texture2D = frames.get_frame_texture(&"default", 0)
		if first:
			var s := minf(220.0 / first.get_width(), 220.0 / first.get_height())
			%Anim.scale = Vector2(s, s)
		%Anim.play(&"default")
	var t := create_tween()
	t.tween_interval(LINGER)
	t.tween_property(self, "modulate:a", 0.0, 0.6)
	t.tween_callback(queue_free)


func _show_flip_reveal() -> void:
	%Anim.visible = false
	var flip := NarfFlip.new()
	var front: Texture2D = load(PHOTO_FRONT)
	flip.front_texture = front
	flip.back_texture = load(PHOTO_BACK)
	flip.texture = flip.back_texture  # the card starts face-down
	var s := minf(220.0 / front.get_width(), 220.0 / front.get_height())
	flip.scale = Vector2(s, s)
	flip.position = Vector2(120, 120)
	%Anim.get_parent().add_child(flip)
	flip.play()
