@tool
extends RefCounted
## Renders a smart material's layer stack (spsm_document.gd) into texture maps, the way
## Substance Painter would on a mesh whose maps (AO, curvature, ...) were baked for it.
##
## 1. Every generator and fill graph (.sbsar inside the file) is rendered with sbsrender, with
##    the baked mesh maps, flat colours and other graphs wired to its inputs. Several run at once,
##    and each result is cached by its inputs, so a re-render only redoes what changed.
## 2. Embedded bitmaps (grunges) are decoded once into the cache.
## 3. The stack is composited on the GPU (spsm_gpu.gd), bottom layer first: each layer's fills
##    and filters make its content, its mask stack makes its mask, and the content is blended
##    into each channel with the layer's blending mode and opacity. Groups composite their
##    children first. Colour is blended in linear space.
## 4. Channels are written as files and returned as a RenderResult (normal is OpenGL, with the
##    height channel's relief folded in, as Painter exports it).
##
## Anchor points (newer Painter) snapshot every channel where they sit, user channels included;
## a reference reads that snapshot, as a fill source or as a graph input (such graphs render while
## compositing instead of up front).
##
## Not reproduced: paint strokes (skipped, with a warning) and the projection details beyond UV,
## tri-planar and a front planar projection. Blocking: run on a worker thread.

const SpsmDocument := preload("res://addons/substance_bridge/spsm/spsm_document.gd")
const Gpu := preload("res://addons/substance_bridge/spsm/spsm_gpu.gd")
const ToolRunner := preload("res://addons/substance_bridge/core/tool_runner.gd")
const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")
const SbsarReader := preload("res://addons/substance_bridge/backends/substance/sbsar_reader.gd")

const BASECOLOR := 0x1
const HEIGHT := 0x2
const OPACITY := 0x8
const EMISSIVE := 0x10
const ROUGHNESS := 0x80
const METALLIC := 0x2000
const NORMAL := 0x400000
const AO := 0x800000

## Channels the renderer produces, in output order: bit -> [usage, kind, start value (linear)].
const CHANNELS := {
	BASECOLOR: ["baseColor", Gpu.KIND_COLOR, Color(0.214, 0.214, 0.214)],
	ROUGHNESS: ["roughness", Gpu.KIND_SCALAR, Color(0.5, 0.5, 0.5)],
	METALLIC: ["metallic", Gpu.KIND_SCALAR, Color(0, 0, 0)],
	NORMAL: ["normal", Gpu.KIND_NORMAL, Color(0.5, 0.5, 1.0)],
	HEIGHT: ["height", Gpu.KIND_HEIGHT, Color(0, 0, 0)],
	AO: ["ambientOcclusion", Gpu.KIND_SCALAR, Color(1, 1, 1)],
	EMISSIVE: ["emissive", Gpu.KIND_COLOR, Color(0, 0, 0)],
	OPACITY: ["opacity", Gpu.KIND_SCALAR, Color(1, 1, 1)],
}
## Always produced, even when no layer writes them.
const BASE_CHANNELS := [BASECOLOR, ROUGHNESS, METALLIC, NORMAL]

## Stand-ins for mesh maps that were not baked.
const NEUTRAL_MAPS := {
	"ambientOcclusion": Color(1, 1, 1), "curvature": Color(0.5, 0.5, 0.5), "position": Color(0.5, 0.5, 0.5),
	"normalWS": Color(0.5, 0.5, 1.0), "thickness": Color(0.5, 0.5, 0.5),
	"normal": Color(0.5, 0.5, 1.0),  # the baked tangent-space normal (no high-poly mesh: flat)
}
## Inputs Painter feeds mesh-based generators itself, by identifier (the file does not list
## them): input id -> the map that goes in. Painter gives them as signed vectors (-1..1, not
## encoded 0..1; checked against the Very Normal Converter graph), so they are written as float
## EXR. The tangent frame is worked out from the position and world-space normal maps.
const AUTO_INPUTS := {
	"mesh_world_space_normal": "normalWS", "mesh_world_space_tangent": "tangentWS",
	"mesh_world_space_bitangent": "bitangentWS",
}

## The mask's channel bit in newer files (older ones use 0).
const MASK_BIT := 1 << 27

## Height -> normal strength at 1024 px (scaled with the size, so relief looks the same).
const BUMP_STRENGTH := 10.0
## Graphs rendered at once.
const PARALLEL := 4
## stderr text that means sbsrender did not do what was asked, even with exit code 0.
const RENDER_FATAL := ["Could not load image", "Result cannot be saved"]

var doc: SpsmDocument
var size := 512
var size_log2 := 9
## Usage -> absolute path of a baked mesh map.
var mesh_maps := {}
## settings.gd snapshot(): sbsrender, engine, cache_dir.
var config := {}

var result := RenderResult.new()

