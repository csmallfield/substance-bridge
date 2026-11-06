@tool
extends "res://addons/substance_bridge/backends/texture_backend.gd"
## Noise lab backend: the native Godot rebuilds of Substance Designer's noises and Grunge
## Maps (D:\01_github\sd-mm-noise-lab), linked into this project at res://noiselab.
##
## Sources look like "noiselab://grunge_014" or "noiselab://dirt_4". Each render produces
## baseColor (8-bit greyscale), height (full-precision EXR) and normal (Y up, OpenGL).
##
## The generators are GPU passes driven by a Node across frames, so render() runs on the main
## thread as a coroutine (runs_on_main_thread() is true). describe() is plain data.

const SCHEME := "noiselab://"
const GENERATOR := "res://noiselab/grunge_generator.gd"
const STANDALONE := "res://noiselab/standalone.gd"

const RENDER_TIMEOUT_MS := 60000

## Standalone noises that need input textures; not offered here.
const EXCLUDED := ["upscale_1", "upscale_2", "upscale_3"]

## Default "scale" per noise where it is not 1 (mirrors Standalone.build).
const SCALE_DEFAULTS := {
	"cells_1": 32, "cells_2": 32, "cells_3": 32, "cells_4": 32, "crystal_1": 32, "gaussian_noise": 32,
	"liquid": 32, "plasma": 32, "microscope_view": 32, "perlin_noise": 32, "directional_scratches": 4, "fur_1": 2,
}

## Noises without the common scale/disorder settings.
const NO_SCALE := ["fractal_sum_1", "fractal_sum_2", "fractal_sum_3", "fractal_sum_4", "fractal_sum_base",
		"white_noise", "dirt_6", "fur_4", "anisotropic_noise", "blue_noise_fast", "dirt_gradient"]
const NO_DISORDER := ["fur_2"]
## Noises with disorder but no scale.
const DISORDER_ONLY := ["dirt_gradient"]

## Extra settings per noise: [id, type, default, min, max, step]. type: "float", "int", "bool", "float2".
## Names are SD's (as the noise lab's builders read them); ranges follow SD where known.
const EXTRAS := {
	"bnw_spots_1": [["roughness", "float", 1.0, 0.0, 1.0, 0.01]],
	"cells_2": [["edge_width", "float", 2.0, 0.0, 10.0, 0.01], ["invert", "bool", false]],
	"cells_3": [["hardness", "float", 0.5, 0.0, 1.0, 0.01], ["invert", "bool", false]],
	"cells_4": [["color_source", "int", 0, 0, 3, 1], ["pseudo_random_seed", "int", 0, 0, 100, 1]],
	"creased": [["warp_intensity", "float", 0.25, 0.0, 1.0, 0.01]],
	"directional_noise_1": [["angle", "float", 0.0, 0.0, 1.0, 0.01], ["angle_random", "float", 0.0, 0.0, 1.0, 0.01]],
	"directional_noise_2": [["angle", "float", 0.0, 0.0, 1.0, 0.01], ["angle_random", "float", 0.0, 0.0, 1.0, 0.01]],
	"directional_noise_3": [["angle", "float", 0.0, 0.0, 1.0, 0.01], ["angle_random", "float", 0.0, 0.0, 1.0, 0.01]],
	"directional_noise_4": [["angle", "float", 0.0, 0.0, 1.0, 0.01], ["angle_random", "float", 0.0, 0.0, 1.0, 0.01]],
	"directional_scratches": [["angle", "float", 0.0, 0.0, 1.0, 0.01], ["angle_random", "float", 0.0, 0.0, 1.0, 0.01],
		["pattern_amount", "float", 1.0, 0.0, 1.0, 0.01], ["pattern_size", "float2", Vector2(0.5, 20.0)],
		["pattern_size_random", "float2", Vector2.ZERO]],
	"fluid": [["warp_intensity", "float", 0.5, 0.0, 1.0, 0.01], ["pattern_size", "float2", Vector2(0.5, 1.0)]],
	"fractal_sum_base": [["Roughness", "float", 1.0, 0.0, 1.0, 0.01], ["GlobalOpacity", "float", 1.0, 0.0, 1.0, 0.01],
		["MinLevel", "int", 1, 1, 11, 1], ["MaxLevel", "int", 11, 1, 11, 1]],
	"fur_2": [["waves_scale", "float", 0.0, 0.0, 1.0, 0.01], ["waves_rotation", "float", 0.125, 0.0, 1.0, 0.01]],
	"fur_3": [["waves_amount", "float", 2.0, 0.0, 10.0, 0.01]],
	"fur_4": [["Disorder", "float", 0.7, 0.0, 1.0, 0.01]],
	"liquid": [["warp_intensity", "float", 0.5, 0.0, 1.0, 0.01]],
	"microscope_view": [["warp_intensity", "float", 0.5, 0.0, 1.0, 0.01]],
	"messy_fibers_1": [["angle", "float", 0.0, 0.0, 1.0, 0.01], ["angle_random", "float", 0.5, 0.0, 1.0, 0.01],
		["lines_number", "int", 16, 1, 64, 1]],
	"messy_fibers_2": [["angle", "float", 0.0, 0.0, 1.0, 0.01], ["angle_random", "float", 0.5, 0.0, 1.0, 0.01],
		["links_number", "int", 16, 1, 64, 1]],
	"messy_fibers_3": [["angle", "float", 0.0, 0.0, 1.0, 0.01], ["angle_random", "float", 0.5, 0.0, 1.0, 0.01],
		["color_random", "float", 0.0, 0.0, 1.0, 0.01]],
	"moisture_noise": [["global_opacity", "float", 1.6, 0.0, 2.0, 0.01], ["pattern_size", "float2", Vector2.ONE],
		["pattern_angle", "float", 0.0, 0.0, 1.0, 0.01], ["pattern_angle_random", "float", 0.0, 0.0, 1.0, 0.01]],
	"anisotropic_noise": [["X_Amount", "int", 4, 1, 64, 1], ["Y_Amount", "int", 256, 1, 1024, 1],
		["y_amount_by_resolution", "bool", false], ["rotate", "bool", false],
		["smoothness", "float", 1.0, 0.0, 4.0, 0.01], ["smoothness_interpolation", "float", 0.5, 0.0, 1.0, 0.01]],
	"blue_noise_fast": [["noise_control", "float", 1.0, 0.0, 1.0, 0.01]],
}

