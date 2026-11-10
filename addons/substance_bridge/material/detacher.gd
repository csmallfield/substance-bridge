@tool
extends RefCounted
## Detaches a bridge material from its graph: copies its maps into a folder of their own and
## rebuilds it as a ShaderMaterial with its own .gdshader. The result has no link to the
## GraphSettings (no settings meta, nothing in the bridge's output folder), so re-rendering the
## graph never touches it and it can be committed like any other asset.
##
## Optionally packs ambient occlusion, roughness and metallic into one ORM map
## (R = AO, G = roughness, B = metallic) when at least two of them are present; a missing
## channel is white, so the shader's scalar (roughness, metallic) carries it alone.
##
## Optionally optimizes the copies for size: emission and ORM (or the separate AO, roughness
## and metallic maps) at half resolution, where the loss rarely shows, and normal maps as
## 8-bit PNGs (the GPU formats they import to are 8-bit per channel anyway, so 16-bit sources
## only cost disk space). Optimized copies drop alpha, which none of those maps use.
## Albedo and height are copied as they are.
##
## The shader is written for exactly the features the material uses, mirroring what
## StandardMaterial3D does for them (tiling, alpha scissor, normal strength, AO light affect,
## emission add/multiply, parallax). Main thread only (EditorInterface); detach() awaits the
## import and the ORM packing (a worker thread).

const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")
const Routing := preload("res://addons/substance_bridge/material/routing.gd")
const Task := preload("res://addons/substance_bridge/core/task.gd")

const ORM_SLOTS := ["ambientOcclusion", "roughness", "metallic"]
## Optimize: maps written at half resolution, and maps only reduced to 8 bits.
const HALF_SLOTS := ["emissive", "ambientOcclusion", "roughness", "metallic"]
const EIGHT_BIT_SLOTS := ["normal"]
## Slot -> file suffix of the detached copy.
const SUFFIX := {"baseColor": "albedo", "normal": "normal", "roughness": "roughness",
		"metallic": "metallic", "ambientOcclusion": "ao", "emissive": "emission", "height": "height"}
## Slot -> shader uniform holding its texture.
const UNIFORM := {"baseColor": "texture_albedo", "normal": "texture_normal", "roughness": "texture_roughness",
		"metallic": "texture_metallic", "ambientOcclusion": "texture_ambient_occlusion",
		"emissive": "texture_emission", "height": "texture_heightmap", "orm": "texture_orm"}

const FILTERS := ["filter_nearest", "filter_linear", "filter_nearest_mipmap", "filter_linear_mipmap",
		"filter_nearest_mipmap_anisotropic", "filter_linear_mipmap_anisotropic"]
const CULL := ["cull_back", "cull_front", "cull_disabled"]
const DIFFUSE := ["diffuse_burley", "diffuse_lambert", "diffuse_lambert_wrap", "diffuse_toon"]
const SPECULAR := ["specular_schlick_ggx", "specular_toon", "specular_disabled"]

var log_lines := PackedStringArray()


## What the detached material needs from a bridge material: {"maps": {slot: res path}, plus the
## shader spec's feature flags}, or {"error": String}. Only slots the material actually uses.
static func describe(mat: StandardMaterial3D) -> Dictionary:
	var maps := {}
	var used := {
		"baseColor": true,
		"normal": mat.normal_enabled,
		"roughness": true,
		"metallic": true,
		"ambientOcclusion": mat.ao_enabled,
		"emissive": mat.emission_enabled,
		"height": mat.heightmap_enabled,
	}
	for slot: String in used:
		if not used[slot]:
			continue
		var tex := Routing.slot_texture(mat, slot)
		if tex == null:
			continue
		var path := tex.resource_path
		if path.is_empty() or path.contains("::") or not FileAccess.file_exists(path):
			return {"error": "The %s map is not saved yet (a live preview?). Wait for the render to finish, then detach." % slot}
		maps[slot] = path
	if maps.is_empty():
		return {"error": "The material has no maps to detach."}
	var alpha := ""
	if maps.has("baseColor"):
		match mat.transparency:
			BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR: alpha = "scissor"
			BaseMaterial3D.TRANSPARENCY_ALPHA: alpha = "blend"
	return {
		"maps": maps,
		"alpha": alpha,
		"emission_add": mat.emission_operator == BaseMaterial3D.EMISSION_OP_ADD,
		"deep_parallax": mat.heightmap_deep_parallax,
		"height_flip_texture": mat.heightmap_flip_texture,
		"unshaded": mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"cull": int(mat.cull_mode),
		"diffuse": int(mat.diffuse_mode),
		"specular": int(mat.specular_mode),
		"filter": int(mat.texture_filter),
		"repeat": mat.texture_repeat,
	}