var _gpu: Gpu
var _cache := ""
var _mutex := Mutex.new()
## Procedural (by key) -> {identifier: png path}; filled by prefetch, read while compositing.
var _rendered := {}
var _textures := {}  # file path / "map:<usage>" -> uploaded RID
var _sbsars := {}  # sha1 -> extracted path
var _jobs: Array = []
var _next_job := 0
var _stats := {"graphs": 0, "cached": 0, "filters": 0, "skipped_paint": 0}
## Channel bits the stack writes that are not material channels (Painter's user channels): they
## composite like colour so anchors can capture them, and are not written out.
var _extra_bits := {}
## Anchor uid -> {channel bit: RID}, the stack where the anchor sits; and anchors met in the
## layer being composited, snapshot once it is blended.
var _anchors := {}
var _pending_anchors: Array[int] = []
## sbsar sha1 -> automatic input ids it declares (AUTO_INPUTS); usage -> file for them.
var _auto := {}
var _auto_files := {}


## Renders the stack into out_dir. Returns the RenderResult (maps by usage, outputs, errors).
static func render_stack(spsm_path: String, maps: Dictionary, size_px_log2: int, cfg: Dictionary, out_dir: String) -> RenderResult:
	var r := new()
	r.config = cfg
	r.mesh_maps = maps
	r.size_log2 = size_px_log2
	r.size = 1 << size_px_log2
	r._run(spsm_path, out_dir)
	return r.result


func _run(spsm_path: String, out_dir: String) -> void:
	var started := Time.get_ticks_msec()
	doc = SpsmDocument.open(spsm_path)
	if not doc.is_ok():
		result.errors.append_array(doc.errors)
		return
	_cache = String(config.get("cache_dir", OS.get_cache_dir())).path_join("spsm")
	DirAccess.make_dir_recursive_absolute(_cache)

	# 1-2. Graphs and bitmaps, before the GPU work.
	_collect(doc.root.get("layerGroup", {}))
	_prepare_resources()
	if not result.errors.is_empty():
		return
	_gpu = Gpu.new()
	var err := _gpu.init(size)
	if not err.is_empty():
		result.errors.append(err)
		return
	_prepare_auto_inputs()
	_render_graphs()
	var graphs_done := Time.get_ticks_msec()

	# 3. Composite.
	var acc := {}
	for bit: int in _channels():
		acc[bit] = _gpu.new_texture(CHANNELS[bit][2])
	for bit: int in _extra_bits:
		acc[bit] = _gpu.new_texture(Color(0, 0, 0))
	if acc.has(AO) and _map_texture("ambientOcclusion").is_valid() and mesh_maps.has("ambientOcclusion"):
		_gpu.sample(acc[AO], _map_texture("ambientOcclusion"), {}, Gpu.F_GRAY)  # Painter exports AO x the baked AO
	var top: Dictionary = doc.root.get("layerGroup", {})
	_composite_children(top, acc)

	# 4. Write the maps.
	if acc.has(HEIGHT) and acc.has(NORMAL):
		_gpu.bump(acc[NORMAL], acc[HEIGHT], BUMP_STRENGTH * size / 1024.0)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for f in DirAccess.get_files_at(out_dir):
		DirAccess.remove_absolute(out_dir.path_join(f))
	var base := spsm_path.get_file().get_basename().validate_filename()
	for bit: int in acc:
		if not CHANNELS.has(bit):
			continue  # user channels are not material maps
		var usage: String = CHANNELS[bit][0]
		var path := _write(acc[bit], bit, out_dir.path_join("%s_%s" % [base, usage]))
		if path.is_empty():
			continue
		result.maps[usage] = path
		result.outputs.append({"id": usage, "label": usage.capitalize(), "usages": [usage], "path": path})
	result.normal_convention = "opengl"
	_gpu.close()
	_gpu = null
	if _stats["skipped_paint"] > 0:
		result.warnings.append("%d paint stroke step(s) skipped: brush strokes are not reproduced" % _stats["skipped_paint"])
	var done := Time.get_ticks_msec()
	result.commands.append("Smart material %s: %d graph run(s), %d of them filters, %d from cache; graphs %.1f s, compositing %.1f s" % [
			doc.label, _stats["graphs"], _stats["filters"], _stats["cached"], (graphs_done - started) / 1000.0,
			(done - graphs_done) / 1000.0])
	result.duration_ms = done - started


## Channels to produce: the base set plus any the stack writes.
func _channels() -> Array[int]:
	var written := 0
	for name: String in doc.stats()["channels"]:
		for bit: int in SpsmDocument.CHANNELS:
			if SpsmDocument.CHANNELS[bit] == name:
				written |= bit
	var out: Array[int] = []
	for bit: int in CHANNELS:
		if bit in BASE_CHANNELS or written & bit:
			out.append(bit)
	return out


# --- layers -------------------------------------------------------------------------------------

func _composite_children(group: Dictionary, acc: Dictionary) -> void:
	for l: Dictionary in SpsmDocument._items(group.get("subStack")):
		if bool(l.get("enabled", true)):
			_composite_layer(l, acc)


