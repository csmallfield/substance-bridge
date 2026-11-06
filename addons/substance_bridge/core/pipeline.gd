@tool
extends RefCounted
## Renders a GraphSettings resource and updates its material. Main thread only: the
## render itself runs on a worker thread, the import and material work on the main thread.
##
## Renders are skipped when nothing that affects the maps changed (GraphSettings.render_key).

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const Task := preload("res://addons/substance_bridge/core/task.gd")
const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")
const Backends := preload("res://addons/substance_bridge/backends/backends.gd")
const TextureBackend := preload("res://addons/substance_bridge/backends/texture_backend.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")
const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")
const MeshBaker := preload("res://addons/substance_bridge/backends/substance/mesh_baker.gd")
const ObjWriter := preload("res://addons/substance_bridge/core/obj_writer.gd")

const SETTINGS_META := "substance_bridge_settings"

## Receives log lines (String). Optional.
var log_callback: Callable


## Creates a GraphSettings resource for an .sbsar, saved under the output folder with a
## unique name. Returns null if it could not be saved.
func create_settings(sbsar: String, random_seed: int = 0) -> GraphSettings:
	var gs := GraphSettings.new()
	gs.random_seed = random_seed
	gs.source = sbsar
	return _save_new(gs, sbsar.get_file().get_basename().validate_filename())


## A variant: a copy of gs (same .sbsar, values, mesh and sizes) with another seed, saved
## under its own name ("<name>_seed<seed>"). Returns null if it could not be saved.
func duplicate_settings(gs: GraphSettings, random_seed: int) -> GraphSettings:
	var v := GraphSettings.new()
	v.source = gs.source
	v.values = gs.values.duplicate(true)
	v.random_seed = random_seed
	v.preview_size = gs.preview_size
	v.final_size = gs.final_size
	v.bake_size = gs.bake_size
	v.auto_preview = gs.auto_preview
	v.mesh_obj = gs.mesh_obj
	v.baked_mesh = gs.baked_mesh
	var base := gs.output_name
	var m := RegEx.create_from_string("_seed\\d+$").search(base)
	if m:
		base = base.substr(0, m.get_start())
	return _save_new(v, "%s_seed%d" % [base, random_seed])


func _save_new(gs: GraphSettings, base: String) -> GraphSettings:
	var folder := String(Settings.snapshot()["output_folder"])
	var name := base
	var n := 2
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder.path_join(name))):
		name = "%s_%d" % [base, n]
		n += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
	gs.output_name = name
	var path := folder.path_join(name).path_join(name + "_graph.tres")
	var err := ResourceSaver.save(gs, path)
	if err != OK:
		_log("Could not save %s: %s" % [path, error_string(err)])
		return null
	gs.take_over_path(path)
	EditorInterface.get_resource_filesystem().update_file(path)
	return gs


## Every graph settings file under a folder (res:// path), sorted.
static func find_all_settings(folder: String) -> PackedStringArray:
	var found := PackedStringArray()
	_find_settings(folder, found)
	found.sort()
	return found


