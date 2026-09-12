# src/level/level.gd
class_name Level
extends Node2D

enum State { AIMING, FLIGHT, RESOLVING, CLEARED, FAILED }

const STONE_SCENE := preload("res://scenes/stone.tscn")
const HIT_TEXT_SCENE := preload("res://src/effects/HitTextEffect.tscn")
const UNLOCK_FRAME_SCENE := preload("res://scenes/ui/rare_unlock_frame.tscn")
const INVALID_LEVEL_SCENE := preload("res://scenes/ui/invalid_level.tscn")
const DEFAULT_LAYOUT := "res://levels/basics.json"
const RESOLVE_MIN := 1.5
const RESOLVE_MAX := 6.0
const IDLE_SPEED := 20.0  # px/s — below this a body no longer holds the turn open

# Set this before changing to the level scene to play any layout —
# built-in, or a player-made file from user://levels/.
# DELIBERATELY PERSISTENT (not consume-and-clear like the statics
# below): Restart and FAILED-retry reload the current level through
# this path. Every navigation (menu, advance, jump) sets it first.
static var next_layout_path := ""
# Set to a LevelLayout to bypass the path entirely (cleared in _ready).
static var next_layout: LevelLayout = null
# When true the level returns to the editor on end/pause rather than reloading.
static var return_to_editor := false
# Test seam: every shipped level now opens with an intro, whose pause
# deadlocks physics awaits in headless tests (SceneTree.physics_frame
# fires while paused; the space doesn't step). The GUT pre-run hook
# sets this true; test_intro_dialog opts back out to test the real thing.
static var suppress_intro := false
# Unspent buffs riding into the next level after a CLEAR (spec §5).
# Consume-and-clear in _ready, like every Level static.
static var carry_buffs: Array[StringName] = []

var layout: LevelLayout
var state := State.AIMING
var shots_left := 0
var _resolve_clock := 0.0
var _ledger := LeanLedger.new()
var _active_stones: Array[Stone] = []
var pending_buffs: Array[StringName] = []
# Injectable for tests; production uses randf.
var _ghost_roll: Callable = func() -> float: return randf()
var _backdrop := BackdropMode.new()
var _checking := false
var _pristine: LevelLayout = null
var _editor_session := false
var current_stem := ""
var _chain_end := false

@onready var trebuchet: Trebuchet = $Trebuchet
@onready var cam: CameraDirector = $CameraDirector
@onready var hud: Hud = $Hud

# Per-piece tween trackers for peek fade (kill-on-retarget hygiene).
var _peek_tweens: Dictionary = {}  # NarfDecor instance_id → Tween


