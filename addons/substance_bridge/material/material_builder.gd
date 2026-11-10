@tool
extends RefCounted
## Builds a StandardMaterial3D from texture maps keyed by usage. Backend-agnostic: it
## only reads a RenderResult.
##
## Files are copied into <output_folder>/<name>/ as <name>_<usage>.png, imported, and the
## material is saved next to them as <name>.tres (updated in place on re-render, so
## scenes that use it pick up the change).
##
## Colour space: Godot 4 decodes albedo and emission as sRGB in the shader and samples
## every other slot (normal, roughness, metallic, AO, height) as linear, so all files are
## imported as-is. Only normal maps get special import settings: normal-map compression,
## and a green flip when the backend produced DirectX normals (Godot uses OpenGL, Y+).
##
## Must run on the main thread (it uses EditorInterface); build() awaits the import.

const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")
const Routing := preload("res://addons/substance_bridge/material/routing.gd")

## Usages wired into material slots, in the order they are applied.
const WIRED_USAGES := ["baseColor", "diffuse", "normal", "roughness", "metallic",
		"ambientOcclusion", "emissive", "height", "opacity"]

const IMPORT_TIMEOUT_MS := 60000

var log_lines := PackedStringArray()


## Returns the saved material, or null on failure (see log_lines).
## routes: GraphSettings.routes (see routing.gd); empty = every output by its usage.
func build(result: RenderResult, output_folder: String, name: String, routes: Dictionary = {}) -> StandardMaterial3D:
	var dir := output_folder.path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var outputs: Array = result.outputs.duplicate()
	if outputs.is_empty():  # backends that only fill maps
		for usage: String in result.maps:
			outputs.append({"id": usage, "label": usage, "usages": [usage], "path": result.maps[usage]})
	# Outputs that share a usage: the one in maps is the backend's pick, so it goes first.
	outputs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return _is_mapped(result, x) and not _is_mapped(result, y))
	var plan := Routing.plan(routes, outputs)
	for o: Dictionary in result.outputs:
		for u in o.get("usages", []):
			if not u in WIRED_USAGES and not u in ["diffuse"]:
				log_lines.append("Not wired: %s" % u)

	# Opacity is packed into the albedo's alpha (no texture of its own).
	var alpha: Image = null
	if plan.has("opacity") and plan.has("baseColor"):
		var op_src := String(plan["opacity"]["output"].get("path", ""))
		var op_img := Image.load_from_file(op_src) if not op_src.is_empty() else null
		if op_img == null or op_img.is_empty():
			log_lines.append("Could not read the opacity map %s" % op_src)
		else:
			alpha = Routing.transform(op_img, plan["opacity"], "opacity")

	var fs := EditorInterface.get_resource_filesystem()
	var tex_paths := {}
	var known := PackedStringArray()  # already imported once: needs an explicit reimport
	for slot: String in plan:
		if slot == "opacity":
			continue
		var entry: Dictionary = plan[slot]
		var src := String(entry["output"].get("path", ""))
		if src.is_empty():
			continue
		var pack := slot == "baseColor" and alpha != null
		var is_float := src.get_extension().to_lower() == "exr" and not pack
		var dst := dir.path_join("%s_%s.%s" % [name, slot, "png" if pack else src.get_extension().to_lower()])
		var image: Image = null
		if pack or entry["bake"] or (entry["explicit"] and Routing.slot_info(slot)["scalar"]):
			image = Image.load_from_file(src)
			if image == null or image.is_empty():
				log_lines.append("Could not read %s" % src)
				continue
			image = Routing.transform(image, entry, slot)
			if pack:
				image = Routing.pack_alpha(image, alpha)
		if not fs.get_file_type(dst).is_empty():
			known.append(dst)
		var err: Error
		if image:
			err = image.save_exr(ProjectSettings.globalize_path(dst), image.get_format() in [Image.FORMAT_RF, Image.FORMAT_RH]) if is_float \
					else image.save_png(ProjectSettings.globalize_path(dst))
		else:
			err = DirAccess.copy_absolute(src, ProjectSettings.globalize_path(dst))
		if err != OK:
			log_lines.append("Could not write %s: %s" % [dst, error_string(err)])
			continue
		var from_normal := "normal" in Array(entry["output"].get("usages", []))
		_write_import_settings(dst, slot == "normal", slot == "normal" and from_normal and result.normal_convention == "directx")
		tex_paths[slot] = dst
	if tex_paths.is_empty():
		log_lines.append("No usable maps to build a material from")
		return null

	if not await _import(tex_paths.values(), known):
		return null

	var mat_path := dir.path_join(name + ".tres")
	var mat: StandardMaterial3D = null
	if ResourceLoader.exists(mat_path):
		mat = ResourceLoader.load(mat_path) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
	for usage in WIRED_USAGES:
		if usage == "opacity":
			continue  # handled below: it lives in the albedo's alpha
		if String(routes.get(usage, {}).get("source", "")) == "-":
			Routing.clear_slot(mat, usage)
			continue
		if not tex_paths.has(usage):
			if Routing.is_generated(Routing.slot_texture(mat, usage), usage, dir, name):
				Routing.clear_slot(mat, usage)  # was routed here before; nothing feeds it now
			continue
		var tex := ResourceLoader.load(tex_paths[usage], "Texture2D") as Texture2D
		if tex == null:
			log_lines.append("Could not load imported texture %s" % tex_paths[usage])
			continue
		_assign(mat, usage, tex)
		Routing.apply_settings(mat, usage, routes, plan[usage])
	if alpha != null and tex_paths.has("baseColor"):
		Routing.enable_alpha(mat)
		Routing.apply_settings(mat, "opacity", routes, plan["opacity"])
	else:
		Routing.clear_slot(mat, "opacity")

	var err := ResourceSaver.save(mat, mat_path)
	if err != OK:
		log_lines.append("Could not save %s: %s" % [mat_path, error_string(err)])
		return null
	if mat.resource_path != mat_path:
		mat.take_over_path(mat_path)
	fs.update_file(mat_path)
	log_lines.append("Material: %s (%s normals%s)" % [mat_path, result.normal_convention,
			", green flipped on import" if result.normal_convention == "directx" else ""])
	return mat


