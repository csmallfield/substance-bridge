extends SceneTree
## Checks the OBJ writer: exports the imported rock mesh, bakes AO and curvature from the OBJ
## and compares them with the bakes made directly from rock01.fbx in step 1.
##   godot --headless --path <project> --script res://addons/substance_bridge/tests/obj_check.gd

const ObjWriter := preload("res://addons/substance_bridge/core/obj_writer.gd")
const ToolRunner := preload("res://addons/substance_bridge/core/tool_runner.gd")

const SBSBAKER := "C:/Program Files/Allegorithmic/Substance Automation Toolkit/sbsbaker.exe"
const FBX_BAKES := "D:/04_projects/SDB/validation/bakes"


func _init() -> void:
	var fails := 0
	var mesh := load("res://test/rock01_mesh.res") as Mesh
	var out := OS.get_temp_dir().path_join("sb_obj_check")
	DirAccess.make_dir_recursive_absolute(out)
	var obj := out.path_join("rock.obj")

	var t0 := Time.get_ticks_msec()
	var err := ObjWriter.write(ObjWriter.collect_arrays(mesh), obj)
	print("  export: %d ms, %.1f MB" % [Time.get_ticks_msec() - t0, FileAccess.get_file_as_bytes(obj).size() / 1048576.0])
	fails += _expect(err.is_empty(), "OBJ written %s" % err)

	var info := ToolRunner.run(SBSBAKER, ["info", obj])
	fails += _expect(info.is_ok() and info.stdout.contains("Contained within unit square: 1"), "sbsbaker reads it, UVs in unit square")

	for pair in [["ambient-occlusion-from-mesh", "rock01_ao_lowashigh"], ["curvature", "rock01_curv_plain"], ["normal-world-space", "rock01_wsnormal"]]:
		var args := PackedStringArray([pair[0], "--output-size", "11,11", "--output-path", out, "--output-name", pair[1], obj])
		if pair[0].ends_with("-from-mesh"):
			args.insert(1, "true")
			args.insert(1, "--use-lowdef-as-highdef")
		var r := ToolRunner.run(SBSBAKER, args, PackedStringArray(["No high poly scene given"]))
		var a := Image.load_from_file(out.path_join(pair[1] + ".png"))
		var b := Image.load_from_file(FBX_BAKES.path_join(pair[1] + ".png"))
		var diff := _mean_diff(a, b) if a and b else 999.0
		fails += _expect(r.is_ok() and diff < 3.0, "%s from OBJ matches FBX bake: mean diff %.2f/255 (%.1f s)" % [pair[0], diff, r.duration_ms / 1000.0])

	print("OBJ CHECK %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(fails)


## Mean absolute RGB difference on a 256-px grid, in 0-255 units.
func _mean_diff(a: Image, b: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(0, a.get_height(), a.get_height() / 256):
		for x in range(0, a.get_width(), a.get_width() / 256):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			n += 1
	return total / n * 255.0


func _expect(cond: bool, what: String) -> int:
	print(("  ok   " if cond else "  FAIL ") + what)
	return 0 if cond else 1
