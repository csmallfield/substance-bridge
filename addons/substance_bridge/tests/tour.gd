@tool
extends RefCounted
## Screenshot tour for the tutorial site (docs/). Drives the dock through every feature in a
## windowed editor and saves editor screenshots (full window and crops) as PNG.
##
## Run on a COPY of the project (it creates materials and edits the test scene in memory):
##   set SUBSTANCE_BRIDGE_TOUR=<output folder>
##   godot --editor --path <copy> --log-file <temp>/tour.log
## Quits when done. Not part of the plugin's normal use.

const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")

const TARMAC := "C:/Program Files/Allegorithmic/Adobe Substance 3D for Maya/2022/sbsars/tarmac.sbsar"
const EDGING := "D:/07_resources/JRO/Industrial_SmartMaterials/Generators/PL_ISF_Gen_Edging01.sbsar"
const SCENE := "res://test/rock_test.tscn"
const ROCK_SCALE := 14.0
const VARIANT_SCALE := 7.0

var plugin: EditorPlugin
var _out := ""
var _tree: SceneTree
var _dock: Node


func run(dock: Node, out_dir: String) -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_dock = dock
	_out = out_dir
	DirAccess.make_dir_recursive_absolute(_out)
	OS.low_processor_usage_mode = false
	var screen := DisplayServer.screen_get_usable_rect()
	var size := Vector2i(mini(1920, screen.size.x), mini(1080, screen.size.y))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position)
	var fs := EditorInterface.get_resource_filesystem()
	while fs.is_scanning():
		await _tree.process_frame

	plugin.hide_bottom_panel()
	if OS.get_environment("SUBSTANCE_BRIDGE_TOUR_ONLY") == "projection":
		await _projection_tour()
		print("[tour] done: ", _out)
		_tree.quit(0)
		return
	var library := OS.get_environment("SUBSTANCE_BRIDGE_TOUR_LIBRARY")
	if not library.is_empty():
		await _library_tour(library)
		print("[tour] done: ", _out)
		_tree.quit(0)
		return
	EditorInterface.open_scene_from_path(SCENE)
	await _settle(1.0)
	EditorInterface.set_main_screen_editor("3D")
	var root := EditorInterface.get_edited_scene_root()
	var rock: MeshInstance3D = root.get_node("Rock")
	var base_scale := rock.scale
	rock.scale = base_scale * ROCK_SCALE
	rock.position = Vector3.ZERO
	_select([rock])
	_focus_tab(_dock)
	await _settle(1.5)
	_shot("01_editor", null)
	_shot("02_dock_empty", _dock)

	# --- create from an .sbsar
	_dock._source_kind.select(0)
	_dock._refresh_source_rows()
	_dock._sbsar_edit.text = TARMAC
	var gs: GraphSettings = await _dock.create_material(TARMAC, [rock] as Array[MeshInstance3D])
	await _settle(1.5)
	_focus_tab(_dock)
	await _settle(0.5)
	_shot("03_dock_created", _dock)
	await _view_shot("04_view_tarmac")
	_focus_tab(EditorInterface.get_inspector())
	EditorInterface.edit_resource(gs)
	await _settle(1.0)
	_shot("05_inspector_settings", EditorInterface.get_inspector())
	await _inspector_scrolled("05b_inspector_params", gs)
	_shot("06_editor_inspector", null)

	# --- edit parameters: preview follows
	gs.set("asphalt_color", Color(0.42, 0.12, 0.09))
	gs.set("tarmac_damage", 0.95)
	gs.set("tarmac_dirtiness", 0.8)
	await _idle()
	EditorInterface.edit_resource(gs)
	await _settle(1.0)
	await _view_shot("07_view_edited")

	# --- 2D preview panel: live outputs (before the commit render), then tiling and a channel
	var panel: Control = plugin._preview
	plugin.make_bottom_panel_item_visible(panel)
	await _settle(0.5)
	panel.custom_minimum_size.y = 430  # the editor then makes room for it
	await _settle(0.5)
	gs.set("tarmac_damage", 0.7)
	await _tree.process_frame
	while _dock._live.is_running():
		await _tree.process_frame
	await _settle(0.4)
	_shot("22_panel_live", panel)
	for i in panel._items.size():
		if panel._items[i]["label"] == "Base Color":
			panel._selected = i
			panel._selected_label = "Base Color"
	panel._tile.select(2)
	panel._update_view()
	await _settle(0.4)
	_shot("23_panel_tiled", panel)
	panel._tile.select(0)
	panel._selected_label = ""
	panel._update_view()
	await _idle()
	panel.custom_minimum_size.y = 260
	plugin.hide_bottom_panel()  # later view shots keep their full height
	await _settle(0.3)
	await _inspector_scrolled("08_inspector_edited", gs)

	# --- visibility rules
	gs.set("painted_arrows", false)
	await _idle()
	await _settle(0.5)
	await _inspector_scrolled("09_inspector_visibleif", gs)
	gs.set("painted_arrows", true)
	await _idle()

	# --- final render
	gs.final_size = 11
	_focus_tab(_dock)
	_dock._queue(_dock.Job.FINAL)
	await _idle()
	await _settle(0.5)
	_shot("10_dock_final", _dock)

	# --- seed variants on three rocks
	var rocks: Array[MeshInstance3D] = [rock]
	for i in 2:
		var r := rock.duplicate() as MeshInstance3D
		r.name = "Rock%d" % (i + 2)
		root.add_child(r)
		r.owner = root
		rocks.append(r)
	# Line them up across the screen: along the editor camera's right vector, on the ground.
	var right := EditorInterface.get_editor_viewport_3d(0).get_camera_3d().global_transform.basis.x
	right = Vector3(right.x, 0, right.z).normalized()
	for i in rocks.size():
		rocks[i].scale = base_scale * VARIANT_SCALE
		rocks[i].position = right * (i - 1) * 2.4
	_select(rocks)
	await _settle(0.5)
	await _dock.make_variants(3, rocks)
	await _settle(1.5)
	await _view_shot("11_view_variants")
	_shot("12_dock_variants", _dock)

	# --- batch
	_dock._batch_size.select(2)  # 512
	var paths := PackedStringArray()
	for r in rocks:
		var settings = load("res://addons/substance_bridge/core/pipeline.gd").settings_for_material(r.material_override)
		if settings:
			paths.append(settings.resource_path)
	await _dock.render_all(paths, 9)
	await _settle(0.5)
	_shot("13_dock_batch", _dock)

	# --- mesh-adaptive graph: bakes from the selected mesh
	for i in [1, 2]:
		rocks[i].queue_free()
	rock.position = Vector3.ZERO
	rock.scale = base_scale * ROCK_SCALE
	_select([rock])
	await _settle(0.5)
	_dock._sbsar_edit.text = EDGING
	var edge: GraphSettings = await _dock.create_material(EDGING, [rock] as Array[MeshInstance3D])
	if edge:
		edge.set("EdgingWidth", 1.0)
		edge.set("GrungeScratchesAmount", 1.0)
		await _idle()
	_focus_tab(_dock)
	await _settle(1.0)
	_shot("14_dock_mesh_maps", _dock)
	await _view_shot("15_view_edging")
	if edge:
		_focus_tab(EditorInterface.get_inspector())
		EditorInterface.edit_resource(edge)
		await _settle(1.0)
		_focus_tab(EditorInterface.get_inspector())
		EditorInterface.edit_resource(edge)
		await _settle(0.6)
		_shot("16_inspector_baker", EditorInterface.get_inspector())
		edge.baker = GraphSettings.BAKER_NATIVE
		await _idle()
		await _settle(0.5)
		_focus_tab(_dock)
		await _settle(0.5)
		_shot("17_dock_native", _dock)

	# --- noise lab
	_dock._source_kind.select(1)
	_dock._refresh_source_rows()
	for i in _dock._noise_option.item_count:
		if _dock._noise_option.get_item_text(i) == "grunge_014":
			_dock._noise_option.select(i)
	_focus_tab(_dock)
	await _settle(0.5)
	_shot("18_dock_noise", _dock)
	var noise: GraphSettings = await _dock.create_material("noiselab://grunge_014", [rock] as Array[MeshInstance3D])
	if noise:
		noise.set("normal_strength", 8.0)
		await _idle()
	await _settle(1.5)
	await _view_shot("19_view_noise")
	if noise:
		_focus_tab(EditorInterface.get_inspector())
		EditorInterface.edit_resource(noise)
		await _settle(1.0)
		await _inspector_scrolled("20_inspector_noise", noise)
	# --- channel routing: the grunge also drives roughness (inverted, 0.35..1) and AO
	if noise:
		noise.set("slot_roughness_source", "Height")
		noise.set("slot_roughness_invert", true)
		noise.set("slot_roughness_min", 0.35)
		noise.set("slot_ambientOcclusion_source", "Height")
		noise.set("slot_ambientOcclusion_strength", 0.6)
		await _idle()
		await _settle(1.0)
		await _view_shot("25_view_routed")
		_focus_tab(EditorInterface.get_inspector())
		EditorInterface.edit_resource(noise)
		await _settle(1.0)
		await _slots_shot("24_inspector_slots")
	await _dock.create_material("noiselab://moisture_noise", [rock] as Array[MeshInstance3D])
	await _settle(1.5)
	await _view_shot("21_view_moisture")

	print("[tour] done: ", _out)
	_tree.quit(0)


