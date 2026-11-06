@tool
extends RefCounted
## Renders a GraphSettings resource and updates its material. Main thread only: the
## render itself runs on a worker thread, the import and material work on the main thread.
##
## Renders are skipped when nothing that affects the maps changed (GraphSettings.render_key).

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const Task := preload("res://addons/substance_bridge/core/task.gd")
const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")
const SubstanceBackend := preload("res://addons/substance_bridge/backends/substance/substance_backend.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")
const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")

const SETTINGS_META := "substance_bridge_settings"

## Receives log lines (String). Optional.
var log_callback: Callable


## Creates a GraphSettings resource for an .sbsar, saved under the output folder with a
## unique name. Returns null if it could not be saved.
func create_settings(sbsar: String, random_seed: int = 0) -> GraphSettings:
	var config := Settings.snapshot()
	var folder := String(config["output_folder"])
	var base := sbsar.get_file().get_basename().validate_filename()
	var name := base
	var n := 2
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder.path_join(name))):
		name = "%s_%d" % [base, n]
		n += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join(name)))

	var gs := GraphSettings.new()
	gs.output_name = name
	gs.random_seed = random_seed
	gs.source = sbsar
	var path := folder.path_join(name).path_join(name + "_graph.tres")
	var err := ResourceSaver.save(gs, path)
	if err != OK:
		_log("Could not save %s: %s" % [path, error_string(err)])
		return null
	gs.take_over_path(path)
	EditorInterface.get_resource_filesystem().update_file(path)
	return gs


## Renders at size_log2 (e.g. 9 = 512) and builds/updates the material.
## Returns {"material": StandardMaterial3D, "skipped": bool, "seconds": float} or {"error": String}.
func render(gs: GraphSettings, size_log2: int) -> Dictionary:
	var key := gs.render_key(size_log2)
	if key == gs.last_render_key and gs.material != null:
		return {"material": gs.material, "skipped": true, "seconds": 0.0}

	var config := Settings.snapshot()
	var backend := SubstanceBackend.new(config)
	var problems := backend.check_available()
	if not problems.is_empty():
		return {"error": "; ".join(problems)}

	var request := RenderRequest.new()
	request.source = gs.source
	request.description = gs.get_description()  # may be null; the backend then describes itself
	request.values = gs.values.duplicate(true)
	request.random_seed = gs.random_seed
	request.size_log2 = Vector2i(size_log2, size_log2)
	request.output_dir = String(config["cache_dir"]).path_join("renders").path_join(gs.output_name)

	var started := Time.get_ticks_msec()
	var task := Task.new()
	task.start(func() -> RenderResult: return backend.render(request))
	var result: RenderResult = await task.finished
	for cmd in result.commands:
		_log(cmd)
	for w in result.warnings:
		_log("warning: " + w)
	if not result.is_ok():
		for e in result.errors:
			_log("ERROR: " + e)
		return {"error": "; ".join(result.errors)}

	var builder := MaterialBuilder.new()
	var mat := await builder.build(result, String(config["output_folder"]), gs.output_name)
	for line in builder.log_lines:
		_log(line)
	if mat == null:
		return {"error": "Building the material failed"}

	# Link material -> settings so selecting a mesh finds its settings again.
	if mat.get_meta(SETTINGS_META, "") != gs.resource_path:
		mat.set_meta(SETTINGS_META, gs.resource_path)
		ResourceSaver.save(mat, mat.resource_path)
	gs.material = mat
	gs.last_render_key = key
	if not gs.resource_path.is_empty():
		ResourceSaver.save(gs, gs.resource_path)

	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	_log("%s at %s: render %.2f s, total %.2f s" % [gs.output_name, gs.size_name(size_log2),
			result.duration_ms / 1000.0, seconds])
	return {"material": mat, "skipped": false, "seconds": seconds}


## The GraphSettings that generated a material, or null.
static func settings_for_material(mat: Material) -> GraphSettings:
	if mat == null or not mat.has_meta(SETTINGS_META):
		return null
	var path := String(mat.get_meta(SETTINGS_META))
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as GraphSettings


func _log(line: String) -> void:
	if log_callback.is_valid():
		log_callback.call(line)
	else:
		print("[Substance Bridge] ", line)
