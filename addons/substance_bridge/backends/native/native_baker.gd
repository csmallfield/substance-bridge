@tool
extends RefCounted
## Native mesh-map baker: AO, curvature, position and world-space normal, baked in Godot
## through SubViewports (no external tools, no raw RenderingDevice).
##
## - UV-space raster: a spatial shader writes POSITION from UV, so the mesh is drawn into its
##   own texture layout and the fragment stage sees each texel's object-space position/normal.
## - Curvature: change of the normal against the change of the position (screen derivatives).
## - AO: the mesh is drawn from DIRECTIONS directions into depth maps (orthographic); a UV pass
##   then tests every texel against each depth map facing it, cosine-weighted.
## - Dilation: empty texels next to UV islands take the nearest island colour, so mip-mapping and
##   filtering at seams don't pull in black.
##
## Main thread only, as a coroutine. It needs a drawing window (not headless, not minimised).
## Maps are keyed by Substance usage, like mesh_baker.gd, and cached per mesh and size.

const USAGES := ["ambientOcclusion", "curvature", "position", "normalWS"]

const DIRECTIONS := 64
const DEPTH_SIZE := 512
const DILATE_RADIUS := 16
## Curvature gain, as a multiple of 1 / (mesh size). Calibrated against sbsbaker's curvature.
const CURVATURE_GAIN := 0.0028
## Occluder distance as a fraction of the mesh's bounding-box diagonal, with linear falloff.
## sbsbaker's default is 0.1, but the depth-map estimate of occluder distance overshoots in
## crevices; 0.4 matches sbsbaker's mean and spread on the test rock (calibrated).
const AO_MAX_DISTANCE := 0.4
const TIMEOUT_MS := 120000

const UV_HEADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled,
	ambient_light_disabled, fog_disabled, skip_vertex_transform;
varying vec3 obj_pos;
varying vec3 obj_nrm;
void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	// Viewport textures read back with clip y = -1 at the top row, so UV v maps straight across.
	POSITION = vec4(UV.x * 2.0 - 1.0, UV.y * 2.0 - 1.0, 0.5, 1.0);
}
"""

const POSITION_FRAG := """
uniform vec3 bbox_min;
uniform vec3 bbox_size;
void fragment() {
	ALBEDO = clamp((obj_pos - bbox_min) / bbox_size, 0.0, 1.0);
}
"""

const NORMAL_FRAG := """
void fragment() {
	ALBEDO = normalize(obj_nrm) * 0.5 + 0.5;
}
"""

const CURVATURE_FRAG := """
uniform float gain;
void fragment() {
	vec3 n = normalize(obj_nrm);
	vec3 dpx = dFdx(obj_pos);
	vec3 dpy = dFdy(obj_pos);
	vec3 dnx = dFdx(n);
	vec3 dny = dFdy(n);
	float kx = dot(dnx, dpx) / max(dot(dpx, dpx), 1e-20);
	float ky = dot(dny, dpy) / max(dot(dpy, dpy), 1e-20);
	ALBEDO = vec3(clamp(0.5 + 0.5 * (kx + ky) * gain, 0.0, 1.0));
}
"""

const AO_FRAG := """
uniform sampler2DArray depths : filter_nearest;
uniform mat4 light_view[64];
uniform vec3 light_dir[64];
uniform int count;
uniform float ortho_size;
uniform float far_dist;
uniform float bias;
uniform float offset;
uniform float max_dist;
void fragment() {
	vec3 n = normalize(obj_nrm);
	vec3 p = obj_pos + n * offset;
	float seen = 0.0;
	float total = 0.0;
	for (int i = 0; i < count; i++) {
		float c = dot(n, light_dir[i]);
		if (c <= 0.0) {
			continue;
		}
		vec4 v = light_view[i] * vec4(p, 1.0);
		vec2 uv = vec2(v.x / ortho_size + 0.5, 0.5 - v.y / ortho_size);
		float d = -v.z / far_dist;
		float stored = texture(depths, vec3(uv, float(i))).r;
		// Distance to the outermost surface in front of the texel along this direction: an
		// approximation of the occluder distance (exact for one occluding layer).
		float gap = (d - stored) * far_dist;
		float occlusion = gap < bias * far_dist ? 0.0 : clamp(1.0 - gap / max_dist, 0.0, 1.0);
		seen += (1.0 - occlusion) * c;
		total += c;
	}
	ALBEDO = vec3(total > 0.0 ? seen / total : 1.0);
}
"""

## Writes linear depth along the camera axis, as a fraction of far_dist.
const DEPTH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;
uniform float far_dist;
varying float view_z;
void vertex() {
	view_z = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	ALBEDO = vec3(view_z / far_dist);
}
"""

