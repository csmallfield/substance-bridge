@tool
extends RefCounted
## Editor check of material hints: a graph's "specular=<v>" keyword sets the material's Specular when the bridge first
## creates the material, a re-render keeps the user's own value, and a graph without the hint keeps Godot's 0.5.
##
##   set SUBSTANCE_BRIDGE_HINTS_TEST=<.sbsar with a specular= keyword>;<.sbsar without one>
##   godot --headless --editor --path <project> --log-file <temp>/hints.log
## Everything it writes is under res://_hints_test, removed at the end.

const SubstanceBackend := preload("res://addons/substance_bridge/backends/substance/substance_backend.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const MaterialBuilder := preload("res://addons/substance_bridge/material/material_builder.gd")
const GraphDescription := preload("res://addons/substance_bridge/backends/graph_description.gd")

const OUT := "res://_hints_test"

var _fails := 0


func run(arg: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var fs := EditorInterface.get_resource_filesystem()
	while fs.is_scanning():
		await tree.process_frame
	var d := GraphDescription.new()
	d.meta["keywords"] = "ground;grass; Specular = 0.12 ;bad=x;=3"
	var h := d.material_hints()
	_expect(h.size() == 1 and is_equal_approx(h.get("specular", -1.0), 0.12), "keywords parse to {specular: 0.12}")

	var paths := arg.split(";")
	var backend := SubstanceBackend.new({
		"sbsrender": Settings.TOOL_DEFAULTS[Settings.SBSRENDER],
		"seven_zip": Settings.TOOL_DEFAULTS[Settings.SEVEN_ZIP],
		"engine": "d3d11pc",
		"cache_dir": ProjectSettings.globalize_path("user://substance_bridge"),
	})
	var with := _render(backend, paths[0], "with")
	if with.size():
		var hints: Dictionary = with["desc"].material_hints()
		_expect(hints.has("specular"), "the cooked graph carries a specular hint (%s)" % str(hints))
		var mat: StandardMaterial3D = await MaterialBuilder.new().build(with["result"], OUT, "hinted", {}, hints)
		_expect(mat != null and is_equal_approx(mat.metallic_specular, float(hints.get("specular", -1.0))),
				"new material starts at the graph's specular (%.3f)" % (mat.metallic_specular if mat else -1.0))
		if mat:
			mat.metallic_specular = 0.3  # the user tunes it
			ResourceSaver.save(mat, mat.resource_path)
			var again: StandardMaterial3D = await MaterialBuilder.new().build(with["result"], OUT, "hinted", {}, hints)
			_expect(again != null and is_equal_approx(again.metallic_specular, 0.3), "re-render keeps the user's 0.3")
	if paths.size() > 1:
		var without := _render(backend, paths[1], "without")
		if without.size():
			var hints2: Dictionary = without["desc"].material_hints()
			var m2: StandardMaterial3D = await MaterialBuilder.new().build(without["result"], OUT, "plain", {}, hints2)
			_expect(hints2.is_empty() and m2 != null and is_equal_approx(m2.metallic_specular, 0.5),
					"graph without hints: Godot's default 0.5")

	_remove(ProjectSettings.globalize_path(OUT))
	fs.scan()
	print("MATERIAL HINTS CHECK ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	tree.quit(1 if _fails else 0)


func _render(backend: SubstanceBackend, sbsar: String, tag: String) -> Dictionary:
	var desc := backend.describe(sbsar)
	_expect(desc.is_ok(), "describe %s" % sbsar.get_file())
	if not desc.is_ok():
		return {}
	var req := RenderRequest.new()
	req.source = sbsar
	req.description = desc
	req.size_log2 = Vector2i(8, 8)
	req.output_dir = ProjectSettings.globalize_path("user://substance_bridge/check/hints_" + tag)
	var r := backend.render(req)
	_expect(r.is_ok(), "render %s" % sbsar.get_file())
	return {"desc": desc, "result": r} if r.is_ok() else {}


static func _remove(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _expect(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		_fails += 1