func _composite_layer(l: Dictionary, acc: Dictionary) -> void:
	var blends := _blends(l)
	var mask := _layer_mask(l)
	var debug_dir := String(config.get("spsm_debug_dir", ""))
	if not debug_dir.is_empty() and mask.is_valid():  # tests: look at each layer's mask
		DirAccess.make_dir_recursive_absolute(debug_dir)
		var m := _gpu.download(mask)
		m.convert(Image.FORMAT_L8)
		m.save_png(debug_dir.path_join("mask_%s.png" % String(l.get("label", "layer")).validate_filename()))
	var content := {}
	if l.get("@") == "DataLayerGroup":
		# Children composite onto the parent's channels (or the blend's neutral value), then the
		# result goes back through the group's blend, mask and opacity.
		for bit: int in acc:
			var mode: int = blends.get(bit, [_default_blend(bit), 1.0])[0]
			var start: Variant = _neutral(mode, _kind(bit))
			content[bit] = _gpu.new_texture(start) if start is Color else _gpu.copy(acc[bit])
		_composite_children(l, content)
	else:
		for a: Dictionary in SpsmDocument._items(l.get("actions")):
			_layer_action(a, acc, content)
	for bit: int in content:
		var b: Array = blends.get(bit, [_default_blend(bit), 1.0])
		if int(b[0]) != 0 and float(b[1]) > 0.0:
			_gpu.blend(acc[bit], content[bit], _layer_mode(int(b[0])), _kind(bit), float(b[1]), mask)
		_gpu.free_texture(content[bit])
	if mask.is_valid():
		_gpu.free_texture(mask)
	# Anchors in this layer capture the stack as it is now, this layer included.
	for uid in _pending_anchors:
		var snap := {}
		for bit: int in acc:
			snap[bit] = _gpu.copy(acc[bit])
		_anchors[uid] = snap
	_pending_anchors.clear()


func _layer_action(a: Dictionary, acc: Dictionary, content: Dictionary) -> void:
	if not bool(a.get("enabled", true)):
		return
	match a.get("@"):
		"DataActionFill":
			var fb := _blends(a)
			var enabled := int(a.get("channelTypes", 0xFFFFFFFF))
			for s: Variant in a.get("sources", []):
				if not s is Dictionary:
					continue
				for bit: int in acc:
					if not int(s.get("channelTypes", 0)) & bit or not enabled & bit:
						continue
					var kind := _kind(bit)
					var v: Variant = _source_value(s, a, bit, kind)
					if v == null:
						continue
					var b: Array = fb.get(bit, [_default_blend(bit), 1.0])
					if not content.has(bit):
						var start: Variant = _neutral(int(b[0]), kind)
						content[bit] = _gpu.new_texture(start) if start is Color else _gpu.copy(acc[bit])
					_gpu.blend(content[bit], v, _layer_mode(int(b[0])), kind, float(b[1]))
					if v is RID:
						_gpu.free_texture(v)
		"DataActionFilterLevels":
			for bit: int in content:
				if _kind(bit) != Gpu.KIND_NORMAL:
					_levels(a, content[bit])
		"DataActionFilterProcedural":
			var fb := _blends(a)
			for bit: int in content:
				if _kind(bit) == Gpu.KIND_NORMAL:
					continue
				var filtered := _filter(a, content[bit], _kind(bit))
				if filtered.is_valid():
					var b: Array = fb.get(bit, [2, 1.0])
					_gpu.blend(content[bit], filtered, _layer_mode(int(b[0])), _kind(bit), float(b[1]))
					_gpu.free_texture(filtered)
		"DataActionGroup":
			for inner: Dictionary in SpsmDocument._items(a.get("subStack")):
				_layer_action(inner, acc, content)
		"DataActionPaint":
			_stats["skipped_paint"] += 1
		"DataActionAnchor":
			_pending_anchors.append(int(a.get("uid", -1)))


## The layer's mask, or an empty RID when it has none (fully visible).
func _layer_mask(l: Dictionary) -> RID:
	var actions := SpsmDocument._items(l.get("maskActions"))
	if actions.is_empty() or not bool(l.get("maskEnabled", true)):
		return RID()
	var v := float(l.get("maskInitial", 1))
	var mask := _gpu.new_texture(Color(v, v, v))
	for a: Dictionary in actions:
		_mask_action(a, mask)
	return mask


func _mask_action(a: Dictionary, mask: RID) -> void:
	if not bool(a.get("enabled", true)):
		return
	var b := _mask_blend(a)
	match a.get("@"):
		"DataActionFill":
			for s: Variant in a.get("sources", []):
				if s is Dictionary:
					var v: Variant = _source_value(s, a, 0, Gpu.KIND_SCALAR)
					if v != null:
						_gpu.blend(mask, v, b[0], Gpu.KIND_SCALAR, b[1])
						if v is RID:
							_gpu.free_texture(v)
		"DataActionGroup":
			for inner: Dictionary in SpsmDocument._items(a.get("subStack")):
				_mask_action(inner, mask)
		"DataActionFilterLevels":
			_levels(a, mask)
		"DataActionFilterProcedural":
			var filtered := _filter(a, mask, Gpu.KIND_SCALAR)
			if filtered.is_valid():
				_gpu.blend(mask, filtered, b[0], Gpu.KIND_SCALAR, b[1])
				_gpu.free_texture(filtered)
		"DataActionPaint":
			_stats["skipped_paint"] += 1


func _levels(a: Dictionary, tex: RID) -> void:
	var L: Dictionary = a.get("levels") if a.get("levels") is Dictionary else a
	var x := func(key: String, fallback: float) -> float:
		var v: Variant = L.get(key)
		return v.x if v is Vector3 else fallback
	_gpu.levels(tex, x.call("inputMinimum", 0.0), x.call("inputMaximum", 1.0), x.call("gamma", 1.0),
			x.call("outputMinimum", 0.0), x.call("outputMaximum", 1.0), int(L.get("clamp", 1)) != 0)


