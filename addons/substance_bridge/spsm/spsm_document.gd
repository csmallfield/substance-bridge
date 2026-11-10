@tool
extends RefCounted
## A Substance Painter smart material (.spsm), read in place.
##
## The file is HDF5 (see hdf5_reader.gd) holding:
##   preset.bin               the layer stack (spsm_preset.gd)
##   resources/<sha1>.sbsar   the Substance graphs its fills, generators and filters use
##   resources/<sha1>.image   embedded bitmaps: a Qt header then raw or LZ4 pixels
##   resources.toc            resource URLs (missing in some files; not needed)
##   .alg_meta/preset.bin     Painter's metadata, sometimes with WebP previews
##
## Opening reads only the structure and the layer stack; resources are read on demand. Layer
## order in the file is bottom first, as Painter stores it.

const HDF5 := preload("res://addons/substance_bridge/spsm/hdf5_reader.gd")
const Preset := preload("res://addons/substance_bridge/spsm/spsm_preset.gd")
const QtStream := preload("res://addons/substance_bridge/spsm/qt_stream.gd")
const Lz4 := preload("res://addons/substance_bridge/spsm/lz4.gd")

## Painter channel bits (channelTypes) seen in files, and the bridge's names for them.
const CHANNELS := {
	0x1: "basecolor", 0x2: "height", 0x8: "opacity", 0x10: "emissive", 0x80: "roughness",
	0x2000: "metallic", 0x400000: "normal", 0x800000: "ambientOcclusion",
}
## Painter's blending modes by number. 0, 2, 4, 10, 11, 23, 25 and 27 were read back from
## Painter 2019.2 (remote scripting) on its sample projects; the rest follow the order of
## Painter's internal blend codes (Disa, Repl, Norm, Drk, Mul, ... Sadd), which those confirm.
const BLEND_MODES := {
	0: "Disable", 1: "Replace", 2: "Normal", 3: "Darken (Min)", 4: "Multiply", 5: "Color burn",
	6: "Linear burn", 7: "Lighten (Max)", 8: "Screen", 9: "Color dodge", 10: "Linear dodge (Add)",
	11: "Overlay", 12: "Soft light", 13: "Hard light", 14: "Vivid light", 15: "Linear light",
	16: "Pin light", 17: "Difference", 18: "Exclusion", 19: "Saturation", 20: "Color", 21: "Value",
	22: "Tint", 23: "Divide", 24: "Inverse divide", 25: "Passthrough", 26: "Normal map combine",
	27: "Normal map detail", 28: "Normal map inverse detail", 29: "Subtract", 30: "Inverse subtract",
	31: "Signed addition (AddSub)",
}
## Painter's default blend per channel; only differences are reported.
const DEFAULT_BLEND := {0x2: 10, 0x400000: 27, 0x800000: 4}
## Mesh maps a procedural can take, as resource aliases -> MeshBaker usage names.
const MESH_MAPS := {
	"resourcealias:AmbientOcclusion": "ambientOcclusion",
	"resourcealias:Curvature": "curvature",
	"resourcealias:Position": "position",
	"resourcealias:NormalWorldSpace": "normalWS",
	"resourcealias:Thickness": "thickness",
}
const DEFAULT_PREVIEW := "__DEFAULT_PREVIEW__"
## Bytes read for an image header (the Qt map is about 350 bytes).
const IMAGE_HEADER_READ := 2048

var path := ""
var errors := PackedStringArray()
var label := ""
var uuid := ""
var data_version := 0
## The decoded layer stack (DataLayersPreset).
var root := {}
## sha1 -> {"sha1", "ext" ("sbsar"/"image"), "dataset", "size", "name" (from the URLs, may be "")}
var resources := {}

var _h5: HDF5
var _meta := {}
var _meta_read := false


## Opens a file. Always returns a document; check errors / is_ok().
static func open(file_path: String) -> RefCounted:
	var doc := new()
	doc._open(file_path)
	return doc


func is_ok() -> bool:
	return errors.is_empty()


