@tool
extends "res://addons/substance_bridge/backends/texture_backend.gd"
## Smart-material backend: renders a Substance Painter smart material (.spsm) into maps
## (spsm/spsm_renderer.gd). The mesh maps its generators take (AO, curvature, position,
## world-space normal, thickness) are declared as image inputs with their usages, so the
## pipeline bakes them from the mesh exactly as it does for mesh-driven .sbsar graphs.
##
## A smart material has no parameters of its own to expose; describe() lists its mesh-map
## inputs and the channels it writes. render() blocks (worker thread) and needs sbsrender plus a
## RenderingDevice (Forward+ or Mobile) for the compositing.

const SpsmDocument := preload("res://addons/substance_bridge/spsm/spsm_document.gd")
const SpsmRenderer := preload("res://addons/substance_bridge/spsm/spsm_renderer.gd")

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func get_backend_id() -> String:
	return "spsm"


func get_display_name() -> String:
	return "Painter smart material"


func get_source_extensions() -> PackedStringArray:
	return PackedStringArray(["spsm"])


func check_available() -> PackedStringArray:
	var problems := PackedStringArray()
	var path: String = _config.get("sbsrender", "")
	if not FileAccess.file_exists(path):
		problems.append("sbsrender not found at \"%s\"" % path)
	return problems


func describe(source: String) -> GraphDescription:
	var d := GraphDescription.new()
	d.source = source
	d.graph_url = source
	var doc: SpsmDocument = SpsmDocument.open(source)
	if not doc.is_ok():
		d.errors.append_array(doc.errors)
		return d
	d.label = doc.label
	var stats := doc.stats()
	d.meta = {"category": "Painter smart material", "keywords": ",".join(PackedStringArray(stats["graphs"].keys()))}
	var usages := doc.mesh_usages()
	for usage in SpsmRenderer.auto_mesh_usages(doc, _config):  # inputs Painter fills itself
		if not usage in usages:
			usages.append(usage)
	for usage: String in usages:
		d.params.append({"id": usage, "type": "image", "default": "", "label": usage.capitalize(), "group": "Mesh maps",
				"widget": "image", "visibleif": "", "usages": PackedStringArray([usage])})
	var channels := PackedStringArray(stats["channels"])
	for bit: int in SpsmRenderer.CHANNELS:
		var usage: String = SpsmRenderer.CHANNELS[bit][0]
		if bit in SpsmRenderer.BASE_CHANNELS or SpsmDocument.CHANNELS.get(bit, "") in channels:
			d.outputs.append({"id": usage, "label": usage.capitalize(), "group": "", "visibleif": "", "usertag": "",
					"usages": PackedStringArray([usage])})
	return d


func render(request: RenderRequest) -> RenderResult:
	if request.output_dir.is_empty():
		var r := RenderResult.new()
		r.errors.append("No output folder given")
		return r
	# Image inputs are keyed by usage (see describe()), so they are the mesh maps as they are.
	return SpsmRenderer.render_stack(request.source, request.image_inputs, request.size_log2.x, _config, request.output_dir)
