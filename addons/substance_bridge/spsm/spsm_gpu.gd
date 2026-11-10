@tool
extends RefCounted
## GPU compositing for smart materials: one compute shader on a local RenderingDevice, so it
## runs on a worker thread (a local device never draws to the screen). Every image is a square
## RGBA half-float texture; scalar channels and masks keep the same value in r, g and b.
##
## Ops (each one dispatch, finished before the call returns):
##   fill     dst = colour
##   sample   dst = src read through a fill's projection (UV / tri-planar / planar), tiling,
##            rotation and offset, with mip-mapped filtering so heavy tiling does not alias
##   blend    dst = Painter blend of dst and (src or a colour), through a mask and an opacity
##   levels   dst = levels(dst)
##   bump     dst = dst normal detailed with the normal of a height map
##   frame    dst = the mesh's world-space tangent or bitangent, from the position and normal maps
##
## Needs a RenderingDevice driver (Forward+ or Mobile); not available headless or on the
## Compatibility renderer. Call init() and check its error first.

const OP_FILL := 0
const OP_SAMPLE := 1
const OP_BLEND := 2
const OP_LEVELS := 3
const OP_BUMP := 4
const OP_FRAME := 5

## Value kinds: how blends treat and clamp a channel.
const KIND_COLOR := 0   # rgb, 0..1
const KIND_SCALAR := 1  # one value in rgb, 0..1 (roughness, metallic, masks, ...)
const KIND_NORMAL := 2  # tangent-space normal, encoded 0..1 (OpenGL, Y+)
const KIND_HEIGHT := 3  # one value in rgb, not clamped

## sample flags
const F_SRGB := 1       # source is sRGB-encoded colour: decode to linear
const F_GRAY := 2       # use the source's red channel in r, g and b
const F_FLIP_Y := 4     # DirectX normal: flip green
## blend flags
const F_SRC_TEX := 1    # blend the src texture (else the colour)
const F_MASK := 2       # multiply opacity by mask's red channel

const PROJ_UV := 0
const PROJ_TRIPLANAR := 1
const PROJ_PLANAR := 2

const SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, rgba16f) uniform restrict image2D dst;
layout(set = 0, binding = 1) uniform sampler2D src;
layout(set = 0, binding = 2) uniform sampler2D mask_tex;
layout(set = 0, binding = 3) uniform sampler2D pos_tex;
layout(set = 0, binding = 4) uniform sampler2D nrm_tex;
layout(push_constant, std430) uniform Params {
	ivec4 op;    // op, blend mode, kind, flags
	vec4 color;  // constant source
	vec4 a;      // sample: scale.xy, offset.xy | blend: opacity | levels: in min, in max, gamma, out min
	vec4 b;      // sample: rotation, projection, side hardness, lod bias | levels: out max, clamp | bump: strength
} p;