## {channel bit: [mode, opacity]} from an object's perChannelBlending. Older files have one
## entry per channel; newer ones list only what differs from the default, and one entry can
## cover several channels (a bit mask, -1 for all). Single-channel entries win over shared ones.
static func _blends(o: Dictionary) -> Dictionary:
	var out := {}
	var entries: Array = (o.get("perChannelBlending", []) as Array).filter(func(b: Variant) -> bool: return b is Dictionary)
	entries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return _bit_count(int(x.get("channelTypes", 0))) > _bit_count(int(y.get("channelTypes", 0))))
	for b: Dictionary in entries:
		var v := [int(b.get("blendingMode", 2)), float(b.get("opacity", 1.0))]
		var bits := int(b.get("channelTypes", 0))
		if bits == 0:
			out[0] = v
			continue
		for i in 63:
			if bits & (1 << i):
				out[1 << i] = v
	return out


static func _bit_count(bits: int) -> int:
	var n := 0
	for i in 64:
		if bits & (1 << i):
			n += 1
	return n


## A mask step's blend (the mask is channel 0, or MASK_BIT in newer files): [mode, opacity].
static func _mask_blend(a: Dictionary) -> Array:
	var b := _blends(a)
	return b.get(0, b.get(MASK_BIT, [2, 1.0]))


## How a channel blends and clamps (user channels: like colour).
static func _kind(bit: int) -> int:
	return CHANNELS[bit][1] if CHANNELS.has(bit) else Gpu.KIND_COLOR


static func _default_blend(bit: int) -> int:
	return int(SpsmDocument.DEFAULT_BLEND.get(bit, 2))


## Blends that need no special case on a layer: Passthrough and Replace act as Normal.
static func _layer_mode(mode: int) -> int:
	return 2 if mode in [1, 25] else mode


## The value a blend leaves unchanged, used to start a group's or layer's content so channels it
## does not touch come out as before. null: start from the channel below (Normal-like blends).
static func _neutral(mode: int, kind: int) -> Variant:
	if kind == Gpu.KIND_NORMAL:
		return Color(0.5, 0.5, 1.0) if mode in [26, 27, 28] else null
	match mode:
		10, 29, 30, 8, 7, 17, 18:  # add, subtract, screen, lighten, difference, exclusion
			return Color(0, 0, 0)
		4, 23, 3:  # multiply, divide, darken
			return Color(1, 1, 1)
		11, 12, 13, 15, 31:  # overlay, soft/hard/linear light, signed addition
			return Color(0.5, 0.5, 0.5)
	return null


# --- sources ------------------------------------------------------------------------------------

## The value a fill source gives a channel: a Color, or a new texture (owned by the caller), or
## null when it gives nothing (a graph that failed, a channel it has no output for).
func _source_value(s: Dictionary, fill: Dictionary, bit: int, kind: int) -> Variant:
	var colour_channel := bit in [BASECOLOR, EMISSIVE]
	match s.get("@"):
		"DataSourceUniform":
			var c: Variant = s.get("color")
			if not c is Vector3:
				return null
			return Color(c.x, c.y, c.z) if kind in [Gpu.KIND_COLOR, Gpu.KIND_NORMAL] else Color(c.x, c.x, c.x)
		"DataSourceBitmap":
			var bm: Dictionary = s.get("bitmap", {}) if s.get("bitmap") is Dictionary else {}
			var url := String(bm.get("urlToBitmapRes", ""))
			var tex := RID()
			if url.begins_with("resourcealias:"):
				tex = _map_texture(_alias_usage(url))
			else:
				tex = _file_texture(_bitmap_path(SpsmDocument.sha1_of(url)))
			if not tex.is_valid():
				return null
			return _sampled(tex, fill, Gpu.F_SRGB if colour_channel else (0 if kind in [Gpu.KIND_COLOR, Gpu.KIND_NORMAL] else Gpu.F_GRAY))
		"DataSourceProcedural":
			var p: Dictionary = s.get("procedural", {}) if s.get("procedural") is Dictionary else {}
			var found: Variant = _rendered.get(_key(p))
			if not found is Dictionary:
				found = _procedural(p)  # takes a reference: renders now, with the anchor's snapshot
			var path := _pick_output(p, found, bit)
			var tex := _file_texture(path)
			if not tex.is_valid():
				return null
			var flags := Gpu.F_GRAY
			if colour_channel:
				flags = Gpu.F_SRGB
			elif kind == Gpu.KIND_NORMAL:
				flags = Gpu.F_FLIP_Y  # Substance graphs write DirectX normals
			elif kind == Gpu.KIND_COLOR:
				flags = 0
			return _sampled(tex, fill, flags)
		"DataSourceReference":
			var ref := _reference_texture(s)
			if not ref.is_valid():
				return null
			return _sampled(ref, fill, 0 if kind in [Gpu.KIND_COLOR, Gpu.KIND_NORMAL] else Gpu.F_GRAY)
	return null


