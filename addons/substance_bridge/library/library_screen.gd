@tool
extends VBoxContainer
## The "Substance Library" main screen: a grid of sphere thumbnails of the .sbsar files in the
## library folders, and for the selected one a large interactive preview (drag to orbit,
## wheel to zoom, sphere / cube / plane) with its mesh inputs, parameters and outputs.
##
## "Use for New Material" (or a double-click) puts the file's path in the dock: the material
## references the .sbsar where it is; nothing is copied into the project.

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")
const GraphDescription := preload("res://addons/substance_bridge/backends/graph_description.gd")
const Library := preload("res://addons/substance_bridge/library/library.gd")
const LibraryRenderer := preload("res://addons/substance_bridge/library/library_renderer.gd")
const PreviewStage := preload("res://addons/substance_bridge/library/preview_stage.gd")
const MeshBaker := preload("res://addons/substance_bridge/backends/substance/mesh_baker.gd")

## The user chose a file for a new material.
signal use_requested(path: String)
## Thumbnail generation finished (all entries have one, or failed).
signal thumbnails_done

const TILE := 112
const ALL := "All categories"

var renderer: LibraryRenderer

var _entries: Array[Dictionary] = []
var _tiles := {}  # path -> Button
var _selected := {}
var _scanned := false
var _thumbs_running := false
## "<path>|<key>" -> error. Kept across rescans: an unchanged file that failed is not retried.
var _thumb_failures := {}
var _preview_next := ""
var _preview_running := false
var _preview_stage: PreviewStage

var _folders_menu: MenuButton
var _search: LineEdit
var _category: OptionButton
var _status: Label
var _grid: HFlowContainer
var _grid_scroll: ScrollContainer
var _empty: VBoxContainer
var _body: HSplitContainer
var _view: SubViewportContainer
var _view_status: Label
var _shape: OptionButton
var _use_button: Button
var _reveal_button: Button
var _info: RichTextLabel
var _dir_dialog: EditorFileDialog
var _group := ButtonGroup.new()


func _init() -> void:
	name = "Substance Library"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	renderer = LibraryRenderer.new()
	add_child(renderer)

	var bar := HBoxContainer.new()
	_folders_menu = MenuButton.new()
	_folders_menu.text = "Folders"
	_folders_menu.flat = false
	_folders_menu.tooltip_text = "Library folders (saved in Editor Settings, shared by every project)."
	_folders_menu.about_to_popup.connect(_fill_folders_menu)
	_folders_menu.get_popup().id_pressed.connect(_on_folder_menu)
	bar.add_child(_folders_menu)
	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.tooltip_text = "Matches the file name, folder, and the graph's category and keywords."
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(240, 0)
	_search.text_changed.connect(func(_t: String) -> void: _apply_filter())
	bar.add_child(_search)
	_category = OptionButton.new()
	_category.item_selected.connect(func(_i: int) -> void: _apply_filter())
	bar.add_child(_category)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.tooltip_text = "Look for new, changed and removed files."
	rescan.pressed.connect(rescan_library)
	bar.add_child(rescan)
	add_child(bar)
	_status = Label.new()
	_status.clip_text = true
	_status.add_theme_font_size_override("font_size", 12)
	_status.modulate = Color(1, 1, 1, 0.7)

	_empty = VBoxContainer.new()
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	var hint := Label.new()
	hint.text = "Add a folder of .sbsar files to start your library.\nFiles stay where they are; materials reference them in place."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(hint)
	var add := Button.new()
	add.text = "Add Folder..."
	add.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func() -> void: _dir_dialog.popup_file_dialog())
	_empty.add_child(add)
	add_child(_empty)

	_body = HSplitContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.add_child(_grid)
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_grid_scroll)
	left.add_child(_status)
	_body.add_child(left)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(420, 0)
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.custom_minimum_size = Vector2(380, 380)
	_view.tooltip_text = "Drag: orbit. Wheel: zoom. Double-click: reset."
	_view.gui_input.connect(_on_view_input)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	_preview_stage = PreviewStage.new(false)
	vp.add_child(_preview_stage)
	_view.add_child(vp)
	side.add_child(_view)
	_view_status = Label.new()
	_view_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_view_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_view_status)

	var row := HBoxContainer.new()
	_shape = OptionButton.new()
	for s in PreviewStage.SHAPE_NAMES:
		_shape.add_item(s)
	_shape.item_selected.connect(func(i: int) -> void: _preview_stage.set_shape(i as PreviewStage.Shape))
	row.add_child(_shape)
	_use_button = Button.new()
	_use_button.text = "Use for New Material"
	_use_button.tooltip_text = "Put this file in the dock's New material field (it is referenced where it is, not copied)."
	_use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_use_button.disabled = true
	_use_button.pressed.connect(func() -> void:
		if not _selected.is_empty():
			use_requested.emit(_selected["path"]))
	row.add_child(_use_button)
	_reveal_button = Button.new()
	_reveal_button.text = "Show File"
	_reveal_button.disabled = true
	_reveal_button.pressed.connect(func() -> void:
		if not _selected.is_empty():
			OS.shell_show_in_file_manager(String(_selected["path"])))
	row.add_child(_reveal_button)
	side.add_child(row)

	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.selection_enabled = true
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.custom_minimum_size = Vector2(0, 160)
	_info.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	side.add_child(_info)
	_body.add_child(side)


