extends GutTest

func before_each() -> void:
	EditorAssets.scan()

func test_finds_six_crates_sorted():
	var list := EditorAssets.crates()
	assert_eq(list.size(), 6)
	assert_eq(list[0]["id"], "crate-blue")  # alpha order
	assert_not_null(list[0]["texture"])

func test_sidecar_descriptions():
	for e in EditorAssets.crates():
		if e["id"] == "crate-gold":
			assert_string_contains(e["description"], "golden")

func test_texture_for():
	assert_not_null(EditorAssets.texture_for("crate-wood"))
	assert_null(EditorAssets.texture_for("crate-imaginary"))
