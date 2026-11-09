@tool
extends RefCounted
## Editor check of opacity: render a graph with an opacity output through the Substance backend, build the material
## with MaterialBuilder, and check that the albedo carries the opacity in its alpha and alpha scissor is on; then
## route Opacity to None, rebuild, and check alpha scissor is off again.
##
##   set SUBSTANCE_BRIDGE_OPACITY_TEST=<path to an .sbsar with an opacity output>
##   godot --headless --editor --path <project> --log-file <temp>/opacity.log

const SubstanceBackend := preload("res://addons/substance_bridge/backends/substance/substance_backend.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")

const OUT := "res://test/opacity_check"

var _fails := 0


func run(sbsar: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var fs := EditorInterface.get_resource_filesystem()
	while fs.is_scanning():
		await tree.process_frame
	print("[opacity] ", sbsar)
	var config := {
		"sbsrender": Settings.TOOL_DEFAULTS[Settings.SBSRENDER],
		"seven_zip": Settings.TOOL_DEFAULTS[Settings.SEVEN_ZIP],
		"engine": "d3d11pc",
		"cache_dir": ProjectSettings.globalize_path("user://substance_bridge"),
	}
	var backend := SubstanceBackend.new(config)
	var d := backend.describe(sbsar)
	_expect(d.is_ok(), "describe")
	var req := RenderRequest.new()
	req.source = sbsar
	req.description = d
	req.size_log2 = Vector2i(10, 9)
	req.output_dir = ProjectSettings.globalize_path("user://substance_bridge/check/opacity")
	var r := backend.render(req)
	_expect(r.is_ok() and r.maps.has("opacity"), "render has an opacity map")

	var b := MaterialBuilder.new()
	var mat: StandardMaterial3D = await b.build(r, OUT, "opacity_test")
	for l in b.log_lines:
		print("    ", l)
	_expect(mat != null, "material built")
	if mat:
		_expect(mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				and is_equal_approx(mat.alpha_scissor_threshold, 0.5), "alpha scissor on, threshold 0.5")
		var img := mat.albedo_texture.get_image() if mat.albedo_texture else null
		if img and img.is_compressed():
			img.decompress()
		var lo := 0
		var hi := 0
		if img:
			for i in 400:
				var a := img.get_pixel(i * 37 % img.get_width(), i * 53 % img.get_height()).a
				lo += 1 if a < 0.2 else 0
				hi += 1 if a > 0.8 else 0
		_expect(img != null and lo > 20 and hi > 20, "albedo alpha has holes and solid parts (%d low, %d high of 400)" % [lo, hi])
		_expect(not FileAccess.file_exists(OUT.path_join("opacity_test/opacity_test_opacity.png")), "no separate opacity texture")

		b = MaterialBuilder.new()
		mat = await b.build(r, OUT, "opacity_test", {"opacity": {"source": "-"}})
		_expect(mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Opacity routed to None: alpha scissor off")

	print("OPACITY CHECK ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	tree.quit(1 if _fails else 0)


func _expect(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		_fails += 1