func _open(file_path: String) -> void:
	path = file_path
	label = file_path.get_file().get_basename()
	_h5 = HDF5.new()
	if not _h5.open(file_path):
		errors.append_array(_h5.errors)
		return
	if not _h5.has("preset.bin"):
		errors.append("%s has no layer stack (preset.bin); is it a smart material?" % file_path.get_file())
		return
	var decoded := Preset.decode(_h5.read("preset.bin"))
	if not String(decoded["error"]).is_empty():
		errors.append(decoded["error"])
		return
	root = decoded["root"]
	if root.get("@") != "DataLayersPreset":
		errors.append("Unexpected layer stack root %s" % root.get("@"))
		return
	uuid = root.get("uuid", "")
	data_version = root.get("preset_dataversion", 0)
	var top: Variant = root.get("layerGroup")
	if top is Dictionary and not String(top.get("label", "")).is_empty():
		label = top["label"]
	for ds: String in _h5.datasets:
		if ds.begins_with("resources/") and ds.count("/") == 1:
			var file := ds.get_file()
			resources[file.get_basename()] = {
				"sha1": file.get_basename(), "ext": file.get_extension(), "dataset": ds,
				"size": _h5.size_of(ds), "name": "",
			}
	_walk(root, func(o: Dictionary) -> void:
		for key in ["urlToSbsRes", "urlToBitmapRes"]:
			var sha := sha1_of(String(o.get(key, "")))
			if resources.has(sha) and String(resources[sha]["name"]).is_empty():
				resources[sha]["name"] = resource_name(o[key]))


# --- resources -------------------------------------------------------------------------------------

## The sha1 a resource URL refers to ("/dirt_6/ratio_dirt_6?version=<sha1>.sbsar"), or "".
static func sha1_of(url: String) -> String:
	var i := url.find("version=")
	if i < 0:
		return ""
	return url.substr(i + 8).get_basename()


## A readable name for a resource URL: its first path element ("dirt_6", "PL_grunge_06").
static func resource_name(url: String) -> String:
	if url.begins_with("resourcealias:"):
		return url.trim_prefix("resourcealias:")
	return url.get_slice("?", 0).trim_prefix("/").get_slice("/", 0)


## The raw bytes of a resource ("" sha1 or a missing one gives an empty array).
func read_resource(sha1: String) -> PackedByteArray:
	if not resources.has(sha1):
		return PackedByteArray()
	return _h5.read(resources[sha1]["dataset"])


## Writes a resource to <dir>/<sha1>.<ext> (once: the name is its content hash) and returns
## the path, or "" if it cannot. Embedded .sbsar files are ordinary 7z archives that
## sbsrender renders as they are.
func extract_resource(sha1: String, dir: String) -> String:
	if not resources.has(sha1):
		return ""
	var r: Dictionary = resources[sha1]
	var out := dir.path_join("%s.%s" % [sha1, r["ext"]])
	if FileAccess.file_exists(out) and FileAccess.open(out, FileAccess.READ).get_length() == int(r["size"]):
		return out
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := out + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(read_resource(sha1))
	f.close()
	DirAccess.remove_absolute(out)
	return out if DirAccess.rename_absolute(tmp, out) == OK else ""


## An embedded image's header: width, height, format (LUM8, LUM16, BGRA8, RGBA16), compression
## ("lz4" or "raw"), dataSizeRaw, ... plus "data_offset" (where the pixels start). Empty if the
## resource is not an image or the header cannot be read.
func image_info(sha1: String) -> Dictionary:
	if not resources.has(sha1) or resources[sha1]["ext"] != "image":
		return {}
	var qs := QtStream.new(_h5.read(resources[sha1]["dataset"], 0, IMAGE_HEADER_READ))
	var info := qs.qmap()
	if not qs.ok() or not info.has("width"):
		return {}
	info["data_offset"] = qs.pos
	return info


