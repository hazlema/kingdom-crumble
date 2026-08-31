# src/level/level.gd
class_name Level
extends Node2D

enum State { AIMING, FLIGHT, RESOLVING, CLEARED, FAILED }

const STONE_SCENE := preload("res://scenes/stone.tscn")
const HIT_TEXT_SCENE := preload("res://src/effects/HitTextEffect.tscn")
const UNLOCK_FRAME_SCENE := preload("res://scenes/ui/rare_unlock_frame.tscn")
const DEFAULT_LAYOUT := "res://levels/demo.json"
const RESOLVE_MIN := 1.5
const RESOLVE_MAX := 6.0

# Set this before changing to the level scene to play any layout —
# built-in, or a player-made file from user://levels/.
static var next_layout_path := ""
# Set to a LevelLayout to bypass the path entirely (cleared in _ready).
static var next_layout: LevelLayout = null
# When true the level returns to the editor on end/pause rather than reloading.
static var return_to_editor := false
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

@onready var trebuchet: Trebuchet = $Trebuchet
@onready var cam: CameraDirector = $CameraDirector
@onready var hud: Hud = $Hud

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
	_spawn_crates()
	shots_left = layout.shots if layout.shots > 0 \
		else Settings.preset.shots_per_level
	hud.set_shots(shots_left)
	Music.play_tier(Settings.tier)
	trebuchet.fired.connect(_on_fired)
	hud.menu_pressed.connect(func() -> void:
		if has_node("PauseMenu"):
			$PauseMenu.open())
	if has_node("PauseMenu"):
		$PauseMenu.restart_requested.connect(func() -> void:
			if _editor_session:
				Level.next_layout = _pristine
				Level.return_to_editor = true
			get_tree().reload_current_scene())
		$PauseMenu.quit_requested.connect(
			func() -> void: get_tree().change_scene_to_file(
				"res://scenes/main_menu.tscn"))
		$PauseMenu.back_to_editor_requested.connect(_back_to_editor)
		$PauseMenu.set_editor_mode(_editor_session)

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("backdrop_toggle"):
		_apply_backdrop_alpha(_backdrop.toggle())
	_update_crate_check()
	match state:
		State.AIMING:
			trebuchet.process_aim(delta)
			hud.set_power(trebuchet.charge)
			cam.aim_focus = trebuchet.preview_end_global()
			if Input.get_axis("scout_left", "scout_right") != 0.0:
				cam.set_mode(CameraDirector.next_mode(cam.mode, "scout_input"))
			elif Input.get_axis("aim_left", "aim_right") != 0.0 \
					or Input.is_action_pressed("fire"):
				cam.set_mode(CameraDirector.next_mode(cam.mode, "aim_input"))
		State.FLIGHT:
			_resolve_clock += delta
			if _resolve_clock > RESOLVE_MIN and (_all_sleeping() or _resolve_clock > RESOLVE_MAX):
				_settle()
		State.RESOLVING:
			pass
		State.CLEARED, State.FAILED:
			if Input.is_action_just_pressed("advance"):
				if _editor_session:
					_back_to_editor()
				else:
					if state == State.CLEARED:
						Level.carry_buffs = pending_buffs.duplicate()
					get_tree().reload_current_scene()

func _spawn_crates() -> void:
	for crate in LevelBuilder.spawn_crates(self, layout, false, _crate_texture):
		crate.knocked_out.connect(_on_crate_knocked)

func _crate_texture(id: String) -> Texture2D:
	return EditorAssets.texture_for(id)

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
		velocities = [velocity, velocity.rotated(deg_to_rad(2.5)),
			velocity.rotated(deg_to_rad(-2.5))]
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
	await _award_leans()
	cam.set_mode(CameraDirector.next_mode(cam.mode, "settled"))
	var standing := count_standing(_crates())
	if standing == 0:
		state = State.CLEARED
		var _cleared_sub := "press ENTER to return to editor" if _editor_session \
				else "press ENTER to play again"
		hud.banner("KINGDOM CRUMBLED!", _cleared_sub)
		var effects: Array = layout.triggers.get("on_all_cleared", [])
		if not effects.is_empty():
			var center := Vector2(1400, 400)
			if not _crates().is_empty():
				center = _crates()[0].global_position
			Effects.fire_all(effects, self, center)
	elif shots_left <= 0:
		state = State.FAILED
		var _failed_sub := "press ENTER to return to editor" if _editor_session \
				else "press ENTER to retry"
		hud.banner("OUT OF STONES", _failed_sub)
	else:
		trebuchet.recock()  # ammo remains: reset the arm and reload
		state = State.AIMING

func _back_to_editor() -> void:
	LevelEditor.resume_layout = _pristine
	Level.return_to_editor = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/editor.tscn")

func _award_leans() -> void:
	for crate in _crates():
		if not Lean.is_lean_angle(crate.rotation):
			continue
		var bodies: Array = crate.get_colliding_bodies()
		for i in bodies.size():
			var other: Node = bodies[i]
			if other is Crate and _ledger.claim(crate.get_instance_id(), other.get_instance_id()):
				hud.banner("LEAN BONUS!", "")
				await get_tree().create_timer(1.2).timeout
				hud.clear_banner()

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

func _stone_is_done() -> bool:
	for stone in _active_stones:
		if not is_instance_valid(stone):
			continue
		if stone.global_position.y <= 2000.0 and not stone.sleeping:
			return false
	return true

func _all_sleeping() -> bool:
	if not _stone_is_done():
		return false
	for crate in _crates():
		if not crate.sleeping:
			return false
	return true

static func count_standing(crates: Array) -> int:
	var n := 0
	for c in crates:
		if c.is_standing():
			n += 1
	return n

static func count_standing_rotations(rotations: Array) -> int:
	var n := 0
	for r in rotations:
		if Crate.is_standing_rotation(r):
			n += 1
	return n

func _on_crate_knocked(crate: Crate) -> void:
	# During editor playtests the skunk is treated as already unlocked so
	# the once-ever ceremony never fires — the plain pool rolls instead.
	var verdict := PowerupRules.route(crate.type_id,
		Unlocks.has_flag("skunk") or _editor_session, _ghost_roll)
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
			var frame: RareUnlockFrame = UNLOCK_FRAME_SCENE.instantiate()
			hud.add_child(frame)
			frame.show_unlock("Rare Unlock", RareUnlockFrame.skunk_frames())

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