## Projection shots only (SUBSTANCE_BRIDGE_TOUR_ONLY=projection): the rock with auto-generated
## UVs (Godot's unwrapper), tarmac through those UVs on the left and triplanar on the right.
func _projection_tour() -> void:
	EditorInterface.open_scene_from_path(SCENE)
	await _settle(1.0)
	EditorInterface.set_main_screen_editor("3D")
	var root := EditorInterface.get_edited_scene_root()
	var rock: MeshInstance3D = root.get_node("Rock")
	var mesh := _auto_uv_mesh(rock.mesh)
	var scale := rock.scale * float(OS.get_environment("TOUR_PROJ_SCALE") if OS.has_environment("TOUR_PROJ_SCALE") else "8")
	var spread := float(OS.get_environment("TOUR_PROJ_SPREAD") if OS.has_environment("TOUR_PROJ_SPREAD") else "0.6")
	var width := mesh.get_aabb().size.x * scale.x
	var pair: Array[MeshInstance3D] = []
	for side in [-1, 1]:
		var mi := MeshInstance3D.new()
		mi.name = "AutoUV_%s" % ("UV" if side < 0 else "Triplanar")
		mi.mesh = mesh
		mi.scale = scale
		mi.rotation = rock.rotation
		mi.position = Vector3(side * width * spread, 0, 0)
		root.add_child(mi)
		mi.owner = root
		pair.append(mi)
	rock.visible = false
	for n in ["Camera3D"]:
		if root.has_node(n):
			(root.get_node(n) as Node3D).visible = false
	_focus_tab(_dock)
	await _dock.create_material(TARMAC, [pair[0]] as Array[MeshInstance3D])
	var gs: GraphSettings = await _dock.create_material(TARMAC, [pair[1]] as Array[MeshInstance3D])
	gs.projection = 2
	await _idle()
	await _dock.bake_from_mesh(pair[1])
	await _idle()
	gs.fit_projection_to_mesh()
	gs.projection_tile_size = snappedf(gs.projection_tile_size * 0.6, 0.001)
	await _idle()
	await _settle(2.0)
	await _view_shot("30_view_projection")
	_focus_tab(EditorInterface.get_inspector())
	EditorInterface.edit_resource(gs)
	await _settle(1.0)
	await _group_shot("31_inspector_projection", &"projection")


