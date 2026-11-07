@tool
extends RefCounted
## Bakes projected maps into a mesh's own UV layout.
##
## The mesh is drawn into UV space (like the native baker): every texel knows its object-space
## position, normal and tangent frame. The source map (a tiling texture) is sampled through a
## planar, triplanar, cylindrical or spherical projection of that position, so the result lines
## up across UV seams and doesn't care how the UVs were laid out (auto-generated UVs welcome).
##
## Normal maps are re-oriented: the source's tangent-space normal is taken in the projection's
## own frame, bent onto the surface, then expressed in the mesh's tangent space, so the baked
## map is an ordinary (OpenGL) normal map for the mesh. Every map renders in one batch of GPU
## passes, then empty texels around the UV islands are dilated.
##
## Main thread only, as a coroutine; it draws through the editor window like the native baker.

const NativeBaker := preload("res://addons/substance_bridge/backends/native/native_baker.gd")

enum Mode { UV, PLANAR, TRIPLANAR, CYLINDRICAL, SPHERICAL }

const TIMEOUT_MS := 60000
const DILATE_RADIUS := 8
## How Godot's mesh binormal relates to the projection's +v direction (the direction a source
## normal map's green channel points along, OpenGL convention). Set by the plane identity
## check in tests/projection_test.gd.
const BINORMAL_SIGN := -1.0

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled,
	ambient_light_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D source : filter_linear_mipmap, repeat_enable;
uniform int mode;             // 1 planar, 2 triplanar, 3 cylindrical, 4 spherical
uniform int axis;             // planar / cylindrical / spherical axis: 0 X, 1 Y, 2 Z (local)
uniform vec3 center;          // object space
uniform mat3 rot;             // local -> object
uniform float tile;           // object units per repeat
uniform vec2 repeats;         // around / along (cylindrical, spherical)
uniform float sharpness;      // triplanar blend
uniform bool is_normal;
uniform float binormal_sign;

varying vec3 obj_pos;
varying vec3 obj_nrm;
varying vec3 obj_tan;
varying vec3 obj_bin;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	obj_tan = TANGENT;
	obj_bin = BINORMAL;
	POSITION = vec4(UV.x * 2.0 - 1.0, UV.y * 2.0 - 1.0, 0.5, 1.0);
}

