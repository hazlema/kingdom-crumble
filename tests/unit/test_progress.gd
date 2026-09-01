extends GutTest

const TEST_PATH := "user://test_progress.cfg"

func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path(TEST_PATH)

func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path("user://progress.cfg")

func test_absent_file_means_nothing_cleared() -> void:
	assert_false(Progress.is_cleared("chill", "pineapple"))

func test_clear_round_trips_through_disk() -> void:
	Progress.mark_cleared("chill", "pineapple")
	assert_true(Progress.is_cleared("chill", "pineapple"))
	Progress.use_path(TEST_PATH)
	assert_true(Progress.is_cleared("chill", "pineapple"), "survives reload")

func test_tiers_are_separate_dimensions() -> void:
	Progress.mark_cleared("chill", "pineapple")
	assert_false(Progress.is_cleared("hardcore", "pineapple"))
	assert_false(Progress.is_cleared("chill", "watermelon"))
