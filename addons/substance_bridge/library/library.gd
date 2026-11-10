@tool
extends RefCounted
## The Substance library: .sbsar files and Painter smart materials (.spsm) in folders outside
## the project, referenced in place.
##
## Each library folder is scanned recursively; a file's subfolder is its category. Thumbnails
## (a sphere render) are cached in <folder>/.thumbnails, named after the file plus a short
## hash of its relative path, size and modification time, so editing an .sbsar regenerates
## only its thumbnail. A folder that cannot be written (e.g. under Program Files) keeps its
## thumbnails in the editor's cache instead.

const THUMB_DIR := ".thumbnails"
const THUMB_SIZE := 256
## File types the library lists.
const EXTENSIONS := ["sbsar", "spsm"]
## Bumped when how smart-material thumbnails are made changes, so they are redone.
const SPSM_THUMB_VERSION := 1


## Every .sbsar and .spsm under the folders, sorted by category then name. Entry keys:
##   path      absolute path to the file
##   kind      "sbsar" or "spsm"
##   root      the library folder it was found in
##   category  subfolder relative to root ("" at the top)
##   name      file name without extension
##   key       hash of relative path, size and modification time
##   thumb     where its thumbnail is (or will be) cached
static func scan(folders: PackedStringArray, cache_dir: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for root in folders:
		root = root.replace("\\", "/").trim_suffix("/")
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			continue
		var thumbs := thumb_dir(root, cache_dir)
		_scan_dir(root, "", root, thumbs, entries)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["category"] != b["category"]:
			return String(a["category"]).naturalnocasecmp_to(b["category"]) < 0
		return String(a["name"]).naturalnocasecmp_to(b["name"]) < 0)
	return entries


static func _scan_dir(root: String, rel: String, dir: String, thumbs: String, entries: Array[Dictionary]) -> void:
	for f in DirAccess.get_files_at(dir):
		var kind := f.get_extension().to_lower()
		if not kind in EXTENSIONS:
			continue
		var path := dir.path_join(f)
		var rel_path := rel.path_join(f) if not rel.is_empty() else f
		var size := 0
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa:
			size = fa.get_length()
			fa.close()
		var stamp := "%s|%d|%d" % [rel_path, size, FileAccess.get_modified_time(path)]
		if kind == "spsm":
			stamp += "|spsm%d" % SPSM_THUMB_VERSION
		var key := stamp.md5_text().substr(0, 10)
		var name := f.get_basename()
		entries.append({
			"path": path, "kind": kind, "root": root, "category": rel, "name": name, "key": key,
			"thumb": thumbs.path_join("%s_%s.png" % [name.validate_filename(), key]),
		})
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue  # .thumbnails, and hidden folders
		_scan_dir(root, rel.path_join(d) if not rel.is_empty() else d, dir.path_join(d), thumbs, entries)


## Thumbnail folder for a library folder: <root>/.thumbnails when it can be written, else a
## folder in the editor cache named after the root.
static func thumb_dir(root: String, cache_dir: String) -> String:
	var dir := root.path_join(THUMB_DIR)
	if _writable(dir):
		return dir
	return cache_dir.path_join("library_thumbnails").path_join(root.md5_text().substr(0, 12))


static func _writable(dir: String) -> bool:
	if not DirAccess.dir_exists_absolute(dir) and DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var probe := dir.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Deletes cached thumbnails that no entry uses any more (renamed, edited or removed files).
## Only touches PNGs in the thumbnail folders of the scanned roots. Returns how many.
static func prune(entries: Array[Dictionary], folders: PackedStringArray, cache_dir: String) -> int:
	var used := {}
	for e in entries:
		used[e["thumb"]] = true
	var removed := 0
	for root in folders:
		root = root.replace("\\", "/").trim_suffix("/")
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			continue
		var dir := thumb_dir(root, cache_dir)
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() == "png" and not used.has(dir.path_join(f)):
				if DirAccess.remove_absolute(dir.path_join(f)) == OK:
					removed += 1
	return removed


## The cached thumbnail as a texture, or null when there is none yet.
static func load_thumb(entry: Dictionary) -> Texture2D:
	var path: String = entry["thumb"]
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## Display name for a category ("" = the library folder's own name).
static func category_label(entry: Dictionary) -> String:
	var root: String = entry["root"]
	return root.get_file() if String(entry["category"]).is_empty() else "%s/%s" % [root.get_file(), entry["category"]]
