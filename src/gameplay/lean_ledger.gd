class_name LeanLedger
extends RefCounted

var _paid := {}

static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

func claim(a_id: int, b_id: int) -> bool:
	var key := pair_key(a_id, b_id)
	if _paid.has(key):
		return false
	_paid[key] = true
	return true