## True when packing would merge at least two maps into one.
static func orm_useful(maps: Dictionary) -> bool:
	var n := 0
	for slot in ORM_SLOTS:
		if maps.has(slot):
			n += 1
	return n >= 2


## Packs AO, roughness and metallic (any may be null) into one RGB8 image: R = AO,
## G = roughness, B = metallic, each from its source's red channel, white where missing.
## Resized to the largest input. Pure: safe on a worker thread.
static func pack_orm(ao: Image, roughness: Image, metallic: Image) -> Image:
	var size := Vector2i.ZERO
	for img: Image in [ao, roughness, metallic]:
		if img:
			size = size.max(img.get_size())
	if size == Vector2i.ZERO:
		return null
	var count := size.x * size.y
	var data := PackedByteArray()
	data.resize(count * 3)
	data.fill(255)
	var channel := 0
	for img: Image in [ao, roughness, metallic]:
		if img:
			var red := _red_channel(img, size)
			for i in count:
				data[i * 3 + channel] = red[i]
		channel += 1
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, data)


## The image's red channel as 8-bit bytes, one per pixel, at `size`.
static func _red_channel(src: Image, size: Vector2i) -> PackedByteArray:
	var img: Image = src.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	if img.get_format() in Routing.GREY_FORMATS or img.get_format() == Image.FORMAT_LA8:
		img.convert(Image.FORMAT_L8)  # grey: the value itself
	else:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_size() != size:
		img.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	var data := img.get_data()
	if img.get_format() == Image.FORMAT_L8:
		return data
	var out := PackedByteArray()
	out.resize(size.x * size.y)
	for i in out.size():
		out[i] = data[i * 4]
	return out


## An 8-bit copy of img without alpha (grey stays grey), halved when `half`. Only for maps
## whose alpha nothing reads (normal, emission, AO, roughness, metallic, ORM): Substance
## normal maps often carry an alpha the material never uses. Pure: safe on a worker thread.
static func optimized(src: Image, half: bool) -> Image:
	var img: Image = src.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_L8 if img.get_format() in Routing.GREY_FORMATS or img.get_format() == Image.FORMAT_LA8
			else Image.FORMAT_RGB8)
	if half:
		img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_LANCZOS)
	return img