func _ready() -> void:
	if Settings.preset == null:
		Settings.load_tier("chill")
	_editor_session = Level.return_to_editor
	Level.return_to_editor = false
	pending_buffs = Level.carry_buffs
	Level.carry_buffs = []
	hud.set_buffs.call_deferred(pending_buffs.duplicate())
	if next_layout != null:
		layout = next_layout
		_pristine = next_layout
		next_layout = null
	else:
		var path := next_layout_path if next_layout_path != "" else DEFAULT_LAYOUT
		layout = LevelStore.load_level(path)
		if layout == null:
			layout = LevelStore.load_level(DEFAULT_LAYOUT)
			if layout != null:
				current_stem = LevelChain.level_id(DEFAULT_LAYOUT)
		else:
			current_stem = LevelChain.level_id(path)
	if layout == null:
		# even the default failed (e.g. hand-edited to invalid) — the
		# owner's dialog tells the player, then exits; empty field
		# underneath so nothing crashes in the meantime
		push_warning("No loadable layout (default included)")
		hud.add_child(INVALID_LEVEL_SCENE.instantiate())
		layout = LevelLayout.new()
	var _pieces := SceneryBuilder.spawn(self, layout)
	# Back scenery lives BEHIND the whole stage (spec: below crates AND the
	# trebuchet) — tuck back pieces right after the Environment backdrop.
	# and need no reordering here.
	var _back_idx := 1
	for piece in _pieces:
		if piece.get_parent() == self:
			move_child(piece, _back_idx)
			_back_idx += 1
	_spawn_crates()
	# Start the peek watcher timer (0.1s poll, gameplay-side only).
	var _peek_timer := Timer.new()
	_peek_timer.wait_time = 0.1
	_peek_timer.autostart = true
	_peek_timer.timeout.connect(_tick_peek)
	add_child(_peek_timer)
	PropBuilder.spawn_props(self, layout)
	if layout.title != "":
		hud.toast(layout.title)
	if layout.intro != "" and not suppress_intro:
		_show_intro()
	var _chain := LevelChain.entries()
	var _pos := -1
	for i in _chain.size():
		if _chain[i]["id"] == current_stem and current_stem != "":
			_pos = i + 1
			break
	hud.set_level_info(layout.title, _pos, layout.intro != "")
	hud.info_pressed.connect(_show_intro)
	shots_left = layout.shots if layout.shots > 0 else Settings.preset.shots_per_level
	hud.set_shots(shots_left)
	Music.play_tier(Settings.tier)
	trebuchet.fired.connect(_on_fired)
	hud.menu_pressed.connect(
		func() -> void:
			if has_node("PauseMenu"):
				$PauseMenu.open()
	)
	if has_node("PauseMenu"):
		$PauseMenu.restart_requested.connect(
			func() -> void:
				if _editor_session:
					Level.next_layout = _pristine
					Level.return_to_editor = true
				get_tree().reload_current_scene()
		)
		$PauseMenu.quit_requested.connect(
			func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		)
		$PauseMenu.back_to_editor_requested.connect(_back_to_editor)
		$PauseMenu.jump_levels_requested.connect(_open_jump)
		$PauseMenu.set_editor_mode(_editor_session)
	%JumpDialog.level_picked.connect(
		func(picked: String) -> void:
			Level.next_layout_path = picked
			get_tree().paused = false
			get_tree().reload_current_scene()
	)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("backdrop_toggle"):
		_apply_backdrop_alpha(_backdrop.toggle())
	if not _editor_session and Input.is_action_just_pressed("jump_levels"):
		_open_jump()
	_tick_hold(delta)
	_update_crate_check()
	match state:
		State.AIMING:
			trebuchet.process_aim(delta)
			hud.set_power(trebuchet.charge)
			hud.set_angle(trebuchet.aim_angle_deg)
			cam.aim_focus = trebuchet.preview_end_global()
			if Input.get_axis("scout_left", "scout_right") != 0.0:
				cam.set_mode(CameraDirector.next_mode(cam.mode, "scout_input"))
			elif Input.get_axis("aim_left", "aim_right") != 0.0 or Input.is_action_pressed("fire"):
				cam.set_mode(CameraDirector.next_mode(cam.mode, "aim_input"))
		State.FLIGHT:
			_resolve_clock += delta
			if _resolve_clock > RESOLVE_MIN and (_all_sleeping() or _resolve_clock > RESOLVE_MAX):
				_settle()
		State.RESOLVING:
			pass
		State.CLEARED, State.FAILED:
			if Input.is_action_just_pressed("advance"):
				_advance()


# Long-press-the-battlefield = the H crate check (owner: "a long press,
# somewhere other than the fire button"). Hold still this long to light
# it; wander further than the slop and it's a drag, not a press.
const CHECK_HOLD_SEC := 0.4
const CHECK_HOLD_SLOP := 24.0

var _hold_pos := Vector2.ZERO
var _hold_clock := -1.0  # below zero = no press pending
var _hold_checking := false


# Phones have no ENTER key: once the banner is up, any unclaimed tap
# advances too. Mouse-only on purpose -- a touch tap also emits an
# emulated mouse click, so handling both events would double-advance.
# The same handler tracks the long-press check on the open battlefield.
func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_cancel_hold()
	if state == State.CLEARED or state == State.FAILED:
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_advance()
		return
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_hold_pos = mb.position
		_hold_clock = 0.0
	elif event is InputEventMouseMotion and _hold_clock >= 0.0:
		if (event as InputEventMouseMotion).position.distance_to(_hold_pos) > CHECK_HOLD_SLOP:
			_cancel_hold()


