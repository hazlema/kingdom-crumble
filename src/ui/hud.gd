class_name Hud
extends CanvasLayer

signal menu_pressed
signal info_pressed

const FIRE_STONE := preload("res://assets/ui/stone.png")
const DEED_BANNER_SCRIPT := preload("res://src/ui/deed_banner.gd")

# Deed banner layer — sits above everything, manages its own FIFO queue.
var _deed_banner: Node = null

# Stale-request guard for deferred deed banners (mirrors _banner_seq discipline).
var _pending_deeds: Array[Dictionary] = []  # deferred deed banners, FIFO
var _deed_drain_armed := false


func _ready() -> void:
	%MenuButton.pressed.connect(func() -> void: menu_pressed.emit())
	%MenuButton.focus_mode = Control.FOCUS_NONE
	# FIRE! is a screen-sized spacebar: hold to charge, release to loose.
	# ALWAYS so the release still lands if the tree pauses mid-press —
	# a lost button_up left "fire" stuck down and froze the scout camera.
	%FireButton.process_mode = Node.PROCESS_MODE_ALWAYS
	%FireButton.focus_mode = Control.FOCUS_NONE
	%FireButton.button_down.connect(func() -> void: Input.action_press("fire"))
	%FireButton.button_up.connect(func() -> void: Input.action_release("fire"))
	%FireButton.icon = FIRE_STONE
	%StatCard.get_node("%CrateIcon").texture = Pieces.texture_for("crate-wood")
	# Touch angle controls (audit: touch players were stuck at 45
	# degrees). Hold-to-adjust via the same Input bridge as FIRE; the
	# readout keeps aiming predictable. Desktop keeps its arrow keys.
	var touch := DisplayServer.is_touchscreen_available()
	%AngleUp.visible = touch
	%AngleDown.visible = touch
	%AngleReadout.visible = touch
	for btn: Button in [%AngleUp, %AngleDown]:
		btn.focus_mode = Control.FOCUS_NONE
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
	%AngleUp.button_down.connect(func() -> void: Input.action_press("aim_left"))
	%AngleUp.button_up.connect(func() -> void: Input.action_release("aim_left"))
	%AngleDown.button_down.connect(func() -> void: Input.action_press("aim_right"))
	%AngleDown.button_up.connect(func() -> void: Input.action_release("aim_right"))
	%StatCard.info_pressed.connect(func() -> void: info_pressed.emit())
	# The crates row is touch's H key — same Input bridge as FIRE.
	%StatCard.check_held.connect(
		func(held: bool) -> void:
			if held:
				Input.action_press("check")
			else:
				Input.action_release("check")
	)
	# Deed banner: create the layer now; connect Deeds signal.
	_deed_banner = DEED_BANNER_SCRIPT.new()
	add_child(_deed_banner)
	Deeds.deed_unlocked.connect(_on_deed_unlocked)
	# Disconnect cleanly when this hud leaves the tree (Deeds is an autoload —
	# connections outlive scenes; dangling callbacks cause the classic leak).
	tree_exiting.connect(func() -> void:
		if Deeds.deed_unlocked.is_connected(_on_deed_unlocked):
			Deeds.deed_unlocked.disconnect(_on_deed_unlocked)
	)


# Alt-tabbing away mid-charge eats the release the same way.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.action_release("fire")
		Input.action_release("check")
		Input.action_release("aim_left")
		Input.action_release("aim_right")


func set_shots(n: int) -> void:
	%StatCard.set_shots(n)


func set_crates(standing: int, total: int) -> void:
	%StatCard.set_crates(standing, total)


func set_power(ratio: float) -> void:
	%StatCard.set_power(ratio)


# Short-lived level-title announcement at level start — clears itself
# unless a real banner (lean bonus, cleared) has taken the stage since.
const TOAST_SECS := 1.8

var _toast_until := 0.0  # while now < this, a display: toast owns the banner slot
var _banner_seq := 0     # stale-request guard for the deferred paths


func toast(text: String, secs: float = TOAST_SECS) -> void:
	if %BannerCenter.visible and %BannerSub.visible:
		return  # a real banner outranks a late toast
	_banner_seq += 1
	var seq := _banner_seq
	_toast_until = Time.get_ticks_msec() * 0.001 + secs
	_apply_banner(text, "")
	get_tree().create_timer(secs).timeout.connect(
		func() -> void:
			if _banner_seq == seq:
				clear_banner()
	)


