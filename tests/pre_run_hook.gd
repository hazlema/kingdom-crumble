extends GutHookScript

# Suite-wide: suppress level intros (their tree-pause deadlocks physics
# awaits — see Level.suppress_intro). test_intro_dialog re-enables.


func run() -> void:
	Level.suppress_intro = true
	# Suite-wide: seams fire during every gameplay test — point Deeds at a
	# scratch cfg so runs never pollute the developer's REAL save (review
	# catch). Deeds tests that need their own sandbox re-point and restore.
	Deeds.cfg_path = "user://gut_deeds_scratch.cfg"
	if FileAccess.file_exists(Deeds.cfg_path):
		DirAccess.remove_absolute(Deeds.cfg_path)
	Deeds.reload()
