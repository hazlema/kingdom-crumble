extends GutTest

const TEST_PATH := "user://test_chain_progress.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path(TEST_PATH)


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Progress.use_path("user://progress.cfg")


func _fruit_chain() -> Array:
	# Ids are namespaced (audit: user aim.json vs builtin aim.json
	# used to share completion) -- the ledger speaks "user:apple".
	return [
		{"stem": "apple", "id": "user:apple", "path": "user://levels/apple.json", "title": "Apple"},
		{"stem": "pineapple", "id": "user:pineapple", "path": "user://levels/pineapple.json", "title": "Pineapple"},
		{"stem": "watermelon", "id": "user:watermelon", "path": "user://levels/watermelon.json", "title": "Watermelon"},
	]


func test_entries_structure_and_order() -> void:
	var chain := LevelChain.entries()
	assert_gt(chain.size(), 0, "chain should include the built-ins")
	var seen_user := false
	var prev_stem := ""
	for e in chain:
		assert_true(e.has("stem") and e.has("id") and e.has("path") and e.has("title") and e.has("thumb"))
		var is_user: bool = e["path"].begins_with("user://")
		if seen_user:
			assert_true(is_user, "built-ins never follow user levels")
		if is_user and not seen_user:
			seen_user = true
			prev_stem = ""
		if prev_stem != "":
			assert_true(e["stem"] >= prev_stem, "each block is alphabetical")
		prev_stem = e["stem"]


func test_first_level_always_unlocked() -> void:
	assert_true(LevelChain.is_unlocked(_fruit_chain(), 0, "chill"))


func test_pineapple_rule() -> void:
	var chain := _fruit_chain()
	assert_false(LevelChain.is_unlocked(chain, 1, "chill"), "apple uncleared locks pineapple")
	Progress.mark_cleared("chill", "user:apple")
	assert_true(
		LevelChain.is_unlocked(chain, 1, "chill"),
		"apple cleared unlocks pineapple — even inserted later"
	)
	assert_false(
		LevelChain.is_unlocked(chain, 1, "hardcore"), "per-tier: hardcore pineapple stays locked"
	)


func test_frontier() -> void:
	var chain := _fruit_chain()
	assert_eq(LevelChain.frontier(chain, "chill"), 0, "fresh log starts at 0")
	Progress.mark_cleared("chill", "user:apple")
	assert_eq(LevelChain.frontier(chain, "chill"), 1)
	Progress.mark_cleared("chill", "user:pineapple")
	Progress.mark_cleared("chill", "user:watermelon")
	assert_eq(LevelChain.frontier(chain, "chill"), 2, "all cleared parks at last")


func test_next_index_after() -> void:
	var chain := _fruit_chain()
	assert_eq(LevelChain.next_index_after(chain, "user:apple"), 1)
	assert_eq(LevelChain.next_index_after(chain, "user:watermelon"), -1, "end of chain")
	assert_eq(LevelChain.next_index_after(chain, "user:durian"), -1, "unknown stem")


func test_frontier_of_empty_chain_is_minus_one() -> void:
	assert_eq(LevelChain.frontier([], "chill"), -1)
