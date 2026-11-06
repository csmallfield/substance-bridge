@tool
extends "res://addons/substance_bridge/backends/texture_backend.gd"
## Substance backend: describes .sbsar files from their embedded XML (via 7-Zip) and
## renders them with sbsrender. Command lines mirror docs/validated-commands.md.

const ToolRunner := preload("res://addons/substance_bridge/core/tool_runner.gd")
const SbsarReader := preload("res://addons/substance_bridge/backends/substance/sbsar_reader.gd")

## stderr text that means the render did not do what was asked, even with exit code 0.
## ("Image input "<id>" has not been set" is only fatal for ids we passed; see render().)
const RENDER_FATAL := [
	"Could not load image",    # --set-entry file missing or unreadable
	"Result cannot be saved",  # output folder problem (exit 303)
]

var _config: Dictionary


## config: settings.gd snapshot() (sbsrender, seven_zip, engine, cache_dir).
func _init(config: Dictionary) -> void:
	_config = config


func get_backend_id() -> String:
	return "substance"


func get_display_name() -> String:
	return "Substance (sbsrender)"


func get_source_extensions() -> PackedStringArray:
	return PackedStringArray(["sbsar"])


func check_available() -> PackedStringArray:
	var problems := PackedStringArray()
	for key in ["sbsrender", "seven_zip"]:
		var path: String = _config.get(key, "")
		if not FileAccess.file_exists(path):
			problems.append("%s not found at \"%s\"" % [key, path])
	return problems


func describe(source: String) -> GraphDescription:
	var xml := SbsarReader.extract_xml(source, _config.get("seven_zip", ""),
			String(_config.get("cache_dir", "")).path_join("xml"))
	if xml.has("error"):
		var d := GraphDescription.new()
		d.source = source
		d.errors.append(xml["error"])
		return d
	var desc := SbsarReader.parse(xml["path"])
	desc.source = source
	return desc


func render(request: RenderRequest) -> RenderResult:
	var res := RenderResult.new()
	var started := Time.get_ticks_msec()

	var desc := request.description
	if desc == null:
		desc = describe(request.source)
	if not desc.is_ok():
		res.errors.append_array(desc.errors)
		return res

	if request.output_dir.is_empty():
		res.errors.append("No output folder given")
		return res
	# sbsrender does not create its output folder (fails with exit 303).
	DirAccess.make_dir_recursive_absolute(request.output_dir)
	_clear_images(request.output_dir)

	var values := request.values.duplicate()
	res.normal_convention = _resolve_normal_format(desc, values, request.normal_convention)

	var args := PackedStringArray([
		"render",
		"--input", request.source,
		"--engine", _config.get("engine", "d3d11pc"),
		"--output-path", request.output_dir,
		"--output-name", "{outputNodeName}",
		# Default PNG compression is ~5x slower than best_speed; 16-bit maps stay 16-bit.
		"--png-format-compression", "best_speed",
		"--set-value", "$outputsize@%d,%d" % [request.size_log2.x, request.size_log2.y],
		"--set-value", "$randomseed@%d" % request.random_seed,
	])
	for id: String in values:
		var type: String = desc.find_param(id).get("type", "")
		args.append_array(["--set-value", "%s@%s" % [id, format_value(values[id], type)]])
	for id: String in request.image_inputs:
		args.append_array(["--set-entry", "%s@%s" % [id, request.image_inputs[id]]])

	var run := ToolRunner.run(_config.get("sbsrender", ""), args, PackedStringArray(RENDER_FATAL))
	res.commands.append(run.command_line())
	# An image input we passed that sbsrender did not take (wrong id) is a failure; other
	# unset image inputs are optional ones we left alone, so only a warning.
	for w in run.warnings:
		var failed_entry := false
		for id: String in request.image_inputs:
			if w.contains("Image input \"%s\" has not been set" % id):
				failed_entry = true
		if failed_entry:
			run.errors.append(w)
		else:
			res.warnings.append(w)
	if not run.is_ok():
		res.errors.append_array(run.errors)
		res.duration_ms = Time.get_ticks_msec() - started
		return res

	_read_report(run.stdout, res)
	res.duration_ms = Time.get_ticks_msec() - started
	return res


## Parses sbsrender's JSON report and maps outputs by usage, never by file name.
func _read_report(stdout: String, res: RenderResult) -> void:
	var start := stdout.find("[")
	var report: Variant = JSON.parse_string(stdout.substr(start)) if start >= 0 else null
	if not report is Array:
		res.errors.append("Could not parse the sbsrender JSON report")
		return
	for graph: Dictionary in report:
		for o: Dictionary in graph.get("outputs", []):
			var path: String = o.get("value", "")
			var usages: Array = o.get("usages", [])
			res.outputs.append({"id": o.get("identifier", ""), "label": o.get("label", ""),
					"usages": usages, "path": path})
			if not FileAccess.file_exists(path):
				res.errors.append("Reported output was not written: %s" % path)
				continue
			for u: String in usages:
				if not res.maps.has(u):
					res.maps[u] = path
	if res.maps.is_empty() and res.errors.is_empty():
		res.errors.append("The graph has no outputs with a usage (baseColor, normal, ...)")


## Asks the graph for the wanted normal convention when it exposes a switch
## (usertag "$normal_map_format", a DirectX/OpenGL combobox). Returns the convention the
## normal output will actually have; graphs without a switch are DirectX (Substance default).
func _resolve_normal_format(desc: GraphDescription, values: Dictionary, wanted: String) -> String:
	var p := desc.find_param_by_usertag("$normal_map_format")
	if p.is_empty():
		p = desc.find_param("normal_format")
	if p.is_empty() or p.get("items", []).is_empty():
		return "directx"
	var id: String = p["id"]
	if not values.has(id):
		for item: Dictionary in p["items"]:
			if String(item["text"]).to_lower().contains(wanted):
				values[id] = item["value"]
				break
	var chosen := int(values.get(id, int(p.get("default", "0"))))
	for item: Dictionary in p["items"]:
		if item["value"] == chosen:
			return "opengl" if String(item["text"]).to_lower().contains("opengl") else "directx"
	return "directx"


## Formats a Godot value for --set-value. type is the graph's type for the id (may be "").
static func format_value(v: Variant, type: String) -> String:
	var comps: Array = []
	match typeof(v):
		TYPE_BOOL:
			return "1" if v else "0"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return String.num(v, 6)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v)
		TYPE_COLOR:
			comps = [v.r, v.g, v.b, v.a]
		TYPE_VECTOR2, TYPE_VECTOR2I:
			comps = [v.x, v.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			comps = [v.x, v.y, v.z]
		TYPE_VECTOR4, TYPE_VECTOR4I:
			comps = [v.x, v.y, v.z, v.w]
		_:
			return str(v)
	var count := comps.size()
	if type.length() > 0 and type[-1].is_valid_int():
		count = mini(count, int(type[-1]))
	var is_int := type.begins_with("int")
	var parts := PackedStringArray()
	for i in count:
		parts.append(str(roundi(comps[i])) if is_int else String.num(comps[i], 6))
	return ",".join(parts)


static func _clear_images(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in ["png", "tga", "exr"]:
			DirAccess.remove_absolute(dir.path_join(f))
