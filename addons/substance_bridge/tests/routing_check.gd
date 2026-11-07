extends SceneTree
## Headless checks of the channel-routing plan and its baked transforms.
## godot --headless --path . --script res://addons/substance_bridge/tests/routing_check.gd

const Routing := preload("res://addons/substance_bridge/material/routing.gd")

var _failed := 0


func _initialize() -> void:
	var outputs := [
		{"id": "diffuse", "usages": ["diffuse"], "path": "d.png"},
		{"id": "basecolor", "usages": ["baseColor"], "path": "b.png"},
		{"id": "rough", "usages": ["roughness"], "path": "r.png"},
		{"id": "mask", "usages": [], "path": "m.png"},
	]
	var p := Routing.plan({}, outputs)
	_expect(p.keys() == ["baseColor", "roughness"] and p["baseColor"]["output"]["id"] == "basecolor"
			and not p["baseColor"]["bake"] and not p["roughness"]["explicit"], "no routes: usages only, nothing baked")
	_expect(Routing.plan({}, [outputs[0]]).get("baseColor", {}).get("output", {}).get("id") == "diffuse", "albedo falls back to diffuse")
	var masks := [{"id": "mask_a", "usages": [], "path": "a.png"}, {"id": "mask_b", "usages": [], "path": "b.png"}]
	_expect(Routing.plan({}, masks).keys() == ["baseColor"] and Routing.plan({}, masks)["baseColor"]["output"]["id"] == "mask_a",
			"no usages at all (mask generator): albedo takes the first output")
	_expect(not Routing.plan({}, [outputs[2], outputs[3]]).has("baseColor"), "a usage-less output is not auto-wired when others declare usages")

	p = Routing.plan({"roughness": {"source": "mask", "invert": true, "range": Vector2(0.2, 0.9)},
			"metallic": {"source": "mask"}, "baseColor": {"source": "-"}}, outputs)
	var r: Dictionary = p["roughness"]
	_expect(r["explicit"] and r["bake"] and is_equal_approx(r["a"], -0.7) and is_equal_approx(r["offset"], 0.9),
			"inverted range: v' = 0.9 - 0.7 v")
	_expect(p.has("metallic") and p["metallic"]["output"]["id"] == "mask" and not p.has("baseColor"),
			"one output feeds two slots; None drops a slot")
	p = Routing.plan({"baseColor": {"strength": 0.25}}, outputs)
	_expect(p["baseColor"]["bake"] and is_equal_approx(p["baseColor"]["a"], 0.25) and is_equal_approx(p["baseColor"]["offset"], 0.75),
			"albedo strength fades toward white")

	# Transforms on a ramp.
	var ramp := Image.create(256, 1, false, Image.FORMAT_RGB8)
	for x in 256:
		ramp.set_pixel(x, 0, Color(x / 255.0, x / 510.0, 0.0))
	var grey := Routing.transform(ramp, {"explicit": true, "bake": false, "a": 1.0, "offset": 0.0}, "roughness")
	_expect(grey.get_format() == Image.FORMAT_L8, "colour output into a scalar slot becomes greyscale")
	var same := Routing.transform(ramp, {"explicit": false, "bake": false, "a": 1.0, "offset": 0.0}, "baseColor")
	_expect(same == ramp, "nothing to do: the same image")
	var hf := Image.create(256, 1, false, Image.FORMAT_RF)
	for x in 256:
		hf.set_pixel(x, 0, Color(x / 255.0, 0, 0))
	for c in [[-0.7, 0.9], [0.3, 0.5], [1.0, 0.1], [-1.0, 1.0]]:
		var img := Routing.transform(hf, {"explicit": true, "bake": true, "a": c[0], "offset": c[1]}, "height")
		var worst := 0.0
		for x in 256:
			worst = maxf(worst, absf(img.get_pixel(x, 0).r - (c[1] + c[0] * x / 255.0)))
		_expect(worst < 0.004 and img.get_format() == Image.FORMAT_RF, "float affine a=%.1f offset=%.1f (worst %.5f)" % [c[0], c[1], worst])

	print("ROUTING CHECK ", "PASS" if _failed == 0 else "FAIL (%d)" % _failed)
	quit(1 if _failed else 0)


func _expect(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		_failed += 1
