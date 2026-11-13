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
## Graph metadata when the backend has it (Substance: category, author, authorurl, keywords,
## description, physicalSize, primaryinput).
var meta := {}
## Graphs in the source; the bridge uses the first (graph_url).
var graph_count := 1
var errors := PackedStringArray()


func is_ok() -> bool:
	return errors.is_empty()


func find_param(id: String) -> Dictionary:
	for p in params:
		if p["id"] == id:
			return p
	return {}


## Starting values for the material, declared by the graph as "key=value" entries in its keywords (tags), e.g.
## "specular=0.1". Applied once, when the bridge first creates the material; the user tunes them after that.
## Known keys: specular (StandardMaterial3D Specular, 0.5 = the usual 4 % reflectance of non-metals).
func material_hints() -> Dictionary:
	var hints := {}
	for kw in String(meta.get("keywords", "")).split(";", false):
		var kv := kw.strip_edges().split("=")
		if kv.size() == 2 and not kv[0].strip_edges().is_empty() and kv[1].strip_edges().is_valid_float():
			hints[kv[0].strip_edges().to_lower()] = kv[1].to_float()
	return hints


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