func _tick_hold(delta: float) -> void:
	if _hold_clock < 0.0 or _hold_checking:
		return
	_hold_clock += delta
	if _hold_clock >= CHECK_HOLD_SEC:
		_hold_checking = true
		Input.action_press("check")


func _cancel_hold() -> void:
	_hold_clock = -1.0
	if _hold_checking:
		_hold_checking = false
		Input.action_release("check")


# The banner's call to action, told honestly per device.
func _advance_hint(rest: String) -> String:
	var verb := "tap" if DisplayServer.is_touchscreen_available() else "press ENTER"
	return "%s %s" % [verb, rest]


var _advancing := false  # the fade takes a beat; a second ENTER must not double-book it


func _advance() -> void:
	if _advancing:
		return
	_advancing = true
	if _editor_session:
		_back_to_editor()
		return
	if state == State.CLEARED:
		if _chain_end:
			NarfFade.change_scene(get_tree(), "res://scenes/main_menu.tscn")
			return
		var nxt := _next_path_after_clear()
		if nxt != "":
			Level.next_layout_path = nxt
		Level.carry_buffs = pending_buffs.duplicate()
	NarfFade.change_scene(get_tree(), "")


func _spawn_crates() -> void:
	for crate in LevelBuilder.spawn_crates(self, layout, false, _crate_texture):
		crate.knocked_out.connect(_on_crate_knocked)
	hud.set_crates.call_deferred(layout.crates.size(), layout.crates.size())


func _crate_texture(id: String) -> Texture2D:
	return Pieces.texture_for(id)


func _on_fired(velocity: Vector2) -> void:
	shots_left -= 1
	hud.set_shots(shots_left)
	hud.set_power(0.0)
	var d := PowerupRules.drain(pending_buffs)
	pending_buffs = d["remaining"]
	hud.set_buffs(pending_buffs)
	var consumed: Array[StringName] = d["consumed"]
	var velocities: Array[Vector2] = [velocity]
	if consumed.has(&"multishot"):
		velocities = [
			velocity, velocity.rotated(deg_to_rad(2.5)), velocity.rotated(deg_to_rad(-2.5))
		]
	_active_stones.clear()
	for v in velocities:
		var stone: Stone = STONE_SCENE.instantiate()
		stone.exploding = consumed.has(&"exploding")
		stone.super_bounce = consumed.has(&"super_bounce")
		add_child(stone)
		stone.launch(trebuchet.get_node("LaunchPoint").global_position, v)
		if trebuchet.loaded_texture and stone.has_node("Visual"):
			stone.get_node("Visual").texture = trebuchet.loaded_texture
		_active_stones.append(stone)
	# Exempt every sibling pair from physical perturbation so the fan
	# trajectory is not disturbed by stone-on-stone collisions at launch.
	for i in _active_stones.size():
		for j in range(i + 1, _active_stones.size()):
			_active_stones[i].add_collision_exception_with(_active_stones[j])
	cam.follow_target = _active_stones[0]
	cam.set_mode(CameraDirector.next_mode(cam.mode, "fired"))
	_resolve_clock = 0.0
	state = State.FLIGHT


func _settle() -> void:
	state = State.RESOLVING
	_retire_restless_stones()
	_award_leans()
	cam.set_mode(CameraDirector.next_mode(cam.mode, "settled"))
	var standing := count_standing(_crates())
	if standing == 0:
		state = State.CLEARED
		_record_clear()
		_chain_end = current_stem != "" and _next_path_after_clear() == ""
		if _chain_end: Deeds.bump("tiers_cleared")
		# on_all_cleared fires FIRST so its display: toasts claim the banner
		# slot; the victory banner then queues politely behind them.
		var effects: Array = layout.triggers.get("on_all_cleared", [])
		if not effects.is_empty():
			var center := Vector2(1400, 400)
			if not _crates().is_empty():
				center = _crates()[0].global_position
			_fire_action_list(effects, center)
		if _editor_session:
			hud.banner("KINGDOM CRUMBLED!", _advance_hint("to return to editor"))
		elif _chain_end:
			hud.banner("KINGDOM CONQUERED!", _advance_hint("for the throne room"))
		else:
			hud.banner("KINGDOM CRUMBLED!", _advance_hint("for the next level"))
	elif shots_left <= 0:
		state = State.FAILED
		var _failed_sub := (
			_advance_hint("to return to editor") if _editor_session else _advance_hint("to retry")
		)
		hud.banner("OUT OF STONES", _failed_sub)
	else:
		trebuchet.recock()  # ammo remains: reset the arm and reload
		state = State.AIMING


