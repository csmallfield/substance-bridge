@tool
extends RefCounted
## Live preview: follows parameter edits by putting freshly rendered maps straight into the
## material as ImageTextures (no import), and reports every output for the 2D preview panel.
##
## - Backends that render into memory (supports_live(), the noise lab) render at the preview
##   size, about 0.15 s at 512.
## - Others (Substance) render at LIVE_SIZE_LOG2 with the CPU engine, which starts fastest
##   (about 0.55 s at 256), into a cache folder whose PNGs are loaded directly.
##
## Requests that arrive while one renders are coalesced: only the latest settings render
## next. The material only changes in memory; the normal render (Pipeline.render) writes and
## imports the maps and puts the imported textures back.

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")
const Backends := preload("res://addons/substance_bridge/backends/backends.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")
const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")
const Routing := preload("res://addons/substance_bridge/material/routing.gd")

## Live size for backends that render to files (256). sbsrender's start-up dominates below it.
const LIVE_SIZE_LOG2 := 8
## sbsrender engine for live renders: the CPU engine starts faster than d3d11pc at small sizes.
const LIVE_ENGINE := "sse2"

## Emitted after each live update: the settings, the milliseconds it took, and an error ("" if none).
signal updated(gs: GraphSettings, msec: int, error: String)
## Every output of a live update, in the graph's order: [{label, usages, image: Image}].
signal outputs_ready(gs: GraphSettings, outputs: Array)

## Used for file-based backends (render_maps); set by the owner.
var pipeline: RefCounted

var _running := false
var _next: GraphSettings


## True when gs can be previewed live (it needs a material to update).
static func supports(gs: GraphSettings) -> bool:
	return gs != null and gs.material != null


func is_running() -> bool:
	return _running


## Renders gs live, now or right after the render in progress.
func request(gs: GraphSettings) -> void:
	_next = gs
	if _running:
		return
	_running = true
	while _next:
		var current := _next
		_next = null
		await _render_once(current)
	_running = false


func _render_once(gs: GraphSettings) -> void:
	var started := Time.get_ticks_msec()
	var config := Settings.snapshot()
	var backend := Backends.create(gs.backend_id, config)
	var out: Dictionary
	if backend.supports_live():
		out = await _render_in_memory(gs, backend)
	else:
		out = await _render_files(gs, config)
	var mat := gs.material
	if not out["errors"].is_empty() or mat == null:
		updated.emit(gs, Time.get_ticks_msec() - started, "; ".join(out["errors"]) if mat else "no material")
		return
	var plan := Routing.plan(gs.routes, out["outputs"])
	for s in Routing.SLOTS:
		var slot: String = s["id"]
		if String(gs.routes.get(slot, {}).get("source", "")) == "-":
			Routing.clear_slot(mat, slot)
		elif plan.has(slot):
			apply(mat, slot, Routing.transform(plan[slot]["output"]["image"], plan[slot], slot))
			Routing.apply_settings(mat, slot, gs.routes, plan[slot])
		elif Routing.is_generated(Routing.slot_texture(mat, slot), slot, mat.resource_path.get_base_dir(), gs.output_name):
			Routing.clear_slot(mat, slot)
	updated.emit(gs, Time.get_ticks_msec() - started, "")
	outputs_ready.emit(gs, out["outputs"])


## {"images": {usage: Image}, "outputs": [...], "errors": PackedStringArray}
func _render_in_memory(gs: GraphSettings, backend: RefCounted) -> Dictionary:
	var req := RenderRequest.new()
	req.source = gs.source
	req.description = gs.get_description()
	req.values = gs.values.duplicate(true)
	req.random_seed = gs.random_seed
	req.size_log2 = Vector2i(gs.preview_size, gs.preview_size)
	var res: Dictionary = await backend.generate_images(req, true)
	var images := {}
	var outputs := []
	for usage in res:
		if res[usage] is Image:
			images[usage] = res[usage]
			outputs.append({"id": usage, "label": String(usage).capitalize(), "usages": [usage], "image": res[usage]})
	return {"images": images, "outputs": outputs, "errors": res["errors"]}


func _render_files(gs: GraphSettings, config: Dictionary) -> Dictionary:
	config["engine"] = LIVE_ENGINE
	var dir := String(config["cache_dir"]).path_join("live").path_join(gs.output_name)
	var result: RenderResult = await pipeline.render_maps(gs, LIVE_SIZE_LOG2, config, dir, false, true)
	var out := {"images": {}, "outputs": [], "errors": result.errors}
	if not result.is_ok():
		return out
	var by_path := {}
	for o: Dictionary in result.outputs:
		var path := String(o.get("path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var img: Image = by_path.get(path)
		if img == null:
			img = Image.load_from_file(path)
			if img == null or img.is_empty():
				continue
			by_path[path] = img
		var usages: Array = Array(o.get("usages", []))
		if "normal" in usages and result.normal_convention == "directx":
			img = img.duplicate()
			flip_green(img)  # Godot expects OpenGL (Y+) normals
		for u in usages:
			if result.maps.get(u) == path:
				out["images"][u] = img
		var label := String(o.get("label", ""))
		out["outputs"].append({"id": String(o.get("id", "")), "label": label if label else String(o.get("id", "")), "usages": usages, "image": img})
	return out


## Puts an image into a material slot, reusing the slot's ImageTexture when it matches.
static func apply(mat: StandardMaterial3D, usage: String, image: Image) -> void:
	if not image.has_mipmaps():
		image = image.duplicate()
		image.generate_mipmaps()
	var current := _slot_texture(mat, usage)
	if current is ImageTexture and current.get_size() == Vector2(image.get_size()) \
			and (current as ImageTexture).get_format() == image.get_format():
		(current as ImageTexture).update(image)
		return
	MaterialBuilder._assign(mat, usage, ImageTexture.create_from_image(image))


## DirectX -> OpenGL normal map, in place.
static func flip_green(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	for i in range(1, data.size(), 4):
		data[i] = 255 - data[i]
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


static func _slot_texture(mat: StandardMaterial3D, usage: String) -> Texture2D:
	match usage:
		"baseColor", "diffuse": return mat.albedo_texture
		"normal": return mat.normal_texture
		"roughness": return mat.roughness_texture
		"metallic": return mat.metallic_texture
		"ambientOcclusion": return mat.ao_texture
		"emissive": return mat.emission_texture
		"height": return mat.heightmap_texture
	return null
