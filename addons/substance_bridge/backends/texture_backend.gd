@tool
extends RefCounted
## Base class for texture backends.
##
## A backend turns a source (an .sbsar file, later a native noise-generator graph) plus
## parameter values into texture files keyed by usage. The dock, the future inspector
## and the material builder only talk to this interface, so a new backend gets them for free.
##
## describe() and render() block and may run on a worker thread: implementations must not
## touch the scene tree, EditorInterface or EditorSettings. Take settings in _init instead.

const GraphDescription := preload("res://addons/substance_bridge/backends/graph_description.gd")
const RenderRequest := preload("res://addons/substance_bridge/backends/render_request.gd")
const RenderResult := preload("res://addons/substance_bridge/backends/render_result.gd")


## Stable id, e.g. "substance".
func get_backend_id() -> String:
	return ""


func get_display_name() -> String:
	return get_backend_id()


## File extensions this backend opens, without the dot.
func get_source_extensions() -> PackedStringArray:
	return PackedStringArray()


## Reasons the backend cannot run on this machine; empty when ready.
func check_available() -> PackedStringArray:
	return PackedStringArray()


## Parameters, image inputs and outputs of a source. Blocking.
func describe(_source: String) -> GraphDescription:
	var d := GraphDescription.new()
	d.errors.append("%s does not implement describe()" % get_display_name())
	return d


## Render the request to files in request.output_dir. Blocking.
func render(_request: RenderRequest) -> RenderResult:
	var r := RenderResult.new()
	r.errors.append("%s does not implement render()" % get_display_name())
	return r