## The anchor snapshot a reference reads (its first binding's channel), or an empty RID. The
## texture belongs to the snapshot: don't free it.
func _reference_texture(s: Dictionary) -> RID:
	var ref: Dictionary = s["reference"] if s.get("reference") is Dictionary else {}
	var snap: Dictionary = _anchors.get(int(ref.get("source", -1)), {})
	var bit := -1
	for b: Variant in ref.get("bindings", []):
		if b is Dictionary:
			bit = int(b.get("source", -1))
			break
	if not snap.has(bit):
		_note_reference()
		return RID()
	return snap[bit]


## The mesh-map usage a resource alias stands for ("resourcealias:Curvature" -> "curvature");
## aliases the baker has no map for ("Normal": the high-poly normal) get a neutral stand-in.
static func _alias_usage(url: String) -> String:
	if SpsmDocument.MESH_MAPS.has(url):
		return SpsmDocument.MESH_MAPS[url]
	return url.trim_prefix("resourcealias:").to_lower()


## A reference whose anchor is not below it (or reads a channel the stack lacks).
func _note_reference() -> void:
	_mutex.lock()
	if not _stats.get("reference_noted", false):
		_stats["reference_noted"] = true
		result.warnings.append("A reference to an anchor point could not be resolved: that input uses its default")
	_mutex.unlock()


## A graph's output file for a channel (bit 0: a mask, its first grey output).
static func _pick_output(p: Dictionary, files: Dictionary, bit: int) -> String:
	var fallback := ""
	for o: Variant in p.get("outputs", []):
		if not o is Dictionary:
			continue
		var path := String(files.get(String(o.get("identifier", "")), ""))
		if path.is_empty():
			continue
		var ch := int(o.get("channelTypes", 0))
		if bit != 0 and ch & bit:
			return path
		if bit == 0 and (ch == 0 or String(o.get("identifier")) == "output"):
			return path
		if fallback.is_empty():
			fallback = path
	return fallback if bit == 0 else ""


func _sampled(tex: RID, fill: Dictionary, flags: int) -> RID:
	var t := {}
	# Older files: uvScale / uvPosition / uvRotation. Newer: a uvTransformation0 object.
	var tr: Dictionary = fill["uvTransformation0"] if fill.get("uvTransformation0") is Dictionary else {}
	var sc: Variant = tr.get("scale", fill.get("uvScale"))
	t["scale"] = sc if sc is Vector2 else Vector2.ONE
	var off: Variant = tr.get("translation", fill.get("uvPosition"))
	t["offset"] = off if off is Vector2 else Vector2.ZERO
	t["rotation"] = float(tr.get("rotation", fill.get("uvRotation", 0.0)))
	var proj := int(fill.get("projection", 0))
	if proj in [Gpu.PROJ_TRIPLANAR, Gpu.PROJ_PLANAR] and mesh_maps.has("position") and mesh_maps.has("normalWS"):
		t["projection"] = proj
		t["hardness"] = float(fill.get("sideHardness", 0.5))
		t["pos"] = _map_texture("position")
		t["nrm"] = _map_texture("normalWS")
	var out := _gpu.new_texture()
	_gpu.sample(out, tex, t, flags)
	return out


func _map_texture(usage: String) -> RID:
	var key := "map:" + usage
	if not _textures.has(key):
		var path := String(mesh_maps.get(usage, ""))
		var img := Image.load_from_file(path) if not path.is_empty() and FileAccess.file_exists(path) else null
		if img == null or img.is_empty():
			img = Image.create_empty(4, 4, false, Image.FORMAT_RGBAH)
			img.fill(NEUTRAL_MAPS.get(usage, Color(0.5, 0.5, 0.5)))
		_textures[key] = _gpu.upload(img)
	return _textures[key]


func _file_texture(path: String) -> RID:
	if path.is_empty():
		return RID()
	if not _textures.has(path):
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if img == null or img.is_empty():
			result.warnings.append("Could not read %s" % path)
			_textures[path] = RID()
		else:
			_textures[path] = _gpu.upload(img)
	return _textures[path]


# --- filters ------------------------------------------------------------------------------------

## Runs a filter graph on a texture: the texture is written out, passed to the graph's "input"
## and its output read back. Returns a new texture, or an empty RID if the graph failed.
func _filter(a: Dictionary, tex: RID, kind: int) -> RID:
	var p: Dictionary = a.get("procedural", {}) if a.get("procedural") is Dictionary else {}
	var img := _gpu.download(tex)
	if kind == Gpu.KIND_COLOR:  # graphs see colour as stored (sRGB)
		img.convert(Image.FORMAT_RGBA8)
		img.linear_to_srgb()
	else:
		img.convert(Image.FORMAT_L8 if kind != Gpu.KIND_HEIGHT else Image.FORMAT_RH)
	# Named by content: the same input keeps its file (and time stamp), so the filter's render
	# comes from the cache next time.
	var dir := _cache.path_join("filter_in")
	DirAccess.make_dir_recursive_absolute(dir)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_MD5)
	hash.update(img.get_data())
	var input := dir.path_join("%s.%s" % [hash.finish().hex_encode(), "exr" if kind == Gpu.KIND_HEIGHT else "png"])
	if not FileAccess.file_exists(input):
		var err := img.save_exr(input, true) if kind == Gpu.KIND_HEIGHT else img.save_png(input)
		if err != OK:
			result.warnings.append("Could not write a filter input: %s" % error_string(err))
			return RID()
	var entries := {}
	for i: Variant in a.get("inputs", []):
		if i is Dictionary:
			entries[String(i.get("identifier", "input"))] = input
	if entries.is_empty():
		entries["input"] = input
	var files := _render_graph(p, entries)
	_stats["filters"] += 1
	var path := _pick_output(p, files, 0)
	if path.is_empty():
		return RID()
	var out_img := Image.load_from_file(path)
	if out_img == null or out_img.is_empty():
		return RID()
	var up := _gpu.upload(out_img)
	var out := _gpu.new_texture()
	_gpu.sample(out, up, {}, Gpu.F_SRGB if kind == Gpu.KIND_COLOR else Gpu.F_GRAY)
	_gpu.free_texture(up)
	return out


