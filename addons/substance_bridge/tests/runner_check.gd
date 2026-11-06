extends SceneTree
## Headless check of the tool runner against the real tools:
##   godot --headless --path <project> --script res://addons/substance_bridge/tests/runner_check.gd

const ToolRunner := preload("res://addons/substance_bridge/core/tool_runner.gd")

const SBSRENDER := "C:/Program Files/Allegorithmic/Substance Designer/sbsrender.exe"
const TARMAC := "C:/Program Files/Allegorithmic/Adobe Substance 3D for Maya/2022/sbsars/tarmac.sbsar"
const EDGING := "D:/07_resources/JRO/Industrial_SmartMaterials/Generators/PL_ISF_Gen_Edging01.sbsar"


func _init() -> void:
	var fails := 0
	var out_dir := OS.get_temp_dir().path_join("sb_runner_check")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var r := ToolRunner.run(SBSRENDER, ["--version"])
	print("version: ", r.summary(), " stdout=", r.stdout.strip_edges())
	fails += _expect(r.is_ok() and r.stdout.contains("11."), "--version ok")

	r = ToolRunner.run(SBSRENDER, ["info", TARMAC])
	fails += _expect(r.is_ok() and r.stdout.contains("OUTPUT basecolor baseColor"), "info stdout captured (%d bytes)" % r.stdout.length())

	r = ToolRunner.run(SBSRENDER, ["render", "--input", TARMAC, "--output-path", out_dir.path_join("missing_dir"), "--set-value", "$outputsize@8,8"])
	fails += _expect(not r.is_ok() and r.exit_code == 303, "missing output dir fails with 303 (got %d)" % r.exit_code)

	r = ToolRunner.run(SBSRENDER, ["render", "--input", EDGING, "--output-path", out_dir, "--set-value", "$outputsize@8,8", "--set-entry", "nope@C:/x.png"],
			PackedStringArray(["has not been set", "Could not load image"]))
	fails += _expect(not r.is_ok() and r.exit_code == 0, "unset image input fails despite exit 0 (errors=%d)" % r.errors.size())

	r = ToolRunner.run(SBSRENDER, ["render", "--input", TARMAC, "--output-path", out_dir, "--set-value", "$outputsize@9,9"])
	fails += _expect(r.is_ok() and r.stdout.begins_with("[") and JSON.parse_string(r.stdout) is Array, "render JSON report parsed (%.2f s)" % (r.duration_ms / 1000.0))

	r = ToolRunner.run("C:/nope/missing.exe", [])
	fails += _expect(not r.is_ok(), "missing exe reported")

	print("RUNNER CHECK %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(fails)


func _expect(cond: bool, what: String) -> int:
	print(("  ok   " if cond else "  FAIL ") + what)
	return 0 if cond else 1
