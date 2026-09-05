class_name NarfFade
extends CanvasLayer

# NarfKit: fade the world through black. A self-managing veil that
# covers the screen, swaps (or reloads) the scene behind it, then
# lifts and cleans itself up. Fire-and-forget:
#
#   NarfFade.change_scene(get_tree(), "res://scenes/level.tscn")
#   NarfFade.change_scene(get_tree(), "")   # empty path = reload
#
# The veil lives on the tree root, so it survives the scene change --
# and it processes while paused, so a paused screen can still fade.

const DURATION := 0.28

var _veil: ColorRect


func _init() -> void:
	layer = 120  # above every game CanvasLayer
	process_mode = Node.PROCESS_MODE_ALWAYS
	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 0)
	_veil.anchors_preset = Control.PRESET_FULL_RECT
	_veil.anchor_right = 1.0
	_veil.anchor_bottom = 1.0
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks mid-fade
	add_child(_veil)


## Fade to black, change (or reload) the scene, fade back in.
static func change_scene(tree: SceneTree, path: String) -> void:
	var f := NarfFade.new()
	tree.root.add_child(f)
	f._run(tree, path)


func _run(tree: SceneTree, path: String) -> void:
	var down := create_tween()
	down.tween_property(_veil, "color:a", 1.0, DURATION)
	await down.finished
	if path == "":
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file(path)
	# Let the incoming scene draw its first frame under the veil.
	await tree.process_frame
	var up := create_tween()
	up.tween_property(_veil, "color:a", 0.0, DURATION)
	await up.finished
	queue_free()