## The mesh with UVs from Godot's lightmap unwrapper moved into UV0 (scattered islands, like
## many auto-generated UVs), with tangents rebuilt for them.
static func _auto_uv_mesh(source: Mesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	for i in source.get_surface_count():
		var arrays := source.surface_get_arrays(i)
		arrays[Mesh.ARRAY_TANGENT] = null
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.lightmap_unwrap(Transform3D.IDENTITY, 0.02)
	var out := ArrayMesh.new()
	for i in am.get_surface_count():
		var arrays := am.surface_get_arrays(i)
		arrays[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV2]
		arrays[Mesh.ARRAY_TEX_UV2] = null
		arrays[Mesh.ARRAY_TANGENT] = null
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
		st.generate_tangents()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	return out


## An Inspector shot scrolled to the property `first`, with sections unfolded.
func _group_shot(name: String, first: StringName) -> void:
	var inspector := EditorInterface.get_inspector()
	for section in inspector.find_children("*", "EditorInspectorSection", true, false):
		section.call("unfold")
	await _settle(0.6)
	for prop in inspector.find_children("*", "EditorProperty", true, false):
		if (prop as EditorProperty).get_edited_property() == first:
			var y := (prop as Control).global_position.y - inspector.global_position.y + inspector.scroll_vertical
			inspector.scroll_vertical = int(y - 120)
			break
	await _settle(0.5)
	_shot(name, inspector)
	inspector.scroll_vertical = 0


## Library shots only (SUBSTANCE_BRIDGE_TOUR_LIBRARY=<folder>): the Substance tab with a
## tiling material and a mesh-driven one selected, and the dock after "Use". The library
## folders setting is restored afterwards.
func _library_tour(folder: String) -> void:
	const Settings := preload("res://addons/substance_bridge/core/settings.gd")
	var saved := Settings.library_folders()
	Settings.set_library_folders(PackedStringArray([folder]))
	EditorInterface.open_scene_from_path(SCENE)
	await _settle(1.0)
	var screen: Node = plugin._library
	EditorInterface.set_main_screen_editor(plugin.SCREEN_NAME)
	await _settle(0.5)
	if screen.is_generating():
		await screen.thumbnails_done
	var pick := {}
	var mesh := {}
	for e in screen.entries():
		if String(e["name"]) == "rusted_painted_metal":
			pick = e
		if String(e["name"]).contains("Edging01"):
			mesh = e
	EditorInterface.distraction_free_mode = true  # the docks hide: the tab gets the window
	screen.select(pick)
	await screen.preview_done
	screen.preview_stage().orbit(Vector2(-60, -25))
	await _settle(1.0)
	_shot("26_library", null)
	EditorInterface.distraction_free_mode = false
	await _settle(0.5)

	screen.select(mesh)
	await screen.preview_done
	screen._shape.select(0)
	screen.preview_stage().orbit(Vector2(90, 0))
	await _settle(1.0)
	_shot("27_library_mesh", screen._body.get_child(1))

	screen._search.text = "metal"
	screen._apply_filter()
	await _settle(0.5)
	_shot("28_library_search", screen._grid_scroll)
	screen._search.text = ""
	screen._apply_filter()

	screen.use_requested.emit(pick["path"])
	_focus_tab(_dock)
	await _settle(1.0)
	_shot("29_dock_library", _dock)
	Settings.set_library_folders(saved)


# --- helpers ----------------------------------------------------------------------------------

func _select(nodes: Array) -> void:
	var sel := EditorInterface.get_selection()
	sel.clear()
	for n in nodes:
		sel.add_node(n)


## Shows the tab (in a dock's TabContainer) that holds `control`.
func _focus_tab(control: Control) -> void:
	var n: Node = control
	while n and n.get_parent():
		var p := n.get_parent()
		if p is TabContainer:
			(p as TabContainer).current_tab = (p as TabContainer).get_tab_idx_from_control(n)
			return
		n = p


## A 3D view shot without the selection gizmo (the selection stays cleared; later steps
## that need one select explicitly).
func _view_shot(name: String) -> void:
	EditorInterface.get_selection().clear()
	await _settle(0.4)
	_shot(name, _view())


## An Inspector shot of es, scrolled down to the graph's parameters.
func _inspector_scrolled(name: String, res: Resource) -> void:
	var inspector := EditorInterface.get_inspector()
	_focus_tab(inspector)
	EditorInterface.edit_resource(res)
	await _settle(0.6)
	inspector.scroll_vertical = 540
	await _settle(0.4)
	_shot(name, inspector)
	inspector.scroll_vertical = 0


## Moves the bottom panel's divider so panel is about height px tall.
func _set_panel_height(panel: Control, height: int) -> void:
	var n: Node = panel
	while n and not (n is SplitContainer and (n as SplitContainer).vertical):
		n = n.get_parent()
	if n:
		(n as SplitContainer).split_offset -= int(height - panel.size.y)


## An Inspector shot scrolled to the Material Slots group, with its sections unfolded.
func _slots_shot(name: String) -> void:
	var inspector := EditorInterface.get_inspector()
	for section in inspector.find_children("*", "EditorInspectorSection", true, false):
		section.call("unfold")
	await _settle(0.6)
	for prop in inspector.find_children("*", "EditorProperty", true, false):
		if (prop as EditorProperty).get_edited_property() == &"slot_baseColor_source":
			var y := (prop as Control).global_position.y - inspector.global_position.y + inspector.scroll_vertical
			inspector.scroll_vertical = int(y - 60)
			break
	await _settle(0.5)
	_shot(name, inspector)
	inspector.scroll_vertical = 0


## The 3D editor viewport's on-screen control.
func _view() -> Control:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var n: Node = vp
	while n and not n is Control:
		n = n.get_parent()
	return n as Control


func _idle() -> void:
	await _tree.process_frame
	var deadline := Time.get_ticks_msec() + 120000
	while _dock.is_busy() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame


func _settle(seconds: float) -> void:
	await _tree.create_timer(seconds).timeout
	for i in 3:
		await RenderingServer.frame_post_draw


## Saves the editor window, or the part `control` covers, as <name>.png.
func _shot(name: String, control: Control) -> void:
	var vp := EditorInterface.get_base_control().get_viewport()
	var img := vp.get_texture().get_image()
	if control:
		var visible := vp.get_visible_rect().size
		var scale := Vector2(img.get_size()) / visible
		var r := control.get_global_rect()
		var rect := Rect2i(Vector2i(r.position * scale), Vector2i(r.size * scale)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if rect.size.x > 0 and rect.size.y > 0:
			img = img.get_region(rect)
	img.save_png(_out.path_join(name + ".png"))
	print("[tour] ", name, " ", img.get_size())
