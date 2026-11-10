extends SceneTree
## Headless check of the Substance backend (describe + render), no editor needed:
##   godot --headless --path <project> --script res://addons/substance_bridge/tests/backend_check.gd

const SubstanceBackend := preload("res://addons/substance_bridge/backends/substance/substance_backend.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")
const Settings := preload("res://addons/substance_bridge/core/settings.gd")

const TARMAC := "C:/Program Files/Allegorithmic/Adobe Substance 3D for Maya/2022/sbsars/tarmac.sbsar"
const EDGING := "D:/07_resources/JRO/Industrial_SmartMaterials/Generators/PL_ISF_Gen_Edging01.sbsar"
const BAKES := "D:/04_projects/SDB/validation/bakes"


func _init() -> void:
	var fails := 0
	var config := {
		"sbsrender": Settings.TOOL_DEFAULTS[Settings.SBSRENDER],
		"seven_zip": Settings.TOOL_DEFAULTS[Settings.SEVEN_ZIP],
		"engine": "d3d11pc",
		"cache_dir": ProjectSettings.globalize_path("user://substance_bridge"),
	}
	var backend := SubstanceBackend.new(config)
	fails += _expect(backend.check_available().is_empty(), "tools available")

	# --- describe
	var d := backend.describe(TARMAC)
	fails += _expect(d.is_ok(), "describe tarmac: %s" % ", ".join(d.errors))
	fails += _expect(d.params.size() == 30 and d.outputs.size() == 8 and d.presets.size() == 2,
			"tarmac: %d params, %d outputs, %d presets (want 30/8/2)" % [d.params.size(), d.outputs.size(), d.presets.size()])
	var dmg := d.find_param("tarmac_damage")
	fails += _expect(dmg.get("label") == "Tarmac Damage" and dmg.get("max") == 1.0 and dmg.get("default") == "0.6",
			"slider metadata: %s" % dmg)
	var nf := d.find_param_by_usertag("$normal_map_format")
	fails += _expect(nf.get("items", []).size() == 2, "normal format combobox: %s" % str(nf.get("items")))
	fails += _expect(d.find_param("signs_color").get("visibleif") == "input[\"painted_arrows\"]==true",
			"visibleif unescaped: %s" % d.find_param("signs_color").get("visibleif"))

	var e := backend.describe(EDGING)
	var ao := e.image_input_for_usage("ambientOcclusion")
	fails += _expect(ao.get("id") == "ambient_occlusion" and e.image_input_for_usage("curvature").get("id") == "curvature",
			"edging image inputs by usage: %s" % ao.get("id"))

	# --- value formatting
	fails += _expect(SubstanceBackend.format_value(Color(0.1, 0.2, 0.3, 1.0), "float3") == "0.1,0.2,0.3", "color -> float3")
	fails += _expect(SubstanceBackend.format_value(true, "int") == "1", "bool -> int")
	fails += _expect(SubstanceBackend.format_value(Vector2(3.4, 5.6), "int2") == "3,6", "vector2 -> int2")

	# --- report with a value output (a float, not a file), as some graphs have
	var rr := RenderResult.new()
	backend._read_report('[{"outputs": [{"identifier": "range_out", "value": 0.53, "usages": []}, '
			+ '{"identifier": "basecolor", "value": "%s", "usages": ["baseColor"]}]}]' % ProjectSettings.globalize_path("res://project.godot"), rr)
	fails += _expect(rr.errors.is_empty() and rr.outputs.size() == 1 and rr.maps.has("baseColor"),
			"a value output in the report is skipped, not read as a file (%s)" % ", ".join(rr.errors))

	# --- render tarmac, OpenGL normals requested
	var req := RenderRequest.new()
	req.source = TARMAC
	req.description = d
	req.size_log2 = Vector2i(10, 10)
	req.random_seed = 42
	req.values = {"tarmac_damage": 0.9, "asphalt_color": Color(0.1, 0.1, 0.12)}
	req.output_dir = ProjectSettings.globalize_path("user://substance_bridge/check/tarmac")
	var r := backend.render(req)
	print("  cmd: ", r.commands[0] if r.commands.size() else "-")
	fails += _expect(r.is_ok(), "render tarmac in %.2f s: %s" % [r.duration_ms / 1000.0, ", ".join(r.errors)])
	fails += _expect(r.maps.has("baseColor") and r.maps.has("normal") and r.maps.has("roughness"), "maps: %s" % str(r.maps.keys()))
	fails += _expect(r.normal_convention == "opengl", "normal convention %s" % r.normal_convention)
	fails += _expect(r.commands.size() > 0 and r.commands[0].contains("normal_format@1"), "normal_format@1 sent")

	# --- render edging with real bakes
	req = RenderRequest.new()
	req.source = EDGING
	req.size_log2 = Vector2i(10, 10)
	req.image_inputs = {"ambient_occlusion": BAKES.path_join("rock01_ao_lowashigh.png"),
			"curvature": BAKES.path_join("rock01_curv_plain.png")}
	req.output_dir = ProjectSettings.globalize_path("user://substance_bridge/check/edging")
	r = backend.render(req)
	fails += _expect(r.is_ok() and r.maps.has("baseColor"), "render edging with image inputs: %s" % ", ".join(r.errors))
	fails += _expect(r.normal_convention == "directx", "no normal switch -> directx")

	# --- failure: missing image
	req.image_inputs = {"ambient_occlusion": "C:/does/not/exist.png"}
	r = backend.render(req)
	fails += _expect(not r.is_ok(), "missing image input is a failure (%d errors)" % r.errors.size())

	print("BACKEND CHECK %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(fails)


func _expect(cond: bool, what: String) -> int:
	print(("  ok   " if cond else "  FAIL ") + what)
	return 0 if cond else 1
