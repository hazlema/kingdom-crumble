class_name ThumbCapture
extends RefCounted

# Save-time portrait (thumb-capture spec §2). Borrows the editor's own
# viewport for one frame — a separate SubViewport would not render the
# ParallaxBackground (CanvasLayers don't cross viewports), baking in
# exactly the black rows the framing algorithm exists to avoid.

const OUT_W := 416
const OUT_H := 256


static func grab(editor: LevelEditor) -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var vp := editor.get_viewport()
	var cam: Camera2D = editor.get_node("Camera")
	var overlay: Node2D = editor.get_node("GridOverlay")
	var ui: CanvasLayer = editor.get_node("Ui")
	var rect := ThumbFraming.capture_rect(editor.current.crates)

	# Freeze input too: set_process(false) alone still delivers _unhandled_input,
	# so Ctrl+S or Ctrl+T during the awaited window would start a second grab
	# or change scene — both leave camera and UI permanently broken.
	editor.set_process(false)
	editor.set_process_unhandled_input(false)
	var was_overlay := overlay.visible
	var was_ui := ui.visible
	var saved_pos := cam.position
	var saved_zoom := cam.zoom
	var saved_limits := [cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom]
	overlay.visible = false
	ui.visible = false
	cam.limit_left = -10000000
	cam.limit_top = -10000000
	cam.limit_right = 10000000
	cam.limit_bottom = 10000000
	# Viewport (16:9) is wider than the 13:8 rect — fit by height.
	var view_scale := vp.get_visible_rect().size.y / rect.size.y
	cam.zoom = Vector2(view_scale, view_scale)
	cam.position = rect.get_center()
	cam.force_update_scroll()
	# Teleporting the camera without this may capture a mid-interpolation frame
	# when physics_interpolation is enabled in project settings.
	cam.reset_physics_interpolation()

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var b64 := ""
	if img != null:
		# World -> rendered-image pixels, robust to window size under
		# the canvas_items stretch mode.
		var xf := vp.get_final_transform() * vp.get_canvas_transform()
		var tl := (xf * rect.position).round()
		var br := (xf * rect.end).round()
		var crop := Rect2i(Vector2i(tl), Vector2i(br - tl)).intersection(
			Rect2i(Vector2i.ZERO, img.get_size())
		)
		if crop.size.x > 0 and crop.size.y > 0:
			img = img.get_region(crop)
			img.resize(OUT_W, OUT_H, Image.INTERPOLATE_LANCZOS)
			b64 = Marshalls.raw_to_base64(img.save_png_to_buffer())

	cam.position = saved_pos
	cam.zoom = saved_zoom
	cam.limit_left = saved_limits[0]
	cam.limit_top = saved_limits[1]
	cam.limit_right = saved_limits[2]
	cam.limit_bottom = saved_limits[3]
	# Avoid a visible smear frame when the camera snaps back to its saved position.
	cam.reset_physics_interpolation()
	overlay.visible = was_overlay
	ui.visible = was_ui
	editor.set_process(true)
	editor.set_process_unhandled_input(true)
	return b64
