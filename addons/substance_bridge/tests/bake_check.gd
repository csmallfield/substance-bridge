extends SceneTree
## Times mesh baking in parallel vs one after another, checks the cache and a bad mesh.
##   godot --headless --path <project> --script res://addons/substance_bridge/tests/bake_check.gd

const ObjWriter := preload("res://addons/substance_bridge/core/obj_writer.gd")
const MeshBaker := preload("res://addons/substance_bridge/backends/substance/mesh_baker.gd")

const SBSBAKER := "C:/Program Files/Allegorithmic/Substance Automation Toolkit/sbsbaker.exe"
const USAGES := ["ambientOcclusion", "curvature", "position", "normalWS"]


func _init() -> void:
	var fails := 0
	var root := OS.get_temp_dir().path_join("sb_bake_check")
	DirAccess.make_dir_recursive_absolute(root)
	var obj := root.path_join("rock.obj")
	ObjWriter.write(ObjWriter.collect_arrays(load("res://test/rock01_mesh.res")), obj)

	for mode in [["sequential", false], ["parallel", true]]:
		var dir := root.path_join(mode[0])
		for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
			DirAccess.remove_absolute(dir.path_join(f))
		var r := MeshBaker.bake(SBSBAKER, obj, PackedStringArray(USAGES), 11, dir, mode[1])
		fails += _expect(r["errors"].is_empty() and r["maps"].size() == 4 and r["baked"] == 4,
				"%s 2K bake of 4 maps: %.1f s %s" % [mode[0], r["seconds"], "; ".join(r["errors"])])

	var cached := MeshBaker.bake(SBSBAKER, obj, PackedStringArray(USAGES), 11, root.path_join("parallel"))
	fails += _expect(cached["baked"] == 0 and cached["maps"].size() == 4, "second bake comes from cache (%.2f s)" % cached["seconds"])

	var thick := MeshBaker.bake(SBSBAKER, obj, PackedStringArray(["thickness"]), 10, root.path_join("thickness"))
	fails += _expect(thick["errors"].is_empty() and thick["maps"].has("thickness"), "thickness bakes (%.1f s at 1K) %s" % [thick["seconds"], "; ".join(thick["errors"])])

	var bad := root.path_join("bad.obj")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("not an obj\n")
	f.close()
	var r := MeshBaker.bake(SBSBAKER, bad, PackedStringArray(["curvature"]), 9, root.path_join("bad"))
	fails += _expect(not r["errors"].is_empty(), "broken mesh is reported: %s" % (r["errors"][0] if r["errors"].size() else "-"))

	print("BAKE CHECK %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(fails)


func _expect(cond: bool, what: String) -> int:
	print(("  ok   " if cond else "  FAIL ") + what)
	return 0 if cond else 1