func _ready() -> void:
	# Headings (bold) a step larger than the body, at any editor scale.
	var body_size := _info.get_theme_font_size("normal_font_size")
	_info.add_theme_font_size_override("bold_font_size", int(body_size * 1.2))
	_dir_dialog = EditorFileDialog.new()
	_dir_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_dir_dialog.title = "Add a Library Folder"
	_dir_dialog.dir_selected.connect(add_folder)
	add_child(_dir_dialog)
	_show_body(not Settings.library_folders().is_empty())


## Scans the library the first time the screen is shown.
func on_shown() -> void:
	if not _scanned:
		rescan_library()


func add_folder(dir: String) -> void:
	dir = dir.replace("\\", "/").trim_suffix("/")
	var folders := Settings.library_folders()
	if dir in folders:
		return
	folders.append(dir)
	Settings.set_library_folders(folders)
	rescan_library()


func remove_folder(dir: String) -> void:
	var folders := Settings.library_folders()
	var i := folders.find(dir)
	if i >= 0:
		folders.remove_at(i)
		Settings.set_library_folders(folders)
		rescan_library()


func _fill_folders_menu() -> void:
	var p := _folders_menu.get_popup()
	p.clear()
	p.add_item("Add Folder...", 0)
	var folders := Settings.library_folders()
	if not folders.is_empty():
		p.add_separator("Click a folder to remove it from the library")
	for i in folders.size():
		p.add_item(folders[i], 100 + i)


func _on_folder_menu(id: int) -> void:
	if id == 0:
		_dir_dialog.popup_file_dialog()
		return
	var folders := Settings.library_folders()
	var i := id - 100
	if i >= 0 and i < folders.size():
		remove_folder(folders[i])


func _show_body(has_folders: bool) -> void:
	_empty.visible = not has_folders
	_body.visible = has_folders


# --- scanning and thumbnails ------------------------------------------------------------------

## Re-reads the library folders, rebuilds the grid and renders missing thumbnails.
func rescan_library() -> void:
	_scanned = true
	var folders := Settings.library_folders()
	_show_body(not folders.is_empty())
	var cache_dir := String(Settings.snapshot()["cache_dir"])
	_entries = Library.scan(folders, cache_dir)
	Library.prune(_entries, folders, cache_dir)
	_rebuild_grid()
	_render_missing_thumbs()


func entries() -> Array[Dictionary]:
	return _entries


func _rebuild_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_tiles.clear()
	var categories := PackedStringArray()
	for e in _entries:
		var tile := _make_tile(e)
		_grid.add_child(tile)
		_tiles[e["path"]] = tile
		var cat := Library.category_label(e)
		if not cat in categories:
			categories.append(cat)
	var previous := _category.get_item_text(_category.selected) if _category.item_count > 0 else ALL
	_category.clear()
	_category.add_item(ALL)
	for c in categories:
		_category.add_item(c)
		if c == previous:
			_category.select(_category.item_count - 1)
	_apply_filter()
	if not _selected.is_empty():
		for e in _entries:
			if e["path"] == _selected["path"]:
				_tiles[e["path"]].set_pressed_no_signal(true)
	_update_status()


func _make_tile(e: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _group
	b.custom_minimum_size = Vector2(TILE + 12, TILE + 30)
	b.icon = Library.load_thumb(e)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.text = e["name"]
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 12)
	b.tooltip_text = "%s\n%s" % [e["name"], e["path"]]
	b.pressed.connect(func() -> void: select(e))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
			use_requested.emit(e["path"]))
	return b


func _apply_filter() -> void:
	var words := _search.text.strip_edges().to_lower().split(" ", false)
	var cat := _category.get_item_text(_category.selected) if _category.item_count > 0 else ALL
	for e in _entries:
		var tile: Button = _tiles.get(e["path"])
		if tile == null:
			continue
		var show := cat == ALL or Library.category_label(e) == cat
		if show and not words.is_empty():
			var hay := ("%s %s %s" % [e["name"], e["category"], _keywords(e)]).to_lower()
			for w in words:
				if not hay.contains(w):
					show = false
					break
		tile.visible = show


