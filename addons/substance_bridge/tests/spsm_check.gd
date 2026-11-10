extends SceneTree
## Headless checks of the .spsm (Substance Painter smart material) reader.
## Unit checks always run. With SUBSTANCE_BRIDGE_SPSM set to a folder, every .spsm under it is
## opened, its resources resolved and extracted, and one image of each format decoded.
## SUBSTANCE_BRIDGE_SPSM_ALL_IMAGES=1 decodes every embedded image (slow: minutes).
##   set SUBSTANCE_BRIDGE_SPSM=D:\path\to\smart_materials
##   godot --headless --path . --script res://addons/substance_bridge/tests/spsm_check.gd

const SpsmDocument := preload("res://addons/substance_bridge/spsm/spsm_document.gd")
const Preset := preload("res://addons/substance_bridge/spsm/spsm_preset.gd")
const QtStream := preload("res://addons/substance_bridge/spsm/qt_stream.gd")
const Lz4 := preload("res://addons/substance_bridge/spsm/lz4.gd")

const SEVEN_ZIP_MAGIC := [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]

var _failed := 0


func _initialize() -> void:
	_unit_checks()
	var folder := OS.get_environment("SUBSTANCE_BRIDGE_SPSM")
	if folder.is_empty():
		print("SUBSTANCE_BRIDGE_SPSM not set: skipping the file checks.")
	else:
		_file_checks(folder.replace("\\", "/"), OS.get_environment("SUBSTANCE_BRIDGE_SPSM_ALL_IMAGES") == "1")
	print("spsm_check: %s" % ("PASS" if _failed == 0 else "%d FAILED" % _failed))
	quit(1 if _failed else 0)


func _unit_checks() -> void:
	# LZ4: literals "abc", then a match of 9 at offset 3 (overlapping), then literals "Z".
	var block := PackedByteArray([0x35, 0x61, 0x62, 0x63, 0x03, 0x00, 0x10, 0x5A])
	var out := Lz4.decompress_block(block, 0, 13)
	_expect(out.get_string_from_ascii() == "abcabcabcabcZ", "lz4 overlapping match (%s)" % out.get_string_from_ascii())
	_expect(Lz4.decompress_block(block, 0, 12).is_empty(), "lz4 rejects a wrong raw size")
	_expect(Lz4.decompress_block(PackedByteArray([0x10, 0x61, 0x05, 0x00]), 0, 5).is_empty(), "lz4 rejects an offset before the start")
	# Long literal and match lengths (the 15 + extra-bytes path).
	# 20 literals A..T, then a match of 300 at offset 1 (repeats T), then the literal "z".
	var lit := PackedByteArray([0xFF, 20 - 15])
	for i in 20:
		lit.append(65 + i)
	lit.append_array([0x01, 0x00, 255, 300 - 15 - 4 - 255, 0x10, 0x7A])
	out = Lz4.decompress_block(lit, 0, 20 + 300 + 1)
	_expect(out.size() == 321 and out[20] == 84 and out[319] == 84 and out[320] == 0x7A, "lz4 extended lengths")

	# Qt stream: a QVariantMap with a string, an int and a byte array.
	var qs := PackedByteArray([0, 0, 0, 3])
	qs.append_array(_qstring("format"))
	qs.append_array([0, 0, 0, 10, 0])
	qs.append_array(_qstring("LUM8"))
	qs.append_array(_qstring("width"))
	qs.append_array([0, 0, 0, 3, 0, 0, 0, 4, 0])
	qs.append_array(_qstring("blob"))
	qs.append_array([0, 0, 0, 12, 0, 0, 0, 0, 2, 7, 9])
	var m := QtStream.new(qs).qmap()
	_expect(m.get("format") == "LUM8" and m.get("width") == 1024 and m.get("blob") == PackedByteArray([7, 9]), "qt variant map %s" % m)
	var bad := QtStream.new(PackedByteArray([0, 0, 0, 1, 0, 0, 0, 2, 0, 0x41, 0, 0, 0, 99, 0]))
	bad.qmap()
	_expect(not bad.ok(), "qt stream stops on an unknown type")

	# Preset: an object holding a float, a string, a vec3, a 64-bit channel mask (type 0x15, newer
	# files) and a list of one null object.
	var p := PackedByteArray()
	p.resize(12)
	var body := PackedByteArray()
	body.append_array(_field("opacity", 0x01, _f32(0.5)))
	body.append_array(_field("label", 0x10, _str("Base")))
	body.append_array(_field("color", 0x03, _f32(1.0) + _f32(0.5) + _f32(0.25)))
	var mask64 := PackedByteArray()
	mask64.resize(8)
	mask64.encode_s64(0, 1 << 39)
	body.append_array(_field("channelType", 0x15, mask64))
	var list := PackedByteArray([0x12, 0xFF])
	body.append_array(_field("items", 0x11, list, true))
	var obj := PackedByteArray([0x12, 0x00, 0, 0, 0, 0]) + _str("DataLayersPreset") + PackedByteArray([5, 0]) + body
	p.append_array(obj)
	_fix_ends(p)
	var d := Preset.decode(p)
	var r: Dictionary = d["root"]
	_expect(d["error"] == "" and r.get("@") == "DataLayersPreset" and r.get("label") == "Base"
			and r.get("color") == Vector3(1.0, 0.5, 0.25) and r.get("channelType") == 1 << 39 and r.get("items") == [null],
			"preset decode %s %s" % [d["error"], r])
	p[p.size() - 2] = 0x77  # corrupt the list item's type byte: must report, not misread
	_expect(Preset.decode(p)["error"] != "", "preset reports a corrupt type")


