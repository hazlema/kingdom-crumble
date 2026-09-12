class_name DeedBanner
extends Control

# Deed stamp-banner — celebrates a single deed unlock with a medallion
# stamp and gold ribbon.
#
# Usage: call celebrate(entry) where entry is a validated Deeds manifest
# dict (keys: id, name, solid, ...). Multiple calls queue FIFO.
#
# Choreography: scale-punch (1.6→1.0, 0.25s TRANS_BACK), hold 2.5s,
# fade out 0.3s, then queue_free. Cosmetic only — never blocks input,
# never touches pause. process_mode stays INHERIT (runs normally).
#
# Art loading: entry["solid"] is relative to res://achievements/. If the
# file cannot be loaded, a push_warning is emitted and the ribbon label
# still displays (graceful degradation).
#
# Sound: plays res://assets/sfx/deed.ogg on the Sfx bus only if the file
# exists (ResourceLoader.exists check — graceful silence otherwise).
#
# Confetti: fires the Effects._confetti pattern at the medallion position.

const SFX_PATH := "res://assets/sfx/deed.ogg"
const ART_DIR := "res://achievements/"

const PUNCH_DURATION := 0.25  # scale-punch settle time (s)
const PUNCH_SCALE := 1.6      # starting scale factor
const HOLD_SECS := 2.5        # dwell time after punch
const FADE_SECS := 0.3        # fade-out duration

# Emitted when this banner's animation fully completes (lets hud drain queue)
signal deed_completed(id: String)

# The formatted ribbon text — readable by tests without node traversal.
var ribbon_text: String = ""

# Internal queue so multiple rapid unlock signals are served FIFO.
var _queue: Array[Dictionary] = []
var _busy := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0   # full-width overlay so center math works
	anchor_bottom = 1.0
	visible = false


## Enqueue a deed celebration. Executes immediately if not busy.
func celebrate(entry: Dictionary) -> void:
	_queue.append(entry)
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return  # leave modulate.a at 0.0 / visible=false — test can observe that
	_busy = true
	var entry: Dictionary = _queue.pop_front()
	_run(entry)


func _run(entry: Dictionary) -> void:
	var id: String = entry.get("id", "")
	var name_val: String = entry.get("name", "")
	ribbon_text = "⚜ Deed Accomplished — %s ⚜" % name_val

	visible = true
	modulate.a = 1.0

	# Build transient container — cleared on next call so no nodes accumulate.
	for c in get_children():
		c.queue_free()

	# Center container so everything sits center-top.
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	vbox.offset_top = 60.0  # push below the HUD's stat card
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	# Medallion TextureRect
	var medallion := TextureRect.new()
	medallion.custom_minimum_size = Vector2(128, 128)
	medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medallion.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var solid_file: String = entry.get("solid", "")
	var tex: Texture2D = _load_medallion(solid_file, id)
	if tex != null:
		medallion.texture = tex
	vbox.add_child(medallion)

	# Gold ribbon label
	var ribbon := Label.new()
	ribbon.text = ribbon_text
	ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ribbon.add_theme_color_override("font_color", Color(0.96, 0.77, 0.26, 1))
	ribbon.add_theme_font_size_override("font_size", 28)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(ribbon)

	# Confetti burst at the medallion center (needs a Node2D host — use a
	# temporary Node2D attached to our Control's parent canvas layer).
	_fire_confetti()

	# Sound (graceful silence if file absent)
	_play_deed_sound()

	# Tween: scale-punch → hold → fade → free
	medallion.pivot_offset = Vector2(64, 64)
	medallion.scale = Vector2(PUNCH_SCALE, PUNCH_SCALE)

	var tw := create_tween()
	tw.set_parallel(false)
	tw.tween_property(medallion, "scale", Vector2(1.0, 1.0), PUNCH_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD_SECS)
	tw.tween_property(self, "modulate:a", 0.0, FADE_SECS)
	tw.tween_callback(func() -> void:
		visible = false
		deed_completed.emit(id)
		_next()  # restores modulate.a = 1.0 at top of _run if queue non-empty
	)


func _load_medallion(filename: String, entry_id: String) -> Texture2D:
	if filename == "":
		push_warning("DeedBanner: entry '%s' has no solid art filename" % entry_id)
		return null
	var path := ART_DIR + filename
	# ResourceLoader.exists handles .remap disguises transparently.
	if not ResourceLoader.exists(path):
		push_warning("DeedBanner: medallion art not found for '%s': %s" % [entry_id, path])
		return null
	var res = ResourceLoader.load(path, "Texture2D")
	if res == null:
		push_warning("DeedBanner: failed to load medallion art for '%s': %s" % [entry_id, path])
		return null
	return res as Texture2D


func _play_deed_sound() -> void:
	if not ResourceLoader.exists(SFX_PATH):
		return  # graceful silence — art dept supplies later
	var player := AudioStreamPlayer.new()
	player.bus = "Sfx" if AudioServer.get_bus_index("Sfx") != -1 else "Master"
	player.stream = load(SFX_PATH)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _fire_confetti() -> void:
	# THE Effects confetti (review catch: never shadow the library — a
	# tuned Effects burst must stay the single source of celebration).
	# The banner is a Control on a CanvasLayer; Effects wants a Node2D
	# host, so spawn a transient one at the medallion position.
	var parent := get_parent()
	if parent == null:
		return
	var host := Node2D.new()
	parent.add_child(host)
	var at := Vector2(0.0, 150.0)
	var vp := get_viewport()
	if vp != null:
		at = Vector2(vp.get_visible_rect().size.x * 0.5, 150.0)
	Effects._confetti(host, at)
	get_tree().create_timer(3.0).timeout.connect(host.queue_free)
