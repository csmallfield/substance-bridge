@tool
extends RefCounted
## Library self-test: run the editor with
##   set SUBSTANCE_BRIDGE_LIBRARY=<a scratch folder of .sbsar files, with subfolders>
## It points the library at that folder only (your own folders are restored at the end),
## checks scanning, thumbnails and their cache, the preview, the info panel and "Use".
## The folder should hold tarmac.sbsar and a mesh-driven graph (PL_ISF_Gen_Edging02.sbsar).
## Add Painter smart materials (.spsm), one with Painter's preview stored (e.g.
## PL_ISF_MetalPainted02) and one without (PL_ISF_MetalGoldish01), to check those too
## (windowed only: their stacks composite on a RenderingDevice).

const Settings := preload("res://addons/substance_bridge/core/settings.gd")
const Library := preload("res://addons/substance_bridge/library/library.gd")

var plugin: EditorPlugin
var _failures := 0
var _checks := 0


func run(dock: Node, folder: String) -> void:
	folder = folder.replace("\\", "/").trim_suffix("/")
	print("[library] start: ", folder)
	var saved := Settings.library_folders()
	Settings.set_library_folders(PackedStringArray([folder]))
	var screen: Node = plugin._library
	var tree := screen.get_tree()

	# Start clean: no cached thumbnails for the test folder.
	var cache_dir := String(Settings.snapshot()["cache_dir"])
	var thumbs := Library.thumb_dir(folder, cache_dir)
	_expect(thumbs == folder.path_join(".thumbnails"), "thumbnails go into the library folder (%s)" % thumbs)
	for f in DirAccess.get_files_at(thumbs):
		DirAccess.remove_absolute(thumbs.path_join(f))

	EditorInterface.set_main_screen_editor(plugin.SCREEN_NAME)
	await tree.process_frame
	_expect(screen.visible, "the Substance tab shows the library")
	var entries: Array[Dictionary] = screen.entries()
	var count := entries.size()
	_expect(count >= 3, "scan found %d files" % count)
	var categories := {}
	for e in entries:
		categories[e["category"]] = true
	_expect(categories.size() >= 2, "subfolders become categories (%s)" % ", ".join(PackedStringArray(categories.keys())))

	var started := Time.get_ticks_msec()
	if screen.is_generating():
		await screen.thumbnails_done
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	var made := 0
	for e in entries:
		if FileAccess.file_exists(e["thumb"]):
			made += 1
	print("[library] thumbnails: %d/%d in %.1f s, failures %s" % [made, count, secs, screen._thumb_failures])
	var tarmac := _find(entries, "tarmac")
	var edging := _find(entries, "Edging02")
	_expect(not tarmac.is_empty() and FileAccess.file_exists(tarmac["thumb"]), "tarmac has a thumbnail")
	_expect(not edging.is_empty() and FileAccess.file_exists(edging["thumb"]), "the mesh-driven graph has a thumbnail")
	if not tarmac.is_empty() and FileAccess.file_exists(tarmac["thumb"]):
		var img := Image.load_from_file(tarmac["thumb"])
		img.convert(Image.FORMAT_RGBA8)
		var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		var corner := img.get_pixel(2, 2)
		_expect(img.get_width() == Library.THUMB_SIZE, "thumbnail is %d px" % img.get_width())
		_expect(c.a > 0.99 and c.get_luminance() > 0.03, "sphere is drawn in the middle (%s)" % c)
		_expect(corner.a < 0.01, "background is transparent (%s)" % corner)

	# Cached: a rescan renders nothing.
	var mtimes := {}
	for e in entries:
		mtimes[e["thumb"]] = FileAccess.get_modified_time(e["thumb"])
	screen.rescan_library()
	await tree.process_frame
	_expect(not screen.is_generating(), "a rescan reuses every cached thumbnail")

	# A changed file gets a new thumbnail; the old one is pruned.
	if not tarmac.is_empty():
		var old_thumb: String = tarmac["thumb"]
		var bytes := FileAccess.get_file_as_bytes(tarmac["path"])
		await _wait_seconds(1.1)  # modification times have one-second resolution
		var f := FileAccess.open(tarmac["path"], FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		screen.rescan_library()
		var regenerated := 0
		if screen.is_generating():
			await screen.thumbnails_done
		for e in screen.entries():
			if mtimes.has(e["thumb"]) and FileAccess.get_modified_time(e["thumb"]) != mtimes[e["thumb"]]:
				regenerated += 1
		tarmac = _find(screen.entries(), "tarmac")
		_expect(tarmac["thumb"] != old_thumb and FileAccess.file_exists(tarmac["thumb"]), "the edited file got a new thumbnail")
		_expect(not FileAccess.file_exists(old_thumb), "its old thumbnail was pruned")
		_expect(regenerated == 0, "the other thumbnails were left alone")

	# Read-only folders keep thumbnails in the editor cache.
	var ro := Library.thumb_dir("C:/Program Files/Allegorithmic", cache_dir)
	_expect(ro.begins_with(cache_dir), "a read-only folder's thumbnails go to the cache (%s)" % ro)

	# Selecting shows the large preview and the info.
	if not tarmac.is_empty():
		screen.select(tarmac)
		var t0 := Time.get_ticks_msec()
		await screen.preview_done
		var mat: StandardMaterial3D = screen.preview_material()
		print("[library] tarmac preview in %d ms" % (Time.get_ticks_msec() - t0))
		_expect(mat != null and mat.albedo_texture != null and mat.normal_texture != null, "preview material has albedo and normal")
		_expect(mat != null and mat.albedo_texture.get_width() == 512, "preview maps are 512")
		await tree.process_frame
		var info: String = screen._info.get_parsed_text()
		_expect(info.contains("Tarmac") and info.contains("Allegorithmic"), "info shows the graph label and author")
		_expect(info.contains("tiling material"), "info says tarmac needs no mesh")
		_expect(info.contains("Parameters") and info.contains("Outputs"), "info lists parameters and outputs")
		screen._search.text = "asphalt"  # a keyword, not in the file name
		screen._apply_filter()
		_expect(screen._tiles[tarmac["path"]].visible, "search finds tarmac by keyword")
		screen._search.text = "zzzz"
		screen._apply_filter()
		_expect(not screen._tiles[tarmac["path"]].visible, "search hides what doesn't match")
		screen._search.text = ""
		screen._apply_filter()
		for shape in [1, 2, 0]:
			screen._preview_stage.set_shape(shape)
		_expect(is_equal_approx(mat.uv1_scale.x, 2.0), "sphere repeats the texture twice around")

	if not edging.is_empty():
		screen.select(edging)
		await screen.preview_done
		var mat: StandardMaterial3D = screen.preview_material()
		var info: String = screen._info.get_parsed_text()
		print("[library] mesh-driven preview: ", screen._view_status.text)
		_expect(info.contains("Driven by the mesh"), "info says the graph is driven by the mesh")
		_expect(mat != null and mat.albedo_texture != null, "mesh-driven preview rendered (maps baked on the sphere)")
		_expect(mat != null and is_equal_approx(mat.uv1_scale.x, 1.0), "mesh-driven preview uses the sphere's own UVs")

	# Smart materials (.spsm), when the folder has some: one with Painter's preview (its thumbnail),
	# one without (a rendered thumbnail). Both render their stack on the sphere.
	var with_preview := {}
	var without_preview := {}
	for e in screen.entries():
		if e.get("kind") != "spsm":
			continue
		var doc: RefCounted = screen.renderer.spsm_for(e["path"])
		if doc.preview_image() != null:
			with_preview = e if with_preview.is_empty() else with_preview
		elif without_preview.is_empty():
			without_preview = e
	if with_preview.is_empty() and without_preview.is_empty():
		print("[library] no .spsm files in the folder: skipping the smart material checks")
	for e: Dictionary in [with_preview, without_preview]:
		if e.is_empty():
			continue
		_expect(FileAccess.file_exists(e["thumb"]), "%s (smart material) has a thumbnail" % e["name"])
		screen.select(e)
		var t1 := Time.get_ticks_msec()
		await screen.preview_done
		await tree.process_frame
		print("[library] %s preview in %d ms: %s" % [e["name"], Time.get_ticks_msec() - t1, screen._view_status.text])
		var info: String = screen._info.get_parsed_text()
		_expect(info.contains("Painter smart material") and info.contains("Layers") and info.contains("top first"),
				"%s: info shows the layer stack" % e["name"])
		_expect(not screen._use_button.disabled, "%s: Use is enabled for a smart material" % e["name"])
		var mat: StandardMaterial3D = screen.preview_material()
		_expect(mat != null and mat.albedo_texture != null and mat.normal_texture != null and mat.roughness_texture != null,
				"%s: its layer stack renders on the sphere (albedo, normal, roughness)" % e["name"])
		_expect(screen._view_status.text.contains("layer stack"), "%s: the status says the stack was built" % e["name"])
		var graphs: Array = screen.renderer.spsm_for(e["path"]).stats()["graphs"].keys()
		if not graphs.is_empty():
			screen._search.text = String(graphs[0])  # a graph inside, not in the file name
			screen._apply_filter()
			_expect(screen._tiles[e["path"]].visible, "%s: search finds it by a graph inside (%s)" % [e["name"], graphs[0]])
		screen._search.text = ""
		screen._apply_filter()
	if not without_preview.is_empty():
		screen.use_requested.emit(without_preview["path"])
		await tree.process_frame
		_expect(dock._sbsar_edit.text == without_preview["path"], "Use puts a smart material in the dock")
		EditorInterface.set_main_screen_editor(plugin.SCREEN_NAME)
		await tree.process_frame

	# "Use" puts the path in the dock and goes back to 3D.
	if not tarmac.is_empty():
		screen.use_requested.emit(tarmac["path"])
		await tree.process_frame
		_expect(dock._sbsar_edit.text == tarmac["path"], "Use puts the file in the dock")
		_expect(not screen.visible, "and returns to the 3D view")

	Settings.set_library_folders(saved)
	print("[library] %d checks, %d failed" % [_checks, _failures])
	print("[library] RESULT: %s" % ("PASS" if _failures == 0 else "FAIL"))
	EditorInterface.get_base_control().get_tree().quit(0 if _failures == 0 else 1)


func _find(entries: Array, part: String) -> Dictionary:
	for e in entries:
		if String(e["name"]).containsn(part):
			return e
	return {}


func _wait_seconds(seconds: float) -> void:
	await EditorInterface.get_base_control().get_tree().create_timer(seconds).timeout


func _expect(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("[library] ok: ", what)
	else:
		_failures += 1
		print("[library] FAIL: ", what)
