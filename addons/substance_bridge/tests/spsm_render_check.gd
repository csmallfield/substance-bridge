extends SceneTree
## Renders Painter smart materials (.spsm) into maps on the JRO preview sphere, through the
## smart-material backend, on a worker thread like the pipeline does. Needs a window (the
## compositing runs on a RenderingDevice), sbsrender and sbsbaker:
##   set SUBSTANCE_BRIDGE_SPSM=<folder of .spsm files>
##   <godot> --path . --script res://addons/substance_bridge/tests/spsm_render_check.gd
## SUBSTANCE_BRIDGE_SPSM_ALL=1 renders every file in the folder (not just the sample set).
## SUBSTANCE_BRIDGE_SPSM_ONLY=<name> renders just that file (no extension).
## SUBSTANCE_BRIDGE_SPSM_OUT=<folder> also writes a contact sheet of the base colours there.
## SUBSTANCE_BRIDGE_SPSM_DEBUG=<folder> writes every layer's mask there.

const ObjWriter := preload("res://addons/substance_bridge/core/obj_writer.gd")
const MeshBaker := preload("res://addons/substance_bridge/backends/substance/mesh_baker.gd")
const Backends := preload("res://addons/substance_bridge/backends/backends.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")

const SBSRENDER := "C:/Program Files/Allegorithmic/Substance Designer/sbsrender.exe"
const SBSBAKER := "C:/Program Files/Allegorithmic/Substance Automation Toolkit/sbsbaker.exe"
const SEVEN_ZIP := "C:/Program Files/7-Zip/7z.exe"
## One of each feature: plain masks with a stored preview, a fill graph + HSL filter, an
## emboss filter + paint strokes, planar projection, a blur filter, a bitmap fill.
const SAMPLES := ["PL_ISF_MetalPainted02", "PL_ISF_MetalGoldish01", "PL_ISF_FabricCoveredPlastic01",
		"PL_ISF_MetalPainted06", "PL_ISF_WeaveSynthetic01", "PL_ISF_MetalGun01"]
const SIZE_LOG2 := 9

var _checks := 0
var _fails := 0


