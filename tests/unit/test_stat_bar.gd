extends GutTest

const BAR := preload("res://scenes/ui/stat_bar.tscn")

func test_value_clamps():
	var bar: StatBar = add_child_autofree(BAR.instantiate())
	bar.value = 1.7
	assert_eq(bar.value, 1.0)
	bar.value = -0.3
	assert_eq(bar.value, 0.0)

func test_icon_export_applies():
	var bar: StatBar = add_child_autofree(BAR.instantiate())
	var tex := PlaceholderTexture2D.new()
	bar.icon = tex
	assert_eq(bar.get_node("%Icon").texture, tex)
