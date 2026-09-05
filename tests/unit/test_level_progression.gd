extends GutTest

const TEST_PATH := "user://test_levelprog.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path(TEST_PATH)


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path("user://progress.cfg")
	Level.next_layout_path = ""


func _level_for_first_builtin() -> Level:
	Level.next_layout_path = LevelStore.list_builtin()[0]
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	return l


func test_current_stem_derived_from_path() -> void:
	var l := _level_for_first_builtin()
	var expected: String = LevelChain.level_id(LevelStore.list_builtin()[0])
	assert_eq(l.current_stem, expected, "identity is the namespaced id (audit 4)")


func test_record_clear_writes_tier_and_stem() -> void:
	var l := _level_for_first_builtin()
	l._record_clear()
	assert_true(Progress.is_cleared(Settings.tier, l.current_stem))


func test_editor_session_never_records() -> void:
	Level.next_layout = LevelLayout.new()
	Level.return_to_editor = true
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	l._record_clear()
	var cfg := ConfigFile.new()
	cfg.load(TEST_PATH)
	assert_eq(cfg.get_sections().size(), 0, "sandbox clears must not log")


func test_next_path_after_clear_walks_the_chain() -> void:
	var l := _level_for_first_builtin()
	var chain := LevelChain.entries()
	if chain.size() > 1:
		assert_eq(l._next_path_after_clear(), chain[1]["path"])
	l.current_stem = chain[chain.size() - 1]["stem"]
	assert_eq(l._next_path_after_clear(), "", "end of chain returns empty")


func test_jump_dialog_present_and_wired() -> void:
	var l := _level_for_first_builtin()
	var dialog: LevelJumpDialog = l.get_node("%JumpDialog")
	assert_not_null(dialog)
	assert_false(dialog.visible)


func test_deleted_level_falls_back_to_demo_stem() -> void:
	Level.next_layout_path = "user://levels/definitely_deleted_ghost.json"
	var l: Level = load("res://scenes/level.tscn").instantiate()
	add_child_autofree(l)
	assert_eq(l.current_stem, "builtin:demo", "fallback must use demo id, not the ghost path")
	assert_not_null(l.layout, "layout must not be null after fallback")

func test_level_title_toast_shows_then_clears() -> void:
	var l := _level_for_first_builtin()
	await wait_physics_frames(2)
	assert_eq(l.hud.get_node("%Banner").text, l.layout.title, "title toast on start")
	assert_true(l.hud.get_node("%BannerCenter").visible)
	await wait_seconds(2.2)
	assert_false(l.hud.get_node("%BannerCenter").visible, "toast clears itself")
