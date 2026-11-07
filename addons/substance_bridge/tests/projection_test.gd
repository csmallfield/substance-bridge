@tool
extends RefCounted
## Projection and tiling test: run the editor with
##   set SUBSTANCE_BRIDGE_PROJECTION=<path to tarmac.sbsar>
## 1. Identity: a planar projection straight down onto a 2x2 plane with tile size 2 must
##    reproduce the source exactly, colour and normal map (this pins the tangent frame).
## 2. Every mode on a box and a sphere: full coverage, plausible values, unit normals.
## 3. End to end in the dock: tarmac on the test rock, triplanar, live update, final files;
##    then tiling on the material without a render. The material it makes is removed.

const GraphSettings := preload("res://addons/substance_bridge/core/graph_settings.gd")
const Projector := preload("res://addons/substance_bridge/material/projector.gd")
const SCENE := "res://test/rock_test.tscn"

var plugin: EditorPlugin
var _failures := 0
var _checks := 0


func run(dock: Node, sbsar: String) -> void:
	var tree := EditorInterface.get_base_control().get_tree()
	print("[projection] start")
	await _identity()
	await _modes()
	await _end_to_end(dock, sbsar, tree)
	print("[projection] %d checks, %d failed" % [_checks, _failures])
	print("[projection] RESULT: %s" % ("PASS" if _failures == 0 else "FAIL"))
	tree.quit(0 if _failures == 0 else 1)


# --- 1. identity ------------------------------------------------------------------------------

func _identity() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane.get_mesh_arrays())
	var color := _gradient(256)
	var normal := _bumps(256)
	var base := {"mode": Projector.Mode.PLANAR, "axis": 1, "tile": 2.0, "offset": Vector3.ZERO, "rotation": Vector3.ZERO}
	var errs := {}
	for sign in [-1.0, 1.0]:
		var s := base.duplicate()
		s["binormal_sign"] = sign
		var out: Dictionary = await Projector.project(mesh, [
			{"id": "c", "image": color, "normal": false},
			{"id": "n", "image": normal, "normal": true}], s)
		_expect(String(out["error"]).is_empty(), "plane projection ran (%s)" % out["error"])
		if not String(out["error"]).is_empty():
			return
		errs[sign] = [_mean_error(out["images"]["c"], color), _mean_error(out["images"]["n"], normal)]
		print("[projection] binormal_sign %+d: colour error %.4f, normal error %.4f" % [sign, errs[sign][0], errs[sign][1]])
	var used: Array = errs[Projector.BINORMAL_SIGN]
	_expect(used[0] < 0.01, "planar identity reproduces the colour map (error %.4f)" % used[0])
	_expect(used[1] < 0.02, "planar identity reproduces the normal map with BINORMAL_SIGN %+d (error %.4f)" % [Projector.BINORMAL_SIGN, used[1]])


# --- 2. every mode -------------------------------------------------------------------------------

func _modes() -> void:
	var color := _gradient(256)
	var normal := _bumps(256)
	var meshes := {"box": BoxMesh.new(), "sphere": SphereMesh.new()}
	for mname: String in meshes:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (meshes[mname] as PrimitiveMesh).get_mesh_arrays())
		for mode in [Projector.Mode.PLANAR, Projector.Mode.TRIPLANAR, Projector.Mode.CYLINDRICAL, Projector.Mode.SPHERICAL]:
			var s := Projector.defaults()
			s["mode"] = mode
			s["tile"] = 0.5
			s["rotation"] = Vector3(10, 20, 0)
			var t0 := Time.get_ticks_msec()
			var out: Dictionary = await Projector.project(mesh, [
				{"id": "c", "image": color, "normal": false},
				{"id": "n", "image": normal, "normal": true}], s)
			var label := "%s %s" % [mname, Projector.Mode.keys()[mode].to_lower()]
			if not String(out["error"]).is_empty():
				_expect(false, "%s: %s" % [label, out["error"]])
				continue
			var c: Image = out["images"]["c"]
			var n: Image = out["images"]["n"]
			var stats := _normal_stats(n)
			var mean := _mean(c)
			print("[projection] %s: %d ms, colour mean %.3f, normal z mean %.3f, worst |len-1| %.3f" % [
					label, Time.get_ticks_msec() - t0, mean, stats[0], stats[1]])
			_expect(mean > 0.2 and mean < 0.8, "%s: colour covers the layout (mean %.3f)" % [label, mean])
			_expect(stats[0] > 0.8 and stats[1] < 0.08, "%s: normals point out and are unit length" % label)


# --- 3. end to end -----------------------------------------------------------------------------

