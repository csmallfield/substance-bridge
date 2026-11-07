@tool
extends EditorPlugin
## Substance Bridge: drives Adobe's Substance command-line tools from the editor.

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const Task := preload("res://addons/substance_bridge/core/task.gd")
const ToolRunner := preload("res://addons/substance_bridge/core/tool_runner.gd")
const Dock := preload("res://addons/substance_bridge/ui/bridge_dock.gd")
const PreviewPanel := preload("res://addons/substance_bridge/ui/preview_panel.gd")
const LibraryScreen := preload("res://addons/substance_bridge/library/library_screen.gd")

## The main-screen tab (next to 2D, 3D, Script, AssetLib).
const SCREEN_NAME := "Substance"

var _dock: Dock
var _preview: PreviewPanel
var _library: LibraryScreen
var _check_task: Task
var _selftest: RefCounted


func _enter_tree() -> void:
	Settings.register()
	_dock = Dock.new()
	_dock.undo_redo = get_undo_redo()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_preview = PreviewPanel.new()
	_preview.attach(_dock)
	add_control_to_bottom_panel(_preview, "Substance Preview")
	_library = LibraryScreen.new()
	_library.hide()
	EditorInterface.get_editor_main_screen().add_child(_library)
	_library.use_requested.connect(func(path: String) -> void:
		_dock.use_library_file(path)
		EditorInterface.set_main_screen_editor("3D"))
	_dock.library_requested.connect(func() -> void: EditorInterface.set_main_screen_editor(SCREEN_NAME))
	_check_tools()

	var tour := OS.get_environment("SUBSTANCE_BRIDGE_TOUR")
	if not tour.is_empty():
		# Screenshot tour for the tutorial site; held in a member like the self-test.
		_selftest = load("res://addons/substance_bridge/tests/tour.gd").new()
		_selftest.plugin = self
		_selftest.run.call_deferred(_dock, tour)
		return

	var library_test := OS.get_environment("SUBSTANCE_BRIDGE_LIBRARY")
	if not library_test.is_empty():
		_selftest = load("res://addons/substance_bridge/tests/library_test.gd").new()
		_selftest.plugin = self
		_selftest.run.call_deferred(_dock, library_test)
		return

	var selftest := OS.get_environment("SUBSTANCE_BRIDGE_SELFTEST")
	if not selftest.is_empty():
		# Held in a member: a deferred call does not keep a RefCounted alive.
		_selftest = load("res://addons/substance_bridge/tests/selftest.gd").new()
		_selftest.run.call_deferred(_dock, selftest)


func _exit_tree() -> void:
	if _library:
		_library.queue_free()
		_library = null
	if _preview:
		remove_control_from_bottom_panel(_preview)
		_preview.queue_free()
		_preview = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _library:
		_library.visible = visible
		if visible:
			_library.on_shown()


func _get_plugin_name() -> String:
	return SCREEN_NAME


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	for icon in ["MaterialPreviewSphere", "StandardMaterial3D"]:
		if theme.has_icon(icon, "EditorIcons"):
			return theme.get_icon(icon, "EditorIcons")
	return null


## Checks the configured tool paths, then asks each tool for its version on a worker thread.
func _check_tools() -> void:
	var config := Settings.snapshot()
	var missing := Settings.missing_tools(config)
	for m in missing:
		push_warning("Substance Bridge: " + m)
	_dock.set_status("Checking tools...")

	_check_task = Task.new()
	_check_task.finished.connect(_on_tools_checked.bind(missing))
	_check_task.start(func() -> PackedStringArray: return _tool_versions(config))


static func _tool_versions(config: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key in ["sbsrender", "sbsbaker"]:
		var path: String = config[key]
		if FileAccess.file_exists(path):
			var r := ToolRunner.run(path, PackedStringArray(["--version"]), PackedStringArray(), 20.0)
			lines.append("%s %s" % [key, r.stdout.strip_edges() if r.is_ok() else "FAILED: " + "; ".join(r.errors)])
	var seven: String = config["seven_zip"]
	if FileAccess.file_exists(seven):
		# 7z has no --version; its banner is the first non-empty line of plain `7z`.
		var r := ToolRunner.run(seven, PackedStringArray(), PackedStringArray(), 20.0)
		var banner := ""
		for line in r.stdout.split("\n", false):
			if line.strip_edges().begins_with("7-Zip"):
				banner = line.strip_edges().get_slice(":", 0).strip_edges()
				break
		lines.append("7-Zip: %s" % (banner if banner else "found"))
	return lines


func _on_tools_checked(lines: PackedStringArray, missing: PackedStringArray) -> void:
	_check_task = null
	if not is_instance_valid(_dock):
		return
	for line in lines:
		_dock.log_line(line)
	if missing.is_empty():
		_dock.set_status("Ready.")
	else:
		_dock.set_status("Missing tools: " + "; ".join(missing))
