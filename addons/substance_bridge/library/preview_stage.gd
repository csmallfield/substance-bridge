@tool
extends Node3D
## A small 3D scene for showing a material: a sphere, cube or plane, a camera, a key light
## and a procedural sky for ambient light and reflections. Used for the library thumbnails
## (transparent background) and its interactive preview (drag to orbit, wheel to zoom).

enum Shape { SPHERE, CUBE, PLANE }

const SHAPE_NAMES := ["Sphere", "Cube", "Plane"]
const DISTANCE := 1.65
## Texture repeats per shape so texels stay square: a SphereMesh's U runs around it (2:1),
## a BoxMesh lays its faces out in a 3x2 atlas.
const UV_SCALE := [Vector3(2, 1, 1), Vector3(3, 2, 1), Vector3(1, 1, 1)]

var model: MeshInstance3D
var camera: Camera3D
var shape := Shape.SPHERE
## Mesh maps were baked on the sphere's own UVs: show the texture once, unrepeated.
var mesh_driven := false

var _pivot: Node3D
var _yaw := 0.0
var _pitch := -0.15
var _distance := DISTANCE
var _material: StandardMaterial3D


func _init(transparent := false) -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	model = MeshInstance3D.new()
	_pivot.add_child(model)
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.02
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.4
	light.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-35), 0)
	add_child(light)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.45, 0.6)
	sky_mat.sky_horizon_color = Color(0.68, 0.7, 0.74)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.sky = sky
	env.background_mode = Environment.BG_CLEAR_COLOR if transparent else Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	set_shape(Shape.SPHERE)
	_update_camera()


func set_shape(s: Shape) -> void:
	shape = s
	match s:
		Shape.SPHERE:
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			m.radial_segments = 128
			m.rings = 64
			model.mesh = m
		Shape.CUBE:
			var m := BoxMesh.new()
			m.size = Vector3(0.75, 0.75, 0.75)
			model.mesh = m
		Shape.PLANE:
			var m := PlaneMesh.new()
			m.size = Vector2(1.1, 1.1)
			m.orientation = PlaneMesh.FACE_Z
			model.mesh = m
	_apply_uv_scale()


func set_material(mat: StandardMaterial3D) -> void:
	_material = mat
	model.material_override = mat
	_apply_uv_scale()


func _apply_uv_scale() -> void:
	if _material:
		_material.uv1_scale = Vector3.ONE if mesh_driven else UV_SCALE[shape]


## Rotates the view by a mouse drag (pixels).
func orbit(relative: Vector2) -> void:
	_yaw -= relative.x * 0.01
	_pitch = clampf(_pitch - relative.y * 0.01, -1.4, 1.4)
	_update_camera()


func zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, 0.7, 5.0)
	_update_camera()


func reset_view() -> void:
	_yaw = 0.0
	_pitch = -0.15
	_distance = DISTANCE
	_update_camera()


func _update_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	camera.position = dir * _distance
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