func _back_to_editor() -> void:
	LevelEditor.resume_layout = _pristine
	Level.return_to_editor = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/editor.tscn")


# Non-blocking fanfare (owner: lean bonuses were stalling the turn —
# each one used to hold the settle hostage for a 1.2s banner, stacking
# sequentially). The toast channel self-clears and cannot collide with
# the CRUMBLED/OUT-OF-STONES banner the settle may raise right after.
func _award_leans() -> void:
	var leans := 0
	var peek_at := Vector2.INF
	for crate in _crates():
		if not Lean.is_lean_angle(crate.rotation):
			continue
		var bodies: Array = crate.get_colliding_bodies()
		for i in bodies.size():
			var other: Node = bodies[i]
			if other is Crate and _ledger.claim(crate.get_instance_id(), other.get_instance_id()):
				leans += 1
				if peek_at == Vector2.INF:
					peek_at = crate.global_position
	if leans == 1:
		hud.toast("LEAN BONUS!")
	elif leans > 1:
		hud.toast("LEAN BONUS x%d!" % leans)
	# Mr. Skunk's first job: once he's yours, he pops up to admire the
	# lean with you (editor TEST counts as owning him, for proofing).
	if leans > 0 and (Unlocks.has_flag("skunk") or _editor_session):
		SkunkPeek.pop(self, peek_at)


# Hold H: standing crates glow green, fallen ones red — what's left
# to hit at a glance. Preserves backdrop-mode alpha.
func _update_crate_check() -> void:
	var want := Input.is_action_pressed("check")
	if want == _checking:
		return
	_checking = want
	for crate in _crates():
		var a: float = crate.modulate.a
		var c := Color.WHITE
		if _checking:
			c = Color(0.55, 1.0, 0.55) if crate.is_standing() else Color(1.0, 0.45, 0.45)
		c.a = a
		crate.modulate = c


func _apply_backdrop_alpha(alpha: float) -> void:
	var targets: Array = [trebuchet]
	targets.append_array(_crates())
	for stone in _active_stones:
		if is_instance_valid(stone):
			targets.append(stone)
	var tween := create_tween().set_parallel(true)
	for target in targets:
		tween.tween_property(target, "modulate:a", alpha, 0.25)


func _crates() -> Array:
	return get_tree().get_nodes_in_group("crates")


# The turn is over — its stones retire with it. A boom+bounce cluster
# stone never frees itself and would keep exploding through the next
# aiming phase (turn rules fix this, not physics — the 6s carnage
# window is untouched). Sleeping stones stay as harmless rubble.
func _retire_restless_stones() -> void:
	for stone in _active_stones:
		if is_instance_valid(stone) and not stone.sleeping:
			var tw := stone.create_tween()
			tw.tween_property(stone, "modulate:a", 0.0, 0.35)
			tw.tween_callback(stone.queue_free)


func _stone_is_done() -> bool:
	for stone in _active_stones:
		if not is_instance_valid(stone):
			continue
		if stone.global_position.y <= 2000.0 and not _is_idle(stone):
			return false
	return true


func _all_sleeping() -> bool:
	if not _stone_is_done():
		return false
	for crate in _crates():
		if not _is_idle(crate):
			return false
	return true


