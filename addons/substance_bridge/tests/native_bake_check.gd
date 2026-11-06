extends SceneTree
## Bakes the rock with the native baker and compares it with sbsbaker's bakes from step 1.
## Needs a window (GPU): godot --path <project> --script res://addons/substance_bridge/tests/native_bake_check.gd

const NativeBaker := preload("res://addons/substance_bridge/backends/native/native_baker.gd")

const REF := "D:/04_projects/SDB/validation/bakes"
const OUT := "D:/04_projects/SDB/validation/native"
const PAIRS := {"normalWS": "rock01_wsnormal", "curvature": "rock01_curv_plain", "ambientOcclusion": "rock01_ao_lowashigh",
		"position": "rock01_position"}


var _mask: Image


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var mesh := load("res://test/rock01_mesh.res") as Mesh
	var r: Dictionary = await NativeBaker.bake(mesh, PackedStringArray(PAIRS.keys()), 11, OUT, true)
	fails += _expect(r["errors"].is_empty() and r["maps"].size() == 4, "native 2K bake of 4 maps in %.1f s %s" % [r["seconds"], "; ".join(r["errors"])])
	_mask = await NativeBaker.coverage(mesh, 11)
	for usage: String in PAIRS:
		var a := Image.load_from_file(OUT.path_join(usage + ".png"))
		var b := Image.load_from_file(REF.path_join(PAIRS[usage] + ".png"))
		if a == null or b == null:
			fails += _expect(false, "%s images present" % usage)
			continue
		var s := _stats(a, b)
		print("  %-16s corr %.3f  mean %.3f vs %.3f  spread %.3f vs %.3f  mean |diff| %.1f/255" % [usage, s["corr"], s["mean_a"], s["mean_b"], s["sd_a"], s["sd_b"], s["diff"] * 255.0])
		match usage:
			"normalWS":
				fails += _expect(s["diff"] * 255.0 < 6.0, "world normal matches sbsbaker")
			"curvature", "ambientOcclusion":
				fails += _expect(s["corr"] > 0.6, "%s correlates with sbsbaker" % usage)
	_sheet()
	print("NATIVE BAKE CHECK %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(fails)


## Correlation, means and spreads of the red channel over texels covered in both maps.
func _stats(a: Image, b: Image) -> Dictionary:
	var step := maxi(1, a.get_width() / 512)
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var diff := 0.0
	for y in range(0, a.get_height(), step):
		for x in range(0, a.get_width(), step):
			if _mask and _mask.get_pixel(x, y).r < 0.5:
				continue  # island texels only: the two bakers fill the gutter differently
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x * b.get_width() / a.get_width(), y * b.get_height() / a.get_height())
			xs.append(ca.r)
			ys.append(cb.r)
			diff += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
	var n := xs.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += xs[i]
		mb += ys[i]
	ma /= n
	mb /= n
	var cov := 0.0
	var va := 0.0
	var vb := 0.0
	for i in n:
		cov += (xs[i] - ma) * (ys[i] - mb)
		va += (xs[i] - ma) * (xs[i] - ma)
		vb += (ys[i] - mb) * (ys[i] - mb)
	return {"corr": cov / sqrt(maxf(va * vb, 1e-12)), "mean_a": ma, "mean_b": mb,
			"sd_a": sqrt(va / n), "sd_b": sqrt(vb / n), "diff": diff / n}


## Native (top row) vs sbsbaker (bottom row), 320 px each.
func _sheet() -> void:
	var w := 320
	var sheet := Image.create(w * PAIRS.size(), w * 2, false, Image.FORMAT_RGB8)
	var i := 0
	for usage: String in PAIRS:
		for row in 2:
			var img := Image.load_from_file(OUT.path_join(usage + ".png") if row == 0 else REF.path_join(PAIRS[usage] + ".png"))
			img.convert(Image.FORMAT_RGB8)
			img.resize(w, w, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(img, Rect2i(0, 0, w, w), Vector2i(i * w, row * w))
		i += 1
	sheet.save_png(OUT.path_join("_compare.png"))


func _expect(cond: bool, what: String) -> int:
	print(("  ok   " if cond else "  FAIL ") + what)
	return 0 if cond else 1