func _file_checks(folder: String, all_images: bool) -> void:
	var files := _find(folder)
	_expect(not files.is_empty(), "found .spsm files under %s" % folder)
	var tmp := OS.get_cache_dir().path_join("substance_bridge_spsm_check")
	var classes := {}
	var formats := {}  # format -> [doc, sha1, bytes] (smallest)
	var images := 0
	var with_previews := 0
	var total_ms := 0
	for f in files:
		var t := Time.get_ticks_msec()
		var doc: SpsmDocument = SpsmDocument.open(f)
		total_ms += Time.get_ticks_msec() - t
		if not _expect(doc.is_ok(), "%s opens (%s)" % [f.get_file(), "; ".join(doc.errors)]):
			continue
		SpsmDocument._walk(doc.root, func(o: Dictionary) -> void:
			classes[o["@"]] = int(classes.get(o["@"], 0)) + 1)
		# Every resource URL in the stack points at an embedded resource.
		var missing := PackedStringArray()
		SpsmDocument._walk(doc.root, func(o: Dictionary) -> void:
			for key in ["urlToSbsRes", "urlToBitmapRes"]:
				var url := String(o.get(key, ""))
				if not url.is_empty() and not url.begins_with("resourcealias:") and not doc.resources.has(SpsmDocument.sha1_of(url)):
					missing.append(url))
		_expect(missing.is_empty(), "%s: every resource URL resolves (missing %s)" % [f.get_file(), missing])
		var tree := doc.layer_tree()
		var stats := doc.stats()
		_expect(not tree.is_empty() and stats["layers"] > 0, "%s: %d layers, %d graphs, mesh maps %s" % [
				f.get_file(), stats["layers"], stats["graphs"].size(), stats["mesh_maps"]])
		for sha: String in doc.resources:
			var res: Dictionary = doc.resources[sha]
			if res["ext"] == "sbsar":
				var out := doc.extract_resource(sha, tmp)
				var head := FileAccess.get_file_as_bytes(out).slice(0, 6) if not out.is_empty() else PackedByteArray()
				_expect(Array(head) == SEVEN_ZIP_MAGIC, "%s: %s.sbsar extracts as a 7z archive" % [f.get_file(), res["name"]])
			elif res["ext"] == "image":
				images += 1
				var info := doc.image_info(sha)
				if not _expect(not info.is_empty(), "%s: image %s header" % [f.get_file(), res["name"]]):
					continue
				var key := "%s/%s" % [info["format"], info["compression"]]
				if not formats.has(key) or int(res["size"]) < int(formats[key][2]):
					formats[key] = [doc, sha, res["size"]]
				if all_images:
					_check_image(doc, sha)
		if not doc.preview_names().is_empty():
			with_previews += 1
			var img := doc.preview_image()
			_expect(img != null and img.get_width() > 0, "%s: Painter preview decodes" % f.get_file())
	print("Opened %d files in %d ms (%.0f ms each); %d images; %d with Painter previews" % [
			files.size(), total_ms, total_ms / float(maxi(files.size(), 1)), images, with_previews])
	var names := classes.keys()
	names.sort()
	for n: String in names:
		print("  %6d %s" % [classes[n], n])
	if not all_images:
		for key: String in formats:
			_check_image(formats[key][0], formats[key][1])
	if not files.is_empty():
		var doc: SpsmDocument = SpsmDocument.open(files[0])
		print("\nLayer tree of %s (top first):" % doc.label)
		_print_tree(doc.layer_tree(), 1)
		print("Base values: %s" % doc.base_values())
	DirAccess.remove_absolute(tmp)