## Fills empty texels (alpha 0) with the nearest filled texel within `radius`.
const DILATE_SHADER := """
shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D source : filter_nearest;
uniform int radius;
void fragment() {
	vec4 c = texture(source, UV);
	if (c.a > 0.5) {
		COLOR = vec4(c.rgb, 1.0);
	} else {
		vec2 texel = 1.0 / vec2(textureSize(source, 0));
		vec4 best = vec4(0.0);
		float best_d = 1e9;
		for (int y = -radius; y <= radius; y++) {
			for (int x = -radius; x <= radius; x++) {
				float d = float(x * x + y * y);
				if (d >= best_d) {
					continue;
				}
				vec4 s = texture(source, UV + vec2(float(x), float(y)) * texel);
				if (s.a > 0.5) {
					best = vec4(s.rgb, 1.0);
					best_d = d;
				}
			}
		}
		COLOR = best;
	}
}
"""


static func supported_usages() -> PackedStringArray:
	return PackedStringArray(USAGES)


## Bakes the requested usages of `mesh` at 2^size_log2 into out_dir/<usage>.png (cached unless
## force). Returns {"maps": {usage: path}, "errors": PackedStringArray, "baked": int, "seconds": float}.
static func bake(mesh: Mesh, usages: PackedStringArray, size_log2: int, out_dir: String,
		force: bool = false) -> Dictionary:
	var started := Time.get_ticks_msec()
	var out := {"maps": {}, "errors": PackedStringArray(), "baked": 0}
	DirAccess.make_dir_recursive_absolute(out_dir)
	var todo := PackedStringArray()
	for usage in usages:
		if not usage in USAGES:
			out["errors"].append("The native baker cannot bake \"%s\"" % usage)
			continue
		var file := out_dir.path_join(usage + ".png")
		if FileAccess.file_exists(file) and not force:
			out["maps"][usage] = file
		else:
			todo.append(usage)
	if todo.is_empty() or not out["errors"].is_empty():
		out["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
		return out

	var tree := Engine.get_main_loop() as SceneTree
	var low_processor := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false  # passes wait for frame_post_draw: draw every frame
	var size := Vector2i(1 << size_log2, 1 << size_log2)
	var aabb := mesh.get_aabb()
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS

	for usage in todo:
		var image: Image = null
		match usage:
			"position":
				image = await _uv_pass(tree, mesh, size, POSITION_FRAG,
						{"bbox_min": aabb.position, "bbox_size": aabb.size}, deadline)
			"normalWS":
				image = await _uv_pass(tree, mesh, size, NORMAL_FRAG, {}, deadline)
			"curvature":
				image = await _uv_pass(tree, mesh, size, CURVATURE_FRAG,
						{"gain": CURVATURE_GAIN * aabb.size.length()}, deadline)
			"ambientOcclusion":
				image = await _ao(tree, mesh, size, deadline)
		if image != null:
			image = await _dilate(tree, image, deadline)
		if image == null:
			out["errors"].append("Native %s bake did not finish: it renders through the editor window, so keep the editor visible (not minimised, not headless)." % usage)
			break
		var file := out_dir.path_join(usage + ".png")
		image.convert(Image.FORMAT_L8 if usage in ["ambientOcclusion", "curvature"] else Image.FORMAT_RGB8)
		var err := image.save_png(file)
		if err != OK:
			out["errors"].append("Could not write %s: %s" % [file, error_string(err)])
			break
		out["maps"][usage] = file
		out["baked"] += 1

	OS.low_processor_usage_mode = low_processor
	out["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	return out


# --- passes ---------------------------------------------------------------------------------

static func _new_viewport(tree: SceneTree, size: Vector2i, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.use_hdr_2d = true        # float target, no sRGB conversion: values stay data
	vp.transparent_bg = transparent
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = 0
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(vp)
	return vp


## Draws once and reads the result back; null on timeout.
static func _render(tree: SceneTree, vp: SubViewport, deadline: int) -> Image:
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var frames := 0
	var image: Image = null
	# Two drawn frames: the first can still show the cleared target on some drivers.
	while frames < 2 and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		frames += 1
		if frames == 1:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if frames >= 2:
		image = vp.get_texture().get_image()
	return image


static func _mesh_instance(mesh: Mesh, shader_code: String, params: Dictionary) -> MeshInstance3D:
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0  # UV-space draws ignore the camera; never cull them
	return mi


static func _uv_pass(tree: SceneTree, mesh: Mesh, size: Vector2i, fragment: String, params: Dictionary,
		deadline: int) -> Image:
	var vp := _new_viewport(tree, size, true)
	var cam := Camera3D.new()
	cam.position = mesh.get_aabb().get_center() + Vector3(0, 0, mesh.get_aabb().size.length() * 2.0)
	vp.add_child(cam)
	vp.add_child(_mesh_instance(mesh, UV_HEADER + fragment, params))
	var image := await _render(tree, vp, deadline)
	vp.queue_free()
	return image


static func _ao(tree: SceneTree, mesh: Mesh, size: Vector2i, deadline: int) -> Image:
	var aabb := mesh.get_aabb()
	var center := aabb.get_center()
	var radius := aabb.size.length() * 0.5
	var far_dist := radius * 4.0
	var dirs := _sphere_directions(DIRECTIONS)

	# 1. Depth maps from every direction.
	var vp := _new_viewport(tree, Vector2i(DEPTH_SIZE, DEPTH_SIZE), false)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = radius * 2.0
	cam.near = 0.001 * radius
	cam.far = far_dist
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.add_child(cam)
	vp.add_child(_mesh_instance(mesh, DEPTH_SHADER, {"far_dist": far_dist}))
	var layers: Array[Image] = []
	var views: Array[Projection] = []
	for d in dirs:
		var eye := center + d * radius * 2.0
		var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD
		cam.global_transform = Transform3D(Basis.looking_at(-d, up), eye)
		var img := await _render(tree, vp, deadline)
		if img == null:
			vp.queue_free()
			return null
		img.convert(Image.FORMAT_RH)
		layers.append(img)
		views.append(Projection(cam.global_transform.affine_inverse()))
	vp.queue_free()

	# 2. One UV pass testing every texel against all depth maps.
	var depths := Texture2DArray.new()
	depths.create_from_images(layers)
	return await _uv_pass(tree, mesh, size, AO_FRAG, {
		"depths": depths, "light_view": views, "light_dir": dirs, "count": dirs.size(),
		"ortho_size": radius * 2.0, "far_dist": far_dist,
		"bias": 1.5 * (radius * 2.0 / DEPTH_SIZE) / far_dist,  # ~1.5 depth-map texels
		"offset": 0.004 * radius,
		"max_dist": AO_MAX_DISTANCE * aabb.size.length(),
	}, deadline)


static func _dilate(tree: SceneTree, image: Image, deadline: int) -> Image:
	var vp := _new_viewport(tree, image.get_size(), true)
	var shader := Shader.new()
	shader.code = DILATE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("source", ImageTexture.create_from_image(image))
	mat.set_shader_parameter("radius", DILATE_RADIUS)
	var rect := ColorRect.new()
	rect.size = Vector2(image.get_size())
	rect.material = mat
	vp.add_child(rect)
	var out := await _render(tree, vp, deadline)
	vp.queue_free()
	return out


## UV coverage mask (white where the mesh covers the layout, black elsewhere); for checks.
static func coverage(mesh: Mesh, size_log2: int) -> Image:
	var tree := Engine.get_main_loop() as SceneTree
	var low_processor := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var image := await _uv_pass(tree, mesh, Vector2i(1 << size_log2, 1 << size_log2),
			"void fragment() { ALBEDO = vec3(1.0); }", {}, Time.get_ticks_msec() + TIMEOUT_MS)
	OS.low_processor_usage_mode = low_processor
	if image:
		image.convert(Image.FORMAT_L8)
	return image


## Evenly spread directions on the unit sphere (Fibonacci lattice).
static func _sphere_directions(count: int) -> PackedVector3Array:
	var dirs := PackedVector3Array()
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - (i + 0.5) / count * 2.0
		var r := sqrt(1.0 - y * y)
		dirs.append(Vector3(cos(golden * i) * r, y, sin(golden * i) * r))
	return dirs