func _end_to_end(dock: Node, sbsar: String, tree: SceneTree) -> void:
	EditorInterface.open_scene_from_path(SCENE)
	await tree.create_timer(1.0).timeout
	var rock: MeshInstance3D = EditorInterface.get_edited_scene_root().get_node("Rock")
	var gs: GraphSettings = await dock.create_material(sbsar, [rock] as Array[MeshInstance3D])
	_expect(gs != null and gs.material != null, "tarmac material created")
	if gs == null or gs.material == null:
		return
	var plain := gs.material.albedo_texture.get_image()

	gs.projection = Projector.Mode.TRIPLANAR
	await _idle(dock, tree)
	_expect(dock._bake_button.visible, "the dock offers Bake from Selected Mesh for a projection")
	await dock.bake_from_mesh(rock)
	await _idle(dock, tree)
	gs.fit_projection_to_mesh()
	_expect(gs.projection_tile_size > 0.0, "Fit to Mesh sets the tile size (%.3f)" % gs.projection_tile_size)
	gs.projection_tile_size *= 0.5
	await _idle(dock, tree)
	var mat := gs.material
	var tex := mat.albedo_texture
	_expect(tex != null and not tex is ImageTexture, "projected maps are imported files (%s)" % (tex.resource_path if tex else "none"))
	var projected := tex.get_image()
	if projected.is_compressed():
		projected.decompress()
	if plain.is_compressed():
		plain.decompress()
	projected.resize(256, 256)
	plain.resize(256, 256)
	_expect(_mean_error(projected, plain) > 0.02, "the projection changed the albedo")
	_expect(mat.uv1_scale == Vector3.ONE, "no tiling on a projected material")
	_expect(mat.normal_texture != null, "normal map present")

	# Live: a parameter change projects the live render too.
	var live_ok := [false]
	var on_live := func(g: GraphSettings, _ms: int, err: String) -> void:
		if g == gs:
			live_ok[0] = err.is_empty() and gs.material.albedo_texture is ImageTexture
			if not err.is_empty():
				print("[projection] live error: ", err)
	dock._live.updated.connect(on_live)
	gs.random_seed = 7
	var deadline := Time.get_ticks_msec() + 20000
	while not live_ok[0] and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	_expect(live_ok[0], "live update is projected")
	dock._live.updated.disconnect(on_live)
	await _idle(dock, tree)

	# Tiling: back to UVs, then scale on the material with no render.
	gs.projection = 0
	await _idle(dock, tree)
	var renders := [0]
	var count := func(_g: GraphSettings) -> void: renders[0] += 1
	dock.rendered.connect(count)
	gs.uv_scale = Vector2(3, 2)
	gs.uv_offset = Vector2(0.25, 0)
	await tree.create_timer(2.5).timeout
	await _idle(dock, tree)
	dock.rendered.disconnect(count)
	_expect(gs.material.uv1_scale == Vector3(3, 2, 1) and gs.material.uv1_offset == Vector3(0.25, 0, 0),
			"tiling is on the material (%s, %s)" % [gs.material.uv1_scale, gs.material.uv1_offset])
	_expect(renders[0] == 0, "tiling needed no render")
	var saved := ResourceLoader.load(gs.material.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
	_expect(saved and saved.uv1_scale == Vector3(3, 2, 1), "tiling is saved with the material")

	# Clean up the test material.
	var folder := gs.resource_path.get_base_dir()
	rock.material_override = null
	await tree.create_timer(0.5).timeout
	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	EditorInterface.get_resource_filesystem().scan()
	print("[projection] removed ", folder)


# --- helpers ------------------------------------------------------------------------------------

func _idle(dock: Node, tree: SceneTree) -> void:
	await tree.process_frame
	var deadline := Time.get_ticks_msec() + 120000
	while dock.is_busy() and Time.get_ticks_msec() < deadline:
		await tree.process_frame


## R = u, G = v, B = a soft checker: any flip or shift shows up as error.
static func _gradient(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			img.set_pixel(x, y, Color(u, v, 0.5 + 0.4 * sin(u * TAU * 2.0) * sin(v * TAU * 3.0)))
	return img


## A tileable bumpy tangent-space normal map (OpenGL), slopes differing in x and y.
static func _bumps(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			var n := Vector3(0.5 * sin(u * TAU * 2.0), 0.35 * cos(v * TAU * 3.0), 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return img


static func _mean_error(a: Image, b: Image) -> float:
	var x := a.duplicate() as Image
	var y := b.duplicate() as Image
	x.convert(Image.FORMAT_RGB8)
	y.convert(Image.FORMAT_RGB8)
	var total := 0.0
	var n := 0
	for py in range(4, x.get_height() - 4, 2):  # skip the outermost texels (edge filtering)
		for px in range(4, x.get_width() - 4, 2):
			var c1 := x.get_pixel(px, py)
			var c2 := y.get_pixel(px, py)
			total += (absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b)) / 3.0
			n += 1
	return total / n


static func _mean(img: Image) -> float:
	var x := img.duplicate() as Image
	x.convert(Image.FORMAT_RGB8)
	var total := 0.0
	var n := 0
	for py in range(0, x.get_height(), 4):
		for px in range(0, x.get_width(), 4):
			var c := x.get_pixel(px, py)
			total += (c.r + c.g + c.b) / 3.0
			n += 1
	return total / n


## [mean tangent-space z, worst |length - 1|] of a normal map.
static func _normal_stats(img: Image) -> Array:
	var z := 0.0
	var worst := 0.0
	var n := 0
	for py in range(0, img.get_height(), 4):
		for px in range(0, img.get_width(), 4):
			var c := img.get_pixel(px, py)
			var v := Vector3(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0, c.b * 2.0 - 1.0)
			z += v.z
			worst = maxf(worst, absf(v.length() - 1.0))
			n += 1
	return [z / n, worst]


func _expect(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("[projection] ok: ", what)
	else:
		_failures += 1
		print("[projection] FAIL: ", what)