const float EPS = 1e-4;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 q = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 r = mix(vec4(q.xyw, c.r), vec4(c.r, q.yzx), step(q.x, c.r));
	float d = r.x - min(r.w, r.y);
	return vec3(abs(r.z + (r.w - r.y) / (6.0 * d + 1e-10)), d / (r.x + 1e-10), r.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 q = clamp(abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return c.z * mix(vec3(1.0), q, c.y);
}

vec3 overlay(vec3 d, vec3 s) {
	return mix(2.0 * d * s, 1.0 - 2.0 * (1.0 - d) * (1.0 - s), step(0.5, d));
}

vec3 soft_light(vec3 d, vec3 s) {  // W3C soft light
	vec3 g = mix(((16.0 * d - 12.0) * d + 4.0) * d, sqrt(max(d, 0.0)), step(0.25, d));
	return mix(d - (1.0 - 2.0 * s) * d * (1.0 - d), d + (2.0 * s - 1.0) * (g - d), step(0.5, s));
}

vec3 burn(vec3 d, vec3 s) { return 1.0 - min(vec3(1.0), (1.0 - d) / max(s, vec3(EPS))); }
vec3 dodge(vec3 d, vec3 s) { return min(vec3(1.0), d / max(1.0 - s, vec3(EPS))); }

// Painter's blending modes by number (spsm_document.gd BLEND_MODES).
vec3 blend(int mode, int kind, vec3 d, vec3 s) {
	switch (mode) {
	case 0: return d;
	case 3: return min(d, s);
	case 4: return d * s;
	case 5: return burn(d, s);
	case 6: return d + s - 1.0;
	case 7: return max(d, s);
	case 8: return 1.0 - (1.0 - d) * (1.0 - s);
	case 9: return dodge(d, s);
	case 10: return d + s;
	case 11: return overlay(d, s);
	case 12: return soft_light(d, s);
	case 13: return overlay(s, d);
	case 14: return mix(burn(d, 2.0 * s), dodge(d, 2.0 * s - 1.0), step(0.5, s));
	case 15: return d + 2.0 * s - 1.0;
	case 16: return mix(min(d, 2.0 * s), max(d, 2.0 * s - 1.0), step(0.5, s));
	case 17: return abs(d - s);
	case 18: return d + s - 2.0 * d * s;
	case 19: if (kind != 0) return d; { vec3 hd = rgb_to_hsv(d); return hsv_to_rgb(vec3(hd.x, rgb_to_hsv(s).y, hd.z)); }
	case 20: if (kind != 0) return d; { vec3 hs = rgb_to_hsv(s); return hsv_to_rgb(vec3(hs.x, hs.y, rgb_to_hsv(d).z)); }
	case 21: if (kind != 0) return s; { vec3 hd = rgb_to_hsv(d); return hsv_to_rgb(vec3(hd.x, hd.y, rgb_to_hsv(s).z)); }
	case 22: if (kind != 0) return d; return s * lum(d) / max(lum(s), EPS);
	case 23: return d / max(s, vec3(EPS));
	case 24: return s / max(d, vec3(EPS));
	case 29: return d - s;
	case 30: return s - d;
	case 31: return d + 2.0 * s - 1.0;
	default: return s;  // 1 Replace, 2 Normal, 25 Passthrough
	}
}

vec3 rnm(vec3 base, vec3 detail) {  // reoriented normal mapping, decoded normals
	vec3 t = base + vec3(0.0, 0.0, 1.0);
	vec3 u = detail * vec3(-1.0, -1.0, 1.0);
	return normalize(t * dot(t, u) / max(t.z, EPS) - u);
}

vec3 blend_normal(int mode, vec3 d, vec3 s) {  // decoded normals
	switch (mode) {
	case 0: return d;
	case 26: return normalize(vec3(d.xy + s.xy, d.z * s.z));
	case 27: return rnm(d, s);
	case 28: return rnm(s, d);
	default: return s;
	}
}

vec2 rotate(vec2 v, float r) {
	float c = cos(r), s = sin(r);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vec4 fetch(vec2 uv, float lod) {
	vec4 c = textureLod(src, uv, lod);
	if ((p.op.w & 2) != 0) c = vec4(c.rrr, c.a);
	if ((p.op.w & 1) != 0) c.rgb = srgb_to_linear(clamp(c.rgb, 0.0, 1.0));
	if ((p.op.w & 4) != 0) c.g = 1.0 - c.g;
	return c;
}

vec2 tile(vec2 uv) {
	return rotate(uv * p.a.xy, p.b.x) + p.a.zw;
}

void main() {
	ivec2 size = imageSize(dst);
	ivec2 xy = ivec2(gl_GlobalInvocationID.xy);
	if (xy.x >= size.x || xy.y >= size.y) return;
	vec2 uv = (vec2(xy) + 0.5) / vec2(size);
	int op = p.op.x;
	int mode = p.op.y;
	int kind = p.op.z;

	if (op == 0) {
		imageStore(dst, xy, p.color);
	} else if (op == 1) {
		// Mip level: how many source texels one output texel covers.
		vec2 src_size = vec2(textureSize(src, 0));
		float lod = max(0.0, log2(max(abs(p.a.x), abs(p.a.y)) * max(src_size.x, src_size.y) / float(size.x))) + p.b.w;
		int proj = int(p.b.y);
		vec4 c;
		if (proj == 0) {
			c = fetch(tile(uv), lod);
		} else {
			vec3 pos = texture(pos_tex, uv).xyz;  // object position in the bounding box, 0..1
			if (proj == 2) {
				c = fetch(tile(pos.xy), lod);
			} else {
				vec3 n = abs(texture(nrm_tex, uv).xyz * 2.0 - 1.0);
				vec3 w = pow(n, vec3(1.0 + 15.0 * clamp(p.b.z, 0.0, 1.0)));
				w /= max(w.x + w.y + w.z, EPS);
				c = fetch(tile(pos.zy), lod) * w.x + fetch(tile(pos.xz), lod) * w.y + fetch(tile(pos.xy), lod) * w.z;
			}
		}
		imageStore(dst, xy, c);
	} else if (op == 2) {
		vec4 dv = imageLoad(dst, xy);
		vec3 s = (p.op.w & 1) != 0 ? texture(src, uv).rgb : p.color.rgb;
		float m = p.a.x;
		if ((p.op.w & 2) != 0) m *= clamp(texture(mask_tex, uv).r, 0.0, 1.0);
		vec3 r;
		if (kind == 2) {
			vec3 dn = normalize(dv.rgb * 2.0 - 1.0);
			vec3 sv = s * 2.0 - 1.0;
			if (length(sv) < 0.2) m = 0.0;  // no direction (a grey output): leave the normal alone
			vec3 sn = normalize(sv + vec3(0.0, 0.0, 1e-6));
			r = normalize(mix(dn, blend_normal(mode, dn, sn), m)) * 0.5 + 0.5;
		} else {
			r = mix(dv.rgb, blend(mode, kind, dv.rgb, s), m);
			if (kind != 3) r = clamp(r, 0.0, 1.0);
		}
		imageStore(dst, xy, vec4(r, 1.0));
	} else if (op == 3) {
		vec4 dv = imageLoad(dst, xy);
		vec3 x = clamp((dv.rgb - p.a.x) / max(p.a.y - p.a.x, EPS), 0.0, 1.0);
		x = pow(x, vec3(1.0 / max(p.a.z, EPS)));
		vec3 r = mix(vec3(p.a.w), vec3(p.b.x), x);
		if (p.b.y > 0.5) r = clamp(r, 0.0, 1.0);
		imageStore(dst, xy, vec4(r, 1.0));
	} else if (op == 4) {
		// Height (src, red) to a normal by central differences, detailed onto dst.
		vec2 t = 1.0 / vec2(textureSize(src, 0));
		float hx = texture(src, uv + vec2(t.x, 0.0)).r - texture(src, uv - vec2(t.x, 0.0)).r;
		float hy = texture(src, uv + vec2(0.0, t.y)).r - texture(src, uv - vec2(0.0, t.y)).r;
		// Image rows grow downwards; OpenGL normals point green up (+v).
		vec3 hn = normalize(vec3(-hx * p.b.x, hy * p.b.x, 1.0));
		vec3 dn = normalize(imageLoad(dst, xy).rgb * 2.0 - 1.0);
		imageStore(dst, xy, vec4(rnm(dn, hn) * 0.5 + 0.5, 1.0));
	} else if (op == 5) {
		// Tangent frame: how the position map moves along u (tangent) and v (bitangent), made
		// orthogonal to the normal map. Rows grow downwards, v upwards. mode 0 tangent, 1 bitangent,
		// 2 the normal itself. flags 1: write signed -1..1 (as Painter feeds graphs) instead of 0..1.
		bool signed_out = (p.op.w & 1) != 0;
		ivec2 ps = textureSize(pos_tex, 0);
		ivec2 pxy = clamp(ivec2(uv * vec2(ps)), ivec2(0), ps - 1);
		vec3 du = texelFetch(pos_tex, clamp(pxy + ivec2(1, 0), ivec2(0), ps - 1), 0).xyz
				- texelFetch(pos_tex, clamp(pxy - ivec2(1, 0), ivec2(0), ps - 1), 0).xyz;
		vec3 dv = texelFetch(pos_tex, clamp(pxy - ivec2(0, 1), ivec2(0), ps - 1), 0).xyz
				- texelFetch(pos_tex, clamp(pxy + ivec2(0, 1), ivec2(0), ps - 1), 0).xyz;
		vec3 n = normalize(texture(nrm_tex, uv).xyz * 2.0 - 1.0);
		vec3 t = du - n * dot(n, du);
		vec3 r = vec3(0.0);
		if (mode == 2) {
			r = n;
		} else if (length(t) > 1e-6) {
			t = normalize(t);
			vec3 bt = normalize(cross(n, t));
			if (dot(bt, dv) < 0.0) bt = -bt;
			r = mode == 0 ? t : bt;
		}
		imageStore(dst, xy, vec4(signed_out ? r : r * 0.5 + 0.5, 1.0));
	}
}
"""

var rd: RenderingDevice
var size := 0

var _shader: RID
var _pipeline: RID
var _sampler: RID
var _dummy: RID
var _owned: Array[RID] = []


## Creates the device and compiles the shader. Returns an error message, or "".
func init(size_px: int) -> String:
	size = size_px
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		return "Smart materials need the Forward+ or Mobile renderer (no RenderingDevice; headless or Compatibility)."
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = SHADER
	var spirv := rd.shader_compile_spirv_from_source(src)
	if not spirv.compile_error_compute.is_empty():
		return "Compositing shader: " + spirv.compile_error_compute
	_shader = rd.shader_create_from_spirv(spirv)
	_pipeline = rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_sampler = rd.sampler_create(ss)
	_dummy = _texture_from(_solid(4, Color(0, 0, 0, 1)))
	return ""


## Frees everything. The object is unusable afterwards.
func close() -> void:
	if rd == null:
		return
	for t in _owned:
		if t.is_valid():
			rd.free_rid(t)
	_owned.clear()
	for r in [_pipeline, _shader, _sampler]:
		if r.is_valid():
			rd.free_rid(r)
	rd.free()
	rd = null


## A new size x size texture filled with a colour.
func new_texture(fill := Color(0, 0, 0, 1)) -> RID:
	var t := _texture_from(_solid(size, fill))
	return t


## Uploads an image: converted to half floats, shrunk to at most max_size (0 = the working
## size) and mip-mapped. Returns the texture.
func upload(img: Image, max_size := 0) -> RID:
	var limit := max_size if max_size > 0 else size
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	if im.has_mipmaps():
		im.clear_mipmaps()
	if im.get_width() > limit or im.get_height() > limit:
		var s := float(limit) / maxf(im.get_width(), im.get_height())
		im.resize(maxi(1, roundi(im.get_width() * s)), maxi(1, roundi(im.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	if im.get_format() != Image.FORMAT_RGBAH:
		im.convert(Image.FORMAT_RGBAH)
	im.generate_mipmaps()
	return _texture_from(im)


## Reads a texture back as an RGBAH image (mip level 0).
func download(tex: RID) -> Image:
	var data := rd.texture_get_data(tex, 0)
	var fmt := rd.texture_get_format(tex)
	return Image.create_from_data(fmt.width, fmt.height, false, Image.FORMAT_RGBAH, data)


func free_texture(tex: RID) -> void:
	if tex.is_valid():
		_owned.erase(tex)
		rd.free_rid(tex)


func copy(from: RID) -> RID:
	var t := new_texture()
	sample(t, from, {})
	return t


func fill(dst: RID, color: Color) -> void:
	_run(dst, OP_FILL, 0, 0, 0, color, Vector4.ZERO, Vector4.ZERO)


## t: {"scale": Vector2, "offset": Vector2, "rotation": float (radians), "projection": PROJ_*,
## "hardness": float, "pos": RID, "nrm": RID}; flags: F_SRGB | F_GRAY | F_FLIP_Y.
func sample(dst: RID, src: RID, t: Dictionary, flags := 0) -> void:
	var scale: Vector2 = t.get("scale", Vector2.ONE)
	var offset: Vector2 = t.get("offset", Vector2.ZERO)
	var a := Vector4(scale.x, scale.y, offset.x, offset.y)
	var b := Vector4(float(t.get("rotation", 0.0)), float(t.get("projection", PROJ_UV)), float(t.get("hardness", 0.5)), 0.0)
	_run(dst, OP_SAMPLE, 0, 0, flags, Color(), a, b, src, RID(), t.get("pos", RID()), t.get("nrm", RID()))


## Blends src (a texture, or a Color) into dst. mask may be an empty RID (no mask).
func blend(dst: RID, src: Variant, mode: int, kind: int, opacity := 1.0, mask := RID()) -> void:
	var flags := 0
	var color := Color()
	var tex := RID()
	if src is RID:
		flags |= F_SRC_TEX
		tex = src
	else:
		color = src
	if mask.is_valid():
		flags |= F_MASK
	_run(dst, OP_BLEND, mode, kind, flags, color, Vector4(opacity, 0, 0, 0), Vector4.ZERO, tex, mask)


func levels(dst: RID, in_min: float, in_max: float, gamma: float, out_min: float, out_max: float, clamp_out := true) -> void:
	_run(dst, OP_LEVELS, 0, 0, 0, Color(), Vector4(in_min, in_max, gamma, out_min),
			Vector4(out_max, 1.0 if clamp_out else 0.0, 0, 0))


## Details the normal map in dst with the slopes of the height map in height_tex.
func bump(dst: RID, height_tex: RID, strength: float) -> void:
	_run(dst, OP_BUMP, 0, 0, 0, Color(), Vector4.ZERO, Vector4(strength, 0, 0, 0), height_tex)


## The mesh's world-space tangent (which 0), bitangent (1) or normal (2) from its position and
## world-space normal maps; signed: -1..1 values (else encoded 0..1).
func frame(dst: RID, pos: RID, nrm: RID, which: int, signed := true) -> void:
	_run(dst, OP_FRAME, which, 0, 1 if signed else 0, Color(), Vector4.ZERO, Vector4.ZERO, RID(), RID(), pos, nrm)


func _run(dst: RID, op: int, mode: int, kind: int, flags: int, color: Color, a: Vector4, b: Vector4,
		src := RID(), mask := RID(), pos := RID(), nrm := RID()) -> void:
	var uniforms: Array[RDUniform] = []
	var img := RDUniform.new()
	img.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	img.binding = 0
	img.add_id(dst)
	uniforms.append(img)
	var binding := 1
	for t: RID in [src, mask, pos, nrm]:
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u.binding = binding
		u.add_id(_sampler)
		u.add_id(t if t.is_valid() else _dummy)
		uniforms.append(u)
		binding += 1
	var set := rd.uniform_set_create(uniforms, _shader, 0)
	var pc := PackedByteArray()
	pc.resize(64)
	pc.encode_s32(0, op)
	pc.encode_s32(4, mode)
	pc.encode_s32(8, kind)
	pc.encode_s32(12, flags)
	var floats := [color.r, color.g, color.b, color.a, a.x, a.y, a.z, a.w, b.x, b.y, b.z, b.w]
	for i in floats.size():
		pc.encode_float(16 + i * 4, floats[i])
	var groups := ceili(size / 8.0)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	rd.compute_list_bind_uniform_set(cl, set, 0)
	rd.compute_list_set_push_constant(cl, pc, pc.size())
	rd.compute_list_dispatch(cl, groups, groups, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.free_rid(set)


static func _solid(px: int, c: Color) -> Image:
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBAH)
	img.fill(c)
	return img


func _texture_from(img: Image) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.width = img.get_width()
	fmt.height = img.get_height()
	fmt.mipmaps = img.get_mipmap_count() + 1
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var t := rd.texture_create(fmt, RDTextureView.new(), [img.get_data()])
	_owned.append(t)
	return t