var _config: Dictionary


func _init(config: Dictionary) -> void:
	_config = config


func get_backend_id() -> String:
	return "noiselab"


func get_display_name() -> String:
	return "Noise Lab (native Godot)"


func runs_on_main_thread() -> bool:
	return true


func check_available() -> PackedStringArray:
	if not ResourceLoader.exists(GENERATOR):
		return PackedStringArray(["The noise lab is not linked into this project (res://noiselab). See the README."])
	return PackedStringArray()


## Every noise this backend offers: "grunge_001".."grunge_015", then the standalone noises.
static func noise_names() -> PackedStringArray:
	var names := PackedStringArray()
	if not ResourceLoader.exists(STANDALONE):
		return names
	for i in range(1, 16):
		names.append("grunge_%03d" % i)
	for n: String in load(STANDALONE).NAMES:
		if not n in EXCLUDED:
			names.append(n)
	return names


static func noise_of(source: String) -> String:
	return source.trim_prefix(SCHEME)


func describe(source: String) -> GraphDescription:
	var d := GraphDescription.new()
	d.source = source
	var noise := noise_of(source)
	d.graph_url = source
	d.label = noise.capitalize()
	if not noise in noise_names():
		d.errors.append("Unknown noise \"%s\"%s" % [noise, "" if check_available().is_empty() else " (the noise lab is not linked)"])
		return d

	if noise.begins_with("grunge_"):
		d.params.append(_param("balance", "float", 0.5, 0.0, 1.0, 0.01))
		d.params.append(_param("contrast", "float", 0.5, 0.0, 1.0, 0.01))
		d.params.append(_param("invert", "bool", false))
	else:
		if not noise in NO_SCALE:
			d.params.append(_param("scale", "int", SCALE_DEFAULTS.get(noise, 1), 1, 64, 1, false))
		if (not noise in NO_SCALE and not noise in NO_DISORDER) or noise in DISORDER_ONLY:
			d.params.append(_param("disorder", "float", 0.0, 0.0, 1.0, 0.01))
		for e: Array in EXTRAS.get(noise, []):
			d.params.append(_param(e[0], e[1], e[2], e[3] if e.size() > 3 else 0.0, e[4] if e.size() > 4 else 1.0,
					e[5] if e.size() > 5 else 0.01))
	var strength := _param("normal_strength", "float", 4.0, 0.0, 16.0, 0.1, false)
	strength["group"] = "Normal map"
	d.params.append(strength)

	for usage in ["baseColor", "height", "normal"]:
		d.outputs.append({"id": usage, "label": usage.capitalize(), "group": "", "visibleif": "", "usertag": "",
				"usages": PackedStringArray([usage])})
	return d