## Decodes an embedded image into an Image (L8, R16, RGBA8 or RGBA16), or null with the reason
## pushed to errors. Large maps take a while (LZ4 in GDScript); callers should cache.
func decode_image(sha1: String) -> Image:
	var info := image_info(sha1)
	if info.is_empty():
		errors.append("Resource %s is not a readable image" % sha1)
		return null
	var w: int = info["width"]
	var h: int = info["height"]
	var format := String(info.get("format", ""))
	var bpp: int = {"LUM8": 1, "LUM16": 2, "BGRA8": 4, "RGBA16": 8}.get(format, 0)
	if bpp == 0:
		errors.append("Image %s has an unsupported format %s" % [sha1, format])
		return null
	var raw_size := int(info.get("dataSizeRaw", w * h * bpp))
	var pitch := int(info.get("pitch", w * bpp))
	var bytes := _h5.read(resources[sha1]["dataset"], info["data_offset"])
	var pixels := bytes
	match String(info.get("compression", "raw")):
		"lz4":
			pixels = Lz4.decompress_block(bytes, 0, raw_size)
		"raw":
			pass
		var other:
			errors.append("Image %s uses unsupported compression %s" % [sha1, other])
			return null
	if pixels.size() < pitch * h:
		errors.append("Image %s has %d bytes of pixels, expected %d" % [sha1, pixels.size(), pitch * h])
		return null
	if pitch != w * bpp:  # drop row padding
		var packed := PackedByteArray()
		for y in h:
			packed.append_array(pixels.slice(y * pitch, y * pitch + w * bpp))
		pixels = packed
	elif pixels.size() > w * h * bpp:
		pixels = pixels.slice(0, w * h * bpp)
	match format:
		"LUM8":
			return Image.create_from_data(w, h, false, Image.FORMAT_L8, pixels)
		"LUM16":
			return Image.create_from_data(w, h, false, Image.FORMAT_R16, pixels)
		"BGRA8":
			var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, pixels)
			_swap_red_blue(img)
			return img
		_:
			return Image.create_from_data(w, h, false, Image.FORMAT_RGBA16, pixels)


static func _swap_red_blue(img: Image) -> void:
	var d := img.get_data()
	var r := d.duplicate()
	for i in range(0, d.size(), 4):
		d[i] = r[i + 2]
		d[i + 2] = r[i]
	img.set_data(img.get_width(), img.get_height(), false, img.get_format(), d)


# --- Painter's previews ---------------------------------------------------------------------------

## The preview names stored in the file: "__DEFAULT_PREVIEW__" (Painter's shelf thumbnail, a
## shaded ball) and per-channel swatches ("basecolor", "roughness", ...). Many files have none.
func preview_names() -> PackedStringArray:
	return PackedStringArray(_previews().keys())


## A preview as an Image, or null when the file has none by that name.
func preview_image(name := DEFAULT_PREVIEW) -> Image:
	var webp: PackedByteArray = _previews().get(name, PackedByteArray())
	if webp.is_empty():
		return null
	var img := Image.new()
	return img if img.load_webp_from_buffer(webp) == OK else null


func _previews() -> Dictionary:
	if not _meta_read:
		_meta_read = true
		var qs := QtStream.new(_h5.read(".alg_meta/preset.bin") if _h5 else PackedByteArray())
		var meta := qs.qmap() if not qs.data.is_empty() else {}
		var blob: PackedByteArray = meta.get("previews", PackedByteArray()) if qs.ok() else PackedByteArray()
		if not blob.is_empty():
			var ps := QtStream.new(blob)
			for i in ps.u32():  # QMap<QString, QByteArray>
				var k := ps.qstring()
				var v := ps.qbytes()
				if not ps.ok():
					break
				_meta[k] = v
	return _meta


# --- the layer stack --------------------------------------------------------------------------------

## The top group's layers, bottom first.
func layers() -> Array:
	var top: Dictionary = root.get("layerGroup", {}) if root.get("layerGroup") is Dictionary else {}
	return _items(top.get("subStack"))


## A summary tree of the layer stack for display, top layer first. Each node:
##   name, kind ("fill" | "group"), enabled, blends (PackedStringArray of non-default channel
##   blends, "roughness: Multiply 50%"), sources (PackedStringArray, "basecolor ■ #b08a5c",
##   "graph PL_MetalBase01"), mask (PackedStringArray of mask steps), effects (filters etc.),
##   children (Array of nodes, groups only).
func layer_tree() -> Array:
	return _summarise(layers())


func _summarise(items: Array) -> Array:
	var out := []
	for i in range(items.size() - 1, -1, -1):  # top first, like Painter's layer panel
		var l: Dictionary = items[i]
		var node := {
			"name": String(l.get("label", "")), "enabled": bool(l.get("enabled", true)),
			"kind": "group" if l.get("@") == "DataLayerGroup" else "fill",
			"blends": _blend_notes(l), "sources": PackedStringArray(), "effects": PackedStringArray(),
			"mask": PackedStringArray(), "children": [],
		}
		if node["kind"] == "group":
			node["children"] = _summarise(_items(l.get("subStack")))
		for a: Dictionary in _items(l.get("actions")):
			_describe_action(a, node["sources"], node["effects"])
		var mask := _items(l.get("maskActions"))
		if not mask.is_empty() and bool(l.get("maskEnabled", true)):
			var m := PackedStringArray()
			for a: Dictionary in mask:
				_describe_action(a, m, m)
			node["mask"] = m
		out.append(node)
	return out


