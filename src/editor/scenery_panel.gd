class_name SceneryPanel
extends PanelContainer

signal background_picked(id: String)
signal image_chosen(path: String)
signal done

const BACKGROUNDS: Array[String] = ["meadow"]

var _file_dialog: FileDialog


func _ready() -> void:
	for bg in BACKGROUNDS:
		%BackgroundList.add_item(bg)
	%BackgroundList.item_selected.connect(
		func(i: int) -> void: background_picked.emit(%BackgroundList.get_item_text(i))
	)
	%AddImageBtn.pressed.connect(_open_file_dialog)
	%DoneBtn.pressed.connect(func() -> void: done.emit())

	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = false
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Images"])
	_file_dialog.file_selected.connect(func(path: String) -> void: image_chosen.emit(path))
	add_child(_file_dialog)
	_tame_path_dropdown(_file_dialog)


# FileDialog's internal path dropdown sizes itself to its LONGEST entry
# (fit_to_longest_item), so one deep dev path makes the whole window's
# minimum width wider than the monitor — no popup call can override a
# content minimum. Clip the button text; the dropdown list still shows
# full paths when opened.
func _tame_path_dropdown(node: Node) -> bool:
	if node is OptionButton:
		node.fit_to_longest_item = false
		node.clip_text = true
		return true
	for child in node.get_children(true):
		if _tame_path_dropdown(child):
			return true
	return false


func _open_file_dialog() -> void:
	if OS.has_feature("web"):
		_web_pick_via_js()
		return
	# Clamped, because FileDialog happily grows past the screen edge to
	# fit long filenames — 940x640 wanted, never more than 80% of screen.
	_file_dialog.popup_centered_clamped(Vector2i(940, 640), 0.8)


# The browser guards the real disk and Godot's web backend has no native
# dialog — so we spawn the browser's OWN <input type=file>, read the
# bytes in JS, and hand them across the bridge. Must run inside the
# button-press (user gesture) or the browser vetoes the click().
var _js_pick_cb: JavaScriptObject  # held so it isn't garbage-collected


func _web_pick_via_js() -> void:
	_js_pick_cb = JavaScriptBridge.create_callback(_on_js_file)
	var window := JavaScriptBridge.get_interface("window")
	window.kcPickCallback = _js_pick_cb
	JavaScriptBridge.eval(
		"""
		(function(){
			const inp = document.createElement('input');
			inp.type = 'file';
			inp.accept = '.png,.jpg,.jpeg,.webp';
			inp.onchange = function(e){
				const f = e.target.files[0];
				if(!f) return;
				const r = new FileReader();
				r.onload = function(){
					const b = new Uint8Array(r.result);
					let bin = '';
					const chunk = 0x8000;
					for(let i = 0; i < b.length; i += chunk){
						bin += String.fromCharCode.apply(null, b.subarray(i, i + chunk));
					}
					window.kcPickCallback(f.name, btoa(bin));
				};
				r.readAsArrayBuffer(f);
			};
			inp.click();
		})();
		""",
		true
	)


func _on_js_file(args: Array) -> void:
	if args.size() < 2:
		return
	var fname := str(args[0])
	var bytes := Marshalls.base64_to_raw(str(args[1]))
	if bytes.is_empty():
		return
	# Land it in the sandbox with its real extension (load_from_file
	# sniffs format by extension), then the normal pipeline eats it.
	var ext := fname.get_extension().to_lower()
	if not ext in ["png", "jpg", "jpeg", "webp"]:
		return
	var tmp := "user://web_import_tmp.%s" % ext
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	image_chosen.emit(tmp)
