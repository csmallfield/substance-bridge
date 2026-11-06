@tool
extends Resource
## Source of truth for one generated material: the source graph plus every parameter
## value you changed. Textures and the material are regenerated from this.
##
## The graph's parameters appear as inspector properties generated from its description
## (labels, ranges, groups, colour pickers, dropdowns, toggles, visibility rules, presets).
## Only values that differ from the graph's defaults are stored, in `values`.

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const Task := preload("res://addons/substance_bridge/core/task.gd")
const GraphDescription := preload("res://addons/substance_bridge/backends/graph_description.gd")
const Backends := preload("res://addons/substance_bridge/backends/backends.gd")
const MeshBaker := preload("res://addons/substance_bridge/backends/substance/mesh_baker.gd")
const Routing := preload("res://addons/substance_bridge/material/routing.gd")

## Emitted when something that affects the rendered maps changes (debounced by the dock).
signal parameters_changed
## Emitted when the graph description has loaded (its properties are now listed).
signal description_loaded

const SIZE_NAMES := {8: "256", 9: "512", 10: "1K", 11: "2K", 12: "4K"}

## Our own property names; graph parameters with these ids get a "param_" prefix.
const RESERVED := ["source", "random_seed", "preview_size", "final_size", "auto_preview",
		"material", "values", "output_name", "last_render_key", "backend_id", "preset",
		"bake_size", "baked_mesh", "mesh_obj", "baker", "routes",
		"script", "resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id"]

## The .sbsar this material is generated from. Read-only in the inspector: the folder,
## material name and parameter values all belong to this graph. To try another .sbsar on
## the same mesh, create a new material from the dock.
@export_custom(PROPERTY_HINT_GLOBAL_FILE, "*.sbsar", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY)
var source := "":
	set(v):
		if v == source:
			return
		# Keep loaded values while the resource is being read from disk (source was empty).
		if not source.is_empty():
			values.clear()
		source = v
		backend_id = Backends.id_for_source(v)
		_description = null
		_request_description()
		notify_property_list_changed()
		_params_changed()

@export var random_seed := 0:
	set(v):
		random_seed = v
		_params_changed()

@export_enum("256:8", "512:9", "1K:10", "2K:11") var preview_size := 9:
	set(v):
		preview_size = v
		_params_changed()

@export_enum("512:9", "1K:10", "2K:11", "4K:12") var final_size := 11

## Re-render a preview automatically after each change.
@export var auto_preview := true

## Size of the mesh maps (AO, curvature, ...) baked for mesh-adaptive graphs. They are baked
## once per mesh and size and reused by every preview and final render.
@export_enum("1K:10", "2K:11", "4K:12") var bake_size := 11:
	set(v):
		bake_size = v
		_params_changed()

## Which baker makes the mesh maps. Native bakes AO, curvature, position and world normal in
## Godot (no Substance tools; needs the editor window visible); thickness always uses sbsbaker.
@export_enum("Substance (sbsbaker)", "Native (Godot)") var baker := 0:
	set(v):
		baker = v
		_params_changed()

## Mesh the maps are baked from (set with the dock's "Bake from Selected Mesh").
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY)
var baked_mesh := ""

## The mesh, exported as OBJ into the cache: user://substance_bridge/meshes/<md5>.obj.
@export_storage var mesh_obj := "":
	set(v):
		mesh_obj = v
		_params_changed()

## The material this resource generates: <output_name>.tres next to this file. Shown in the
## inspector but not saved, so tracked settings never reference generated (git-ignored) files.
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "StandardMaterial3D", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var material: StandardMaterial3D:
	get:
		if material == null and not output_name.is_empty() and not resource_path.is_empty():
			var path := resource_path.get_base_dir().path_join(output_name + ".tres")
			if ResourceLoader.exists(path):
				material = ResourceLoader.load(path) as StandardMaterial3D
		return material