# --- graphs -------------------------------------------------------------------------------------

## Finds every graph a fill uses (nested graph inputs included) in enabled layers.
func _collect(o: Variant) -> void:
	if o is Dictionary:
		if not bool(o.get("enabled", true)):
			return
		if o.get("@") == "DataProcedural":
			var sha := SpsmDocument.sha1_of(String(o.get("urlToSbsRes", "")))
			_sbsars[sha] = ""
		if o.get("@") == "DataSourceProcedural" and o.get("procedural") is Dictionary and not _has_reference(o["procedural"]):
			_jobs.append(o["procedural"])
		if String(o.get("@", "")).begins_with("DataSource") or o.get("@") == "DataProceduralOutput":
			var bits := int(o.get("channelTypes", 0))
			for i in 63:
				if bits > 0 and bits & (1 << i) and not CHANNELS.has(1 << i):
					_extra_bits[1 << i] = true
		if o.get("@") == "DataSourceBitmap" and o.get("bitmap") is Dictionary:
			var url := String(o["bitmap"].get("urlToBitmapRes", ""))
			if not url.begins_with("resourcealias:"):
				_bitmap_path(SpsmDocument.sha1_of(url))
		for k: String in o:
			# Filters run while compositing; their graphs are extracted here but not prefetched.
			if o.get("@") == "DataActionFilterProcedural" and k == "procedural":
				_sbsars[SpsmDocument.sha1_of(String(o[k].get("urlToSbsRes", "")))] = ""
				continue
			_collect(o[k])
	elif o is Array:
		for v: Variant in o:
			_collect(v)


