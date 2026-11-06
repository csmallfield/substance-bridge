@tool
extends VBoxContainer
## "Substance Preview" bottom panel: the current material's maps in 2D.
##
## Live updates (LivePreview.outputs_ready) show every output of the graph, wired into the
## material or not, as they render. Otherwise the panel shows the material's own textures.
## Click a thumbnail to view it large; Tile repeats it to check seams, Channel isolates R, G,
## B or A, and the mouse wheel zooms (double-click resets).

const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")

const VIEW_SHADER := """
shader_type canvas_item;
uniform float tiles = 1.0;
uniform int channel = 0;   // 0 RGB, 1 R, 2 G, 3 B, 4 A
uniform bool grey = false; // one-channel image: show R as grey
uniform vec2 zoom_center = vec2(0.5);
uniform float zoom = 1.0;
void fragment() {
	vec2 uv = (UV - 0.5) / zoom + zoom_center;
	vec4 c = textureLod(TEXTURE, fract(uv * tiles), 0.0);
	if (grey) { c = vec4(c.rrr, 1.0); }
	if (channel == 1) { c = vec4(c.rrr, 1.0); }
	else if (channel == 2) { c = vec4(c.ggg, 1.0); }
	else if (channel == 3) { c = vec4(c.bbb, 1.0); }
	else if (channel == 4) { c = vec4(c.aaa, 1.0); }
	else { c.a = 1.0; }
	COLOR = c;
}
"""

const THUMB := 96
const SLOTS := [["Base Color", "baseColor", "albedo_texture"], ["Normal", "normal", "normal_texture"],
		["Roughness", "roughness", "roughness_texture"], ["Metallic", "metallic", "metallic_texture"],
		["Ambient Occlusion", "ambientOcclusion", "ao_texture"], ["Emissive", "emissive", "emission_texture"],
		["Height", "height", "heightmap_texture"]]
const GREY_FORMATS := [Image.FORMAT_L8, Image.FORMAT_R8, Image.FORMAT_RF, Image.FORMAT_RH, Image.FORMAT_RGTC_R]

var dock: Node

var _gs: GraphSettings
var _title: Label
var _tile: OptionButton
var _channel: OptionButton
var _view: TextureRect
var _view_label: Label
var _thumbs: HFlowContainer
var _scroll: ScrollContainer
var _items: Array = []  # [{label, texture: Texture2D, grey: bool}]
var _selected := 0
var _selected_label := ""


func _init() -> void:
	name = "Substance Preview"
	custom_minimum_size = Vector2(0, 260)

	var bar := HBoxContainer.new()
	_title = Label.new()
	_title.text = "No material"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	bar.add_child(_title)
	bar.add_child(_label("Tile"))
	_tile = OptionButton.new()
	for t in ["1×", "2×", "3×"]:
		_tile.add_item(t)
	_tile.tooltip_text = "Repeat the map to check that it tiles."
	_tile.item_selected.connect(func(_i: int) -> void: _update_view())
	bar.add_child(_tile)
	bar.add_child(_label("Channel"))
	_channel = OptionButton.new()
	for c in ["RGB", "R", "G", "B", "A"]:
		_channel.add_item(c)
	_channel.item_selected.connect(func(_i: int) -> void: _update_view())
	bar.add_child(_channel)
	add_child(bar)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	_view = TextureRect.new()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shader := Shader.new()
	shader.code = VIEW_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_view.material = mat
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	_view.tooltip_text = "Mouse wheel: zoom. Double-click: reset."
	left.add_child(_view)
	_view_label = Label.new()
	_view_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_view_label)
	body.add_child(left)

	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_thumbs = HFlowContainer.new()
	_thumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_thumbs)
	body.add_child(scroll)


## Connects to the dock's signals and its live preview.
func attach(bridge_dock: Node) -> void:
	dock = bridge_dock
	dock.current_changed.connect(func(gs: GraphSettings) -> void: show_material(gs))
	dock.rendered.connect(func(gs: GraphSettings) -> void:
		if gs == _gs:
			show_material(gs))
	dock._live.outputs_ready.connect(_on_live_outputs)
	dock._live.updated.connect(_on_live_updated)
	show_material(dock.current)


## Shows the textures on gs's material.
func show_material(gs: GraphSettings) -> void:
	_gs = gs
	var items := []
	var mat := gs.material if gs else null
	if mat:
		for s in SLOTS:
			var tex: Texture2D = mat.get(s[2])
			if tex:
				items.append({"label": s[0], "texture": tex, "grey": _is_grey(tex)})
	_title.text = "%s: %s" % [gs.output_name, "material textures"] if gs else "No material"
	_set_items(items)


