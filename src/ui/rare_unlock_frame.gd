class_name RareUnlockFrame
extends Control

# Gold-framed "Rare Unlock" ceremony (spec §4). Reusable: hand it any
# SpriteFrames. The skunk is its first customer. Not modal — gameplay
# continues behind it.

const SKUNK_SHEET := "res://art/characters/skunk-sprites.png"
const LINGER := 4.0


static func skunk_frames() -> SpriteFrames:
	if ResourceLoader.exists("res://resources/skunk_frames.tres"):
		return load("res://resources/skunk_frames.tres")
	var tex: Texture2D = load(SKUNK_SHEET)
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 8.0)
	frames.set_animation_loop(&"default", true)
	var h := tex.get_height()
	var count := maxi(1, int(tex.get_width() / h))
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * h, 0, h, h)
		frames.add_frame(&"default", at)
	return frames


func show_unlock(title: String, frames: SpriteFrames) -> void:
	%Title.text = title
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
