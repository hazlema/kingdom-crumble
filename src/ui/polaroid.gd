class_name Polaroid
extends Control

# Instant-photo save feedback (polaroid spec §1): the capture flick
# becomes showmanship — the fresh portrait drops in tilted, settles,
# holds a beat, fades. Pure presentation; ignores the mouse entirely.

const DROP_TIME := 0.55
const HOLD_TIME := 1.4
const FADE_TIME := 0.5
const TILT_DEG := 4.0
const DROP_FROM := -520.0  # owner nit: falls in from the top row, lands center
const SHUTTER_SFX := "res://assets/sfx/shutter.ogg"
const PNG_MAGIC := [137, 80, 78, 71, 13, 10, 26, 10]

static var _b64_rx := RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")

var _flip := 1.0
var _tween: Tween

@onready var _home_y: float = %Photo.position.y


func _ready() -> void:
	# Owner-art auto-prefer: drop a shutter.ogg in assets/sfx and the
	# camera gets a voice — absent file, silent camera.
	if ResourceLoader.exists(SHUTTER_SFX):
		%Click.stream = load(SHUTTER_SFX)


func show_b64(b64: String, caption: String) -> void:
	# Own trusted data (the editor just produced it), but the same gates
	# as LevelCard keep every failure silent — Marshalls and the PNG
	# driver both spam engine errors on garbage.
	if b64 == "" or b64.length() % 4 != 0 or _b64_rx.search(b64) == null:
		return
	var buf := Marshalls.base64_to_raw(b64)
	if buf.size() < PNG_MAGIC.size():
		return
	for i in PNG_MAGIC.size():
		if buf[i] != PNG_MAGIC[i]:
			return
	var img := Image.new()
	if img.load_png_from_buffer(buf) != OK:
		return
	show_shot(ImageTexture.create_from_image(img), caption)


func show_shot(tex: Texture2D, caption: String) -> void:
	%Shot.texture = tex
	%Caption.text = caption
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_flip = -_flip
	visible = true
	modulate.a = 1.0
	%Photo.pivot_offset = %Photo.size / 2.0
	%Photo.position.y = _home_y + DROP_FROM
	%Photo.rotation_degrees = TILT_DEG * 2.0 * _flip
	_tween = create_tween()
	(
		_tween
		. tween_property(%Photo, "position:y", _home_y, DROP_TIME)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_tween.parallel().tween_property(%Photo, "rotation_degrees", TILT_DEG * _flip, DROP_TIME)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(func() -> void: visible = false)
	if %Click.stream != null:
		%Click.play()
