@tool
extends RefCounted
## Backend-agnostic description of one graph: parameters, image inputs, outputs, presets.
##
## The Substance backend fills it from the XML inside an .sbsar. A native generator
## backend fills it from code. The inspector and material builder only read this.
##
## params: Array of Dictionary, keys
##   id          String   identifier passed back to the backend ("tarmac_damage", "$randomseed")
##   type        String   "float", "float2".."float4", "int", "int2".."int4", "image", "string"
##   default     String   default value as stored by the backend ("0.6", "0.28,0.25,0.19")
##   label       String   UI label (falls back to id)
##   group       String   UI group ("" = top level)
##   widget      String   "slider", "color", "togglebutton", "combobox", "image", ... ("" = none)
##   visibleif   String   visibility expression, e.g. input["painted_arrows"]==true
##   min/max/step float   slider range (only when widget == "slider")
##   clamp       bool     slider clamps to range
##   items       Array    combobox items: [{value: int, text: String}]
##   usages      PackedStringArray  for image inputs: map usages ("ambientOcclusion", "curvature")
##   usertag     String   backend tag, e.g. "$normal_map_format"
## outputs: Array of Dictionary, keys id, label, group, visibleif, usertag,
##   usages (PackedStringArray: "baseColor", "normal", "roughness", ...)
## presets: Array of Dictionary {label: String, values: {id: String}}

var source := ""
var graph_url := ""
var label := ""
var params: Array[Dictionary] = []
var outputs: Array[Dictionary] = []
var presets: Array[Dictionary] = []
var errors := PackedStringArray()


func is_ok() -> bool:
	return errors.is_empty()


func find_param(id: String) -> Dictionary:
	for p in params:
		if p["id"] == id:
			return p
	return {}


func find_param_by_usertag(tag: String) -> Dictionary:
	for p in params:
		if p.get("usertag", "") == tag:
			return p
	return {}


## Image inputs (type "image"), e.g. the mesh maps of a mesh-adaptive graph.
func image_inputs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p in params:
		if p["type"] == "image":
			result.append(p)
	return result


## Image input whose declared usage matches, or {} (used to auto-wire baked maps).
func image_input_for_usage(usage: String) -> Dictionary:
	for p in image_inputs():
		if usage in p.get("usages", PackedStringArray()):
			return p
	return {}