@export_storage var backend_id := "substance"
## Folder/file name used for the generated textures and material.
@export_storage var output_name := ""
## Parameter id -> value, only for parameters changed from their defaults.
@export_storage var values := {}
## Channel routing (material/routing.gd): slot -> {source?, strength?, invert?, range?},
## only what differs from the defaults. Edited as the inspector's Material Slots group.
@export_storage var routes := {}

## Hash of the inputs of the last render this session; identical inputs are not rendered
## again. Not saved (it is cache state), so the first preview after a restart renders once.
var last_render_key := ""

var _description: GraphDescription
var _describe_task: Task
var _expressions := {}


func get_description() -> GraphDescription:
	return _description


func is_described() -> bool:
	return _description != null and _description.is_ok()


## Hash of everything that affects the rendered maps at this size.
func render_key(size_log2: int) -> String:
	var mtime := FileAccess.get_modified_time(source) if FileAccess.file_exists(source) else 0
	var mesh := [mesh_obj, bake_size, baker] if not mesh_usages().is_empty() else []
	return var_to_str([backend_id, source, mtime, values, random_seed, size_log2, mesh, routes]).md5_text()


const BAKER_SUBSTANCE := 0
const BAKER_NATIVE := 1


## Image input id per mesh-map usage, e.g. {"ambientOcclusion": "ambient_occlusion"}.
func mesh_inputs() -> Dictionary:
	var wanted := {}
	if _description == null:
		return wanted
	for p in _description.image_inputs():
		for u: String in p.get("usages", PackedStringArray()):
			if u in MeshBaker.BAKERS and not wanted.has(u):
				wanted[u] = p["id"]
	return wanted


## Mesh-map usages the graph takes as image inputs and the baker can produce, e.g.
## ["ambientOcclusion", "curvature"]. Empty for plain tiling materials.
func mesh_usages() -> PackedStringArray:
	var usages := PackedStringArray()
	if _description == null:
		return usages
	for p in _description.image_inputs():
		for u: String in p.get("usages", PackedStringArray()):
			if u in MeshBaker.BAKERS and not u in usages:
				usages.append(u)
	return usages


## True when the output name no longer starts with the .sbsar's name (the source was
## changed after creation, e.g. in an older version that allowed editing it).
func is_name_mismatched() -> bool:
	var base := source.get_file().get_basename().validate_filename()
	return not source.is_empty() and not output_name.begins_with(base)


func size_name(size_log2: int) -> String:
	return SIZE_NAMES.get(size_log2, str(1 << size_log2))


## Value of a parameter: the stored override or the graph default.
func get_value(id: String) -> Variant:
	if values.has(id):
		return values[id]
	var p := _param(id)
	return parse_value(p.get("default", ""), p) if not p.is_empty() else null


## Loads the description now on this thread (for tools/tests that cannot wait a frame).
func describe_blocking() -> void:
	if source.is_empty():
		return
	var backend := Backends.for_source(source, Settings.snapshot())
	_set_description(backend.describe(source))


# --- description loading -------------------------------------------------------------

func _request_description() -> void:
	if source.is_empty() or not Engine.is_editor_hint():
		return
	var backend := Backends.for_source(source, Settings.snapshot())
	var src := source
	_describe_task = Task.new()
	_describe_task.finished.connect(func(d: GraphDescription) -> void:
		_describe_task = null
		if src == source:
			_set_description(d))
	_describe_task.start(func() -> GraphDescription: return backend.describe(src))


func _set_description(d: GraphDescription) -> void:
	_description = d
	_expressions.clear()
	if not d.is_ok():
		push_warning("Substance Bridge: could not describe %s: %s" % [source, "; ".join(d.errors)])
	notify_property_list_changed()
	description_loaded.emit()


# --- generated properties ---------------------------------------------------------------