func _describe_action(a: Dictionary, sources: PackedStringArray, effects: PackedStringArray) -> void:
	var off := "" if a.get("enabled", true) else " (off)"
	match a.get("@"):
		"DataActionFill":
			for s: Variant in a.get("sources", []):
				if s is Dictionary:
					sources.append(_describe_source(s) + off)
		"DataActionFilterProcedural":
			var p: Dictionary = a.get("procedural", {}) if a.get("procedural") is Dictionary else {}
			effects.append("filter %s%s" % [resource_name(p.get("urlToSbsRes", "")), off])
		"DataActionFilterLevels":
			effects.append("levels" + off)
		"DataActionGroup":
			var inner := PackedStringArray()
			for b: Dictionary in _items(a.get("subStack")):
				_describe_action(b, inner, inner)
			if not inner.is_empty():
				effects.append("folder (%s)%s" % [", ".join(inner), off])
		var other:
			effects.append(String(other).trim_prefix("DataAction") + off)


func _describe_source(s: Dictionary) -> String:
	var ch := channel_names(int(s.get("channelTypes", 0)))
	var prefix := (", ".join(ch) + " ") if not ch.is_empty() else ""
	match s.get("@"):
		"DataSourceUniform":
			var c: Variant = s.get("color")
			if c is Vector3:
				if ch.size() == 1 and ch[0] in ["basecolor", "emissive"]:
					return prefix + "colour #" + Color(c.x, c.y, c.z).linear_to_srgb().to_html(false)
				return prefix + "%.2f" % c.x
			return prefix + "uniform"
		"DataSourceProcedural":
			var p: Dictionary = s.get("procedural", {}) if s.get("procedural") is Dictionary else {}
			var outs := PackedStringArray()
			for o: Variant in p.get("outputs", []):
				if o is Dictionary and int(o.get("channelTypes", 0)) != 0:
					var names := channel_names(int(o["channelTypes"]))
					outs.append(", ".join(names) if not names.is_empty() else String(o.get("identifier", "")))
			var what := "graph " + resource_name(p.get("urlToSbsRes", ""))
			return (what + " → " + ", ".join(outs)) if not outs.is_empty() else prefix + what
		"DataSourceBitmap":
			var b: Dictionary = s.get("bitmap", {}) if s.get("bitmap") is Dictionary else {}
			return prefix + "bitmap " + resource_name(b.get("urlToBitmapRes", ""))
	return prefix + String(s.get("@", "?")).trim_prefix("DataSource")


## "roughness: Multiply", "height: mode 8 60%" for blends that differ from Painter's defaults.
func _blend_notes(l: Dictionary) -> PackedStringArray:
	var notes := PackedStringArray()
	for b: Variant in l.get("perChannelBlending", []):
		if not b is Dictionary:
			continue
		var bits := int(b.get("channelTypes", 0))  # newer files: one entry can cover several
		var mode := int(b.get("blendingMode", 2))
		var opacity := float(b.get("opacity", 1.0))
		for bit: int in CHANNELS:
			if not bits & bit:
				continue
			if mode == int(DEFAULT_BLEND.get(bit, 2)) and is_equal_approx(opacity, 1.0):
				continue
			var note := "%s: %s" % [CHANNELS[bit], blend_name(mode)]
			if not is_equal_approx(opacity, 1.0):
				note += " %d%%" % roundi(opacity * 100.0)
			notes.append(note)
	return notes


static func blend_name(mode: int) -> String:
	return BLEND_MODES.get(mode, "mode %d" % mode)


static func channel_names(bits: int) -> PackedStringArray:
	var out := PackedStringArray()
	if bits == 0 or bits == 0xFFFFFFFF or bits < 0:  # none, or "all" (-1 in newer files)
		return out
	for bit: int in CHANNELS:
		if bits & bit:
			out.append(CHANNELS[bit])
	return out


