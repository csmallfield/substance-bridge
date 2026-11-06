@tool
extends VBoxContainer
## Minimal dock: pick an .sbsar, size and seed, render it off the main thread, build a
## StandardMaterial3D and apply it to the selected MeshInstance3D nodes (undoable).
## Parameters are the graph defaults for now; the generated inspector comes in phase 3.

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const Task := preload("res://addons/substance_bridge/core/task.gd")
const SubstanceBackend := preload("res://addons/substance_bridge/backends/substance/substance_backend.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")
const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")

const SIZES := [["512", 9], ["1K", 10], ["2K", 11], ["4K", 12]]
const LAST_SBSAR_META := "substance_bridge_last_sbsar"

var undo_redo: EditorUndoRedoManager

var _sbsar_edit: LineEdit
var _size_option: OptionButton
var _seed_spin: SpinBox
var _apply_button: Button
var _status: Label
var _log: TextEdit
var _file_dialog: EditorFileDialog
var _busy := false


func _init() -> void:
	name = "Substance Bridge"
	custom_minimum_size = Vector2(220, 0)

	var src_row := HBoxContainer.new()
	_sbsar_edit = LineEdit.new()
	_sbsar_edit.placeholder_text = ".sbsar file"
	_sbsar_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var browse := Button.new()
	browse.text = "..."
	browse.tooltip_text = "Choose an .sbsar file"
	browse.pressed.connect(_on_browse)
	src_row.add_child(_sbsar_edit)
	src_row.add_child(browse)
	add_child(_labeled("Graph", src_row))

	_size_option = OptionButton.new()
	for s in SIZES:
		_size_option.add_item(s[0])
	_size_option.select(1)
	add_child(_labeled("Size", _size_option))

	_seed_spin = SpinBox.new()
	_seed_spin.max_value = 99999
	_seed_spin.rounded = true
	add_child(_labeled("Seed", _seed_spin))

	_apply_button = Button.new()
	_apply_button.text = "Render and Apply to Selected"
	_apply_button.pressed.connect(_on_apply_pressed)
	add_child(_apply_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_log = TextEdit.new()
	_log.editable = false
	_log.custom_minimum_size = Vector2(0, 160)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_log)


func _ready() -> void:
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.sbsar", "Substance archive")
	_file_dialog.file_selected.connect(func(path: String) -> void: _sbsar_edit.text = path)
	add_child(_file_dialog)
	var last: Variant = EditorInterface.get_editor_settings().get_project_metadata(
			"substance_bridge", LAST_SBSAR_META, "")
	_sbsar_edit.text = String(last)


func set_status(text: String) -> void:
	_status.text = text


func log_line(text: String) -> void:
	_log.text += text + "\n"
	_log.scroll_vertical = _log.get_line_count()
	print("[Substance Bridge] ", text)


func _labeled(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 48
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	return row


func _on_browse() -> void:
	if not _sbsar_edit.text.is_empty():
		_file_dialog.current_dir = _sbsar_edit.text.get_base_dir()
	_file_dialog.popup_file_dialog()


func _on_apply_pressed() -> void:
	if _busy:
		return
	var targets: Array[MeshInstance3D] = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is MeshInstance3D:
			targets.append(node)
	if targets.is_empty():
		set_status("Select one or more MeshInstance3D nodes first.")
		return
	var sbsar := _sbsar_edit.text.strip_edges()
	EditorInterface.get_editor_settings().set_project_metadata("substance_bridge", LAST_SBSAR_META, sbsar)

	var size_log2: int = SIZES[_size_option.selected][1]
	var job := await render_and_build(sbsar, Vector2i(size_log2, size_log2), int(_seed_spin.value))
	if job.has("material"):
		apply_material(job["material"], targets)


## Full pipeline: render on a worker thread, then import and build on the main thread.
## Returns {"material": StandardMaterial3D, "result": RenderResult} or {"error": String}.
## Also used by the self-test.
func render_and_build(sbsar: String, size_log2: Vector2i, random_seed: int) -> Dictionary:
	if not FileAccess.file_exists(sbsar):
		set_status("Choose an existing .sbsar file.")
		return {"error": "missing sbsar"}
	var config := Settings.snapshot()
	var backend := SubstanceBackend.new(config)
	var problems := backend.check_available()
	if not problems.is_empty():
		set_status("; ".join(problems))
		return {"error": "; ".join(problems)}

	var mat_name := "%s_s%d" % [sbsar.get_file().get_basename().validate_filename(), random_seed]
	var request := RenderRequest.new()
	request.source = sbsar
	request.size_log2 = size_log2
	request.random_seed = random_seed
	request.output_dir = String(config["cache_dir"]).path_join("renders").path_join(mat_name)

	_set_busy(true)
	set_status("Rendering %s at %d px..." % [sbsar.get_file(), 1 << size_log2.x])
	var task := Task.new()
	task.start(func() -> RenderResult: return backend.render(request))
	var result: RenderResult = await task.finished
	for cmd in result.commands:
		log_line(cmd)
	for w in result.warnings:
		log_line("warning: " + w)
	if not result.is_ok():
		_set_busy(false)
		for e in result.errors:
			log_line("ERROR: " + e)
		set_status("Render failed. See the log below.")
		return {"error": "; ".join(result.errors), "result": result}
	log_line("Rendered %d maps in %.2f s: %s" % [result.maps.size(), result.duration_ms / 1000.0,
			", ".join(PackedStringArray(result.maps.keys()))])

	set_status("Importing maps and building the material...")
	var builder := MaterialBuilder.new()
	var mat := await builder.build(result, String(config["output_folder"]), mat_name)
	for line in builder.log_lines:
		log_line(line)
	_set_busy(false)
	if mat == null:
		set_status("Building the material failed. See the log below.")
		return {"error": "material build failed", "result": result}
	set_status("Done: %s" % mat.resource_path)
	return {"material": mat, "result": result}


func apply_material(mat: Material, targets: Array[MeshInstance3D]) -> void:
	undo_redo.create_action("Apply Substance material")
	var count := 0
	for mi in targets:
		if not is_instance_valid(mi):
			continue
		undo_redo.add_do_property(mi, "material_override", mat)
		undo_redo.add_undo_property(mi, "material_override", mi.material_override)
		count += 1
	undo_redo.commit_action()
	log_line("Applied to %d mesh(es)." % count)


func _set_busy(busy: bool) -> void:
	_busy = busy
	_apply_button.disabled = busy
