@tool
extends RefCounted
## Base class for texture backends.
##
## A backend turns a source (an .sbsar file, later a native noise-generator graph) plus
## parameter values into texture files keyed by usage. The dock, the future inspector
## and the material builder only talk to this interface, so a new backend gets them for free.
##
## describe() blocks and may run on a worker thread: it must not touch the scene tree,
## EditorInterface or EditorSettings. Take settings in _init instead.
##
## render() runs in one of two ways, chosen by runs_on_main_thread():
## - false (external tools, e.g. sbsrender): render() blocks and runs on a worker thread.
## - true (GPU work in the engine, e.g. the noise lab): render() is a coroutine called on the
##   main thread; it may add nodes to the scene tree and await frames.

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


## True when render() must run on the main thread as a coroutine (see above).
func runs_on_main_thread() -> bool:
	return false


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
