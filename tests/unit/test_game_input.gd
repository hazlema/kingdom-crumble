extends GutTest

func test_actions_registered():
	GameInput.ensure_actions()
	for action in ["aim_left", "aim_right", "fire", "advance", "scout_left", "scout_right", "menu", "backdrop_toggle"]:
		assert_true(InputMap.has_action(action), action)

func test_ensure_actions_is_idempotent():
	GameInput.ensure_actions()
	GameInput.ensure_actions()
	assert_true(InputMap.has_action("fire"))