## A parameter in the same shape the Substance XML reader produces.
static func _param(id: String, type: String, default: Variant, min_v: float = 0.0, max_v: float = 1.0,
		step: float = 0.01, clamp: bool = true) -> Dictionary:
	var p := {"id": id, "label": id.capitalize(), "group": "", "visibleif": "", "usertag": "",
			"items": [], "usages": PackedStringArray()}
	match type:
		"bool":
			p["type"] = "int"
			p["widget"] = "togglebutton"
			p["default"] = "1" if default else "0"
		"float2":
			p["type"] = "float2"
			p["widget"] = ""
			p["default"] = "%s,%s" % [default.x, default.y]
		_:
			p["type"] = type
			p["widget"] = "slider"
			p["default"] = str(default)
			p["min"] = min_v
			p["max"] = max_v
			p["step"] = step
			p["clamp"] = clamp
	return p


## Main thread, coroutine. Renders the noise and writes baseColor/height/normal files.
func render(request: RenderRequest) -> RenderResult:
	var res := RenderResult.new()
	var started := Time.get_ticks_msec()
	var problems := check_available()
	if not problems.is_empty():
		res.errors.append_array(problems)
		return res
	var desc := request.description if request.description else describe(request.source)
	if not desc.is_ok():
		res.errors.append_array(desc.errors)
		return res

	var noise := noise_of(request.source)
	var size := Vector2i(1 << request.size_log2.x, 1 << request.size_log2.y)
	var settings := {}
	for p in desc.params:
		var id: String = p["id"]
		var v: Variant = request.values.get(id, _default_value(p))
		settings[id] = v
	var strength := float(settings.get("normal_strength", 4.0))
	res.commands.append("noiselab %s %dx%d seed %d %s" % [noise, size.x, size.y, request.random_seed, str(request.values)])

	# The generator's passes wait for RenderingServer.frame_post_draw. The editor only draws when
	# something changes (low-processor mode), so draw every frame while the noise renders.
	var low_processor := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var tree := Engine.get_main_loop() as SceneTree
	var gen: Node = load(GENERATOR).new()
	tree.root.add_child(gen)
	var out := {}
	var work := func() -> void:
		var img: Image
		if noise.begins_with("grunge_"):
			img = await gen.generate(int(noise.trim_prefix("grunge_")), size, request.random_seed,
					float(settings["balance"]), float(settings["contrast"]), bool(settings["invert"]))
		else:
			img = await gen.generate_noise(noise, size, request.random_seed, settings)
		out["image"] = img
		if img:
			out["normal"] = await gen.make_normal(img, strength)
		out["done"] = true
	work.call()
	# A minimised or headless editor never draws, so the passes would wait forever.
	var deadline := Time.get_ticks_msec() + RENDER_TIMEOUT_MS
	while not out.has("done") and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	OS.low_processor_usage_mode = low_processor
	if not out.has("done"):
		gen.queue_free()  # also abandons the pending passes
		res.errors.append("The noise lab did not finish %s within %d s. It renders on the GPU through the editor window, so keep the editor visible (not minimised, not headless)."
				% [noise, RENDER_TIMEOUT_MS / 1000])
		return res
	gen.queue_free()
	var image: Image = out.get("image")
	var normal: Image = out.get("normal")
	if image == null or normal == null:
		res.errors.append("The noise lab could not render %s at %dx%d (see the Output panel)." % [noise, size.x, size.y])
		return res

	DirAccess.make_dir_recursive_absolute(request.output_dir)
	var files := {
		"baseColor": request.output_dir.path_join("baseColor.png"),
		"height": request.output_dir.path_join("height.exr"),
		"normal": request.output_dir.path_join("normal.png"),
	}
	var errs := [
		load(GENERATOR).to_display(image).save_png(files["baseColor"]),
		image.save_exr(files["height"], true),
		normal.save_png(files["normal"]),
	]
	for i in errs.size():
		if errs[i] != OK:
			res.errors.append("Could not write %s: %s" % [files.values()[i], error_string(errs[i])])
	if res.errors.is_empty():
		res.maps = files
		for usage: String in files:
			res.outputs.append({"id": usage, "label": usage.capitalize(), "usages": [usage], "path": files[usage]})
	res.normal_convention = "opengl"  # normal_from_height.gdshader encodes Y up, as Godot expects
	res.duration_ms = Time.get_ticks_msec() - started
	return res


## Godot value for a parameter's default (bool for toggles).
static func _default_value(p: Dictionary) -> Variant:
	var raw: String = p["default"]
	match p["type"]:
		"float":
			return float(raw)
		"int":
			return raw != "0" if p["widget"] == "togglebutton" else int(raw)
		"float2":
			var c := raw.split(",")
			return Vector2(float(c[0]), float(c[1]))
	return raw
