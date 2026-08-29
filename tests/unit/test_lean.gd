extends GutTest

func test_lean_band():
	assert_false(Lean.is_lean_angle(deg_to_rad(10)))   # basically upright
	assert_true(Lean.is_lean_angle(deg_to_rad(15)))
	assert_true(Lean.is_lean_angle(deg_to_rad(-40)))
	assert_true(Lean.is_lean_angle(deg_to_rad(75)))
	assert_false(Lean.is_lean_angle(deg_to_rad(80)))   # basically fallen

func test_ledger_pays_once_per_pair_either_order():
	var ledger := LeanLedger.new()
	assert_true(ledger.claim(7, 3))
	assert_false(ledger.claim(3, 7))
	assert_true(ledger.claim(7, 4))

func test_pair_key_is_order_independent():
	assert_eq(LeanLedger.pair_key(9, 2), LeanLedger.pair_key(2, 9))
