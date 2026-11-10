extends SceneTree
## Lit shots of res://test/canister_mesh.res with a map set (basecolor, normal [OpenGL], roughness, metallic,
## ambientocclusion). Needs a window (no --headless).
##   godot --path D:/04_projects/SDB --script canister_shot.gd -- <maps dir> <out prefix> [views=wide,close,back]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var out: String = args[1]
	var views: PackedStringArray = (args[2] if args.size() > 2 else "wide,close,back").split(",")

	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 1400)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.11, 0.115, 0.125)
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new(); env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.5; key.shadow_enabled = true
	key.rotation_degrees = Vector3(-40, -35, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.5; rim.light_color = Color(0.75, 0.85, 1.0)
	rim.rotation_degrees = Vector3(-15, 150, 0)
	vp.add_child(rim)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex(dir, "basecolor")
	mat.normal_enabled = true
	mat.normal_texture = _tex(dir, "normal")
	mat.roughness_texture = _tex(dir, "roughness")
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.metallic = 1.0
	mat.metallic_texture = _tex(dir, "metallic")
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.ao_enabled = true
	mat.ao_texture = _tex(dir, "ambientocclusion")
	mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://test/canister_mesh.res")
	mi.material_override = mat
	vp.add_child(mi)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(6, 6); floor_mi.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.2, 0.2, 0.21); fm.roughness = 0.9
	floor_mi.material_override = fm
	vp.add_child(floor_mi)

	var cam := Camera3D.new(); vp.add_child(cam)
	var shots := {
		"wide": [Vector3(1.1, 0.95, 1.55), Vector3(0, 0.52, 0), 42.0],
		"close": [Vector3(0.42, 1.25, 0.5), Vector3(0, 1.0, 0), 40.0],
		"back": [Vector3(-1.2, 0.55, -1.3), Vector3(0, 0.45, 0), 42.0],
		"low": [Vector3(0.75, 0.2, 0.75), Vector3(0, 0.25, 0), 40.0],
	}
	for v in views:
		var s: Array = shots[v]
		cam.fov = s[2]
		cam.look_at_from_position(s[0], s[1])
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s_%s.png" % [out, v])
	quit()


func _tex(d: String, n: String) -> Texture2D:
	var path := d.path_join(n + ".png")
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