## Keywords and category from the graph, once it has been described this session.
func _keywords(e: Dictionary) -> String:
	var gs: GraphSettings = renderer._settings.get(e["path"])
	if gs == null or gs.get_description() == null:
		return ""
	var meta: Dictionary = gs.get_description().meta
	return "%s %s %s" % [meta.get("keywords", ""), meta.get("category", ""), gs.get_description().label]


func _render_missing_thumbs() -> void:
	if _thumbs_running:
		return
	_thumbs_running = true
	while true:
		var next := {}
		for e in _entries:
			if not FileAccess.file_exists(e["thumb"]) and not _thumb_failures.has(_fail_key(e)):
				next = e
				break
		if next.is_empty():
			break
		# The large preview goes first.
		while _preview_running or not _preview_next.is_empty():
			await get_tree().process_frame
		_update_status(next)
		var err: String = await renderer.make_thumbnail(next)
		if not err.is_empty():
			_thumb_failures[_fail_key(next)] = err
			push_warning("Substance Library: no thumbnail for %s: %s" % [next["name"], err])
		var tile: Button = _tiles.get(next["path"])
		if tile and is_instance_valid(tile):
			tile.icon = Library.load_thumb(next)
			if not err.is_empty():
				tile.tooltip_text += "\nNo thumbnail: " + err
	_thumbs_running = false
	_update_status()
	thumbnails_done.emit()


static func _fail_key(e: Dictionary) -> String:
	return "%s|%s" % [e["path"], e["key"]]


func _failed_count() -> int:
	var n := 0
	for e in _entries:
		if _thumb_failures.has(_fail_key(e)):
			n += 1
	return n


func is_generating() -> bool:
	return _thumbs_running


func _update_status(working := {}) -> void:
	var have := 0
	for e in _entries:
		if FileAccess.file_exists(e["thumb"]):
			have += 1
	var text := "%d file(s) in %d folder(s)" % [_entries.size(), Settings.library_folders().size()]
	if not working.is_empty():
		text += "; thumbnail %d/%d: %s" % [have + _failed_count() + 1, _entries.size(), working["name"]]
	elif _failed_count() > 0:
		text += "; %d without a thumbnail (hover a tile for why)" % _failed_count()
	_status.text = text


# --- selection and the large preview ---------------------------------------------------------

func select(e: Dictionary) -> void:
	_selected = e
	var tile: Button = _tiles.get(e["path"])
	if tile:
		tile.set_pressed_no_signal(true)
	_use_button.disabled = false
	_reveal_button.disabled = false
	_info.text = "[b]%s[/b]\nReading..." % e["name"]
	_request_preview(e["path"])
	var gs := await renderer.settings_for(e["path"])
	if _selected == e:
		_info.text = info_text(e, gs.get_description())
		_apply_filter()  # keywords are known now


func selected_entry() -> Dictionary:
	return _selected


func _request_preview(path: String) -> void:
	_preview_next = path
	if _preview_running:
		return
	_preview_running = true
	while not _preview_next.is_empty():
		var p := _preview_next
		_preview_next = ""
		_view_status.text = "Rendering %s..." % p.get_file().get_basename()
		var out: Dictionary = await renderer.render(p, LibraryRenderer.PREVIEW_SIZE_LOG2)
		if not _preview_next.is_empty():
			continue  # another file was picked meanwhile
		if not String(out["error"]).is_empty():
			_view_status.text = "Could not render: " + String(out["error"])
			_preview_stage.set_material(null)
			continue
		_preview_stage.mesh_driven = out["mesh_driven"]
		_preview_stage.set_material(out["material"])
		_view_status.text = "%s, 512 maps in %.1f s%s" % [p.get_file().get_basename(), out["msec"] / 1000.0,
				"; mesh maps baked on the sphere" if out["mesh_driven"] else ""]
	_preview_running = false
	preview_done.emit()


## A preview render finished (the material is on the large view).
signal preview_done


func is_previewing() -> bool:
	return _preview_running


func preview_material() -> StandardMaterial3D:
	return _preview_stage.model.material_override as StandardMaterial3D


func preview_stage() -> PreviewStage:
	return _preview_stage


func _on_view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.double_click:
			_preview_stage.reset_view()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_preview_stage.zoom(0.9)
			_view.accept_event()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_preview_stage.zoom(1.1)
			_view.accept_event()
	elif e is InputEventMouseMotion and (e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE)):
		_preview_stage.orbit(e.relative)


# --- info ---------------------------------------------------------------------------------------