## The image input ids a graph declares (from its XML, extracted with 7-Zip and cached).
static func graph_inputs(sbsar: String, cfg: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	var xml := SbsarReader.extract_xml(sbsar, String(cfg.get("seven_zip", "")), String(cfg.get("cache_dir", "")).path_join("xml"))
	if xml.has("error"):
		return ids
	for p: Dictionary in SbsarReader.parse(xml["path"]).image_inputs():
		ids.append(p["id"])
	return ids


## Mesh maps the stack's graphs need for Painter's automatic inputs (AUTO_INPUTS): the
## world-space normal, and the position too when a graph takes the tangent frame.
static func auto_mesh_usages(d: SpsmDocument, cfg: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := String(cfg.get("cache_dir", OS.get_cache_dir())).path_join("spsm").path_join("sbsar")
	for sha: String in d.resources:
		if d.resources[sha]["ext"] != "sbsar":
			continue
		var path := d.extract_resource(sha, dir)
		if path.is_empty():
			continue
		for id in graph_inputs(path, cfg):
			if not AUTO_INPUTS.has(id):
				continue
			if not "normalWS" in out:
				out.append("normalWS")
			if AUTO_INPUTS[id] != "normalWS" and not "position" in out:
				out.append("position")
	return out


## Finds the automatic inputs each graph declares and makes their files (the tangent frame is
## computed here, on the GPU, before the graphs render on their threads).
func _prepare_auto_inputs() -> void:
	var wanted := {}
	for sha: String in _sbsars:
		var path := String(_sbsars[sha])
		if path.is_empty():
			continue
		var auto := PackedStringArray()
		for id in graph_inputs(path, config):
			if AUTO_INPUTS.has(id):
				auto.append(id)
				wanted[AUTO_INPUTS[id]] = true
		_auto[sha] = auto
	if wanted.is_empty():
		return
	if not FileAccess.file_exists(String(mesh_maps.get("normalWS", ""))) or 			(not FileAccess.file_exists(String(mesh_maps.get("position", ""))) and (wanted.has("tangentWS") or wanted.has("bitangentWS"))):
		result.warnings.append("A graph needs the mesh's normal and tangent frame, which take the position and world-space normal maps")
		return
	var dir := _cache.path_join("frames")
	DirAccess.make_dir_recursive_absolute(dir)
	for usage: String in wanted:
		var t := _gpu.new_texture()
		_gpu.frame(t, _map_texture("position"), _map_texture("normalWS"), ["tangentWS", "bitangentWS", "normalWS"].find(usage))
		var img := _gpu.download(t)
		_gpu.free_texture(t)
		img.convert(Image.FORMAT_RGBH)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_MD5)
		hash.update(img.get_data())
		var file := dir.path_join("%s_%s.exr" % [usage, hash.finish().hex_encode()])
		if not FileAccess.file_exists(file):
			img.save_exr(file)
		_auto_files[usage] = file


static func _has_reference(o: Variant) -> bool:
	if o is Dictionary:
		if o.get("@") == "DataSourceReference":
			return true
		for v: Variant in o.values():
			if (v is Dictionary or v is Array) and _has_reference(v):
				return true
	elif o is Array:
		for v: Variant in o:
			if _has_reference(v):
				return true
	return false


func _prepare_resources() -> void:
	var dir := _cache.path_join("sbsar")
	for sha: String in _sbsars:
		var path := doc.extract_resource(sha, dir)
		if path.is_empty():
			result.warnings.append("Could not extract graph %s" % sha)
		_sbsars[sha] = path


## Renders the prefetched graphs, PARALLEL at a time. Nested graphs render inside their job.
func _render_graphs() -> void:
	_next_job = 0
	var threads: Array[Thread] = []
	for i in mini(PARALLEL, _jobs.size()):
		var t := Thread.new()
		t.start(_worker)
		threads.append(t)
	for t in threads:
		t.wait_to_finish()


func _worker() -> void:
	while true:
		_mutex.lock()
		var i := _next_job
		_next_job += 1
		_mutex.unlock()
		if i >= _jobs.size():
			return
		_procedural(_jobs[i])


## Renders a fill graph (once per key) and returns {output identifier: file}.
func _procedural(p: Dictionary) -> Dictionary:
	var key := _key(p)
	# A nested graph is both a job of its own and an input of its parent: the first thread to get
	# to it renders it (marked "busy"); any other waits for that result.
	while true:
		_mutex.lock()
		var state: Variant = _rendered.get(key)
		if state == null:
			_rendered[key] = "busy"
		_mutex.unlock()
		if state == null:
			break
		if state is Dictionary:
			return state
		OS.delay_msec(20)
	var entries := {}
	for si: Variant in p.get("sourcesInputs", []):
		if not si is Dictionary or not si.get("source") is Dictionary:
			continue
		var path := _input_file(si["source"])
		if path.is_empty():
			continue
		for i: Variant in si.get("inputs", []):
			if i is Dictionary:
				entries[String(i.get("identifier", ""))] = path
	var files := _render_graph(p, entries)
	_mutex.lock()
	_rendered[key] = files
	_mutex.unlock()
	return files


## The file a graph input gets for a source: a mesh map, a flat colour, a bitmap or another graph.
func _input_file(s: Dictionary) -> String:
	match s.get("@"):
		"DataSourceBitmap":
			var url := String(s.get("bitmap", {}).get("urlToBitmapRes", "")) if s.get("bitmap") is Dictionary else ""
			if url.begins_with("resourcealias:"):
				var usage := _alias_usage(url)
				var path := String(mesh_maps.get(usage, ""))
				return path if FileAccess.file_exists(path) else _constant_file(NEUTRAL_MAPS.get(usage, Color(0.5, 0.5, 0.5)))
			return _bitmap_path(SpsmDocument.sha1_of(url))
		"DataSourceReference":
			return _reference_file(s)
		"DataSourceUniform":
			var c: Variant = s.get("color")
			return _constant_file(Color(c.x, c.y, c.z) if c is Vector3 else Color.WHITE)
		"DataSourceProcedural":
			if s.get("procedural") is Dictionary:
				var files := _procedural(s["procedural"])
				return _pick_output(s["procedural"], files, 0) if not files.is_empty() else ""
	return ""


## An anchor snapshot as a file for a graph input (named by content, so the graph's render is
## cached while the snapshot stays the same). Main render thread only: graphs that take a
## reference are not prefetched (see _collect).
func _reference_file(s: Dictionary) -> String:
	var tex := _reference_texture(s)
	if not tex.is_valid():
		return ""
	var bit := -1
	for b: Variant in (s["reference"] as Dictionary).get("bindings", []):
		if b is Dictionary:
			bit = int(b.get("source", -1))
			break
	var img := _gpu.download(tex)
	img.convert(Image.FORMAT_RGB8)
	if bit in [BASECOLOR, EMISSIVE]:
		img.linear_to_srgb()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_MD5)
	hash.update(img.get_data())
	var path := _cache.path_join("anchors").path_join(hash.finish().hex_encode() + ".png")
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		img.save_png(path)
	return path


## A small flat image file of a colour (graph inputs need a file).
func _constant_file(c: Color) -> String:
	var dir := _cache.path_join("constant")
	var path := dir.path_join(c.to_html(false) + ".png")
	_mutex.lock()
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(dir)
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGB8)
		img.fill(c)
		img.save_png(path)
	_mutex.unlock()
	return path


## The decoded bitmap's file in the cache (decoded on first use). Main render thread only.
func _bitmap_path(sha: String) -> String:
	if sha.is_empty():
		return ""
	var path := _cache.path_join("images").path_join(sha + ".png")
	if FileAccess.file_exists(path):
		return path
	var img := doc.decode_image(sha)
	if img == null:
		result.warnings.append("Could not decode bitmap %s" % sha)
		return ""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if img.get_format() == Image.FORMAT_RGBA16:
		img.convert(Image.FORMAT_RGBA8)
	img.save_png(path)
	return path


