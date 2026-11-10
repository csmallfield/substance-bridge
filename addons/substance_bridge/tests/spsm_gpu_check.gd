extends SceneTree
## Smart-material compositing on the GPU (spsm_gpu.gd), run on a worker thread like a render.
## Needs a window (a RenderingDevice):
##   <godot> --path . --script res://addons/substance_bridge/tests/spsm_gpu_check.gd

const Gpu := preload("res://addons/substance_bridge/spsm/spsm_gpu.gd")

var _fails := 0
var _checks := 0


func _initialize() -> void:
	var t := Thread.new()
	t.start(_work)
	var lines: PackedStringArray = t.wait_to_finish()
	for l in lines:
		print(l)
	print("[spsm_gpu] RESULT: %s" % ("PASS" if not lines.is_empty() and not "FAIL" in "\n".join(lines) else "FAIL"))
	quit(0)


func _work() -> PackedStringArray:
	var out := PackedStringArray()
	var g := Gpu.new()
	var err := g.init(64)
	if not err.is_empty():
		out.append("FAIL init: " + err)
		return out
	var expect := func(cond: bool, what: String) -> void:
		out.append(("ok    " if cond else "FAIL  ") + what)
	var px := func(tex: RID, x := 32, y := 32) -> Color:
		return g.download(tex).get_pixel(x, y)

	var d := g.new_texture(Color(0.5, 0.5, 0.5, 1))
	g.blend(d, Color(0.5, 0.5, 0.5), 4, Gpu.KIND_SCALAR)
	expect.call(absf(px.call(d).r - 0.25) < 0.002, "multiply 0.5 x 0.5 = 0.25 (%.3f)" % px.call(d).r)
	g.blend(d, Color(1, 1, 1), 2, Gpu.KIND_SCALAR, 0.5)
	expect.call(absf(px.call(d).r - 0.625) < 0.002, "normal at 50%% over 0.25 = 0.625 (%.3f)" % px.call(d).r)
	g.blend(d, Color(0.5, 0.5, 0.5), 29, Gpu.KIND_SCALAR)
	expect.call(absf(px.call(d).r - 0.125) < 0.002, "subtract 0.5 = 0.125 (%.3f)" % px.call(d).r)
	g.fill(d, Color(0.2, 0.2, 0.2, 1))
	g.blend(d, Color(0.5, 0.5, 0.5), 8, Gpu.KIND_SCALAR)
	expect.call(absf(px.call(d).r - 0.6) < 0.002, "screen 0.2 with 0.5 = 0.6 (%.3f)" % px.call(d).r)
	g.levels(d, 0.0, 1.0, 1.0, 1.0, 0.0)
	expect.call(absf(px.call(d).r - 0.4) < 0.002, "levels with output 1..0 inverts (%.3f)" % px.call(d).r)
	var h := g.new_texture(Color(0, 0, 0, 1))
	g.blend(h, Color(0.7, 0.7, 0.7), 10, Gpu.KIND_HEIGHT)
	g.blend(h, Color(0.7, 0.7, 0.7), 10, Gpu.KIND_HEIGHT)
	expect.call(absf(px.call(h).r - 1.4) < 0.005, "height adds without clamping (%.3f)" % px.call(h).r)

	# A left/right mask: blend only where the mask is white.
	var m_img := Image.create_empty(64, 64, false, Image.FORMAT_L8)
	m_img.fill_rect(Rect2i(32, 0, 32, 64), Color.WHITE)
	var m := g.upload(m_img)
	var c := g.new_texture(Color(0, 0, 0, 1))
	g.blend(c, Color(1, 0, 0), 2, Gpu.KIND_COLOR, 1.0, m)
	expect.call(px.call(c, 10, 10).r < 0.01 and px.call(c, 50, 10).r > 0.99, "a mask limits the blend")

	# Sampling with tiling: a 2-texel checker repeated 4 times has 8 cells across.
	var chk := Image.create_empty(2, 2, false, Image.FORMAT_L8)
	chk.set_pixel(0, 0, Color.WHITE)
	chk.set_pixel(1, 1, Color.WHITE)
	var ct := g.upload(chk, 2)
	var s := g.new_texture()
	g.sample(s, ct, {"scale": Vector2(4, 4)}, Gpu.F_GRAY)
	var img := g.download(s)
	var flips := 0
	for x in range(1, 64):
		if (img.get_pixel(x, 3).r > 0.5) != (img.get_pixel(x - 1, 3).r > 0.5):
			flips += 1
	expect.call(flips >= 6, "tiling x4 repeats the checker (%d edges in a row)" % flips)

	# Normal-map detail of a flat normal with a tilted one keeps the tilt.
	var n := g.new_texture(Color(0.5, 0.5, 1.0, 1))
	g.blend(n, Color(0.7, 0.5, 0.9), 27, Gpu.KIND_NORMAL)
	expect.call(px.call(n).r > 0.6, "normal map detail onto flat keeps the detail (%s)" % px.call(n))

	g.close()

	# Newer files: one blend entry covers several channels; a single-channel entry wins.
	const Renderer := preload("res://addons/substance_bridge/spsm/spsm_renderer.gd")
	var b := Renderer._blends({"perChannelBlending": [
		{"channelTypes": 0x1 | 0x80 | 0x2000, "blendingMode": 25, "opacity": 1.0},
		{"channelTypes": 0x80, "blendingMode": 4, "opacity": 0.5},
	]})
	expect.call(b.get(0x1) == [25, 1.0] and b.get(0x2000) == [25, 1.0] and b.get(0x80) == [4, 0.5],
			"a shared blend entry applies to each of its channels (%s)" % b)
	var all := Renderer._blends({"perChannelBlending": [{"channelTypes": -1, "blendingMode": 8, "opacity": 1.0}]})
	expect.call(all.get(0x400000) == [8, 1.0], "channelTypes -1 means every channel")
	expect.call(Renderer._mask_blend({"perChannelBlending": [{"channelTypes": 1 << 27, "blendingMode": 29, "opacity": 1.0}]}) == [29, 1.0],
			"the newer mask channel bit is read as the mask's blend")
	return out
