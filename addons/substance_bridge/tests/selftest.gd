@tool
extends RefCounted
## Editor self-test: runs the dock's full pipeline (render -> import -> material) on an
## .sbsar, checks the material, writes res://test/rock_test.tscn with the rock wearing it,
## then quits the editor with exit code 0 (pass) or 1 (fail).
##
## Run with the editor headless:
##   set SUBSTANCE_BRIDGE_SELFTEST=<path to .sbsar>
##   godot --headless --editor --path <project>

const ROCK_FBX := "res://assets/rock01.fbx"
const TEST_DIR := "res://test"

var _fails := 0


func run(dock: Node, sbsar: String) -> void:
	print("[selftest] start: ", sbsar)
	# Let the editor finish its first scan/import of the project.
	var fs := EditorInterface.get_resource_filesystem()
	var tree := Engine.get_main_loop() as SceneTree
	while fs.is_scanning():
		await tree.process_frame

	var job: Dictionary = await dock.render_and_build(sbsar, Vector2i(10, 10), 42)
	_expect(job.has("material"), "pipeline produced a material (%s)" % job.get("error", "ok"))
	if not job.has("material"):
		_quit()
		return

	var mat: StandardMaterial3D = job["material"]
	var result = job["result"]
	_expect(mat.resource_path.ends_with(".tres") and FileAccess.file_exists(mat.resource_path), "material saved: " + mat.resource_path)
	_expect(mat.albedo_texture != null, "albedo wired")
	_expect(mat.normal_enabled and mat.normal_texture != null, "normal wired")
	_expect(mat.roughness_texture != null and mat.metallic_texture != null, "roughness + metallic wired")

	if mat.normal_texture:
		var cfg := ConfigFile.new()
		cfg.load(mat.normal_texture.resource_path + ".import")
		var flipped: bool = cfg.get_value("params", "process/normal_map_invert_y", false)
		var nm: int = cfg.get_value("params", "compress/normal_map", 0)
		_expect(nm == 1, "normal imported as normal map")
		_expect(flipped == (result.normal_convention == "directx"),
				"normal convention %s, green flip on import = %s" % [result.normal_convention, flipped])
		var img := mat.normal_texture.get_image()
		_expect(img != null and img.get_width() == 1024, "normal texture is 1024 px")

	_make_test_scene(mat)

	# Second run over the same name must update in place (reimport path).
	var again: Dictionary = await dock.render_and_build(sbsar, Vector2i(10, 10), 42)
	_expect(again.has("material") and again["material"].resource_path == mat.resource_path, "re-render updates the same material")
	_quit()


func _make_test_scene(mat: Material) -> void:
	var ps := load(ROCK_FBX) as PackedScene
	if ps == null:
		_expect(false, "rock FBX imported")
		return
	var inst := ps.instantiate()
	var src := _find_mesh(inst)
	if src == null:
		_expect(false, "rock FBX contains a MeshInstance3D")
		inst.free()
		return
	var xform := Transform3D.IDENTITY
	var n: Node = src
	while n != null and n is Node3D:
		xform = (n as Node3D).transform * xform
		n = n.get_parent()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var mesh_path := TEST_DIR.path_join("rock01_mesh.res")
	ResourceSaver.save(src.mesh.duplicate(), mesh_path)
	var mesh := load(mesh_path) as Mesh
	inst.free()

	var root := Node3D.new()
	root.name = "RockTest"

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-40), deg_to_rad(35), 0)), Vector3.ZERO)
	root.add_child(sun)

	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	rock.mesh = mesh
	rock.transform = xform
	rock.material_override = mat
	root.add_child(rock)

	var aabb := xform * mesh.get_aabb()
	var center := aabb.get_center()
	var radius := aabb.size.length() * 0.5
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	var eye := center + Vector3(0.35, 0.45, 1.0).normalized() * radius * 2.4
	cam.transform = Transform3D(Basis.looking_at(center - eye, Vector3.UP), eye)
	cam.far = radius * 20.0
	root.add_child(cam)

	for c in root.get_children():
		c.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	var scene_path := TEST_DIR.path_join("rock_test.tscn")
	var err := ResourceSaver.save(packed, scene_path)
	root.free()
	_expect(err == OK, "test scene saved: %s (rock size %.2f)" % [scene_path, aabb.size.length()])


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null


func _expect(cond: bool, what: String) -> void:
	print(("[selftest]   ok   " if cond else "[selftest]   FAIL ") + what)
	if not cond:
		_fails += 1


func _quit() -> void:
	print("[selftest] SELFTEST %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	(Engine.get_main_loop() as SceneTree).quit(0 if _fails == 0 else 1)