func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	if _description == null or not _description.is_ok():
		return props

	props.append({"name": "Graph: " + _description.label, "type": TYPE_NIL,
			"usage": PROPERTY_USAGE_CATEGORY})
	if not _description.presets.is_empty():
		var names := PackedStringArray(["(custom):-1"])
		for i in _description.presets.size():
			names.append("%s:%d" % [_enum_text(_description.presets[i]["label"]), i])
		props.append({"name": "preset", "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM,
				"hint_string": ",".join(names), "usage": PROPERTY_USAGE_EDITOR})

	var ctx := _visibility_context()
	var groups: Array[String] = [""]
	for p in _description.params:
		if not p["group"] in groups:
			groups.append(p["group"])
	for group in groups:
		var group_props: Array[Dictionary] = []
		for p in _description.params:
			if p["group"] != group or not _is_editable(p) or not _is_visible(p, ctx):
				continue
			group_props.append(_property_info(p))
		if group_props.is_empty():
			continue
		if not group.is_empty():
			props.append({"name": group, "type": TYPE_NIL, "usage": PROPERTY_USAGE_GROUP, "hint_string": ""})
		props.append_array(group_props)
	props.append_array(_slot_properties())
	return props


func _get(property: StringName) -> Variant:
	if property == &"preset":
		return -1
	var sf := _slot_field(property)
	if not sf.is_empty():
		return _get_slot_field(sf[0], sf[1])
	var p := _param_for_property(property)
	if p.is_empty():
		return null
	return get_value(p["id"])


func _set(property: StringName, value: Variant) -> bool:
	var sf := _slot_field(property)
	if not sf.is_empty():
		_set_slot_field(sf[0], sf[1], value)
		return true
	if property == &"preset":
		if _description and value >= 0 and value < _description.presets.size():
			_apply_preset(_description.presets[value])
		return true
	var p := _param_for_property(property)
	if p.is_empty():
		return false
	values[p["id"]] = value
	if p["widget"] in ["togglebutton", "combobox"]:
		notify_property_list_changed()  # may change what visibleif shows
	_params_changed()
	return true


func _property_can_revert(property: StringName) -> bool:
	var sf := _slot_field(property)
	if not sf.is_empty():
		return _get_slot_field(sf[0], sf[1]) != _slot_default(sf[0], sf[1])
	var p := _param_for_property(property)
	return not p.is_empty() and values.has(p["id"])


func _property_get_revert(property: StringName) -> Variant:
	var sf := _slot_field(property)
	if not sf.is_empty():
		return _slot_default(sf[0], sf[1])
	var p := _param_for_property(property)
	return parse_value(p.get("default", ""), p) if not p.is_empty() else null


func _params_changed() -> void:
	emit_changed()
	parameters_changed.emit()


func _apply_preset(preset: Dictionary) -> void:
	values.clear()
	for id: String in preset["values"]:
		var raw: String = preset["values"][id]
		if id == "$randomseed":
			random_seed = int(raw)
			continue
		var p := _param(id)
		if p.is_empty() or not _is_editable(p):
			continue
		var v: Variant = parse_value(raw, p)
		if v != parse_value(p["default"], p):
			values[id] = v
	notify_property_list_changed()
	_params_changed()


static func _is_editable(p: Dictionary) -> bool:
	# $outputsize / $randomseed have their own controls; image inputs are wired by the baker (phase 4).
	return not String(p["id"]).begins_with("$") and p["type"] in [
		"float", "float2", "float3", "float4", "int", "int2", "int3", "int4", "string"]