static func _is_mapped(result: RenderResult, o: Dictionary) -> bool:
	for u in o.get("usages", []):
		if result.maps.get(u, "") == o.get("path", ""):
			return true
	return false

static func _assign(mat: StandardMaterial3D, usage: String, tex: Texture2D) -> void:
	match usage:
		"baseColor", "diffuse":
			mat.albedo_texture = tex
		"normal":
			mat.normal_enabled = true
			mat.normal_texture = tex
		"roughness":
			mat.roughness = 1.0
			mat.roughness_texture = tex
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		"metallic":
			mat.metallic = 1.0
			mat.metallic_texture = tex
			mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		"ambientOcclusion":
			mat.ao_enabled = true
			mat.ao_texture = tex
			mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		"emissive":
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			# Multiply: the default (Add) adds the white colour to the texture, so the whole material glows white.
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mat.emission_texture = tex
		"height":
			# Wired but left off: parallax is a per-material choice (enable "Height" in the inspector).
			mat.heightmap_texture = tex


## Writes (or updates) the .import file before Godot first imports the texture, so the
## first import already uses the right settings and never needs a second pass.
static func _write_import_settings(res_path: String, is_normal: bool, flip_green: bool) -> void:
	var cfg := ConfigFile.new()
	var import_path := res_path + ".import"
	if FileAccess.file_exists(import_path):
		cfg.load(import_path)
	cfg.set_value("remap", "importer", "texture")
	cfg.set_value("remap", "type", "CompressedTexture2D")
	cfg.set_value("params", "compress/mode", 2)                       # VRAM compressed
	cfg.set_value("params", "compress/high_quality", false)
	cfg.set_value("params", "compress/normal_map", 1 if is_normal else 2)  # enable / disable
	cfg.set_value("params", "mipmaps/generate", true)
	cfg.set_value("params", "process/normal_map_invert_y", is_normal and flip_green)
	cfg.set_value("params", "detect_3d/compress_to", 0)               # already VRAM; no re-import
	cfg.save(import_path)


## Imports new files and reimports known ones. Returns false on timeout.
func _import(paths: Array, known: PackedStringArray) -> bool:
	var fs := EditorInterface.get_resource_filesystem()
	var tree := Engine.get_main_loop() as SceneTree
	# Known files: reimport now (synchronous) so the new pixels and settings apply. Check again:
	# entries left from a deleted folder of the same name can drop out of the editor's file
	# list (a scan in between) and then count as new; reimporting those only logs errors.
	known = PackedStringArray(Array(known).filter(func(p: String) -> bool: return not fs.get_file_type(p).is_empty()))
	if not known.is_empty():
		fs.reimport_files(known)
	if known.size() == paths.size():
		return true
	# New files: a scan finds them and imports them with the settings written above.
	fs.scan()
	var deadline := Time.get_ticks_msec() + IMPORT_TIMEOUT_MS
	var frames := 0
	var rescan_at := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		frames += 1
		if frames < 3 or fs.is_scanning():
			continue
		var all_imported := true
		for p: String in paths:
			if fs.get_file_type(p).is_empty():
				all_imported = false
				break
		if all_imported:
			return true
		# A scan already running when ours was asked for ignores the request and can miss
		# files written after it started: ask again.
		if Time.get_ticks_msec() > rescan_at:
			fs.scan()
			rescan_at = Time.get_ticks_msec() + 1000
	log_lines.append("Timed out waiting for the editor to import the maps")
	return false
