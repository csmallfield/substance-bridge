@tool
extends RefCounted
## Writes a Godot Mesh as a Wavefront OBJ for the Substance baker (which cannot read glTF,
## and Godot cannot export FBX). Positions, normals and UV0 of every triangle surface, in
## the mesh's local space.
##
## Two conventions differ between Godot and OBJ, and both are converted:
## - UV V runs top-down in Godot and bottom-up in OBJ: v_obj = 1 - v.
## - Godot's front faces are clockwise, OBJ's counter-clockwise: triangles are reversed.
##
## Usage: collect_arrays() on the main thread, then write() anywhere (it is thread-safe).


## Copies the surface arrays out of a mesh. Main thread.
static func collect_arrays(mesh: Mesh) -> Array:
	var surfaces := []
	for i in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(i)
		if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		surfaces.append({
			"name": mesh.surface_get_name(i),
			"vertices": arrays[Mesh.ARRAY_VERTEX],
			"normals": arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array(),
			"uvs": arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array(),
			"indices": arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(),
		})
	return surfaces


## Writes surfaces from collect_arrays() to an OBJ. Returns an error message or "".
static func write(surfaces: Array, path: String) -> String:
	if surfaces.is_empty():
		return "The mesh has no triangle surfaces"
	var lines := PackedStringArray(["# Substance Bridge mesh export (Godot -> OBJ)"])
	var faces := PackedStringArray()
	var offset := 1
	var any_uv := false
	for s: Dictionary in surfaces:
		var verts: PackedVector3Array = s["vertices"]
		var normals: PackedVector3Array = s["normals"]
		var uvs: PackedVector2Array = s["uvs"]
		var idx: PackedInt32Array = s["indices"]
		var has_n := normals.size() == verts.size()
		var has_uv := uvs.size() == verts.size()
		any_uv = any_uv or has_uv
		for v in verts:
			lines.append("v %.6f %.6f %.6f" % [v.x, v.y, v.z])
		if has_uv:
			for uv in uvs:
				lines.append("vt %.6f %.6f" % [uv.x, 1.0 - uv.y])
		if has_n:
			for n in normals:
				lines.append("vn %.6f %.6f %.6f" % [n.x, n.y, n.z])
		faces.append("g %s" % (String(s["name"]) if not String(s["name"]).is_empty() else "surface"))
		var count := idx.size() if not idx.is_empty() else verts.size()
		for t in range(0, count - 2, 3):
			var a := (idx[t] if not idx.is_empty() else t) + offset
			var b := (idx[t + 1] if not idx.is_empty() else t + 1) + offset
			var c := (idx[t + 2] if not idx.is_empty() else t + 2) + offset
			# Reverse winding: Godot clockwise -> OBJ counter-clockwise.
			faces.append("f %s %s %s" % [_corner(a, has_uv, has_n), _corner(c, has_uv, has_n), _corner(b, has_uv, has_n)])
		offset += verts.size()
	if not any_uv:
		return "The mesh has no UVs (UV0); mesh maps need clean, non-overlapping UVs"
	lines.append_array(faces)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())]
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return ""


static func _corner(i: int, has_uv: bool, has_n: bool) -> String:
	if has_uv and has_n:
		return "%d/%d/%d" % [i, i, i]
	if has_uv:
		return "%d/%d" % [i, i]
	if has_n:
		return "%d//%d" % [i, i]
	return str(i)