## The images from the latest live render: every output, wired or not.
func _on_live_outputs(gs: GraphSettings, outputs: Array) -> void:
	if gs != _gs:
		return
	var items := []
	for o: Dictionary in outputs:
		var img: Image = o["image"]
		items.append({"label": o["label"], "texture": ImageTexture.create_from_image(img),
				"grey": img.get_format() in GREY_FORMATS})
	_set_items(items)


func _on_live_updated(gs: GraphSettings, msec: int, error: String) -> void:
	if gs != _gs:
		return
	_title.text = "%s: live, %s" % [gs.output_name, "failed: " + error if error else "%d ms" % msec]


func _set_items(items: Array) -> void:
	# Keep the same map selected across updates (by label).
	_items = items
	_selected = 0
	for i in items.size():
		if items[i]["label"] == _selected_label:
			_selected = i
	# Reuse thumbnails when the count matches, so a live drag doesn't rebuild the UI.
	if _thumbs.get_child_count() != items.size():
		for c in _thumbs.get_children():
			_thumbs.remove_child(c)  # now, so indices below address the new thumbnails
			c.queue_free()
		for i in items.size():
			_thumbs.add_child(_make_thumb(i))
		_scroll.scroll_vertical = 0
	for i in items.size():
		var box := _thumbs.get_child(i)
		(box.get_child(0) as TextureRect).texture = items[i]["texture"]
		(box.get_child(1) as Label).text = items[i]["label"]
	_update_view()


func _make_thumb(index: int) -> Control:
	var box := VBoxContainer.new()
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(THUMB, THUMB)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_selected = index
			_selected_label = _items[index]["label"]
			_update_view())
	box.add_child(rect)
	var l := Label.new()
	l.custom_minimum_size = Vector2(THUMB, 0)
	l.clip_text = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 11)
	box.add_child(l)
	return box


func _update_view() -> void:
	var mat := _view.material as ShaderMaterial
	if _items.is_empty():
		_view.texture = null
		_view_label.text = ""
		return
	var item: Dictionary = _items[clampi(_selected, 0, _items.size() - 1)]
	_view.texture = item["texture"]
	mat.set_shader_parameter("tiles", float(_tile.selected + 1))
	mat.set_shader_parameter("channel", _channel.selected)
	mat.set_shader_parameter("grey", item["grey"])
	var tex: Texture2D = item["texture"]
	_view_label.text = "%s  %d×%d" % [item["label"], tex.get_width(), tex.get_height()]
	for i in _thumbs.get_child_count():
		(_thumbs.get_child(i).get_child(1) as Label).modulate = Color(1, 0.75, 0.4) if i == _selected else Color.WHITE


func _on_view_input(e: InputEvent) -> void:
	var mat := _view.material as ShaderMaterial
	var zoom := float(mat.get_shader_parameter("zoom"))
	if e is InputEventMouseButton and e.pressed:
		if e.double_click:
			mat.set_shader_parameter("zoom", 1.0)
			mat.set_shader_parameter("zoom_center", Vector2(0.5, 0.5))
		elif e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.25 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8
			var new_zoom := clampf(zoom * factor, 1.0, 32.0)
			# Keep the point under the mouse in place.
			var uv := _view_uv(e.position)
			var center: Vector2 = mat.get_shader_parameter("zoom_center")
			var under := (uv - Vector2(0.5, 0.5)) / zoom + center
			center = under - (uv - Vector2(0.5, 0.5)) / new_zoom
			mat.set_shader_parameter("zoom", new_zoom)
			mat.set_shader_parameter("zoom_center", center if new_zoom > 1.0 else Vector2(0.5, 0.5))
			_view.accept_event()
	elif e is InputEventMouseMotion and (e.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_LEFT)):
		var rect_size := _draw_size()
		if rect_size.x > 0:
			var center: Vector2 = mat.get_shader_parameter("zoom_center")
			mat.set_shader_parameter("zoom_center", center - e.relative / rect_size / zoom)


## UV (0..1) of a point in the view, within the drawn (aspect-kept) square.
func _view_uv(pos: Vector2) -> Vector2:
	var s := _draw_size()
	var offset := (_view.size - s) * 0.5
	return ((pos - offset) / s) if s.x > 0 else Vector2(0.5, 0.5)


func _draw_size() -> Vector2:
	if _view.texture == null:
		return Vector2.ZERO
	var ts := Vector2(_view.texture.get_size())
	var k := minf(_view.size.x / ts.x, _view.size.y / ts.y)
	return ts * k


static func _is_grey(tex: Texture2D) -> bool:
	if tex.has_method("get_format"):
		return tex.call("get_format") in GREY_FORMATS
	return false


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
