extends SceneTree
## (techno_grid copy: N alpha layers, square tiles, 2x2 repeats, an optional dark back plate)
## Stacked-layer shots: a material baked once per layer (top, middle, bottom), each layer a plane, stacked in depth,
## alpha-scissored by its opacity, lit by a shadow-casting key light so upper layers shadow lower ones.
##   godot --path <any project> --script stack_shot.gd -- <dir with maps_0, maps_1, maps_2> <out prefix> [aspect] [depth] [parallax]
## Each maps_k needs basecolor_rgba.png (base colour + opacity in alpha), normal, roughness, metallic,
## ambientocclusion, emissive (and height, for parallax) .png. aspect = width / height of one tile (2 for a 2:1 panel); two tiles side by side.
## Needs a window (do not pass --headless).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var out: String = args[1]
	var aspect: float = float(args[2]) if args.size() > 2 else 1.0
	var depth: float = float(args[3]) if args.size() > 3 else 0.08
	var parallax: float = float(args[4]) if args.size() > 4 else 3.0
	var nlayers: int = int(args[5]) if args.size() > 5 else 5
	var backplate: bool = (args[6] == "1") if args.size() > 6 else true

	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_energy = 0.3
	# a sky only for reflections (the background stays dark): bare metal reflects black without one
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new(); env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.ssao_enabled = true
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.4; key.shadow_enabled = true
	key.directional_shadow_max_distance = 12.0
	key.rotation_degrees = Vector3(-35, -40, 0)            # from the upper left, so shadows fall down-right
	vp.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.5, -0.5, 2.5); fill.light_energy = 0.8; fill.omni_range = 10.0
	fill.light_color = Color(0.7, 0.8, 1.0)
	vp.add_child(fill)

	var h := 1.0
	h = 2.0
	var w := aspect * h
	if backplate:
		var bm := StandardMaterial3D.new(); bm.albedo_color = Color(0.02, 0.02, 0.022); bm.roughness = 0.9
		var bi := MeshInstance3D.new(); var bp := PlaneMesh.new(); bp.size = Vector2(w * 3, h * 3)
		bp.orientation = PlaneMesh.FACE_Z; bi.mesh = bp; bi.material_override = bm
		bi.position = Vector3(0, 0, -depth * nlayers); vp.add_child(bi)
	for k in nlayers:
		var md := dir.path_join("maps_%d" % k)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _tex(md, "basecolor_rgba")
		if true:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.5
		mat.normal_enabled = true
		mat.normal_texture = _tex(md, "normal")
		mat.roughness_texture = _tex(md, "roughness")
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.metallic = 1.0
		mat.metallic_texture = _tex(md, "metallic")
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.ao_enabled = true
		mat.ao_texture = _tex(md, "ambientocclusion")
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.emission_enabled = true
		mat.emission_texture = _tex(md, "emissive")
		mat.emission_energy_multiplier = 3.0
		mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		var hm := _tex(md, "height")
		if hm and parallax > 0.0:
			mat.heightmap_enabled = true
			mat.heightmap_texture = hm
			mat.heightmap_scale = parallax
			mat.heightmap_deep_parallax = true
			mat.heightmap_min_layers = 16
			mat.heightmap_max_layers = 48
		mat.uv1_scale = Vector3(2, 2, 1)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(w, h); pm.orientation = PlaneMesh.FACE_Z
		mi.mesh = pm; mi.material_override = mat
		mi.position = Vector3(0, 0, -depth * k)
		vp.add_child(mi)
	var cam := Camera3D.new(); vp.add_child(cam)

	var shots := [
		["front", Vector3(0.0, 0.0, 2.3), Vector3(0.0, 0.0, 0.0), 50.0],
		["steep", Vector3(-2.2, 0.5, 1.3), Vector3(0.3, 0.0, -0.2), 40.0],
		["close", Vector3(-0.45, 0.3, 0.55), Vector3(0.05, 0.05, -0.15), 45.0],
	]
	for s in shots:
		cam.fov = s[3]
		cam.look_at_from_position(s[1], s[2])
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s_%s.png" % [out, s[0]])
	quit()


func _tex(dir: String, n: String) -> Texture2D:
	var path := dir.path_join(n + ".png")
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
