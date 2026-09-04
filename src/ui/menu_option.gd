extends Control
signal MenuOptionSelected(option_text: String)

@export var lbl: String = "Enter Name":
	set(value):
		lbl = value
		if is_node_ready():
			$btnLabel.text = value

func _ready() -> void:
	$btnLabel.text = lbl
	$AnimatedSprite2D.frame = 0
	$btnLabel.mouse_entered.connect(func():
		$btnLabel.add_theme_font_size_override("font_size", 150)
		$AnimatedSprite2D.play()
		# A small celebration out of the crate. The instance is scaled way
		# down in the menu, so counter-scale the burst to world size or
		# the party is microscopic.
		var c := NarfConfetti.burst(self, $AnimatedSprite2D.position, 24)
		if scale.x > 0.0:
			c.scale = Vector2.ONE / scale.x
	)
	$btnLabel.mouse_exited.connect(func(): 
		$btnLabel.remove_theme_font_size_override("font_size")
		$btnLabel.add_theme_font_size_override("font_size", 130)
		$AnimatedSprite2D.play_backwards()
	)
	$btnLabel.button_down.connect(func(): 
		MenuOptionSelected.emit($btnLabel.text)
	)
