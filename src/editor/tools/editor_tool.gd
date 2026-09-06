class_name EditorTool
extends RefCounted

# One interaction model. The editor owns the document, camera, and
# shared services; a tool owns ITS input state and nothing else.
# enter()/exit() are the ONLY places cross-mode state may be touched.

var ed: LevelEditor


func _init(editor: LevelEditor) -> void:
	ed = editor


func enter() -> void:
	pass


func exit() -> void:
	pass


# Called every frame from the editor's _process while active.
func process(_mouse: Vector2, _over_ui: bool) -> void:
	pass
