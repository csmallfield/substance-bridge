@tool
extends Node
## Renders library entries: the graph's maps into an in-memory StandardMaterial3D, and a
## sphere thumbnail of it. Nothing is written to the project; maps go to the editor cache.
##
## Graphs that take mesh maps (AO, curvature, ...) get them baked from the preview sphere
## with the native baker, so edge effects show. One render runs at a time (run()).
##
## Smart materials (.spsm) render the same way (their layer stack is built into maps on the
## sphere, spsm/spsm_renderer.gd); their thumbnail is Painter's own preview when the file has
## one, which saves a full render per file while the library fills in.

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")
const Pipeline := preload("res://addons/substance_bridge/core/pipeline.gd")
const LivePreview := preload("res://addons/substance_bridge/core/live_preview.gd")
const Library := preload("res://addons/substance_bridge/library/library.gd")
const PreviewStage := preload("res://addons/substance_bridge/library/preview_stage.gd")
const SpsmDocument := preload("res://addons/substance_bridge/spsm/spsm_document.gd")

## Thumbnail maps: 256 is plenty for a 256 px sphere.
const THUMB_SIZE_LOG2 := 8
## Preview maps for the large view.
const PREVIEW_SIZE_LOG2 := 9

var pipeline := Pipeline.new()

var _live := LivePreview.new()
var _viewport: SubViewport
var _stage: PreviewStage
var _bake_mesh: MeshInstance3D
var _busy := false
## Settings per .sbsar path (described once per session).
var _settings := {}
## Smart materials per .spsm path: [modified time, SpsmDocument].
var _spsm := {}


func _init() -> void:
	_live.pipeline = pipeline
	pipeline.log_callback = func(_line: String) -> void: pass  # library renders stay quiet

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(Library.THUMB_SIZE, Library.THUMB_SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = PreviewStage.new(true)
	_viewport.add_child(_stage)

	# Mesh-driven graphs bake their maps from this sphere (same mesh as the preview sphere).
	_bake_mesh = MeshInstance3D.new()
	_bake_mesh.name = "Library sphere"
	# The OBJ export needs an ArrayMesh; same vertices and UVs as the stage's SphereMesh.
	var sphere := _stage.model.mesh as PrimitiveMesh
	var arrays := ArrayMesh.new()
	arrays.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	_bake_mesh.mesh = arrays
	_bake_mesh.visible = false
	add_child(_bake_mesh)


func is_busy() -> bool:
	return _busy


## Settings for a library file, described (waits for the description the first time).
func settings_for(path: String) -> GraphSettings:
	var gs: GraphSettings = _settings.get(path)
	if gs == null:
		gs = GraphSettings.new()
		gs.output_name = "library_" + path.md5_text().substr(0, 10)
		gs.source = path  # starts describing on a worker thread
		_settings[path] = gs
	if gs.get_description() == null:
		await gs.description_loaded
	return gs


## A smart material, read once per session (again if the file changes).
func spsm_for(path: String) -> SpsmDocument:
	var stamp := FileAccess.get_modified_time(path)
	var cached: Array = _spsm.get(path, [])
	if cached.is_empty() or cached[0] != stamp:
		cached = [stamp, SpsmDocument.open(path)]
		_spsm[path] = cached
	return cached[1]


## Renders an entry's maps at size_log2 into a new material.
## Returns {"material": StandardMaterial3D, "outputs": [...], "settings": GraphSettings,
## "mesh_driven": bool, "msec": int, "error": String ("" if none)}. A smart material also has
## "spsm" (its SpsmDocument) and "painter_preview" (Painter's own preview Image, or null).
func render(path: String, size_log2: int) -> Dictionary:
	while _busy:
		await get_tree().process_frame
	_busy = true
	var started := Time.get_ticks_msec()
	var out := await _render(path, size_log2)
	out["msec"] = Time.get_ticks_msec() - started
	_busy = false
	return out


func _render(path: String, size_log2: int) -> Dictionary:
	var result := {"material": null, "outputs": [], "settings": null, "mesh_driven": false, "error": ""}
	if path.get_extension().to_lower() == "spsm":
		var doc := spsm_for(path)
		result["spsm"] = doc
		result["painter_preview"] = doc.preview_image() if doc.is_ok() else null
		if not doc.is_ok():
			result["error"] = "; ".join(doc.errors)
			await get_tree().process_frame  # finish on a later frame, like a real render
			return result
	var gs := await settings_for(path)
	result["settings"] = gs
	if not gs.is_described():
		result["error"] = "; ".join(gs.get_description().errors)
		return result
	if not gs.mesh_usages().is_empty():
		result["mesh_driven"] = true
		if gs.mesh_obj.is_empty():
			gs.baker = GraphSettings.BAKER_NATIVE
			gs.bake_size = 10
			var err: String = await pipeline.set_mesh(gs, _bake_mesh)
			if not err.is_empty():
				result["error"] = err
				return result
	var config := Settings.snapshot()
	var dir := String(config["cache_dir"]).path_join("library").path_join("%s_%d" % [gs.output_name, size_log2])
	var maps: Dictionary = await _live._render_files(gs, config, size_log2, dir)
	if not maps["errors"].is_empty():
		result["error"] = "; ".join(maps["errors"])
		return result
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	LivePreview.apply_outputs(mat, {}, maps["outputs"], gs.output_name)
	result["material"] = mat
	result["outputs"] = maps["outputs"]
	return result


## Renders a thumbnail for an entry and saves it to entry["thumb"]. Returns an error or "".
func make_thumbnail(entry: Dictionary) -> String:
	var img: Image = null
	if entry.get("kind") == "spsm":
		var doc := spsm_for(entry["path"])
		img = doc.preview_image() if doc.is_ok() else null
	if img != null:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		img.resize(Library.THUMB_SIZE, Library.THUMB_SIZE, Image.INTERPOLATE_LANCZOS)
		await get_tree().process_frame
	else:
		var out: Dictionary = await render(entry["path"], THUMB_SIZE_LOG2)
		if not String(out["error"]).is_empty():
			return out["error"]
		img = await capture(out["material"], out["mesh_driven"])
	if img == null:
		return "The thumbnail render came back empty"
	DirAccess.make_dir_recursive_absolute(String(entry["thumb"]).get_base_dir())
	var err := img.save_png(entry["thumb"])
	return "" if err == OK else "Could not save %s: %s" % [entry["thumb"], error_string(err)]


## Draws the sphere with mat once and returns the image (transparent background).
func capture(mat: StandardMaterial3D, mesh_driven: bool) -> Image:
	# The thumbnail repeats like the large preview, but on its own copy of the material.
	var m := mat.duplicate() as StandardMaterial3D
	_stage.mesh_driven = mesh_driven
	_stage.set_shape(PreviewStage.Shape.SPHERE)
	_stage.set_material(m)
	# The editor's low-processor mode only draws when something changes: draw every frame
	# while capturing, or frame_post_draw may never come.
	var low_processor := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var deadline := Time.get_ticks_msec() + 10000
	var frames := 0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Two drawn frames: the first can still show the cleared target on some drivers.
	while frames < 2 and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		frames += 1
		if frames == 1:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	OS.low_processor_usage_mode = low_processor
	var img := _viewport.get_texture().get_image() if frames >= 2 else null
	_stage.set_material(null)
	return img