func _property_info(p: Dictionary) -> Dictionary:
	var info := {"name": _property_name(p["id"]), "usage": PROPERTY_USAGE_EDITOR,
			"hint": PROPERTY_HINT_NONE, "hint_string": ""}
	var type: String = p["type"]
	var widget: String = p["widget"]
	if widget == "color" and type in ["float3", "float4"]:
		info["type"] = TYPE_COLOR
		if type == "float3":
			info["hint"] = PROPERTY_HINT_COLOR_NO_ALPHA
	elif type == "int" and widget == "togglebutton":
		info["type"] = TYPE_BOOL
	elif type == "int" and widget == "combobox" and not p["items"].is_empty():
		info["type"] = TYPE_INT
		info["hint"] = PROPERTY_HINT_ENUM
		var items := PackedStringArray()
		for item: Dictionary in p["items"]:
			items.append("%s:%d" % [_enum_text(item["text"]), item["value"]])
		info["hint_string"] = ",".join(items)
	else:
		info["type"] = {
			"float": TYPE_FLOAT, "float2": TYPE_VECTOR2, "float3": TYPE_VECTOR3, "float4": TYPE_VECTOR4,
			"int": TYPE_INT, "int2": TYPE_VECTOR2I, "int3": TYPE_VECTOR3I, "int4": TYPE_VECTOR4I,
			"string": TYPE_STRING,
		}[type]
		if p.has("min") and type in ["float", "int"]:
			info["hint"] = PROPERTY_HINT_RANGE
			var step: float = p["step"] if p["step"] > 0.0 else (1.0 if type == "int" else 0.001)
			info["hint_string"] = "%s,%s,%s%s" % [_num(p["min"]), _num(p["max"]), _num(step),
					"" if p["clamp"] else ",or_greater,or_less"]
	return info


## Converts a stored Substance value string ("0.6", "0.1,0.2,0.3", "1") to the Godot type
## its inspector property uses.
static func parse_value(raw: String, p: Dictionary) -> Variant:
	var type: String = p.get("type", "")
	var c := PackedFloat64Array()
	for s in raw.split(",", false):
		c.append(float(s))
	while c.size() < 4:
		c.append(0.0)
	match type:
		"float":
			return c[0]
		"int":
			return c[0] != 0.0 if p.get("widget") == "togglebutton" else int(c[0])
		"float2":
			return Vector2(c[0], c[1])
		"float3":
			return Color(c[0], c[1], c[2]) if p.get("widget") == "color" else Vector3(c[0], c[1], c[2])
		"float4":
			return Color(c[0], c[1], c[2], c[3]) if p.get("widget") == "color" else Vector4(c[0], c[1], c[2], c[3])
		"int2":
			return Vector2i(int(c[0]), int(c[1]))
		"int3":
			return Vector3i(int(c[0]), int(c[1]), int(c[2]))
		"int4":
			return Vector4i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
		_:
			return raw


# --- visibility (visibleif) ---------------------------------------------------------------

func _visibility_context() -> Dictionary:
	var ctx := {}
	for p in _description.params:
		ctx[p["id"]] = get_value(p["id"])
	return ctx


## Evaluates a Substance visibleif expression such as input["painted_arrows"]==true.
## Anything that fails to parse or run counts as visible, so a parameter is never lost.
func _is_visible(p: Dictionary, ctx: Dictionary) -> bool:
	var text: String = p.get("visibleif", "")
	if text.is_empty():
		return true
	if not _expressions.has(text):
		var e := Expression.new()
		_expressions[text] = e if e.parse(text, ["input"]) == OK else null
	var expr: Expression = _expressions[text]
	if expr == null:
		return true
	var result: Variant = expr.execute([ctx], null, false)
	if expr.has_execute_failed():
		return true
	return bool(result)


# --- helpers -----------------------------------------------------------------------------------

func _param(id: String) -> Dictionary:
	return _description.find_param(id) if _description else {}


func _property_name(id: String) -> String:
	return "param_" + id.trim_prefix("$") if id in RESERVED else id


func _param_for_property(property: StringName) -> Dictionary:
	if _description == null:
		return {}
	var name := String(property)
	var p := _description.find_param(name)
	if not p.is_empty() and not name in RESERVED:
		return p
	if name.begins_with("param_"):
		var id := name.trim_prefix("param_")
		if id in RESERVED:
			return _description.find_param(id)
	return {}


## "1" rather than "1.0", "0.01" rather than "0.01000".
static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else String.num(v, 6)


static func _enum_text(s: String) -> String:
	return s.replace(",", " ").replace(":", " ")

# --- material slots (channel routing) -------------------------------------------------------

## Inspector fields per slot; min and max edit the stored "range" (Vector2).
const SLOT_FIELDS := ["source", "strength", "invert", "min", "max"]