# Real banners (sub != "") wait for an active toast to finish its beat —
# a display: message on the winning hit was being overwritten instantly
# by KINGDOM CRUMBLED (same control; they replace, not stack).
func banner(title: String, sub: String) -> void:
	_banner_seq += 1
	var seq := _banner_seq
	var now := Time.get_ticks_msec() * 0.001
	if sub != "" and now < _toast_until:
		# Courtesy beat, capped: a short toast finishes its say, but a long
		# instructional display never holds the victory banner hostage.
		get_tree().create_timer(minf(_toast_until - now, 2.5) + 0.15).timeout.connect(
			func() -> void:
				if _banner_seq == seq and is_inside_tree():
					_apply_banner(title, sub)
		)
		return
	_apply_banner(title, sub)


func _apply_banner(title: String, sub: String) -> void:
	%Banner.text = title
	%BannerSub.text = sub
	%BannerSub.visible = sub != ""
	%BannerCenter.visible = true


func clear_banner() -> void:
	%BannerCenter.visible = false


func set_buffs(buffs: Array[StringName]) -> void:
	%StatCard.set_buffs(buffs)
	%FireButton.icon = _fire_icon_for(buffs)


func set_level_info(title: String, number: int, has_intro := false) -> void:
	%StatCard.set_title(title)
	%StatCard.set_level_no(number)
	%StatCard.set_info(has_intro)


func _fire_icon_for(buffs: Array[StringName]) -> Texture2D:
	var kinds := {}
	for b in buffs:
		kinds[b] = true
	if kinds.size() >= 2:
		return Pieces.texture_for("crate-gold")
	if kinds.has(&"exploding"):
		return Pieces.texture_for("skull")
	if kinds.has(&"super_bounce"):
		return Pieces.texture_for("crate-green")
	if kinds.has(&"multishot"):
		return Pieces.texture_for("crate-blue")
	return FIRE_STONE


func set_angle(deg: float) -> void:
	%AngleReadout.text = str(roundi(deg))


# ---------------------------------------------------------------------------
# Deed banner — queue politely behind toasts, connect to Deeds signal
# ---------------------------------------------------------------------------

func _on_deed_unlocked(id: String) -> void:
	# Look up the entry from the Deeds manifest to pass art/name to the banner.
	var entry: Dictionary = {}
	for e in Deeds.entries():
		if e["id"] == id:
			entry = e
			break
	if entry.is_empty():
		# Entry not in current manifest (can happen if manifest changed at runtime).
		entry = {"id": id, "name": id, "solid": "", "ghost": "", "text": "", "secret": false, "trigger": ""}
	_queue_deed_banner(entry)


## Queue a deed banner entry — defers behind an active toast using the
## min-remaining cap+epsilon idiom from hud.banner().
func _queue_deed_banner(entry: Dictionary) -> void:
	# Review catch: a seq stale-guard DROPPED all but the last deed when
	# several unlocked together (cascading meta-deeds). A pending queue
	# drained by one timer loses nothing; the DeedBanner's own FIFO is
	# the ordering authority once entries reach it.
	var now := Time.get_ticks_msec() * 0.001
	var busy: bool = now < _toast_until or %BannerCenter.visible  # toast OR victory banner
	if not busy:
		if _deed_banner != null:
			_deed_banner.celebrate(entry)
		return
	_pending_deeds.append(entry)
	if _deed_drain_armed:
		return
	_deed_drain_armed = true
	var wait := minf(maxf(_toast_until - now, 0.0), 2.5) + 0.15
	get_tree().create_timer(wait).timeout.connect(
		func() -> void:
			_deed_drain_armed = false
			if not is_inside_tree() or _deed_banner == null:
				return
			if %BannerCenter.visible:
				# victory banner still up — re-arm one more courtesy beat
				if not _pending_deeds.is_empty():
					_queue_deed_banner(_pending_deeds.pop_front())
				return
			while not _pending_deeds.is_empty():
				_deed_banner.celebrate(_pending_deeds.pop_front())
	)


## Returns true if a deed banner is currently mid-animation (for tests).
func _deed_banner_active() -> bool:
	return _deed_banner != null and _deed_banner.visible
