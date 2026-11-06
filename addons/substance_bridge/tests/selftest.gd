@tool
extends RefCounted
## Editor self-test of the full workflow, driven through the dock:
## create -> generated inspector properties -> auto preview on change -> skip unchanged ->
## preset -> final render -> reload from disk. Uses res://test/rock_test.tscn (its "Rock"
## node; the scene is not saved), then quits with exit code 0 or 1.
##
## Run with the editor headless:
##   set SUBSTANCE_BRIDGE_SELFTEST=<path to tarmac.sbsar>
##   godot --headless --editor --path <project> --log-file <temp>/selftest.log
##
## Pass --log-file: test runs share the project's log folder, and Godot keeps only five logs,
## so without it a test run pushes out the log of an editor you have open.
## Headless has no progress dialogs; run once without --headless to catch editor-UI errors.

const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")
const Pipeline := preload("res://addons/substance_bridge/core/pipeline.gd")

const SCENE := "res://test/rock_test.tscn"
const WAIT_MS := 120000

var _fails := 0
var _tree: SceneTree


func run(dock: Node, sbsar: String) -> void:
	_tree = Engine.get_main_loop() as SceneTree
	print("[selftest] start: ", sbsar)
	var fs := EditorInterface.get_resource_filesystem()
	while fs.is_scanning():
		await _tree.process_frame

	EditorInterface.open_scene_from_path(SCENE)
	await _tree.process_frame
	var root := EditorInterface.get_edited_scene_root()
	var rock: MeshInstance3D = root.get_node_or_null("Rock") if root else null
	_expect(rock != null, "test scene open with a Rock node")
	if rock == null:
		_quit()
		return

	# --- create
	var gs: GraphSettings = await dock.create_material(sbsar, [rock] as Array[MeshInstance3D])
	_expect(gs != null and gs.material != null, "created settings + material")
	if gs == null or gs.material == null:
		_quit()
		return
	_expect(rock.material_override == gs.material, "material applied to Rock")
	_expect(Pipeline.settings_for_material(gs.material) == gs, "material links back to its settings")
	_expect(gs.material.albedo_texture.get_width() == 512, "preview is 512 px")
	if not gs.is_described():
		await gs.description_loaded

	# --- generated properties
	var props := {}
	var groups := PackedStringArray()
	for p in gs.get_property_list():
		props[p["name"]] = p
		if p["usage"] & PROPERTY_USAGE_GROUP:
			groups.append(p["name"])
	var dmg: Dictionary = props.get("tarmac_damage", {})
	_expect(dmg.get("type") == TYPE_FLOAT and dmg.get("hint") == PROPERTY_HINT_RANGE and String(dmg.get("hint_string")).begins_with("0,1,0.01"),
			"tarmac_damage is a 0-1 slider (%s)" % dmg.get("hint_string"))
	_expect(props.get("asphalt_color", {}).get("type") == TYPE_COLOR, "asphalt_color is a colour")
	_expect(props.get("painted_arrows", {}).get("type") == TYPE_BOOL, "painted_arrows is a toggle")
	_expect(props.get("normal_format", {}).get("hint_string") == "DirectX:0,OpenGL:1", "normal_format is a dropdown")
	_expect("Technical parameters" in groups and "Channels" in groups, "groups: %s" % ", ".join(groups))
	_expect(props.has("preset"), "preset dropdown")
	_expect(is_equal_approx(gs.get("tarmac_damage"), 0.6), "default value read from the graph")
	_expect(props.has("signs_color"), "signs_color visible while painted_arrows is on")

	# --- visibleif
	gs.set("painted_arrows", false)
	var names := gs.get_property_list().map(func(p: Dictionary) -> String: return p["name"])
	_expect(not "signs_color" in names and not "tile_arrows" in names, "visibleif hides arrow parameters when painted_arrows is off")
	gs.set("painted_arrows", true)

	# --- auto preview on change
	await _wait_idle(dock)
	var before := _albedo_hash(gs)
	var key_before := gs.last_render_key
	gs.set("tarmac_damage", 0.05)
	gs.set("asphalt_color", Color(0.45, 0.1, 0.08))
	await _tree.process_frame
	_expect(dock.is_busy(), "change schedules a preview")
	await _wait_idle(dock)
	_expect(gs.last_render_key != key_before and _albedo_hash(gs) != before, "preview re-rendered with new values")
	_expect(gs.property_can_revert("tarmac_damage") and is_equal_approx(gs.property_get_revert("tarmac_damage"), 0.6), "revert to default available")

	# --- unchanged inputs are skipped
	var again: Dictionary = await Pipeline.new().render(gs, gs.preview_size)
	_expect(again.get("skipped", false), "unchanged settings skip the render")

	# --- preset
	gs.set("preset", 1)  # "Pristine": tarmac_damage 0
	_expect(is_equal_approx(gs.get("tarmac_damage"), 0.0), "preset applied (tarmac_damage %.2f)" % gs.get("tarmac_damage"))
	gs.set("asphalt_color", Color(0.45, 0.1, 0.08))
	await _wait_idle(dock)

	# --- final
	gs.final_size = 10  # keep the test quick: 1K
	dock._queue(dock.Job.FINAL)
	await _tree.process_frame
	await _wait_idle(dock)
	_expect(gs.material.albedo_texture.get_width() == 1024, "final render at 1K (%d px)" % gs.material.albedo_texture.get_width())

	# --- reload from disk keeps the values
	var reloaded := ResourceLoader.load(gs.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GraphSettings
	_expect(reloaded != null and reloaded.values.has("asphalt_color") and reloaded.source == gs.source,
			"saved settings reload with their values (%s)" % (str(reloaded.values.keys()) if reloaded else "null"))

	var text := FileAccess.get_file_as_string(gs.resource_path)
	_expect(not text.contains("last_render_key") and not text.contains("type=\"Material\""),
			"saved settings hold no cache state or generated-file references")

	var source_prop := gs.get_property_list().filter(func(p: Dictionary) -> bool: return p["name"] == "source")
	_expect(not source_prop.is_empty() and source_prop[0]["usage"] & PROPERTY_USAGE_READ_ONLY, "source is read-only in the inspector")

	# --- seed variants, one per selected mesh
	var rock2 := rock.duplicate() as MeshInstance3D
	rock2.name = "Rock2"
	rock.get_parent().add_child(rock2)
	rock2.owner = rock.owner
	await _wait_idle(dock)
	var variants: Array = await dock.make_variants(2, [rock, rock2] as Array[MeshInstance3D])
	_expect(variants.size() == 2, "made 2 variants: %s" % ", ".join(variants.map(func(v): return v.output_name)))
	if variants.size() == 2:
		var v0: GraphSettings = variants[0]
		var v1: GraphSettings = variants[1]
		_expect(v0.random_seed != v1.random_seed and v0.values == gs.values, "variants keep the values, change the seed (%d, %d)" % [v0.random_seed, v1.random_seed])
		_expect(_albedo_hash(v0) != _albedo_hash(v1), "variants render differently")
		_expect(rock.material_override == v0.material and rock2.material_override == v1.material, "each selected mesh got its own variant")

		# --- batch render at a fixed size
		var batch: Dictionary = await dock.render_all(PackedStringArray([v0.resource_path, v1.resource_path]), 10)
		_expect(batch["done"] == 2 and batch["failed"].is_empty(), "batch rendered %d, failed %s" % [batch["done"], str(batch["failed"])])
		_expect(v0.material.albedo_texture.get_width() == 1024 and v1.material.albedo_texture.get_width() == 1024, "batch at 1K")
		_cleanup(v0)
		_cleanup(v1)
	rock2.free()

	# The scene is not saved: the committed test scene must not reference generated files.
	# Remove this run's generated folder so test output never lands in git.
	rock.material_override = null
	_cleanup(gs)

	var mesh_sbsar := OS.get_environment("SUBSTANCE_BRIDGE_SELFTEST_MESH")
	if not mesh_sbsar.is_empty():
		await _mesh_adaptive(dock, rock, mesh_sbsar)
	fs.scan()
	_quit()


## Mesh-adaptive graph (image inputs with mesh-map usages, e.g. PL_ISF_Gen_Edging01).
func _mesh_adaptive(dock: Node, rock: MeshInstance3D, sbsar: String) -> void:
	print("[selftest] mesh-adaptive: ", sbsar)
	await _wait_idle(dock)
	var gs: GraphSettings = await dock.create_material(sbsar, [rock] as Array[MeshInstance3D])
	_expect(gs != null and gs.material != null and gs.material.albedo_texture != null, "mesh-adaptive material created")
	if gs == null or gs.material == null:
		return
	_expect(gs.mesh_usages() == PackedStringArray(["ambientOcclusion", "curvature"]), "graph takes %s" % ", ".join(gs.mesh_usages()))
	_expect(gs.mesh_obj.begins_with("user://substance_bridge/meshes/") and FileAccess.file_exists(ProjectSettings.globalize_path(gs.mesh_obj)),
			"mesh exported for baking: %s" % gs.baked_mesh)
	var bakes := ProjectSettings.globalize_path("user://substance_bridge/bakes")
	var key := gs.mesh_obj.get_file().get_basename()
	_expect(FileAccess.file_exists(bakes.path_join("%s_11" % key).path_join("ambientOcclusion.png"))
			and FileAccess.file_exists(bakes.path_join("%s_11" % key).path_join("curvature.png")), "AO + curvature baked at 2K")
	_expect(rock.material_override == gs.material, "mesh-adaptive material applied to Rock")

	if OS.get_environment("SUBSTANCE_BRIDGE_KEEP") == "1":
		var packed := PackedScene.new()
		packed.pack(EditorInterface.get_edited_scene_root())
		ResourceSaver.save(packed, "res://test/_demo_mesh_adaptive.tscn")
		print("[selftest] kept output; demo scene res://test/_demo_mesh_adaptive.tscn")

	gs.bake_size = 10
	await _wait_idle(dock)
	_expect(FileAccess.file_exists(bakes.path_join("%s_10" % key).path_join("curvature.png")), "changing the bake size re-bakes at 1K")

	# --- batch with forced re-bake
	var ao_file := bakes.path_join("%s_10" % key).path_join("ambientOcclusion.png")
	var ao_time := FileAccess.get_modified_time(ao_file)
	await _wait_seconds(1.1)  # file times have 1 s resolution
	var batch: Dictionary = await dock.render_all(PackedStringArray([gs.resource_path]), dock.SIZE_PREVIEW, true)
	_expect(batch["done"] == 1 and FileAccess.get_modified_time(ao_file) > ao_time, "batch with re-bake re-bakes the mesh maps")

	gs.auto_preview = false
	gs.mesh_obj = ""
	var r: Dictionary = await Pipeline.new().render(gs, gs.preview_size)
	_expect(String(r.get("error", "")).contains("Bake from Selected Mesh"), "missing mesh is explained: %s" % r.get("error", "no error"))
	if OS.get_environment("SUBSTANCE_BRIDGE_KEEP") != "1":
		rock.material_override = null
		_cleanup(gs)


func _cleanup(gs: GraphSettings) -> void:
	var folder := gs.resource_path.get_base_dir()
	_remove_dir(ProjectSettings.globalize_path(folder))
	print("[selftest] removed ", folder)


static func _remove_dir(abs_path: String) -> void:
	for d in DirAccess.get_directories_at(abs_path):
		_remove_dir(abs_path.path_join(d))
	for f in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(f))
	DirAccess.remove_absolute(abs_path)


func _wait_seconds(seconds: float) -> void:
	await _tree.create_timer(seconds).timeout


func _wait_idle(dock: Node) -> void:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	await _tree.process_frame
	while dock.is_busy() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame


## Hash of the albedo PNG on disk (the headless dummy renderer cannot read textures back).
func _albedo_hash(gs: GraphSettings) -> String:
	return FileAccess.get_md5(ProjectSettings.globalize_path(gs.material.albedo_texture.resource_path))


func _expect(cond: bool, what: String) -> void:
	print(("[selftest]   ok   " if cond else "[selftest]   FAIL ") + what)
	if not cond:
		_fails += 1


func _quit() -> void:
	print("[selftest] SELFTEST %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	_tree.quit(0 if _fails == 0 else 1)