## Inspector properties "slot_<slot>_<field>", one subgroup per material slot.
func _slot_properties() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append({"name": "Material Slots", "type": TYPE_NIL, "usage": PROPERTY_USAGE_GROUP, "hint_string": "slot_"})
	var choices := ",".join(_source_choices().keys().map(func(k: String) -> String: return _enum_text(k)))
	for s in Routing.SLOTS:
		var id: String = s["id"]
		props.append({"name": s["label"], "type": TYPE_NIL, "usage": PROPERTY_USAGE_SUBGROUP, "hint_string": "slot_%s_" % id})
		props.append({"name": "slot_%s_source" % id, "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM,
				"hint_string": choices, "usage": PROPERTY_USAGE_EDITOR})
		props.append({"name": "slot_%s_strength" % id, "type": TYPE_FLOAT, "hint": PROPERTY_HINT_RANGE,
				"hint_string": "0,%s,0.01,or_greater" % _num(s["max"]), "usage": PROPERTY_USAGE_EDITOR})
		props.append({"name": "slot_%s_invert" % id, "type": TYPE_BOOL, "usage": PROPERTY_USAGE_EDITOR})
		for f in ["min", "max"]:
			props.append({"name": "slot_%s_%s" % [id, f], "type": TYPE_FLOAT, "hint": PROPERTY_HINT_RANGE,
					"hint_string": "0,1,0.01,or_greater,or_less", "usage": PROPERTY_USAGE_EDITOR})
	return props


## Dropdown text -> stored source: "Auto" -> "", "None" -> "-", then each output's id.
func _source_choices() -> Dictionary:
	var choices := {"Auto": "", "None": "-"}
	if _description:
		for o: Dictionary in _description.outputs:
			var id := String(o.get("id", ""))
			var label := String(o.get("label", ""))
			var text := label if not label.is_empty() else id
			if choices.has(text):
				text = "%s (%s)" % [text, id]
			choices[text] = id
	return choices


## ["roughness", "strength"] for "slot_roughness_strength", else [].
func _slot_field(property: StringName) -> Array:
	var name := String(property)
	if not name.begins_with("slot_"):
		return []
	var parts := name.trim_prefix("slot_").split("_")
	if parts.size() != 2 or not parts[1] in SLOT_FIELDS or Routing.slot_info(parts[0]).is_empty():
		return []
	return [parts[0], parts[1]]


func _slot_default(slot: String, field: String) -> Variant:
	match field:
		"source": return "Auto"
		"strength": return float(Routing.slot_info(slot)["default"])
		"invert": return false
		"min": return 0.0
		"max": return 1.0
	return null


func _get_slot_field(slot: String, field: String) -> Variant:
	var r: Dictionary = routes.get(slot, {})
	if field in ["min", "max"]:
		var rng: Vector2 = r.get("range", Vector2(0, 1))
		return rng.x if field == "min" else rng.y
	if not r.has(field):
		return _slot_default(slot, field)
	if field == "source":
		var choices := _source_choices()
		for text: String in choices:
			if choices[text] == r["source"]:
				return _enum_text(text)
		return String(r["source"])  # an output the graph no longer has
	return r[field]


func _set_slot_field(slot: String, field: String, value: Variant) -> void:
	var r: Dictionary = routes.get(slot, {}).duplicate()
	var stored: Variant = value
	if field in ["min", "max"]:
		var rng: Vector2 = r.get("range", Vector2(0, 1))
		if field == "min":
			rng.x = float(value)
		else:
			rng.y = float(value)
		field = "range"
		stored = rng
	if field == "source":
		var choices := _source_choices()
		stored = ""
		for text: String in choices:
			if _enum_text(text) == String(value):
				stored = choices[text]
	var is_default: bool = stored == "" if field == "source" else (stored == Vector2(0, 1) if field == "range" else stored == _slot_default(slot, field))
	if is_default:
		r.erase(field)
	else:
		r[field] = stored
	if r.is_empty():
		routes.erase(slot)
	else:
		routes[slot] = r
	_params_changed()
