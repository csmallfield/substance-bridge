@tool
extends RefCounted
## Channel routing: which graph output feeds each material slot, and how.
##
## A GraphSettings stores routes as {slot: {source?, strength?, invert?, range?}}, only the
## keys changed from their defaults:
##   source    ""  (Auto: the output whose usage matches the slot), "-" (None: slot off),
##             or an output id. One output can feed several slots.
##   strength  the slot's own scalar (see SLOTS), always set on the material (default if unset).
##   invert    bool, baked into the slot's texture.
##   range     Vector2(min, max): the texture's 0..1 remapped to min..max, baked.
## Albedo strength is baked too: the map fades toward white as strength goes to 0.
## Without routes the material comes out exactly as before routing existed.

## Slot id (= Substance usage), label, material property for strength, default, max.
const SLOTS := [
	{"id": "baseColor", "label": "Albedo", "strength": "", "default": 1.0, "max": 1.0, "scalar": false},
	{"id": "normal", "label": "Normal", "strength": "normal_scale", "default": 1.0, "max": 16.0, "scalar": false},
	{"id": "roughness", "label": "Roughness", "strength": "roughness", "default": 1.0, "max": 1.0, "scalar": true},
	{"id": "metallic", "label": "Metallic", "strength": "metallic", "default": 1.0, "max": 1.0, "scalar": true},
	{"id": "ambientOcclusion", "label": "Ambient Occlusion", "strength": "ao_light_affect", "default": 0.0, "max": 1.0, "scalar": true},
	{"id": "emissive", "label": "Emission", "strength": "emission_energy_multiplier", "default": 1.0, "max": 16.0, "scalar": false},
	{"id": "height", "label": "Height", "strength": "heightmap_scale", "default": 5.0, "max": 16.0, "scalar": true},
]

const GREY_FORMATS := [Image.FORMAT_L8, Image.FORMAT_R8, Image.FORMAT_RF, Image.FORMAT_RH]


static func is_float(img: Image) -> bool:
	return img.get_format() in [Image.FORMAT_RF, Image.FORMAT_RGF, Image.FORMAT_RGBF, Image.FORMAT_RGBAF,
			Image.FORMAT_RH, Image.FORMAT_RGH, Image.FORMAT_RGBH, Image.FORMAT_RGBAH]


static func slot_info(slot: String) -> Dictionary:
	for s in SLOTS:
		if s["id"] == slot:
			return s
	return {}


## For each slot: {"output": the output Dictionary feeding it (outputs' own keys, e.g. path
## or image), "explicit": bool, "bake": bool (invert/range/albedo strength to apply),
## "a": float, "offset": float (baked affine: v' = offset + a * v)}. Slots set to None, or
## with nothing to feed them, are left out.
## outputs: [{id, label, usages, ...}] in the graph's order.
static func plan(routes: Dictionary, outputs: Array) -> Dictionary:
	var result := {}
	for s in SLOTS:
		var slot: String = s["id"]
		var r: Dictionary = routes.get(slot, {})
		var source := String(r.get("source", ""))
		if source == "-":
			continue
		var out := {}
		if source.is_empty():
			out = _auto_output(slot, outputs)
		else:
			for o: Dictionary in outputs:
				if String(o.get("id", "")) == source:
					out = o
					break
		if out.is_empty():
			continue
		var rng: Vector2 = r.get("range", Vector2(0, 1))
		var inv := bool(r.get("invert", false))
		var a := rng.y - rng.x
		var offset := rng.x
		if inv:
			a = -a
			offset = rng.y
		if slot == "baseColor" and r.has("strength"):
			var k := float(r["strength"])  # fade toward white: v'' = (1 - k) + k * v'
			a *= k
			offset = 1.0 - k + k * offset
		var bake := not is_equal_approx(a, 1.0) or not is_zero_approx(offset)
		result[slot] = {"output": out, "explicit": not source.is_empty(), "bake": bake, "a": a, "offset": offset}
	return result


static func _auto_output(slot: String, outputs: Array) -> Dictionary:
	for usage in ([slot, "diffuse"] if slot == "baseColor" else [slot]):
		for o: Dictionary in outputs:
			if usage in Array(o.get("usages", [])):
				return o
	return {}


## The image a slot gets from its source image: greyscale for scalar slots fed by a colour
## output, then the baked affine. Returns the image itself when nothing changes.
static func transform(image: Image, entry: Dictionary, slot: String) -> Image:
	var img := image
	var to_grey: bool = entry["explicit"] and slot_info(slot).get("scalar", false) \
			and not image.get_format() in GREY_FORMATS
	if not to_grey and not entry["bake"]:
		return img
	img = image.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	if to_grey:  # float maps stay float (one channel); 8-bit ones become luminance
		img.convert(Image.FORMAT_RF if is_float(img) else Image.FORMAT_L8)
	if entry["bake"]:
		affine(img, entry["a"], entry["offset"])
	return img


## v' = offset + a * v on every colour channel, in C++ (Image.adjust_bcs): adjust_bcs(b, k, 1)
## computes 0.5 + k * (b * v - 0.5), so k = 1 - 2 * offset and b = a / k.
static func affine(img: Image, a: float, offset: float) -> void:
	var k := 1.0 - 2.0 * offset
	if absf(k) < 0.002:  # offset 0.5: nudge by under one 8-bit step
		k = 0.002 if k >= 0.0 else -0.002
	img.adjust_bcs(a / k, k, 1.0)


## Sets the slot's strength on the material (the default when the route has none), and turns
## on the features an explicit route asks for (height: parallax).
static func apply_settings(mat: StandardMaterial3D, slot: String, routes: Dictionary, entry: Dictionary) -> void:
	var info := slot_info(slot)
	var r: Dictionary = routes.get(slot, {})
	var prop := String(info.get("strength", ""))
	if not prop.is_empty():
		mat.set(prop, float(r.get("strength", info["default"])))
	if slot == "height" and entry.get("explicit", false):
		mat.heightmap_enabled = true


## Turns a slot off (route set to None, or nothing feeds it any more).
static func clear_slot(mat: StandardMaterial3D, slot: String) -> void:
	match slot:
		"baseColor":
			mat.albedo_texture = null
		"normal":
			mat.normal_enabled = false
			mat.normal_texture = null
		"roughness":
			mat.roughness_texture = null
			mat.roughness = 1.0
		"metallic":
			mat.metallic_texture = null
			mat.metallic = 0.0
		"ambientOcclusion":
			mat.ao_enabled = false
			mat.ao_texture = null
			mat.ao_light_affect = 0.0
		"emissive":
			mat.emission_enabled = false
			mat.emission_texture = null
		"height":
			mat.heightmap_enabled = false
			mat.heightmap_texture = null

## True when the slot holds a texture the bridge made: a live ImageTexture, or a file named
## <name>_<slot>.* in the material's folder. Those are cleared when nothing feeds the slot.
static func is_generated(tex: Texture2D, slot: String, dir: String, name: String) -> bool:
	if tex == null:
		return false
	if tex is ImageTexture:
		return true
	return tex.resource_path.get_base_dir() == dir and tex.resource_path.get_file().get_basename() == "%s_%s" % [name, slot]


static func slot_texture(mat: StandardMaterial3D, slot: String) -> Texture2D:
	match slot:
		"baseColor": return mat.albedo_texture
		"normal": return mat.normal_texture
		"roughness": return mat.roughness_texture
		"metallic": return mat.metallic_texture
		"ambientOcclusion": return mat.ao_texture
		"emissive": return mat.emission_texture
		"height": return mat.heightmap_texture
	return null
