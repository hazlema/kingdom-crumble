extends GutTest

func _fixed(v: float) -> Callable:
	return func() -> float: return v

func test_type_routing() -> void:
	assert_eq(PowerupRules.route("crate-wood", false, _fixed(0.0))["kind"], "none")
	assert_eq(PowerupRules.route("crate-gold", false, _fixed(0.0))["kind"], "refund")
	var skull := PowerupRules.route("skull", false, _fixed(0.0))
	assert_eq(skull["kind"], "buff")
	assert_eq(skull["buff"], &"exploding")
	assert_eq(PowerupRules.route("crate-blue", false, _fixed(0.0))["buff"], &"multishot")
	assert_eq(PowerupRules.route("crate-green", false, _fixed(0.0))["buff"], &"super_bounce")
	assert_eq(PowerupRules.route("mystery-type", false, _fixed(0.0))["kind"], "none")

func test_ghost_rolls_skunk_only_when_locked_and_lucky() -> void:
	assert_eq(PowerupRules.route("crate-ghost", false, _fixed(0.0))["kind"], "skunk")
	assert_ne(PowerupRules.route("crate-ghost", true, _fixed(0.0))["kind"], "skunk")
	assert_ne(PowerupRules.route("crate-ghost", false, _fixed(0.9))["kind"], "skunk")

func test_ghost_pool_reaches_all_four() -> void:
	var kinds := {}
	for v in [0.13, 0.38, 0.63, 0.88]:
		var r := PowerupRules.route("crate-ghost", true, _fixed(v))
		var key: String = r["label"] if r.has("label") else r["kind"]
		kinds[key] = true
	assert_eq(kinds.size(), 4, "four distinct outcomes across the roll range")

func test_drain_one_charge_per_type() -> void:
	var q: Array[StringName] = [&"exploding", &"exploding", &"multishot"]
	var d := PowerupRules.drain(q)
	assert_true(d["consumed"].has(&"exploding"))
	assert_true(d["consumed"].has(&"multishot"))
	assert_eq(d["consumed"].size(), 2)
	assert_eq(d["remaining"], [&"exploding"] as Array[StringName])

func test_drain_empty() -> void:
	var d := PowerupRules.drain([] as Array[StringName])
	assert_eq(d["consumed"].size(), 0)
	assert_eq(d["remaining"].size(), 0)
