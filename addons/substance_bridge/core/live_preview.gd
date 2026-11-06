@tool
extends RefCounted
## Live preview for backends that render into memory (supports_live(), the noise lab).
##
## request(gs) renders gs at its preview size and puts the images straight into its material
## as ImageTextures: no files, no import, so the mesh follows a slider drag within a frame or
## two. Requests that arrive while one renders are coalesced: only the latest settings render
## next. The material is only changed in memory; the normal file render (Pipeline.render)
## writes the maps, imports them and puts the imported textures back.

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")
const Backends := preload("res://addons/substance_bridge/backends/backends.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")

## Emitted after each live update: the settings, the milliseconds it took, and an error ("" if none).
signal updated(gs: GraphSettings, msec: int, error: String)

var _running := false
var _next: GraphSettings


## True when gs can be previewed live.
static func supports(gs: GraphSettings) -> bool:
	if gs == null or gs.material == null:
		return false
	return Backends.create(gs.backend_id, Settings.snapshot()).supports_live()


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
	var backend := Backends.create(gs.backend_id, Settings.snapshot())
	var req := RenderRequest.new()
	req.source = gs.source
	req.description = gs.get_description()
	req.values = gs.values.duplicate(true)
	req.random_seed = gs.random_seed
	req.size_log2 = Vector2i(gs.preview_size, gs.preview_size)
	var out: Dictionary = await backend.generate_images(req, true)
	var mat := gs.material
	if not out["errors"].is_empty() or mat == null:
		updated.emit(gs, Time.get_ticks_msec() - started, "; ".join(out["errors"]) if mat else "no material")
		return
	for usage in MaterialBuilder.WIRED_USAGES:
		if out.has(usage):
			apply(mat, usage, out[usage])
	updated.emit(gs, Time.get_ticks_msec() - started, "")


## Puts an image into a material slot, reusing the slot's ImageTexture when it matches.
static func apply(mat: StandardMaterial3D, usage: String, image: Image) -> void:
	image.generate_mipmaps()
	var current := _slot_texture(mat, usage)
	if current is ImageTexture and current.get_size() == Vector2(image.get_size()) \
			and (current as ImageTexture).get_format() == image.get_format():
		(current as ImageTexture).update(image)
		return
	MaterialBuilder._assign(mat, usage, ImageTexture.create_from_image(image))


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