func _initialize() -> void:
	var folder := OS.get_environment("SUBSTANCE_BRIDGE_SPSM")
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		print("[spsm_render] set SUBSTANCE_BRIDGE_SPSM to a folder of .spsm files")
		quit(1)
		return
	var root := OS.get_temp_dir().path_join("sb_spsm_render")
	var config := {"sbsrender": SBSRENDER, "seven_zip": SEVEN_ZIP, "engine": "d3d11pc", "cache_dir": root.path_join("cache"),
			"spsm_debug_dir": OS.get_environment("SUBSTANCE_BRIDGE_SPSM_DEBUG")}
	var files := PackedStringArray()
	var only := OS.get_environment("SUBSTANCE_BRIDGE_SPSM_ONLY")
	var everything := OS.get_environment("SUBSTANCE_BRIDGE_SPSM_ALL") == "1"
	for path in _spsm_files(folder):  # subfolders included
		var name := path.get_file().get_basename()
		if name == only if not only.is_empty() else (everything or name in SAMPLES):
			files.append(path)

	# The mesh is loaded here: a worker thread must not create render resources while the main
	# thread waits for it.
	DirAccess.make_dir_recursive_absolute(root)
	ObjWriter.write(ObjWriter.collect_arrays(load("res://test/preview_sphere_mesh.res")), root.path_join("preview_sphere.obj"))
	var t := Thread.new()
	t.start(_work.bind(files, config, root))
	var report: Dictionary = t.wait_to_finish()
	for line: String in report["lines"]:
		print(line)
	_checks += int(report["checks"])
	_fails += int(report["fails"])
	var out_dir := OS.get_environment("SUBSTANCE_BRIDGE_SPSM_OUT")
	if not out_dir.is_empty() and not report["sheet"].is_empty():
		_contact_sheet(report["sheet"], out_dir.path_join("spsm_basecolors.png"))
	print("[spsm_render] %d checks, %d failed" % [_checks, _fails])
	print("[spsm_render] RESULT: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)


func _work(files: PackedStringArray, config: Dictionary, root: String) -> Dictionary:
	var rep := {"lines": PackedStringArray(), "checks": 0, "fails": 0, "sheet": []}
	var expect := func(cond: bool, what: String) -> void:
		rep["checks"] += 1
		if not cond:
			rep["fails"] += 1
		rep["lines"].append(("[spsm_render] ok: " if cond else "[spsm_render] FAIL: ") + what)

	var obj := root.path_join("preview_sphere.obj")
	var baked := MeshBaker.bake(SBSBAKER, obj, MeshBaker.supported_usages(), 10, root.path_join("bakes"))
	expect.call(baked["errors"].is_empty(), "mesh maps baked (%.1f s) %s" % [baked["seconds"], "; ".join(baked["errors"])])

	for path in files:
		var backend := Backends.for_source(path, config)
		var desc := backend.describe(path)
		var name := path.get_file().get_basename()
		expect.call(backend.get_backend_id() == "spsm" and desc.is_ok(), "%s: described by the smart-material backend" % name)
		var request := RenderRequest.new()
		request.source = path
		request.description = desc
		request.size_log2 = Vector2i(SIZE_LOG2, SIZE_LOG2)
		request.output_dir = root.path_join("out").path_join(name)
		for p in desc.image_inputs():
			var usage: String = p["usages"][0]
			if baked["maps"].has(usage):
				request.image_inputs[p["id"]] = baked["maps"][usage]
		var started := Time.get_ticks_msec()
		var r: RenderResult = backend.render(request)
		var secs := (Time.get_ticks_msec() - started) / 1000.0
		for c in r.commands:
			rep["lines"].append("[spsm_render]   " + c)
		for w in r.warnings:
			rep["lines"].append("[spsm_render]   warning: " + w)
		expect.call(r.is_ok(), "%s: rendered in %.1f s %s" % [name, secs, "; ".join(r.errors)])
		if not r.is_ok():
			continue
		for usage in ["baseColor", "roughness", "metallic", "normal"]:
			var img := Image.load_from_file(String(r.maps.get(usage, "")))
			expect.call(img != null and img.get_width() == 1 << SIZE_LOG2, "%s: %s map written" % [name, usage])
		var base := Image.load_from_file(r.maps["baseColor"])
		# Some materials are one flat colour (dark leather) and vary only in roughness or relief.
		var spread := 0.0
		for usage in ["baseColor", "roughness", "normal"]:
			spread = maxf(spread, _spread(Image.load_from_file(r.maps[usage])))
		if name in SAMPLES:  # utility smart materials (a normal converter, say) can be flat
			expect.call(spread > 0.01, "%s: the maps vary across the sphere (spread %.3f)" % [name, spread])
		var n := Image.load_from_file(r.maps["normal"])
		var c := n.get_pixel(n.get_width() / 2, n.get_height() / 2)
		expect.call(c.b > 0.5, "%s: normal map points outwards (%s)" % [name, c])
		rep["sheet"].append([name, base])
	return rep


static func _spsm_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() == "spsm":
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_spsm_files(dir.path_join(d)))
	return out


## Standard deviation of luminance over a grid of samples.
static func _spread(img: Image) -> float:
	var vals := PackedFloat32Array()
	for y in range(8, img.get_height(), 16):
		for x in range(8, img.get_width(), 16):
			vals.append(img.get_pixel(x, y).get_luminance())
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	var sq := 0.0
	for v in vals:
		sq += (v - mean) * (v - mean)
	return sqrt(sq / vals.size())


static func _contact_sheet(items: Array, path: String) -> void:
	var cell := 256
	var cols := mini(items.size(), 6)
	var rows := ceili(items.size() / float(cols))
	var sheet := Image.create_empty(cols * cell, rows * cell, false, Image.FORMAT_RGB8)
	for i in items.size():
		var img: Image = (items[i][1] as Image).duplicate()
		img.convert(Image.FORMAT_RGB8)
		img.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	sheet.save_png(path)
	print("[spsm_render] contact sheet: ", path)
