extends GutTest

const TEST_PATH := "user://test_unlocks.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Unlocks.use_path(TEST_PATH)


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Unlocks.use_path("user://unlocks.cfg")


func test_absent_file_means_no_flags() -> void:
	assert_false(Unlocks.has_flag("skunk"))


func test_flag_round_trips_through_disk() -> void:
	Unlocks.set_flag("skunk")
	assert_true(Unlocks.has_flag("skunk"))
	Unlocks.use_path(TEST_PATH)
	assert_true(Unlocks.has_flag("skunk"), "flag survives a reload from disk")


func test_flags_are_independent() -> void:
	Unlocks.set_flag("skunk")
	assert_false(Unlocks.has_flag("dragon"))
