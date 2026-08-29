extends GutTest

func test_firing_always_grabs_camera():
	for m in [CameraDirector.Mode.AIM, CameraDirector.Mode.SCOUT]:
		assert_eq(CameraDirector.next_mode(m, "fired"), CameraDirector.Mode.FOLLOW)

func test_settle_returns_home():
	assert_eq(CameraDirector.next_mode(CameraDirector.Mode.FOLLOW, "settled"),
		CameraDirector.Mode.AIM)

func test_scout_only_from_aim():
	assert_eq(CameraDirector.next_mode(CameraDirector.Mode.AIM, "scout_input"),
		CameraDirector.Mode.SCOUT)
	assert_eq(CameraDirector.next_mode(CameraDirector.Mode.FOLLOW, "scout_input"),
		CameraDirector.Mode.FOLLOW)

func test_aim_input_snaps_back_from_scout():
	assert_eq(CameraDirector.next_mode(CameraDirector.Mode.SCOUT, "aim_input"),
		CameraDirector.Mode.AIM)