## Renders a graph with its tweaks and the given image inputs ({identifier: file}) into the cache,
## keyed by everything that affects it. Returns {output identifier: file}, empty on failure.
func _render_graph(p: Dictionary, entries: Dictionary) -> Dictionary:
	var sha := SpsmDocument.sha1_of(String(p.get("urlToSbsRes", "")))
	_mutex.lock()
	var sbsar := String(_sbsars.get(sha, ""))
	_mutex.unlock()
	if sbsar.is_empty():
		return {}
	var values := PackedStringArray(["$outputsize@%d,%d" % [size_log2, size_log2]])
	for t: Variant in p.get("tweaks", []):
		if not t is Dictionary:
			continue
		var id := String(t.get("identifier", ""))
		if id.is_empty() or id == "$outputsize":
			continue
		values.append("%s@%s" % [id, _format(t.get("value"))])
	entries = entries.duplicate()
	for id: String in _auto.get(sha, PackedStringArray()):  # Painter's automatic inputs
		if not entries.has(id) and _auto_files.has(AUTO_INPUTS[id]):
			entries[id] = _auto_files[AUTO_INPUTS[id]]
	var entry_args := PackedStringArray()
	var stamp := PackedStringArray()
	var ids := entries.keys()
	ids.sort()
	for id: String in ids:
		entry_args.append("%s@%s" % [id, entries[id]])
		stamp.append("%s:%d" % [entries[id], FileAccess.get_modified_time(entries[id])])
	var key := ("%s|%s|%s|%s" % [sha, ",".join(values), ",".join(stamp), config.get("engine", "")]).md5_text()
	var dir := _cache.path_join("graphs").path_join(key)
	var index := dir.path_join("outputs.json")
	if FileAccess.file_exists(index):
		var cached: Variant = JSON.parse_string(FileAccess.get_file_as_string(index))
		if cached is Dictionary and (cached as Dictionary).values().all(func(f: Variant) -> bool: return FileAccess.file_exists(String(f))):
			_mutex.lock()
			_stats["cached"] += 1
			_stats["graphs"] += 1
			_mutex.unlock()
			return cached
	DirAccess.make_dir_recursive_absolute(dir)
	var args := PackedStringArray(["render", "--input", sbsar, "--engine", String(config.get("engine", "d3d11pc")),
			"--output-path", dir, "--output-name", "{outputNodeName}", "--png-format-compression", "best_speed"])
	for v in values:
		args.append_array(["--set-value", v])
	for e in entry_args:
		args.append_array(["--set-entry", e])
	var run := ToolRunner.run(String(config.get("sbsrender", "")), args, PackedStringArray(RENDER_FATAL))
	_mutex.lock()
	_stats["graphs"] += 1
	_mutex.unlock()
	if not run.is_ok():
		_mutex.lock()
		result.warnings.append("Graph %s failed: %s" % [SpsmDocument.resource_name(String(p.get("urlToSbsRes", ""))), "; ".join(run.errors)])
		_mutex.unlock()
		return {}
	var files := {}
	var start := run.stdout.find("[")
	var report: Variant = JSON.parse_string(run.stdout.substr(start)) if start >= 0 else null
	if report is Array:
		for graph: Variant in report:
			if graph is Dictionary:
				for o: Dictionary in graph.get("outputs", []):
					var path := String(o.get("value", ""))
					if FileAccess.file_exists(path):
						files[String(o.get("identifier", ""))] = path
	if not files.is_empty():
		var f := FileAccess.open(index, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(files))
	return files


static func _format(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "1" if v else "0"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return String.num(v, 6)
		TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			var parts := PackedStringArray()
			var n := {TYPE_VECTOR2I: 2, TYPE_VECTOR2: 2, TYPE_VECTOR3I: 3, TYPE_VECTOR3: 3}.get(typeof(v), 4)
			for i in n:
				parts.append(str(v[i]) if typeof(v) in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I] else String.num(v[i], 6))
			return ",".join(parts)
	return str(v)


## Identifies one graph use: its file, tweaks and inputs (the same graph with the same settings
## in two places renders once).
static func _key(p: Dictionary) -> String:
	var copy := p.duplicate(true)
	_strip_uids(copy)
	return var_to_str(copy).md5_text()


static func _strip_uids(o: Variant) -> void:
	if o is Dictionary:
		o.erase("uid")
		for v: Variant in o.values():
			_strip_uids(v)
	elif o is Array:
		for v: Variant in o:
			_strip_uids(v)


# --- output -------------------------------------------------------------------------------------

## Writes a channel: colour as sRGB PNG, normal as RGB PNG, height as a float EXR, the rest as
## greyscale PNG. Returns the file, or "" on failure.
func _write(tex: RID, bit: int, base: String) -> String:
	var img := _gpu.download(tex)
	var kind: int = CHANNELS[bit][1]
	var path := base + (".exr" if kind == Gpu.KIND_HEIGHT else ".png")
	var err: Error
	match kind:
		Gpu.KIND_COLOR:
			img.convert(Image.FORMAT_RGB8)
			img.linear_to_srgb()
			err = img.save_png(path)
		Gpu.KIND_NORMAL:
			img.convert(Image.FORMAT_RGB8)
			err = img.save_png(path)
		Gpu.KIND_HEIGHT:
			img.convert(Image.FORMAT_RH)
			err = img.save_exr(path, true)
		_:
			img.convert(Image.FORMAT_L8)
			err = img.save_png(path)
	if err != OK:
		result.errors.append("Could not write %s: %s" % [path, error_string(err)])
		return ""
	return path