## The shader's source for a spec: describe()'s flags plus "textures" (the uniform names
## present, see UNIFORM) and "orm" (bool: AO/roughness/metallic come from texture_orm).
static func shader_code(spec: Dictionary) -> String:
	var tex: Array = spec.get("textures", [])
	var has := func(slot: String) -> bool: return UNIFORM[slot] in tex
	var orm := bool(spec.get("orm", false))
	var ao: bool = has.call("ambientOcclusion") or (orm and bool(spec.get("orm_ao", false)))
	var height: bool = has.call("height")
	var hint := "%s, %s" % [FILTERS[clampi(int(spec.get("filter", 3)), 0, FILTERS.size() - 1)],
			"repeat_enable" if spec.get("repeat", true) else "repeat_disable"]

	var modes := PackedStringArray(["blend_mix", "depth_draw_opaque", CULL[int(spec.get("cull", 0))]])
	if spec.get("unshaded", false):
		modes.append("unshaded")
	else:
		modes.append(DIFFUSE[int(spec.get("diffuse", 0))])
		modes.append(SPECULAR[int(spec.get("specular", 0))])
	var s := PackedStringArray()
	s.append("// Detached from Substance Bridge: edit freely, nothing regenerates this file.")
	s.append("shader_type spatial;")
	s.append("render_mode %s;" % ", ".join(modes))
	s.append("")
	s.append("uniform vec4 albedo : source_color = vec4(1.0);")
	if has.call("baseColor"):
		s.append("uniform sampler2D texture_albedo : source_color, %s;" % hint)
	if spec.get("alpha", "") == "scissor":
		s.append("uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;")
	s.append("uniform float roughness : hint_range(0.0, 1.0) = 1.0;")
	s.append("uniform float metallic : hint_range(0.0, 1.0) = 0.0;")
	s.append("uniform float specular : hint_range(0.0, 1.0) = 0.5;")
	if orm:
		s.append("uniform sampler2D texture_orm : hint_roughness_g, %s;" % hint)
	else:
		if has.call("roughness"):
			s.append("uniform sampler2D texture_roughness : hint_roughness_r, %s;" % hint)
		if has.call("metallic"):
			s.append("uniform sampler2D texture_metallic : hint_default_white, %s;" % hint)
		if ao:
			s.append("uniform sampler2D texture_ambient_occlusion : hint_default_white, %s;" % hint)
	if ao:
		s.append("uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.0;")
	if has.call("normal"):
		s.append("uniform sampler2D texture_normal : hint_roughness_normal, %s;" % hint)
		s.append("uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;")
	if has.call("emissive"):
		s.append("uniform vec4 emission : source_color = vec4(1.0);")
		s.append("uniform sampler2D texture_emission : source_color, hint_default_black, %s;" % hint)
		s.append("uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;")
	if height:
		s.append("uniform sampler2D texture_heightmap : hint_default_black, %s;" % hint)
		s.append("uniform float heightmap_scale : hint_range(-16.0, 16.0) = 5.0;")
		s.append("uniform vec2 heightmap_flip = vec2(1.0);")
		if spec.get("deep_parallax", false):
			s.append("uniform int heightmap_min_layers : hint_range(1, 64) = 8;")
			s.append("uniform int heightmap_max_layers : hint_range(1, 64) = 16;")
	s.append("uniform vec3 uv1_scale = vec3(1.0);")
	s.append("uniform vec3 uv1_offset = vec3(0.0);")
	s.append("")
	s.append("void vertex() {")
	s.append("\tUV = UV * uv1_scale.xy + uv1_offset.xy;")
	s.append("}")
	s.append("")
	s.append("void fragment() {")
	s.append("\tvec2 base_uv = UV;")
	if height:
		var depth := "texture(texture_heightmap, %s).r" if spec.get("height_flip_texture", false) \
				else "1.0 - texture(texture_heightmap, %s).r"
		s.append("\t{")
		s.append("\t\tvec3 view_dir = normalize(normalize(-VERTEX + EYE_OFFSET) * mat3(TANGENT * heightmap_flip.x, -BINORMAL * heightmap_flip.y, NORMAL));")
		if spec.get("deep_parallax", false):
			s.append("\t\tfloat num_layers = mix(float(heightmap_max_layers), float(heightmap_min_layers), abs(dot(vec3(0.0, 0.0, 1.0), view_dir)));")
			s.append("\t\tfloat layer_depth = 1.0 / num_layers;")
			s.append("\t\tvec2 delta = view_dir.xy * heightmap_scale * 0.01 / num_layers;")
			s.append("\t\tvec2 ofs = base_uv;")
			s.append("\t\tfloat depth = %s;" % (depth % "ofs"))
			s.append("\t\tfloat current_depth = 0.0;")
			s.append("\t\twhile (current_depth < depth) {")
			s.append("\t\t\tofs -= delta;")
			s.append("\t\t\tdepth = %s;" % (depth % "ofs"))
			s.append("\t\t\tcurrent_depth += layer_depth;")
			s.append("\t\t}")
			s.append("\t\tvec2 prev_ofs = ofs + delta;")
			s.append("\t\tfloat after_depth = depth - current_depth;")
			s.append("\t\tfloat before_depth = (%s) - current_depth + layer_depth;" % (depth % "prev_ofs"))
			s.append("\t\tbase_uv = mix(ofs, prev_ofs, after_depth / (after_depth - before_depth));")
		else:
			s.append("\t\tfloat depth = %s;" % (depth % "base_uv"))
			s.append("\t\tbase_uv -= view_dir.xy * depth * heightmap_scale * 0.01;")
		s.append("\t}")
	if has.call("baseColor"):
		s.append("\tvec4 albedo_tex = texture(texture_albedo, base_uv);")
		s.append("\tALBEDO = albedo.rgb * albedo_tex.rgb;")
		match spec.get("alpha", ""):
			"scissor":
				s.append("\tALPHA = albedo.a * albedo_tex.a;")
				s.append("\tALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;")
			"blend":
				s.append("\tALPHA = albedo.a * albedo_tex.a;")
	else:
		s.append("\tALBEDO = albedo.rgb;")
	if orm:
		s.append("\tvec3 orm = texture(texture_orm, base_uv).rgb;")
		if ao:
			s.append("\tAO = orm.r;")
		s.append("\tROUGHNESS = roughness * orm.g;")
		s.append("\tMETALLIC = metallic * orm.b;")
	else:
		s.append("\tROUGHNESS = roughness%s;" % (" * texture(texture_roughness, base_uv).r" if has.call("roughness") else ""))
		s.append("\tMETALLIC = metallic%s;" % (" * texture(texture_metallic, base_uv).r" if has.call("metallic") else ""))
		if ao:
			s.append("\tAO = texture(texture_ambient_occlusion, base_uv).r;")
	if ao:
		s.append("\tAO_LIGHT_AFFECT = ao_light_affect;")
	s.append("\tSPECULAR = specular;")
	if has.call("normal"):
		s.append("\tNORMAL_MAP = texture(texture_normal, base_uv).rgb;")
		s.append("\tNORMAL_MAP_DEPTH = normal_scale;")
	if has.call("emissive"):
		var op := "+" if spec.get("emission_add", false) else "*"
		s.append("\tvec3 emission_tex = texture(texture_emission, base_uv).rgb;")
		s.append("\tEMISSION = (emission.rgb %s emission_tex) * emission_energy;" % op)
	s.append("}")
	return "\n".join(s) + "\n"


