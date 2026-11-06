@tool
extends RefCounted
## Reads parameter metadata from an .sbsar.
##
## An .sbsar is a 7z archive holding assemblies/content/0000/<name>.sbsasm + <name>.xml.
## Godot cannot open 7z, so the XML is extracted with 7-Zip into a cache folder keyed by
## the file's path and modification time, then parsed with XMLParser.

const GraphDescription := preload("res://addons/substance_bridge/backends/graph_description.gd")
const ToolRunner := preload("res://addons/substance_bridge/core/tool_runner.gd")

## Substance input type codes (sbsdescription "type" attribute).
const TYPE_NAMES := {
	0: "float", 1: "float2", 2: "float3", 3: "float4",
	4: "int", 5: "image", 6: "string", 7: "font",
	8: "int2", 9: "int3", 10: "int4",
}


## Extracts the XML (cached). Returns {"path": String} or {"error": String}.
static func extract_xml(sbsar: String, seven_zip: String, cache_root: String) -> Dictionary:
	if not FileAccess.file_exists(sbsar):
		return {"error": "File not found: %s" % sbsar}
	var key := ("%s|%d" % [sbsar, FileAccess.get_modified_time(sbsar)]).md5_text()
	var dir := cache_root.path_join(key)
	var cached := _first_xml(dir)
	if not cached.is_empty():
		return {"path": cached}

	DirAccess.make_dir_recursive_absolute(dir)
	# "e -r" flattens the archive's subfolder; without -r "*.xml" matches nothing and 7z still exits 0.
	var r := ToolRunner.run(seven_zip, PackedStringArray([
		"e", "-y", "-r", "-bso0", "-bsp0", "-o" + dir, sbsar, "*.xml"]))
	if not r.is_ok():
		return {"error": "7-Zip could not extract %s: %s" % [sbsar.get_file(), "; ".join(r.errors)]}
	var xml := _first_xml(dir)
	if xml.is_empty():
		return {"error": "No XML found inside %s" % sbsar.get_file()}
	return {"path": xml}


static func _first_xml(dir: String) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() == "xml":
			return dir.path_join(f)
	return ""


## Parses one graph (the first, or the one whose pkgurl matches graph_url).
static func parse(xml_path: String, graph_url: String = "") -> GraphDescription:
	var d := GraphDescription.new()
	var p := XMLParser.new()
	var err := p.open(xml_path)
	if err != OK:
		d.errors.append("Cannot open %s (%s)" % [xml_path, error_string(err)])
		return d

	var in_graph := false
	var found := false
	var cur := {}          # input or output being read
	var cur_kind := ""     # "input" / "output"
	var preset := {}

	while p.read() == OK:
		var node_type := p.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var tag := p.get_node_name()
			var a := _attributes(p)
			var empty := p.is_empty()

			if tag == "graph":
				var url: String = a.get("pkgurl", "")
				in_graph = not found and (graph_url.is_empty() or url == graph_url)
				if in_graph:
					found = true
					d.graph_url = url
					d.label = a.get("label", url.trim_prefix("pkg://"))
			elif not in_graph:
				pass
			elif tag == "sbspreset":
				preset = {"label": a.get("label", ""), "values": {}}
				if empty:
					d.presets.append(preset)
					preset = {}
			elif tag == "presetinput" and not preset.is_empty():
				preset["values"][a.get("identifier", "")] = a.get("value", "")
			elif tag == "input":
				var code := int(a.get("type", "-1"))
				cur_kind = "input"
				cur = {
					"id": a.get("identifier", ""), "type": TYPE_NAMES.get(code, "unknown"),
					"default": a.get("default", ""), "usertag": a.get("usertag", ""),
					"label": a.get("identifier", ""), "group": "", "widget": "", "visibleif": "",
					"items": [], "usages": PackedStringArray(),
				}
				if empty:
					_finish(d, cur_kind, cur)
					cur = {}
			elif tag == "output":
				cur_kind = "output"
				cur = {
					"id": a.get("identifier", ""), "usertag": a.get("usertag", ""),
					"label": a.get("identifier", ""), "group": "", "visibleif": "",
					"usages": PackedStringArray(),
				}
				if empty:
					_finish(d, cur_kind, cur)
					cur = {}
			elif cur.is_empty():
				pass
			elif tag == "inputgui" or tag == "outputgui":
				cur["label"] = a.get("label", cur["label"])
				cur["group"] = a.get("group", "")
				cur["visibleif"] = a.get("visibleif", "")
				if a.has("widget"):
					cur["widget"] = a["widget"]
			elif tag == "guislider":
				cur["min"] = float(a.get("min", "0"))
				cur["max"] = float(a.get("max", "1"))
				cur["step"] = float(a.get("step", "0.01"))
				cur["clamp"] = a.get("clamp", "") == "on"
			elif tag == "guicomboboxitem":
				cur["items"].append({"value": int(a.get("value", "0")), "text": a.get("text", "")})
			elif tag == "channel":
				for u in String(a.get("names", "")).split(" ", false):
					cur["usages"].append(u)

		elif node_type == XMLParser.NODE_ELEMENT_END:
			var tag := p.get_node_name()
			if tag == "graph":
				in_graph = false
			elif (tag == "input" or tag == "output") and not cur.is_empty():
				_finish(d, cur_kind, cur)
				cur = {}
			elif tag == "sbspreset" and not preset.is_empty():
				d.presets.append(preset)
				preset = {}

	if not found:
		d.errors.append("Graph %s not found in %s" % [graph_url if graph_url else "(any)", xml_path.get_file()])
	return d


static func _finish(d: GraphDescription, kind: String, entry: Dictionary) -> void:
	if kind == "input":
		d.params.append(entry)
	else:
		d.outputs.append(entry)


static func _attributes(p: XMLParser) -> Dictionary:
	var a := {}
	for i in p.get_attribute_count():
		a[p.get_attribute_name(i)] = _unescape(p.get_attribute_value(i))
	return a


static func _unescape(s: String) -> String:
	if not s.contains("&"):
		return s
	return s.replace("&quot;", "\"").replace("&apos;", "'").replace("&lt;", "<") \
		.replace("&gt;", ">").replace("&amp;", "&")
