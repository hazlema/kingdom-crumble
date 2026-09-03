class_name SkunkPeek
extends RefCounted

# Mr. Skunk's first job (owner, 2026-09-02): once unlocked, he pops up
# from the grass wherever a lean bonus lands, hugs his heart for a
# beat, and sinks back down. The reward is friendship.

const SHEET := "res://art/characters/skunk/skunk-spritesheet.png"
const GRID := 3  # the sheet is a 3x3 pose grid, not a strip
const HEART_POSE := Vector2i(1, 2)  # column, row: bottom-middle heart hug
const HEIGHT := 90.0  # on-screen size
const RISE_TIME := 0.35
const PEEK_TIME := 2.4
const SINK_TIME := 0.25


static func pop(host: Node2D, at: Vector2) -> void:
	var tex: Texture2D = load(SHEET)
	if tex == null:
		return
	var fw := tex.get_width() / float(GRID)
	var fh := tex.get_height() / float(GRID)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(HEART_POSE.x * fw, HEART_POSE.y * fh, fw, fh)
	var s := Sprite2D.new()
	s.texture = atlas
	s.centered = false
	s.offset = Vector2(-fw / 2.0, -fh)  # anchor at bottom-center: he grows upward
	var size := HEIGHT / fh
	host.add_child(s)
	s.global_position = Vector2(at.x, EditorGrid.FLOOR_Y + 24.0)
	s.scale = Vector2(size, 0.0)
	var tw := s.create_tween()
	tw.tween_property(s, "scale:y", size, RISE_TIME).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_interval(PEEK_TIME)
	tw.tween_property(s, "scale:y", 0.0, SINK_TIME)
	tw.tween_callback(s.queue_free)