# Owner rule: barely-moving counts as done. True engine sleep takes a
# second of stillness, so a crate wobbling at a crawl used to hold the
# turn open to the RESOLVE_MAX cap.
func _is_idle(body: RigidBody2D) -> bool:
	return (
		body.freeze
		or body.sleeping
		or (body.linear_velocity.length() < IDLE_SPEED and absf(body.angular_velocity) < 1.0)
	)


static func count_standing(crates: Array) -> int:
	var n := 0
	for c in crates:
		if c.is_standing():
			n += 1
	return n


func _on_crate_knocked(crate: Crate) -> void:
	_fire_crate_triggers(crate)
	Deeds.bump("crates_smashed")
	hud.set_crates(count_standing(_crates()), layout.crates.size())
	# During editor playtests the skunk is treated as already unlocked so
	# the once-ever ceremony never fires — the plain pool rolls instead.
	# route_crate reads the crate's SPAWN-TIME powerup snapshot (audit
	# finding 7): a pack toggled mid-level cannot change a live reward.
	var verdict := PowerupRules.route_crate(
		crate, Unlocks.has_flag("skunk") or _editor_session, _ghost_roll
	)
	match verdict["kind"]:
		"refund":
			# Ignore late chain-topple refunds once the level has ended —
			# a gold crate falling after FAILED/CLEARED must not alter shots_left.
			if state == State.CLEARED or state == State.FAILED:
				return
			shots_left += 1
			hud.set_shots(shots_left)
			_floaty(verdict["label"], crate.global_position)
		"buff":
			pending_buffs.append(verdict["buff"])
			hud.set_buffs(pending_buffs)
			_floaty(verdict["label"], crate.global_position)
		"skunk":
			Unlocks.set_flag("skunk")
			Deeds.flag("skunk")
			var frame: RareUnlockFrame = UNLOCK_FRAME_SCENE.instantiate()
			hud.add_child(frame)
			frame.show_unlock("Rare Unlock", RareUnlockFrame.skunk_frames())


# Linked triggers (spec 2026-09-05): a crate registering as hit fires
# its authored actions — scenery show/hide by name, everything else
# through the effects library. One-shot for free: the knocked ledger
# already guarantees this handler runs once per crate, ever.
func _fire_crate_triggers(crate: Crate) -> void:
	if not crate.has_meta("json_coords"):
		return
	var jc: Vector2i = crate.get_meta("json_coords")
	var key := "hit:%d,%d" % [jc.x, jc.y]
	if not layout.triggers.has(key):
		return
	_fire_action_list(layout.triggers[key], crate.global_position, crate)


# Unified action router used by both crate-hit triggers and on_all_cleared.
# show:/hide: prefixed ids go directly to _set_scenery_visible; everything
# else is collected and forwarded to Effects.fire_all in one call.
# source = the hit crate (null for on_all_cleared) — smoke ignites on it.
func _fire_action_list(ids: Array, at: Vector2, source: Node2D = null) -> void:
	var effect_ids: Array = []
	for id in ids:
		var s := str(id)
		if s == "smoke" or s.begins_with("smoke:"):
			if is_instance_valid(source):
				Auras.attach(source, "smog", s.trim_prefix("smoke").trim_prefix(":"))
			continue
		if s.begins_with("display:"):
			hud.toast(Effects.display_message(s), Effects.display_secs(s))
			continue
		if s.begins_with("show:") or s.begins_with("hide:"):
			_set_scenery_visible(s.split(":", true, 1)[1], s.begins_with("show:"))
		else:
			effect_ids.append(s)
	if not effect_ids.is_empty():
		Effects.fire_all(effect_ids, self, at)


func _set_scenery_visible(overlay_name: String, on: bool) -> void:
	var found := false
	for piece in get_tree().get_nodes_in_group("scenery"):
		if piece.get_meta("overlay_name", "") == overlay_name:
			piece.visible = on
			found = true
			break
	# Toggle matching solid body (group "scenery_solid") alongside the sprite.
	# Hidden solid = no collision; shown solid = collision re-enabled.
	for body in get_tree().get_nodes_in_group("scenery_solid"):
		if (body as Node).get_meta("overlay_name", "") == overlay_name:
			(body as Node).process_mode = (
				Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
			)
			break
	if not found:
		push_warning("Trigger references unknown scenery '%s'" % overlay_name)