## The non-texture shader parameters, from the bridge material's own values.
static func parameters(mat: StandardMaterial3D, spec: Dictionary) -> Dictionary:
	var p := {
		"albedo": mat.albedo_color,
		"roughness": mat.roughness,
		"metallic": mat.metallic,
		"specular": mat.metallic_specular,
		"uv1_scale": mat.uv1_scale,
		"uv1_offset": mat.uv1_offset,
	}
	var code := shader_code(spec)
	var optional := {
		"alpha_scissor_threshold": mat.alpha_scissor_threshold,
		"ao_light_affect": mat.ao_light_affect,
		"normal_scale": mat.normal_scale,
		"emission": mat.emission,
		"emission_energy": mat.emission_energy_multiplier,
		"heightmap_scale": mat.heightmap_scale,
		"heightmap_flip": Vector2(-1.0 if mat.heightmap_flip_tangent else 1.0, -1.0 if mat.heightmap_flip_binormal else 1.0),
		"heightmap_min_layers": mat.heightmap_min_layers,
		"heightmap_max_layers": mat.heightmap_max_layers,
	}
	for k: String in optional:
		if RegEx.create_from_string("uniform \\w+ %s\\b" % k).search(code):
			p[k] = optional[k]
	return p


## Detaches `mat` into a new folder under dest_root (<dest_root>/<name>, or <name>_2, ... if
## taken; nothing is ever overwritten). Returns {"material": ShaderMaterial, "dir": String} or
## {"error": String}. See log_lines for what was written. pack: ORM; optimize: see the top.
func detach(mat: StandardMaterial3D, dest_root: String, pack: bool, optimize: bool = false) -> Dictionary:
	var info := describe(mat)
	if info.has("error"):
		return info
	var maps: Dictionary = info["maps"]
	var base := mat.resource_path.get_file().get_basename().validate_filename()
	if base.is_empty():
		base = "material"
	var dir := _unique_dir(dest_root, base)
	var name := dir.get_file()
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK:
		return {"error": "Could not create %s: %s" % [dir, error_string(err)]}

	var orm := pack and orm_useful(maps)
	var written := {}  # uniform -> res path
	for slot: String in maps:
		if orm and slot in ORM_SLOTS:
			continue
		var src: String = maps[slot]
		var half: bool = optimize and slot in HALF_SLOTS
		var reduce := half or (optimize and slot in EIGHT_BIT_SLOTS)
		var dst := dir.path_join("%s_%s.%s" % [name, SUFFIX[slot], "png" if reduce else src.get_extension()])
		if reduce:
			var task := Task.new()
			task.start(func() -> Dictionary:
				var img := Image.load_from_file(ProjectSettings.globalize_path(src))
				if img == null or img.is_empty():
					return {"error": "Could not read %s" % src}
				var out := optimized(img, half)
				var e := out.save_png(ProjectSettings.globalize_path(dst))
				if e != OK:
					return {"error": "Could not write %s: %s" % [dst, error_string(e)]}
				return {"from": img.get_size(), "to": out.get_size()})
			var r: Dictionary = await task.finished
			if r.has("error"):
				return r
			log_lines.append("Optimized %s: %s -> %s, 8-bit" % [dst.get_file(), _size_text(r["from"]), _size_text(r["to"])])
		else:
			err = DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
			if err != OK:
				return {"error": "Could not copy %s: %s" % [src, error_string(err)]}
		_copy_import_settings(src, dst)
		written[UNIFORM[slot]] = dst

	if orm:
		var images := []
		for slot in ORM_SLOTS:
			var img: Image = null
			if maps.has(slot):
				img = Image.load_from_file(ProjectSettings.globalize_path(maps[slot]))
				if img == null or img.is_empty():
					return {"error": "Could not read %s" % maps[slot]}
			images.append(img)
		var task := Task.new()
		task.start(func() -> Image:
			var img := pack_orm(images[0], images[1], images[2])
			return optimized(img, true) if img and optimize else img)
		var packed: Image = await task.finished
		var dst := dir.path_join("%s_orm.png" % name)
		err = packed.save_png(ProjectSettings.globalize_path(dst)) if packed else FAILED
		if err != OK:
			return {"error": "Could not write %s: %s" % [dst, error_string(err)]}
		MaterialBuilder._write_import_settings(dst, false, false)
		written[UNIFORM["orm"]] = dst
		log_lines.append("ORM: %s at %s (R %s, G %s, B %s)" % [dst.get_file(), _size_text(packed.get_size()),
				"AO" if maps.has("ambientOcclusion") else "white",
				"roughness" if maps.has("roughness") else "white",
				"metallic" if maps.has("metallic") else "white"])

	var builder := MaterialBuilder.new()
	var imported: bool = await builder._import(written.values(), PackedStringArray())
	log_lines.append_array(builder.log_lines)
	if not imported:
		return {"error": "The detached maps did not import in time; they are in %s." % dir}

	var spec := info.duplicate()
	spec["textures"] = written.keys()
	spec["orm"] = orm
	spec["orm_ao"] = orm and maps.has("ambientOcclusion")
	var shader := Shader.new()
	shader.code = shader_code(spec)
	var shader_path := dir.path_join(name + ".gdshader")
	err = ResourceSaver.save(shader, shader_path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		return {"error": "Could not save %s: %s" % [shader_path, error_string(err)]}
	shader.take_over_path(shader_path)  # so the material references the file instead of embedding it

	var smat := ShaderMaterial.new()
	smat.shader = shader
	smat.render_priority = mat.render_priority
	for uniform: String in written:
		smat.set_shader_parameter(uniform, ResourceLoader.load(written[uniform], "Texture2D"))
	var params := parameters(mat, spec)
	for k: String in params:
		smat.set_shader_parameter(k, params[k])
	var mat_path := dir.path_join(name + ".tres")
	err = ResourceSaver.save(smat, mat_path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		return {"error": "Could not save %s: %s" % [mat_path, error_string(err)]}
	smat.take_over_path(mat_path)
	var fs := EditorInterface.get_resource_filesystem()
	fs.update_file(shader_path)
	fs.update_file(mat_path)
	log_lines.append("Detached: %s (%s)" % [mat_path, ", ".join(PackedStringArray(written.keys().map(
			func(u: String) -> String: return u.trim_prefix("texture_"))))])
	return {"material": smat, "dir": dir}


static func _size_text(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


static func _unique_dir(root: String, base: String) -> String:
	var dir := root.path_join(base)
	var n := 2
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		dir = root.path_join("%s_%d" % [base, n])
		n += 1
	return dir


## Gives the copy the source's import settings (normal-map mode, green flip, compression),
## without its uid or imported-file paths, so Godot imports it as a new file.
static func _copy_import_settings(src: String, dst: String) -> void:
	var from := ConfigFile.new()
	if from.load(src + ".import") != OK:
		MaterialBuilder._write_import_settings(dst, false, false)
		return
	var cfg := ConfigFile.new()
	cfg.set_value("remap", "importer", from.get_value("remap", "importer", "texture"))
	cfg.set_value("remap", "type", from.get_value("remap", "type", "CompressedTexture2D"))
	if from.has_section("params"):
		for key in from.get_section_keys("params"):
			cfg.set_value("params", key, from.get_value("params", key))
	cfg.save(dst + ".import")