## BBCode for the info panel: file, graph metadata, mesh inputs, parameters, outputs.
static func info_text(e: Dictionary, d: GraphDescription) -> String:
	var t := PackedStringArray()
	var title: String = d.label if d and not d.label.is_empty() else e["name"]
	t.append("[b]%s[/b]" % _esc(title))
	t.append("[color=gray]%s[/color]" % _esc(Library.category_label(e).path_join(String(e["path"]).get_file())))
	if d == null or not d.is_ok():
		t.append("\n[color=salmon]Could not read the file: %s[/color]" % _esc("; ".join(d.errors) if d else "unknown error"))
		return "\n".join(t)

	var meta := d.meta
	var facts := PackedStringArray()
	if meta.has("category"):
		facts.append("[color=gray]Category[/color] " + _esc(meta["category"]))
	if meta.has("author"):
		var author := _esc(meta["author"])
		if meta.has("authorurl"):
			author = "[url=%s]%s[/url]" % [meta["authorurl"], author]
		facts.append("[color=gray]Author[/color] " + author)
	if meta.has("physicalSize"):
		var ps := String(meta["physicalSize"]).split(",")
		if ps.size() >= 2:
			facts.append("[color=gray]Physical size[/color] %s × %s cm" % [_num(ps[0]), _num(ps[1])])
	if d.graph_count > 1:
		facts.append("[color=gray]Graphs[/color] %d (the bridge uses the first, %s)" % [d.graph_count, _esc(d.graph_url)])
	if not facts.is_empty():
		t.append(" · ".join(facts))
	if meta.has("keywords"):
		t.append("[color=gray]Keywords[/color] " + _esc(String(meta["keywords"]).replace(";", ", ")))
	if meta.has("description"):
		t.append(_esc(meta["description"]))

	var images := d.image_inputs()
	t.append("\n[b]Mesh inputs[/b]")
	var mesh := PackedStringArray()
	var other := PackedStringArray()
	for p in images:
		var usages: PackedStringArray = p.get("usages", PackedStringArray())
		var line := "%s [color=gray](%s)[/color]" % [_esc(p["label"]), _esc(", ".join(usages)) if not usages.is_empty() else "image"]
		if _is_mesh_usage(usages):
			mesh.append("  • " + line)
		else:
			other.append("  • " + line)
	if mesh.is_empty():
		t.append("  None: a tiling material, it doesn't need the mesh.")
	else:
		t.append("  Driven by the mesh: the bridge bakes these from the mesh you apply it to.")
		t.append_array(mesh)
	if not other.is_empty():
		t.append("[color=gray]Other image inputs (left empty)[/color]")
		t.append_array(other)

	t.append("\n[b]Parameters[/b]")
	var group := "\u0001"
	var count := 0
	for p in d.params:
		if p["type"] == "image" or String(p["id"]).begins_with("$"):
			continue
		if p["group"] != group:
			group = p["group"]
			if not String(group).is_empty():
				t.append("  [i]%s[/i]" % _esc(group))
		t.append("    %s [color=gray]%s[/color]" % [_esc(p["label"]), _esc(_param_detail(p))])
		count += 1
	if count == 0:
		t.append("  None")
	if not d.presets.is_empty():
		var names := PackedStringArray()
		for pr in d.presets:
			names.append(pr["label"])
		t.append("[color=gray]Presets[/color] " + _esc(", ".join(names)))

	t.append("\n[b]Outputs[/b]")
	for o in d.outputs:
		var usages: PackedStringArray = o.get("usages", PackedStringArray())
		t.append("  • %s [color=gray]%s[/color]" % [_esc(o["label"]), _esc(", ".join(usages))])
	return "\n".join(t)


static func _is_mesh_usage(usages: PackedStringArray) -> bool:
	for u in usages:
		if u in MeshBaker.BAKERS:
			return true
	return false


static func _param_detail(p: Dictionary) -> String:
	var widget := String(p.get("widget", ""))
	var dflt := String(p.get("default", ""))
	if widget == "togglebutton":
		return "on/off, default %s" % ("on" if dflt == "1" else "off")
	if not p.get("items", []).is_empty():
		var texts := PackedStringArray()
		for it in p["items"]:
			texts.append(it["text"])
		return "choice: " + " / ".join(texts)
	if widget == "color":
		return "colour"
	if p.has("min"):
		return "%s to %s, default %s" % [_num(str(p["min"])), _num(str(p["max"])), _short(dflt)]
	return "%s, default %s" % [p["type"], _short(dflt)] if not dflt.is_empty() else String(p["type"])


static func _short(v: String) -> String:
	var parts := PackedStringArray()
	for s in v.split(","):
		parts.append(_num(s))
	return ", ".join(parts)


static func _num(s: String) -> String:
	if not s.strip_edges().is_valid_float():
		return s
	var f := float(s)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else ("%.3f" % f).rstrip("0")


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
