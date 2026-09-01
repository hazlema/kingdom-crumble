extends Control


func _ready():
	var error_time: Timer = Timer.new()
	add_child(error_time)
	error_time.start(5)
	error_time.timeout.connect(ohshit)


func ohshit():
	get_tree().quit(1)
