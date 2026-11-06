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

## Usages wired into material slots, in the order they are applied.
const WIRED_USAGES := ["baseColor", "diffuse", "normal", "roughness", "metallic",
		"ambientOcclusion", "emissive", "height"]

const IMPORT_TIMEOUT_MS := 60000

var log_lines := PackedStringArray()


## Returns the saved material, or null on failure (see log_lines).
func build(result: RenderResult, output_folder: String, name: String) -> StandardMaterial3D:
	var dir := output_folder.path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var fs := EditorInterface.get_resource_filesystem()
	var tex_paths := {}
	var known := PackedStringArray()  # already imported once: needs an explicit reimport
	for usage: String in result.maps:
		if not usage in WIRED_USAGES:
			log_lines.append("Not wired: %s" % usage)
			continue
		if usage == "diffuse" and result.maps.has("baseColor"):
			continue
		var src: String = result.maps[usage]
		var dst := dir.path_join("%s_%s.%s" % [name, usage, src.get_extension().to_lower()])
		# Ask the editor, not ResourceLoader: once a .import file exists, ResourceLoader.exists()
		# is true even before anything has been imported.
		if not fs.get_file_type(dst).is_empty():
			known.append(dst)
		var err := DirAccess.copy_absolute(src, ProjectSettings.globalize_path(dst))
		if err != OK:
			log_lines.append("Could not copy %s: %s" % [src, error_string(err)])
			continue
		_write_import_settings(dst, usage == "normal", result.normal_convention == "directx")
		tex_paths[usage] = dst
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
		if not tex_paths.has(usage):
			continue
		var tex := ResourceLoader.load(tex_paths[usage], "Texture2D") as Texture2D
		if tex == null:
			log_lines.append("Could not load imported texture %s" % tex_paths[usage])
			continue
		_assign(mat, usage, tex)

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
	# Known files: reimport now (synchronous) so the new pixels and settings apply.
	if not known.is_empty():
		fs.reimport_files(known)
	if known.size() == paths.size():
		return true
	# New files: a scan finds them and imports them with the settings written above.
	fs.scan()
	var deadline := Time.get_ticks_msec() + IMPORT_TIMEOUT_MS
	var frames := 0
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
	log_lines.append("Timed out waiting for the editor to import the maps")
	return false
