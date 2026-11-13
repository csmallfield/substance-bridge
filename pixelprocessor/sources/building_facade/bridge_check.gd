extends SceneTree
## Headless Bridge check of building_facade.sbsar: describe, render defaults (GPU and live CPU engine), every preset.

const SubstanceBackend := preload("res://addons/substance_bridge/backends/substance/substance_backend.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const Settings := preload("res://addons/substance_bridge/core/settings.gd")

const SBSAR := "D:/04_projects/substance_experiments/building_facade/building_facade.sbsar"


func _init() -> void:
	var fails := 0
	var config := {
		"sbsrender": Settings.TOOL_DEFAULTS[Settings.SBSRENDER],
		"seven_zip": Settings.TOOL_DEFAULTS[Settings.SEVEN_ZIP],
		"engine": "d3d11pc",
		"cache_dir": ProjectSettings.globalize_path("user://substance_bridge"),
	}
	var backend := SubstanceBackend.new(config)
	var d := backend.describe(SBSAR)
	fails += _expect(d.is_ok(), "describe: %s" % ", ".join(d.errors))
	print("  params %d, outputs %d, presets %d" % [d.params.size(), d.outputs.size(), d.presets.size()])
	for o in d.outputs:
		print("    output ", o)
	for p in d.params:
		if p.get("label", "") == "" or not p.has("default"):
			fails += _expect(false, "param metadata incomplete: %s" % p)
	for id in ["material", "wall_tint", "brick_ratio", "groups", "lane_pattern", "floors", "special_every", "a_bays", "a_width", "b_style", "c_mullions", "odd_windows", "open_windows", "ac_units", "ac_position", "ground_floor", "ground_bays", "door_share", "door_grouping", "glazed_doors", "curtains", "lit", "streaks", "normal_format"]:
		var p := d.find_param(id)
		print("    %s: %s" % [id, p])
		fails += _expect(not p.is_empty(), "param %s present" % id)
	fails += _expect(d.presets.size() == 18, "18 presets")

	var base := ProjectSettings.globalize_path("user://substance_bridge/check/building_facade")
	# defaults, GPU engine, 1024
	var req := RenderRequest.new()
	req.source = SBSAR
	req.description = d
	req.size_log2 = Vector2i(11, 11)
	req.output_dir = base.path_join("default")
	var r := backend.render(req)
	fails += _expect(r.is_ok(), "render default d3d11pc 2048 in %.2f s: %s" % [r.duration_ms / 1000.0, ", ".join(r.errors)])
	print("    maps: ", r.maps, " normal ", r.normal_convention)
	fails += _expect(r.maps.has("baseColor") and r.maps.has("normal") and r.maps.has("roughness") and r.maps.has("metallic")
			and r.maps.has("height") and r.maps.has("ambientOcclusion") and r.maps.has("emissive"), "PBR + emissive maps present")

	# live preview path: CPU engine at 256
	var live_cfg := config.duplicate()
	live_cfg["engine"] = "sse2"
	var live := SubstanceBackend.new(live_cfg)
	req.size_log2 = Vector2i(8, 8)
	req.values = {"seed": 42, "material": 2, "floors": 8, "lane_pattern": 7, "groups": 5, "ground_floor": true, "ac_units": 0.4}
	req.output_dir = base.path_join("live")
	r = live.render(req)
	fails += _expect(r.is_ok(), "live render sse2 256 in %.2f s: %s" % [r.duration_ms / 1000.0, ", ".join(r.errors)])

	# every preset, GPU 512
	for p in d.presets:
		req = RenderRequest.new()
		req.source = SBSAR
		req.description = d
		req.size_log2 = Vector2i(11, 11)
		req.values = p["values"]
		req.output_dir = base.path_join("preset_" + String(p["label"]).to_snake_case())
		r = backend.render(req)
		fails += _expect(r.is_ok() and r.maps.has("baseColor"), "preset %s in %.2f s: %s" % [p["label"], r.duration_ms / 1000.0, ", ".join(r.errors)])

	print("BUILDING FACADE BRIDGE CHECK %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(fails)


func _expect(cond: bool, what: String) -> int:
	print(("  ok   " if cond else "  FAIL ") + what)
	return 0 if cond else 1
