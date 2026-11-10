@tool
extends RefCounted
## Detach test: run the editor (windowed, so the shaders really compile) with
##   set SUBSTANCE_BRIDGE_DETACH=1
##   godot --editor --path <project> --log-file <temp>/detach.log
## 1. ORM packing: channels, white for missing maps, resize to the largest.
## 2. Every shader variant compiles and declares the uniforms it uses.
## 3. A fake bridge material (maps in res://_detach_test/src) detached four times: with ORM,
##    without, then both optimized; files, sizes, import settings, parameters, no link back.
## Everything it writes is under res://_detach_test, removed at the end.

const Detacher := preload("res://addons/substance_bridge/material/detacher.gd")
const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")
const Pipeline := preload("res://addons/substance_bridge/core/pipeline.gd")

const ROOT := "res://_detach_test"

var plugin: EditorPlugin
var _failures := 0
var _checks := 0
var _tree: SceneTree


func run(_dock: Node, _arg: String) -> void:
	_tree = EditorInterface.get_base_control().get_tree()
	var fs := EditorInterface.get_resource_filesystem()
	while fs.is_scanning():
		await _tree.process_frame
	print("[detach] start")
	_pack()
	_shaders()
	await _flow()
	await _cleanup()
	print("[detach] %d checks, %d failed" % [_checks, _failures])
	print("[detach] RESULT: %s" % ("PASS" if _failures == 0 else "FAIL"))
	_tree.quit(0 if _failures == 0 else 1)


# --- 1. packing -------------------------------------------------------------------------------

func _pack() -> void:
	var ao := _grey(4, 0.2)
	var rough := _grey(8, 0.6)
	var metal := Image.create(4, 4, false, Image.FORMAT_RGB8)
	metal.fill(Color(1.0, 0.0, 0.0))  # red channel only
	var orm := Detacher.pack_orm(ao, rough, metal)
	_expect(orm.get_size() == Vector2i(8, 8) and orm.get_format() == Image.FORMAT_RGB8, "ORM is RGB8 at the largest input's size")
	var c := orm.get_pixel(3, 3)
	_expect(absf(c.r - 0.2) < 0.01 and absf(c.g - 0.6) < 0.01 and c.b > 0.99, "R = AO, G = roughness, B = metallic (red channel)")
	var partial := Detacher.pack_orm(null, rough, null).get_pixel(0, 0)
	_expect(partial.r > 0.99 and absf(partial.g - 0.6) < 0.01 and partial.b > 0.99, "missing maps are white")
	_expect(not Detacher.orm_useful({"roughness": "a", "baseColor": "b"}), "one of the three: no ORM")
	_expect(Detacher.orm_useful({"roughness": "a", "metallic": "b"}), "two of the three: ORM")


# --- 2. shaders -------------------------------------------------------------------------------

func _shaders() -> void:
	var all := ["texture_albedo", "texture_normal", "texture_roughness", "texture_metallic",
			"texture_ambient_occlusion", "texture_emission", "texture_heightmap"]
	var variants := {
		"albedo only": {"textures": ["texture_albedo"]},
		"nothing": {"textures": []},
		"every separate map, deep parallax, scissor": {"textures": all, "alpha": "scissor", "deep_parallax": true},
		"ORM with AO, blend, emission add": {"textures": ["texture_albedo", "texture_orm", "texture_emission"],
				"orm": true, "orm_ao": true, "alpha": "blend", "emission_add": true},
		"ORM without AO, simple parallax, flipped": {"textures": ["texture_albedo", "texture_orm", "texture_heightmap"],
				"orm": true, "height_flip_texture": true},
		"unshaded, cull off, nearest, no repeat": {"textures": ["texture_albedo"], "unshaded": true, "cull": 2,
				"filter": 0, "repeat": false},
	}
	var broken := Shader.new()
	broken.code = Detacher.shader_code({"textures": ["texture_albedo"]}).replace("ALBEDO =", "ALBEDO_TYPO =")
	_expect(broken.get_shader_uniform_list().is_empty(), "a shader that does not compile lists no uniforms (the check below means something)")
	for label: String in variants:
		var spec: Dictionary = variants[label]
		var shader := Shader.new()
		shader.code = Detacher.shader_code(spec)
		var names := shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])
		var want: Array = spec["textures"].duplicate()
		want.append_array(["albedo", "roughness", "uv1_scale"])
		var missing := want.filter(func(n: String) -> bool: return not n in names)
		_expect(missing.is_empty(), "shader compiles (%s)%s" % [label, "" if missing.is_empty() else ": missing " + str(missing)])
		if not missing.is_empty():
			print(shader.code)