static func _find_settings(dir: String, found: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with("_graph.tres"):
			found.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_find_settings(dir.path_join(d), found)


## Renders at size_log2 (e.g. 9 = 512) and builds/updates the material.
## force: render even if nothing changed, and re-bake mesh maps instead of using the cache.
## Returns {"material": StandardMaterial3D, "skipped": bool, "seconds": float} or {"error": String}.
func render(gs: GraphSettings, size_log2: int, force: bool = false) -> Dictionary:
	var key := gs.render_key(size_log2)
	if not force and key == gs.last_render_key and gs.material != null:
		return {"material": gs.material, "skipped": true, "seconds": 0.0}

	var config := Settings.snapshot()
	var backend := Backends.create(gs.backend_id, config)
	var problems := backend.check_available()
	if not problems.is_empty():
		return {"error": "; ".join(problems)}

	var request := RenderRequest.new()
	request.source = gs.source
	request.description = gs.get_description()  # may be null; described on the worker then
	request.values = gs.values.duplicate(true)
	request.random_seed = gs.random_seed
	request.size_log2 = Vector2i(size_log2, size_log2)
	request.output_dir = String(config["cache_dir"]).path_join("renders").path_join(gs.output_name)

	var mesh_obj := ProjectSettings.globalize_path(gs.mesh_obj) if not gs.mesh_obj.is_empty() else ""
	var bake_dir := String(config["cache_dir"]).path_join("bakes").path_join(
			"%s_%d" % [gs.mesh_obj.get_file().get_basename(), gs.bake_size])
	var bake_size := gs.bake_size
	var sbsbaker := String(config["sbsbaker"])

	var started := Time.get_ticks_msec()
	var result: RenderResult
	if backend.runs_on_main_thread():
		# GPU work inside the engine (noise lab): a coroutine on the main thread. No mesh maps.
		result = await backend.render(request)
	else:
		var task := Task.new()
		task.start(func() -> RenderResult:
			return _bake_and_render(backend, request, sbsbaker, mesh_obj, bake_size, bake_dir, force))
		result = await task.finished
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


## Worker thread: bakes the mesh maps the graph takes (cached), wires them to its image
## inputs by usage, then renders.
static func _bake_and_render(backend: TextureBackend, request: RenderRequest, sbsbaker: String,
		mesh_obj: String, bake_size: int, bake_dir: String, force_bake: bool = false) -> RenderResult:
	if request.description == null:
		request.description = backend.describe(request.source)
	var desc := request.description
	if desc.is_ok():
		var wanted := {}  # usage -> image input id
		for p in desc.image_inputs():
			for u: String in p.get("usages", PackedStringArray()):
				if u in MeshBaker.BAKERS and not wanted.has(u):
					wanted[u] = p["id"]
		if not wanted.is_empty():
			if mesh_obj.is_empty() or not FileAccess.file_exists(mesh_obj):
				var missing := RenderResult.new()
				missing.errors.append("This graph takes mesh maps (%s). Select the mesh and press \"Bake from Selected Mesh\"."
						% ", ".join(PackedStringArray(wanted.keys())))
				return missing
			var baked := MeshBaker.bake(sbsbaker, mesh_obj, PackedStringArray(wanted.keys()), bake_size,
					bake_dir, true, force_bake)
			if not baked["errors"].is_empty():
				var failed := RenderResult.new()
				failed.commands.append_array(baked["commands"])
				failed.errors.append_array(baked["errors"])
				return failed
			for u: String in baked["maps"]:
				request.image_inputs[wanted[u]] = baked["maps"][u]
			var result := backend.render(request)
			var note := "Mesh maps %s: %s" % [
					"baked in %.1f s" % baked["seconds"] if baked["baked"] > 0 else "from cache",
					", ".join(PackedStringArray(baked["maps"].keys()))]
			var commands := PackedStringArray(baked["commands"])
			commands.append(note)
			commands.append_array(result.commands)
			result.commands = commands
			return result
	return backend.render(request)


## Exports a MeshInstance3D's mesh as OBJ into the cache and points the settings at it.
## Returns an error message, or "".
func set_mesh(gs: GraphSettings, mi: MeshInstance3D) -> String:
	if mi == null or mi.mesh == null:
		return "Select a MeshInstance3D with a mesh."
	var surfaces := ObjWriter.collect_arrays(mi.mesh)
	var vertex_count := 0
	for s: Dictionary in surfaces:
		vertex_count += (s["vertices"] as PackedVector3Array).size()
	var cache_dir := ProjectSettings.globalize_path("user://substance_bridge/meshes")
	var task := Task.new()
	task.start(func() -> Dictionary:
		DirAccess.make_dir_recursive_absolute(cache_dir)
		var tmp := cache_dir.path_join("export_%d.obj" % Time.get_ticks_usec())
		var err := ObjWriter.write(surfaces, tmp)
		if not err.is_empty():
			return {"error": err}
		var md5 := FileAccess.get_md5(tmp)
		var final := cache_dir.path_join(md5 + ".obj")
		if FileAccess.file_exists(final):
			DirAccess.remove_absolute(tmp)
		else:
			DirAccess.rename_absolute(tmp, final)
		return {"md5": md5})
	var r: Dictionary = await task.finished
	if r.has("error"):
		return r["error"]
	gs.baked_mesh = "%s (%d vertices)" % [mi.name, vertex_count]
	gs.mesh_obj = "user://substance_bridge/meshes/%s.obj" % r["md5"]
	if not gs.resource_path.is_empty():
		ResourceSaver.save(gs, gs.resource_path)
	_log("Mesh for baking: %s" % gs.baked_mesh)
	return ""


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
