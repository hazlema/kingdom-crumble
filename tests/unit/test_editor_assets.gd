extends GutTest


func before_each() -> void:
	EditorAssets.scan()


func test_finds_six_crates_sorted():
	var list := EditorAssets.crates()
	assert_eq(list.size(), 6)
	assert_eq(list[0]["id"], "crate-blue")  # alpha order
	assert_not_null(list[0]["texture"])


func test_sidecar_descriptions():
	var found_descriptions := {}
	for e in EditorAssets.crates():
		found_descriptions[e["id"]] = e["description"]

	assert_string_contains(found_descriptions.get("crate-wood", ""), "Plain wooden")
	assert_string_contains(found_descriptions.get("crate-gold", ""), "refunded")
	assert_string_contains(found_descriptions.get("crate-blue", ""), "three stones")
	assert_string_contains(found_descriptions.get("crate-green", ""), "bounces")
	assert_string_contains(found_descriptions.get("crate-ghost", ""), "mystery")
	assert_string_contains(found_descriptions.get("skull", ""), "explodes")


func test_texture_for():
	assert_not_null(EditorAssets.texture_for("crate-wood"))
	assert_null(EditorAssets.texture_for("crate-imaginary"))