# --- 3. flow ----------------------------------------------------------------------------------

func _flow() -> void:
	var src := ROOT.path_join("src")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(src))
	var albedo := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	albedo.fill(Color(0.8, 0.4, 0.2, 0.5))
	var normal := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	normal.fill(Color(0.5, 0.5, 1.0, 0.3))  # an alpha nothing reads, as sbsrender writes
	var files := {"baseColor": albedo, "normal": normal, "roughness": _grey(16, 0.7),
			"metallic": _grey(16, 0.1), "ambientOcclusion": _grey(16, 0.4), "emissive": _grey(16, 0.0)}
	var paths := {}
	for slot: String in files:
		var p := src.path_join("fake_%s.png" % slot)
		(files[slot] as Image).save_png(ProjectSettings.globalize_path(p))
		MaterialBuilder._write_import_settings(p, slot == "normal", slot == "normal")
		paths[slot] = p
	var builder := MaterialBuilder.new()
	_expect(await builder._import(paths.values(), PackedStringArray()), "fake maps imported")

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(paths["baseColor"])
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
	mat.normal_enabled = true
	mat.normal_texture = load(paths["normal"])
	mat.normal_scale = 2.0
	mat.roughness_texture = load(paths["roughness"])
	mat.roughness = 0.9
	mat.metallic_texture = load(paths["metallic"])
	mat.metallic = 1.0
	mat.ao_enabled = true
	mat.ao_texture = load(paths["ambientOcclusion"])
	mat.ao_light_affect = 0.25
	mat.emission_enabled = true
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.emission_texture = load(paths["emissive"])
	mat.uv1_scale = Vector3(3, 2, 1)
	mat.set_meta(Pipeline.SETTINGS_META, "res://somewhere/fake_graph.tres")
	var mat_path := src.path_join("fake.tres")
	_expect(ResourceSaver.save(mat, mat_path, ResourceSaver.FLAG_CHANGE_PATH) == OK, "fake bridge material saved")
	mat.take_over_path(mat_path)

	var out_root := ROOT.path_join("out")
	var d := Detacher.new()
	var r: Dictionary = await d.detach(mat, out_root, true)
	_expect(not r.has("error"), "detach with ORM: %s" % r.get("error", "ok"))
	if r.has("error"):
		return
	var dir: String = r["dir"]
	_expect(dir == out_root.path_join("fake"), "folder named after the material")
	for f in ["fake_albedo.png", "fake_normal.png", "fake_orm.png", "fake_emission.png", "fake.gdshader", "fake.tres"]:
		_expect(FileAccess.file_exists(dir.path_join(f)), "wrote " + f)
	for f in ["fake_roughness.png", "fake_metallic.png", "fake_ao.png"]:
		_expect(not FileAccess.file_exists(dir.path_join(f)), "packed, no " + f)
	var imp := ConfigFile.new()
	imp.load(dir.path_join("fake_normal.png.import"))
	_expect(imp.get_value("params", "process/normal_map_invert_y", false) == true
			and imp.get_value("params", "compress/normal_map", 0) == 1, "normal keeps its import settings (green flip)")
	_expect(ResourceLoader.get_resource_uid(dir.path_join("fake_normal.png")) != ResourceLoader.get_resource_uid(paths["normal"]),
			"copy has its own uid")
	var orm := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join("fake_orm.png")))
	var c := orm.get_pixel(0, 0)
	_expect(absf(c.r - 0.4) < 0.01 and absf(c.g - 0.7) < 0.01 and absf(c.b - 0.1) < 0.01, "ORM pixels from the AO, roughness and metallic maps")

	var saved := ResourceLoader.load(dir.path_join("fake.tres"), "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	_expect(saved != null and saved.shader and saved.shader.resource_path == dir.path_join("fake.gdshader"), "ShaderMaterial on disk uses its .gdshader")
	if saved:
		_expect(not saved.has_meta(Pipeline.SETTINGS_META) and Pipeline.settings_for_material(saved) == null, "no link to the graph")
		_expect(saved.get_shader_parameter("uv1_scale") == Vector3(3, 2, 1)
				and is_equal_approx(saved.get_shader_parameter("roughness"), 0.9)
				and is_equal_approx(saved.get_shader_parameter("normal_scale"), 2.0)
				and is_equal_approx(saved.get_shader_parameter("alpha_scissor_threshold"), 0.3)
				and is_equal_approx(saved.get_shader_parameter("ao_light_affect"), 0.25), "parameters carried over")
		var t: Texture2D = saved.get_shader_parameter("texture_orm")
		_expect(t != null and t.resource_path == dir.path_join("fake_orm.png"), "texture_orm points at the copy")
		var at: Texture2D = saved.get_shader_parameter("texture_albedo")
		_expect(at != null and at.resource_path.begins_with(dir), "albedo points at the copy, not the bridge folder")
		var code := saved.shader.code
		_expect(code.contains("ALPHA_SCISSOR_THRESHOLD") and code.contains("emission.rgb * emission_tex")
				and code.contains("AO = orm.r"), "shader has scissor, multiply emission, AO from ORM")

	var d2 := Detacher.new()
	var r2: Dictionary = await d2.detach(mat, out_root, false)
	_expect(not r2.has("error") and r2.get("dir") == out_root.path_join("fake_2"), "second detach goes to a new folder")
	if not r2.has("error"):
		var dir2: String = r2["dir"]
		_expect(FileAccess.file_exists(dir2.path_join("fake_2_roughness.png")) and not FileAccess.file_exists(dir2.path_join("fake_2_orm.png")),
				"without ORM the maps stay separate")
		_expect(FileAccess.file_exists(dir.path_join("fake.tres")), "first detach untouched")

	var r3: Dictionary = await Detacher.new().detach(mat, out_root, true, true)
	_expect(not r3.has("error"), "detach with ORM, optimized: %s" % r3.get("error", "ok"))
	if not r3.has("error"):
		var dir3: String = r3["dir"]
		_expect(_png_info(dir3.path_join("fake_3_orm.png")) == [8, 8, 8, 2], "optimized ORM at half size")
		_expect(_png_info(dir3.path_join("fake_3_emission.png")) == [8, 8, 8, 0], "optimized emission at half size, 8-bit")
		_expect(_png_info(dir3.path_join("fake_3_normal.png")) == [16, 16, 8, 2], "optimized normal at full size, 8-bit RGB (alpha dropped)")
		_expect(FileAccess.get_md5(dir3.path_join("fake_3_albedo.png")) == FileAccess.get_md5(paths["baseColor"]), "albedo copied unchanged")
		var imp3 := ConfigFile.new()
		imp3.load(dir3.path_join("fake_3_normal.png.import"))
		_expect(imp3.get_value("params", "process/normal_map_invert_y", false) == true, "optimized normal keeps its import settings")
		var m3 := ResourceLoader.load(dir3.path_join("fake_3.tres"), "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
		var t3: Texture2D = m3.get_shader_parameter("texture_orm") if m3 else null
		_expect(t3 != null and t3.get_width() == 8, "material uses the half-size ORM")
	var r4: Dictionary = await Detacher.new().detach(mat, out_root, false, true)
	if not r4.has("error"):
		_expect(_png_info(String(r4["dir"]).path_join("fake_4_roughness.png")) == [8, 8, 8, 0], "optimized without ORM: roughness at half size")
	else:
		_expect(false, "detach without ORM, optimized: %s" % r4["error"])

	var bad := StandardMaterial3D.new()
	bad.albedo_texture = ImageTexture.create_from_image(albedo)
	var r5: Dictionary = await Detacher.new().detach(bad, out_root, true)
	_expect(r5.has("error"), "a live (unsaved) map is refused")


func _cleanup() -> void:
	await _tree.create_timer(0.5).timeout
	_remove_dir(ProjectSettings.globalize_path(ROOT))
	var fs := EditorInterface.get_resource_filesystem()
	fs.scan()
	await _tree.process_frame
	while fs.is_scanning():
		await _tree.process_frame


static func _remove_dir(abs_path: String) -> void:
	for d in DirAccess.get_directories_at(abs_path):
		_remove_dir(abs_path.path_join(d))
	for f in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(f))
	DirAccess.remove_absolute(abs_path)


## [width, height, bit depth, colour type (0 grey, 2 RGB, 6 RGBA)] from a PNG's header.
static func _png_info(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	f.big_endian = true
	f.seek(16)
	var w := f.get_32()
	var h := f.get_32()
	var depth := f.get_8()
	return [w, h, depth, f.get_8()]


static func _grey(size: int, v: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	img.fill(Color(v, v, v))
	return img


func _expect(cond: bool, what: String) -> void:
	_checks += 1
	print(("[detach]   ok   " if cond else "[detach]   FAIL ") + what)
	if not cond:
		_failures += 1