## Counts and lists for the info panel: {"layers": int (fill and group layers, nested),
## "graphs": {name: uses}, "bitmaps": {name: uses}, "mesh_maps": PackedStringArray (see
## mesh_usages()), "channels": PackedStringArray (channels the stack writes)}.
func stats() -> Dictionary:
	var s := {"layers": 0, "graphs": {}, "bitmaps": {}, "mesh_maps": PackedStringArray(), "channels": PackedStringArray()}
	var bits := 0
	var objects: Array[Dictionary] = []
	_walk(root.get("layerGroup", {}), func(o: Dictionary) -> void: objects.append(o))
	for o in objects:
		match o.get("@"):
			"DataLayerColor", "DataLayerGroup":
				s["layers"] += 1
			"DataProcedural":
				var n := resource_name(o.get("urlToSbsRes", ""))
				s["graphs"][n] = int(s["graphs"].get(n, 0)) + 1
			"DataBitmap":
				var u := String(o.get("urlToBitmapRes", ""))
				if not u.begins_with("resourcealias:"):
					var n := resource_name(u)
					s["bitmaps"][n] = int(s["bitmaps"].get(n, 0)) + 1
			"DataSourceUniform", "DataProceduralOutput", "DataSourceBitmap":
				bits |= int(o.get("channelTypes", 0))
	s["layers"] -= 1  # the top group is the material itself
	s["mesh_maps"] = mesh_usages()
	s["channels"] = channel_names(bits)
	return s


## The mesh maps (MeshBaker usages) the enabled layers need: graph inputs, mesh maps used as
## bitmaps, and position + world-space normal for tri-planar and planar fills.
func mesh_usages() -> PackedStringArray:
	var found := {}
	_mesh_usages(root.get("layerGroup", {}), found)
	var out := PackedStringArray()
	for usage: String in MESH_MAPS.values():
		if found.has(usage):
			out.append(usage)
	return out


func _mesh_usages(o: Variant, found: Dictionary) -> void:
	if o is Dictionary:
		if not bool(o.get("enabled", true)):
			return
		var url := String(o.get("urlToBitmapRes", ""))
		if MESH_MAPS.has(url):
			found[MESH_MAPS[url]] = true
		if o.get("@") == "DataActionFill" and int(o.get("projection", 0)) in [1, 2]:
			found["position"] = true
			found["normalWS"] = true
		for v: Variant in o.values():
			if v is Dictionary or v is Array:
				_mesh_usages(v, found)
	elif o is Array:
		for v: Variant in o:
			_mesh_usages(v, found)


## Rough flat values for a quick look before the stack is rendered: per channel, the topmost
## enabled, unmasked layer with a flat colour for it. {"basecolor": Color (sRGB),
## "roughness": float, "metallic": float}; a channel no such layer sets is left out.
func base_values() -> Dictionary:
	var out := {}
	var items := layers()
	for i in range(items.size() - 1, -1, -1):
		var l: Dictionary = items[i]
		if not l.get("enabled", true) or l.get("@") != "DataLayerColor":
			continue
		if not _items(l.get("maskActions")).is_empty() and l.get("maskEnabled", true):
			continue
		for a: Dictionary in _items(l.get("actions")):
			if a.get("@") != "DataActionFill" or not a.get("enabled", true):
				continue
			for s: Variant in a.get("sources", []):
				if not s is Dictionary or s.get("@") != "DataSourceUniform" or not s.get("color") is Vector3:
					continue
				var c: Vector3 = s["color"]
				match int(s.get("channelTypes", 0)):
					0x1:
						if not out.has("basecolor"):
							out["basecolor"] = Color(c.x, c.y, c.z).linear_to_srgb()
					0x80:
						if not out.has("roughness"):
							out["roughness"] = c.x
					0x2000:
						if not out.has("metallic"):
							out["metallic"] = c.x
	return out


static func _items(stack: Variant) -> Array:
	if stack is Dictionary and stack.get("items") is Array:
		return (stack["items"] as Array).filter(func(x: Variant) -> bool: return x is Dictionary)
	return []


static func _walk(o: Variant, visit: Callable) -> void:
	if o is Dictionary:
		visit.call(o)
		for v: Variant in o.values():
			if v is Dictionary or v is Array:
				_walk(v, visit)
	elif o is Array:
		for v: Variant in o:
			if v is Dictionary or v is Array:
				_walk(v, visit)