vec3 axis_vec(int a) {
	return a == 0 ? vec3(1.0, 0.0, 0.0) : (a == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
}

// Image directions (local) for a planar projection along axis a, seen from the side the
// surface faces: u to the right, v down the image.
void plane_frame(int a, float side, out vec3 tu, out vec3 tv) {
	if (a == 0) { tu = vec3(0.0, 0.0, -side); tv = vec3(0.0, -1.0, 0.0); }
	else if (a == 1) { tu = vec3(side, 0.0, 0.0); tv = vec3(0.0, 0.0, 1.0); }
	else { tu = vec3(side, 0.0, 0.0); tv = vec3(0.0, -1.0, 0.0); }
}

// Mip-correct sample; wrapped coordinates (the seam of a cylinder or sphere) take the
// derivative of the unwrapped copy, so the seam doesn't drop to the smallest mip.
vec4 sample_src(vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 alt = fract(uv + 0.5);
	vec2 adx = dFdx(alt);
	vec2 ady = dFdy(alt);
	if (abs(adx.x) + abs(ady.x) < abs(dx.x) + abs(dy.x)) { dx.x = adx.x; dy.x = ady.x; }
	if (abs(adx.y) + abs(ady.y) < abs(dx.y) + abs(dy.y)) { dx.y = adx.y; dy.y = ady.y; }
	return textureGrad(source, uv, dx, dy);
}

// Source tangent-space normal (OpenGL), in a frame whose u and v run along tu and tv
// (object space), bent onto the surface normal n.
vec3 bend(vec4 s, vec3 tu, vec3 tv, vec3 n) {
	vec3 t = s.xyz * 2.0 - 1.0;
	vec3 T = normalize(tu - n * dot(n, tu));
	vec3 B = binormal_sign * normalize(tv - n * dot(n, tv));
	return T * t.x + B * t.y + n * t.z;
}

void fragment() {
	vec3 n = normalize(obj_nrm);
	mat3 inv = transpose(rot);
	vec3 q = inv * (obj_pos - center);
	vec3 nl = inv * n;
	vec4 col = vec4(0.0);
	vec3 nrm = vec3(0.0);
	if (mode == 2) {
		vec3 w = pow(abs(nl), vec3(sharpness));
		w /= max(w.x + w.y + w.z, 1e-6);
		for (int a = 0; a < 3; a++) {
			float side = nl[a] >= 0.0 ? 1.0 : -1.0;
			vec3 tu;
			vec3 tv;
			plane_frame(a, side, tu, tv);
			vec4 s = sample_src(vec2(dot(q, tu), dot(q, tv)) / tile + 0.5);
			col += s * w[a];
			nrm += bend(s, rot * tu, rot * tv, n) * w[a];
		}
	} else if (mode == 1) {
		vec3 tu;
		vec3 tv;
		plane_frame(axis, 1.0, tu, tv);
		vec4 s = sample_src(vec2(dot(q, tu), dot(q, tv)) / tile + 0.5);
		col = s;
		nrm = bend(s, rot * tu, rot * tv, n);
	} else {
		vec3 ax = axis_vec(axis);
		vec3 e1 = axis_vec((axis + 1) % 3);
		vec3 e2 = axis_vec((axis + 2) % 3);
		float h = dot(q, ax);
		vec3 radial = q - ax * h;
		float rl = max(length(radial), 1e-6);
		vec3 rdir = radial / rl;
		float ang = atan(dot(q, e1), dot(q, e2));
		vec3 tu = dot(rdir, e2) * e1 - dot(rdir, e1) * e2;  // direction of increasing angle
		vec2 uv;
		vec3 tv;
		if (mode == 3) {
			uv = vec2(ang / 6.2831853 * repeats.x, -h / tile);
			tv = -ax;
		} else {
			vec3 r = normalize(q);
			float c = clamp(dot(r, ax), -1.0, 1.0);
			uv = vec2(ang / 6.2831853 * repeats.x, acos(c) / 3.14159265 * repeats.y);
			tv = c * rdir - sqrt(1.0 - c * c) * ax;  // down the meridian
		}
		vec4 s = sample_src(uv);
		col = s;
		nrm = bend(s, rot * tu, rot * tv, n);
	}
	if (is_normal) {
		vec3 no = normalize(nrm);
		vec3 T = normalize(obj_tan);
		vec3 B = normalize(obj_bin);
		ALBEDO = vec3(dot(no, T), dot(no, B), dot(no, n)) * 0.5 + 0.5;
	} else {
		ALBEDO = col.rgb;
	}
}
"""


## Projection settings as plain data: {mode, axis, tile, repeats, sharpness, offset, rotation}.
## offset is from the mesh's bounds centre; rotation in degrees.
static func defaults() -> Dictionary:
	return {"mode": Mode.TRIPLANAR, "axis": 1, "tile": 1.0, "repeats": Vector2(4, 2),
			"sharpness": 4.0, "offset": Vector3.ZERO, "rotation": Vector3.ZERO}


## A copy of mesh with tangents (generated where a surface has none). Errors when a surface
## has no UVs: the bake writes into UV0.
static func prepare_mesh(mesh: Mesh) -> Dictionary:
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays[Mesh.ARRAY_TEX_UV] == null or (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty():
			return {"error": "The mesh has no UVs to bake the projection into (surface %d)." % i}
		var primitive := Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			primitive = (mesh as ArrayMesh).surface_get_primitive_type(i)
		if arrays[Mesh.ARRAY_TANGENT] == null or (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).is_empty():
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays, primitive)
			if arrays[Mesh.ARRAY_NORMAL] == null:
				st.generate_normals()
			st.generate_tangents()
			arrays = st.commit_to_arrays()
		out.add_surface_from_arrays(primitive, arrays)
	return {"mesh": out}


## Projects every item onto mesh's UV layout. items: [{id, image: Image, normal: bool}]
## (normal maps in OpenGL convention). Each result has its source's size and format family
## (normal maps come back RGB8). Returns {"images": {id: Image}, "error": String}.
static func project(mesh: Mesh, items: Array, settings: Dictionary) -> Dictionary:
	var result := {"images": {}, "error": ""}
	var prepared := prepare_mesh(mesh)
	if prepared.has("error"):
		result["error"] = prepared["error"]
		return result
	var m: Mesh = prepared["mesh"]
	var tree := Engine.get_main_loop() as SceneTree
	var low_processor := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS

	var aabb := m.get_aabb()
	var r: Vector3 = settings.get("rotation", Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
	var shader := Shader.new()
	shader.code = SHADER
	var viewports: Array[SubViewport] = []
	for item: Dictionary in items:
		var src: Image = (item["image"] as Image).duplicate()
		if src.is_compressed():
			src.decompress()
		if not src.has_mipmaps():
			src.generate_mipmaps()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("source", ImageTexture.create_from_image(src))
		mat.set_shader_parameter("mode", int(settings.get("mode", Mode.TRIPLANAR)))
		mat.set_shader_parameter("axis", int(settings.get("axis", 1)))
		mat.set_shader_parameter("center", aabb.get_center() + Vector3(settings.get("offset", Vector3.ZERO)))
		mat.set_shader_parameter("rot", basis)
		mat.set_shader_parameter("tile", maxf(float(settings.get("tile", 1.0)), 0.0001))
		mat.set_shader_parameter("repeats", Vector2(settings.get("repeats", Vector2(4, 2))))
		mat.set_shader_parameter("sharpness", float(settings.get("sharpness", 4.0)))
		mat.set_shader_parameter("is_normal", bool(item.get("normal", false)))
		mat.set_shader_parameter("binormal_sign", float(settings.get("binormal_sign", BINORMAL_SIGN)))
		var vp := NativeBaker._new_viewport(tree, (item["image"] as Image).get_size(), true)
		var cam := Camera3D.new()
		cam.position = aabb.get_center() + Vector3(0, 0, aabb.size.length() * 2.0)
		vp.add_child(cam)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16384.0
		vp.add_child(mi)
		viewports.append(vp)
	var raw := await _render_all(viewports, deadline)

	# Dilate every map at once: texels outside the UV islands take the nearest island colour.
	var dilate_shader := Shader.new()
	dilate_shader.code = NativeBaker.DILATE_SHADER
	var dilaters: Array[SubViewport] = []
	for img in raw:
		if img == null:
			break
		var vp := NativeBaker._new_viewport(tree, img.get_size(), true)
		var mat := ShaderMaterial.new()
		mat.shader = dilate_shader
		mat.set_shader_parameter("source", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("radius", DILATE_RADIUS)
		var rect := ColorRect.new()
		rect.size = Vector2(img.get_size())
		rect.material = mat
		vp.add_child(rect)
		dilaters.append(vp)
	var done: Array[Image] = []
	if dilaters.size() == raw.size():
		done = await _render_all(dilaters, deadline)
	OS.low_processor_usage_mode = low_processor

	for i in items.size():
		var img: Image = done[i] if i < done.size() else null
		if img == null:
			result["error"] = "The projection bake did not finish: it renders through the editor window, so keep the editor visible (not minimised)."
			return result
		var item: Dictionary = items[i]
		result["images"][item["id"]] = _match_format(img, item["image"], item.get("normal", false))
	return result


## Draws every viewport once (together) and reads them back; null entries on timeout.
static func _render_all(viewports: Array[SubViewport], deadline: int) -> Array[Image]:
	for vp in viewports:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var frames := 0
	# Two drawn frames: the first can still show the cleared target on some drivers.
	while frames < 2 and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		frames += 1
		if frames == 1:
			for vp in viewports:
				vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var images: Array[Image] = []
	for vp in viewports:
		images.append(vp.get_texture().get_image() if frames >= 2 else null)
		vp.queue_free()
	return images


## The projected image in its source's format family: float stays float, grey stays grey.
static func _match_format(img: Image, source: Image, normal: bool) -> Image:
	if normal:
		img.convert(Image.FORMAT_RGB8)
		return img
	var f := source.get_format()
	if f in [Image.FORMAT_L8, Image.FORMAT_R8]:
		img.convert(Image.FORMAT_RF)  # luminance of a float image needs a float step first
		img.convert(f)
	elif f in [Image.FORMAT_RF, Image.FORMAT_RH, Image.FORMAT_RGBF, Image.FORMAT_RGBH,
			Image.FORMAT_RGBAF, Image.FORMAT_RGBAH, Image.FORMAT_RGF, Image.FORMAT_RGH]:
		img.convert(f)
	elif f == Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)  # alpha is not projected; the result is opaque
	else:
		img.convert(Image.FORMAT_RGB8)
	return img
