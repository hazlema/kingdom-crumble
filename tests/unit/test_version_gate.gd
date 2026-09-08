extends GutTest

# VersionGate: testing builds wipe tester progress on version change;
# release builds and fresh installs never delete anything.
# All paths sandboxed — the REAL progress/unlocks are never touched.

const DIR := "user://vgate_gut"
const STAMP := DIR + "/version.cfg"
var _files: Array[String] = [DIR + "/progress.cfg", DIR + "/unlocks.cfg"]


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for f in _files:
		var fa := FileAccess.open(f, FileAccess.WRITE)
		fa.store_string("[fake]\ndata=1\n")
		fa.close()


func after_each() -> void:
	for f in _files + [STAMP]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_fresh_install_never_wipes() -> void:
	var wiped := VersionGate.apply("1.0", true, _files, STAMP)
	assert_false(wiped, "no prior stamp = fresh install, nothing to wipe")
	assert_true(FileAccess.file_exists(_files[0]))


func test_testing_build_wipes_on_version_change() -> void:
	VersionGate.apply("1.0", true, _files, STAMP)
	var wiped := VersionGate.apply("1.1", true, _files, STAMP)
	assert_true(wiped, "version changed under testing")
	assert_false(FileAccess.file_exists(_files[0]), "progress wiped")
	assert_false(FileAccess.file_exists(_files[1]), "unlocks wiped")


func test_same_version_keeps_files() -> void:
	VersionGate.apply("1.0", true, _files, STAMP)
	assert_false(VersionGate.apply("1.0", true, _files, STAMP))
	assert_true(FileAccess.file_exists(_files[0]))


func test_release_build_never_wipes() -> void:
	VersionGate.apply("1.0", false, _files, STAMP)
	var wiped := VersionGate.apply("2.0", false, _files, STAMP)
	assert_false(wiped, "unchecked box = players keep progress across updates")
	assert_true(FileAccess.file_exists(_files[0]))
	# and flipping testing ON later still compares against the recorded 2.0
	assert_false(VersionGate.apply("2.0", true, _files, STAMP))
