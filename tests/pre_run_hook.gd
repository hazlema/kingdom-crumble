extends GutHookScript

# Suite-wide: suppress level intros (their tree-pause deadlocks physics
# awaits — see Level.suppress_intro). test_intro_dialog re-enables.


func run() -> void:
	Level.suppress_intro = true