func _check_image(doc: SpsmDocument, sha: String) -> void:
	var info: Dictionary = doc.image_info(sha)
	var t := Time.get_ticks_msec()
	var img: Image = doc.decode_image(sha)
	var ms := Time.get_ticks_msec() - t
	var ok := img != null and img.get_width() == int(info["width"]) and img.get_height() == int(info["height"])
	var spread := 0.0
	if ok:
		var small := img.duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		var lo := 1.0
		var hi := 0.0
		for y in 32:
			for x in 32:
				var v := small.get_pixel(x, y).r
				lo = minf(lo, v)
				hi = maxf(hi, v)
		spread = hi - lo
	_expect(ok and spread > 0.02, "decode %s %dx%d %s/%s in %d ms (value spread %.2f)" % [
			doc.resources[sha]["name"], info["width"], info["height"], info["format"], info["compression"], ms, spread])


func _print_tree(nodes: Array, depth: int) -> void:
	for n: Dictionary in nodes:
		var pad := "  ".repeat(depth)
		print("%s%s [%s]%s%s" % [pad, n["name"], n["kind"], "" if n["enabled"] else " (hidden)",
				(" blends: " + ", ".join(n["blends"])) if not n["blends"].is_empty() else ""])
		for s: String in n["sources"]:
			print("%s    · %s" % [pad, s])
		for s: String in n["effects"]:
			print("%s    + %s" % [pad, s])
		if not n["mask"].is_empty():
			print("%s    mask: %s" % [pad, ", ".join(n["mask"])])
		_print_tree(n["children"], depth + 1)


func _find(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() == "spsm":
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_find(dir.path_join(d)))
	return out


# --- byte builders for the unit checks -----------------------------------------------------------

static func _qstring(s: String) -> PackedByteArray:
	var b := PackedByteArray([0, 0, 0, s.length() * 2])
	for c in s:
		b.append_array([0, c.unicode_at(0)])
	return b


static func _str(s: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, s.length())
	return b + s.to_utf8_buffer()


static func _f32(v: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_float(0, v)
	return b


## A named field. Lists get a placeholder end offset and a count of 1 (patched by _fix_ends).
static func _field(name: String, type: int, value: PackedByteArray, is_list := false) -> PackedByteArray:
	var b := _str(name) + PackedByteArray([type])
	if is_list:
		b.append_array([0xEE, 0xEE, 0xEE, 0xEE, 1, 0, 0, 0])
	return b + value


## Patches the end offsets: the root object ends at the end of the data, the list too.
static func _fix_ends(p: PackedByteArray) -> void:
	p.encode_u32(14, p.size())
	for i in p.size() - 4:
		if p[i] == 0xEE and p[i + 1] == 0xEE and p[i + 2] == 0xEE and p[i + 3] == 0xEE:
			p.encode_u32(i, p.size())


func _expect(cond: bool, what: String) -> bool:
	if cond:
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what)
	return cond
