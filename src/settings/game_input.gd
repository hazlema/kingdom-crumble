extends Node

const BINDINGS := {
	"aim_left": [KEY_LEFT, KEY_A],
	"aim_right": [KEY_RIGHT, KEY_D],
	"fire": [KEY_SPACE],
	"advance": [KEY_ENTER],
	"scout_left": [KEY_COMMA, KEY_Q],
	"scout_right": [KEY_PERIOD, KEY_E],
	"menu": [KEY_ESCAPE],
	"jump_levels": [KEY_L, KEY_J],
	"check": [KEY_H],
	"backdrop_toggle": [KEY_B],
}


func _ready() -> void:
	ensure_actions()


static func ensure_actions() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for keycode in BINDINGS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = keycode
				InputMap.action_add_event(action, ev)