func _open_jump() -> void:
	%JumpDialog.open(Settings.tier)


func _show_intro() -> void:
	if layout.intro != "":
		%IntroDialog.open(layout.title, layout.intro)


# Log the clear — never from the editor sandbox, never for pathless
# layouts (spec: testing is just testing).
func _record_clear() -> void:
	if _editor_session or current_stem == "":
		return
	Progress.mark_cleared(Settings.tier, current_stem)
	Deeds.bump("levels_cleared")


# "" when the chain is conquered.
func _next_path_after_clear() -> String:
	var chain := LevelChain.entries()
	var nxt := LevelChain.next_index_after(chain, current_stem)
	return "" if nxt == -1 else chain[nxt]["path"]


# Peek watcher (owner design): peek is an object PROPERTY — "fade out when
# a shot comes near".  Peek pieces draw under crates/stones so the goal is
# never obscured; the fade is pure feedback that the object isn't solid.
# A stone inside the piece's rect grown by PEEK_MARGIN → tween modulate.a
# to 0.35 (0.2s); no stone near → restore 1.0.  Kill-on-retarget hygiene
# matches flash_overlay in level_editor.gd.
const PEEK_MARGIN := 120.0  # px around the piece that counts as "near"


func _tick_peek() -> void:
	for piece_node in get_tree().get_nodes_in_group("scenery"):
		var piece := piece_node as NarfDecor
		if piece == null or not is_instance_valid(piece):
			continue  # queue_freed pieces can linger in the group a frame
		if not piece.get_meta("peek", false):
			continue
		if not piece.visible:
			continue  # hidden pieces don't peek (churn + surprise pre-fade)

		# Compute the piece's world-space rect (texture bounds).
		var tex := piece.texture
		if tex == null:
			continue
		var sz := tex.get_size()
		# NarfDecor: centered=false, offset is pivot-derived top-left offset.
		var world_tl: Vector2 = piece.global_position + piece.offset
		var near_rect := Rect2(world_tl, sz).grow(PEEK_MARGIN)

		# "A shot comes near": any stone (group or the level's active list)
		# inside the grown rect.  Crates are irrelevant — they draw over the
		# piece anyway, and the fade is about the incoming shot.
		var shot_near := false
		for stone in get_tree().get_nodes_in_group("stones"):
			var sn := stone as Node2D
			if sn != null and near_rect.has_point(sn.global_position):
				shot_near = true
				break
		if not shot_near:
			for stone in _active_stones:
				if is_instance_valid(stone) and near_rect.has_point(stone.global_position):
					shot_near = true
					break

		var target_alpha := 0.35 if shot_near else 1.0  # feedback: "not solid"
		var current_alpha := piece.modulate.a
		# Skip if already at target (avoid needless tween churn).
		if absf(current_alpha - target_alpha) < 0.01:
			continue

		# Kill any running tween for this piece before starting a new one.
		var iid := piece.get_instance_id()
		if _peek_tweens.has(iid):
			var old_tw: Tween = _peek_tweens[iid]
			if old_tw != null and old_tw.is_valid():
				old_tw.kill()
		var tw := create_tween()
		_peek_tweens[iid] = tw
		tw.tween_property(piece, "modulate:a", target_alpha, 0.2)
		tw.finished.connect(func() -> void:
			if _peek_tweens.get(iid) == tw:
				_peek_tweens.erase(iid)
		)


func _floaty(text: String, world_pos: Vector2) -> void:
	var fx: HitTextEffect = HIT_TEXT_SCENE.instantiate()
	fx.text = text
	# louder than the control's defaults: pickups happen mid-mayhem and
	# a 1-second whisper gets lost under collapsing towers
	fx.scale = Vector2(1.6, 1.6)
	fx.duration = 1.8
	fx.rise = 90.0
	# position BEFORE add_child: the rise tween bakes its destination
	# from position at _ready time
	fx.position = get_viewport_transform() * world_pos
	hud.add_child(fx)
