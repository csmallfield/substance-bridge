@tool
extends RefCounted
## Bakes mesh maps from an OBJ with sbsbaker (docs/validated-commands.md, section 4).
##
## Maps are keyed by Substance usage, the same names image inputs declare in their
## .sbsar XML, so they can be wired to a graph without guessing from identifiers.
## Bakes are cached per mesh content and size: an existing map file is reused.
##
## bake() blocks; run it on a worker thread.

const ToolRunner := preload("res://addons/substance_bridge/core/tool_runner.gd")

## Usage -> sbsbaker command + options. The *-from-mesh bakers need a high-poly mesh; the
## mesh itself stands in for it (without that they write nothing and still exit 0).
const BAKERS := {
	"ambientOcclusion": ["ambient-occlusion-from-mesh", "--use-lowdef-as-highdef", "true"],
	"curvature": ["curvature"],
	"position": ["position"],
	"normalWS": ["normal-world-space"],
	"thickness": ["thickness-from-mesh", "--use-lowdef-as-highdef", "true"],
}

## Output that means the bake failed even with exit code 0.
const FATAL := ["No high poly scene given", "couldn't be loaded", "cannot be loaded"]


static func supported_usages() -> PackedStringArray:
	return PackedStringArray(BAKERS.keys())


## Bakes the requested usages. Returns
## {"maps": {usage: abs path}, "errors": PackedStringArray, "commands": PackedStringArray,
##  "baked": int (maps actually baked, not from cache), "seconds": float}.
static func bake(sbsbaker: String, obj_path: String, usages: PackedStringArray,
		size_log2: int, out_dir: String, parallel: bool = true, force: bool = false) -> Dictionary:
	var started := Time.get_ticks_msec()
	var out := {"maps": {}, "errors": PackedStringArray(), "commands": PackedStringArray(), "baked": 0}
	DirAccess.make_dir_recursive_absolute(out_dir)

	var jobs: Array[Dictionary] = []
	for usage in usages:
		if not BAKERS.has(usage):
			out["errors"].append("No baker for usage \"%s\"" % usage)
			continue
		var file := out_dir.path_join(usage + ".png")
		if force and FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
		if FileAccess.file_exists(file):
			out["maps"][usage] = file
			continue
		var args := PackedStringArray([BAKERS[usage][0]])
		args.append_array(PackedStringArray(BAKERS[usage].slice(1)))
		args.append_array(["--output-size", "%d,%d" % [size_log2, size_log2],
				"--output-path", out_dir, "--output-name", usage, obj_path])
		jobs.append({"usage": usage, "args": args, "file": file})

	var results := []
	if parallel and jobs.size() > 1:
		var threads: Array[Thread] = []
		for job in jobs:
			var t := Thread.new()
			t.start(ToolRunner.run.bind(sbsbaker, job["args"], PackedStringArray(FATAL)))
			threads.append(t)
		for t in threads:
			results.append(t.wait_to_finish())
	else:
		for job in jobs:
			results.append(ToolRunner.run(sbsbaker, job["args"], PackedStringArray(FATAL)))

	for i in jobs.size():
		var job: Dictionary = jobs[i]
		var r = results[i]
		out["commands"].append(r.command_line())
		if not r.is_ok():
			out["errors"].append("%s: %s" % [job["usage"], "; ".join(r.errors)])
		elif not FileAccess.file_exists(job["file"]):
			out["errors"].append("%s: sbsbaker reported success but wrote no file" % job["usage"])
		else:
			out["maps"][job["usage"]] = job["file"]
			out["baked"] += 1
	out["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	return out
