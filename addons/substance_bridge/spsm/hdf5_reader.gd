@tool
extends RefCounted
## Minimal HDF5 reader for Substance Painter smart materials (.spsm).
##
## An .spsm is an HDF5 file of 1-D byte datasets (preset.bin, resources/<sha1>.sbsar, ...).
## This reads just what those files use: superblock v0/v1, v1 object headers, groups stored as
## symbol tables (v1 B-trees, local heaps, symbol nodes) and contiguous, compact or chunked
## (unfiltered, v1 B-tree indexed) storage; Painter writes 64 KB chunks. Anything else (v2+
## superblocks or headers, compressed chunks) is reported, never guessed at. Only the
## structure and chunk index are read up front; dataset bytes are read on demand.

const SIGNATURE := [0x89, 0x48, 0x44, 0x46, 0x0d, 0x0a, 0x1a, 0x0a]
const UNDEFINED := -1  # an all-ones address read as signed 64-bit

const MSG_DATASPACE := 0x0001
const MSG_LAYOUT := 0x0008
const MSG_FILTERS := 0x000B
const MSG_CONTINUATION := 0x0010
const MSG_SYMBOL_TABLE := 0x0011

var path := ""
var errors := PackedStringArray()
## Dataset path ("resources/abc.sbsar") -> {"size": bytes} plus "offset" (contiguous: absolute
## file offset), "data" (compact: the bytes) or "chunks" (see _layout).
var datasets := {}

var _f: FileAccess
var _so := 8  # size of offsets (addresses)
var _sl := 8  # size of lengths
var _base := 0
var _visited := {}  # object header addresses already walked (guards against cycles)


## Opens the file and reads its group structure. Check errors afterwards.
func open(file_path: String) -> bool:
	path = file_path
	_f = FileAccess.open(file_path, FileAccess.READ)
	if _f == null:
		errors.append("Cannot open %s (%s)" % [file_path, error_string(FileAccess.get_open_error())])
		return false
	var sb := _find_superblock()
	if sb < 0:
		errors.append("%s is not an HDF5 file" % file_path.get_file())
		return false
	var head := _raw(sb, 96)
	var version := head[8]
	if version > 1:
		errors.append("HDF5 superblock version %d is not supported" % version)
		return false
	_so = head[13]
	_sl = head[14]
	if not _so in [2, 4, 8] or not _sl in [2, 4, 8]:
		errors.append("Unexpected HDF5 offset/length sizes %d/%d" % [_so, _sl])
		return false
	var p := 24 if version == 0 else 28
	_base = _uint(head, p, _so)
	p += 4 * _so  # base, free-space, end-of-file and driver addresses
	var root_header := _uint(head, p + _so, _so)
	_walk_object(root_header, "")
	return errors.is_empty()


func close() -> void:
	_f = null


## True when the file has a dataset at this path.
func has(dataset: String) -> bool:
	return datasets.has(dataset)


## Size in bytes of a dataset (0 if missing).
func size_of(dataset: String) -> int:
	return int(datasets.get(dataset, {}).get("size", 0))


## Reads a dataset, or `length` bytes of it from `from` (-1 = to the end). Empty if missing.
func read(dataset: String, from := 0, length := -1) -> PackedByteArray:
	var d: Dictionary = datasets.get(dataset, {})
	if d.is_empty():
		return PackedByteArray()
	var size: int = d["size"]
	from = clampi(from, 0, size)
	var n := size - from if length < 0 else mini(length, size - from)
	if d.has("data"):
		return (d["data"] as PackedByteArray).slice(from, from + n)
	if n <= 0 or _f == null:
		return PackedByteArray()
	if d.has("offset"):
		_f.seek(int(d["offset"]) + from)
		return _f.get_buffer(n)
	var out := PackedByteArray()
	var end := from + n
	for c: Array in d["chunks"]:  # sorted by dataset offset
		var c0: int = c[0]
		var c1: int = c0 + int(c[2])
		if c1 <= from or c0 >= end:
			continue
		var a := maxi(from, c0)
		var b := mini(end, c1)
		_f.seek(int(c[1]) + a - c0)
		out.append_array(_f.get_buffer(b - a))
	return out


# --- structure -----------------------------------------------------------------------------------

func _find_superblock() -> int:
	var len := _f.get_length()
	var at := 0
	while at + 8 <= len:
		_f.seek(at)
		var sig := _f.get_buffer(8)
		if Array(sig) == SIGNATURE:
			return at
		at = 512 if at == 0 else at * 2
	return -1


## Reads an object header and records it as a group (recursing) or a dataset.
func _walk_object(header: int, name: String) -> void:
	if header == UNDEFINED or _visited.has(header):
		return
	_visited[header] = true
	var msgs := _messages(header)
	if msgs.is_empty():
		return
	if msgs.has(MSG_SYMBOL_TABLE):
		var st: PackedByteArray = msgs[MSG_SYMBOL_TABLE]
		_walk_group(_uint(st, 0, _so), _uint(st, _so, _so), name)
	elif msgs.has(MSG_LAYOUT):
		if msgs.has(MSG_FILTERS):
			errors.append("Dataset %s is filtered (compressed); not supported" % name)
			return
		var entry := _layout(msgs[MSG_LAYOUT], msgs.get(MSG_DATASPACE, PackedByteArray()), name)
		if not entry.is_empty():
			datasets[name] = entry


func _walk_group(btree: int, heap: int, prefix: String) -> void:
	var names := _local_heap(heap)
	if names.is_empty() and heap != UNDEFINED:
		return  # error already recorded
	for entry: Array in _btree_entries(btree):
		var name := _cstring(names, entry[0])
		_walk_object(entry[1], name if prefix.is_empty() else prefix + "/" + name)


## [name offset in the local heap, object header address] for every symbol under a group B-tree.
func _btree_entries(addr: int) -> Array:
	var out := []
	if addr == UNDEFINED:
		return out
	var head := _raw(addr, 8 + 2 * _so)
	if head.slice(0, 4).get_string_from_ascii() != "TREE":
		errors.append("Bad HDF5 B-tree node at %d" % addr)
		return out
	var level := head[5]
	var used := head.decode_u16(6)
	var body := _raw(addr + 8 + 2 * _so, used * (_sl + _so) + _sl)
	for i in used:
		var child := _uint(body, i * (_sl + _so) + _sl, _so)
		if level > 0:
			out.append_array(_btree_entries(child))
		else:
			out.append_array(_symbol_node(child))
	return out


func _symbol_node(addr: int) -> Array:
	var out := []
	var head := _raw(addr, 8)
	if head.slice(0, 4).get_string_from_ascii() != "SNOD":
		errors.append("Bad HDF5 symbol node at %d" % addr)
		return out
	var count := head.decode_u16(6)
	var size := 2 * _so + 24
	var body := _raw(addr + 8, count * size)
	for i in count:
		out.append([_uint(body, i * size, _so), _uint(body, i * size + _so, _so)])
	return out


## The data segment of a local heap (holds the link names).
func _local_heap(addr: int) -> PackedByteArray:
	if addr == UNDEFINED:
		return PackedByteArray()
	var head := _raw(addr, 8 + 2 * _sl + _so)
	if head.slice(0, 4).get_string_from_ascii() != "HEAP":
		errors.append("Bad HDF5 local heap at %d" % addr)
		return PackedByteArray()
	var size := _uint(head, 8, _sl)
	var data := _uint(head, 8 + 2 * _sl, _so)
	return _raw(data, size)


## Message type -> message data for a v1 object header, following continuation blocks.
func _messages(addr: int) -> Dictionary:
	var out := {}
	var head := _raw(addr, 16)
	if head.size() < 16:
		errors.append("Truncated HDF5 object header at %d" % addr)
		return out
	if head.slice(0, 4).get_string_from_ascii() == "OHDR" or head[0] != 1:
		errors.append("HDF5 object header version at %d is not supported" % addr)
		return out
	var remaining := head.decode_u16(2)
	var blocks := [[addr + 16, head.decode_u32(8)]]
	while not blocks.is_empty() and remaining > 0:
		var block: Array = blocks.pop_front()
		var data := _raw(block[0], block[1])
		var p := 0
		while p + 8 <= data.size() and remaining > 0:
			var type := data.decode_u16(p)
			var size := data.decode_u16(p + 2)
			var body := data.slice(p + 8, p + 8 + size)
			p += 8 + size
			remaining -= 1
			if type == MSG_CONTINUATION:
				blocks.append([_uint(body, 0, _so), _uint(body, _so, _sl)])
			elif not out.has(type):
				out[type] = body
	return out


## A dataset entry from its data layout message: {"offset", "size"} (contiguous),
## {"data", "size"} (compact) or {"chunks": [[dataset offset, file offset, bytes], ...],
## "size"} (chunked; size comes from the dataspace message).
func _layout(m: PackedByteArray, space: PackedByteArray, name: String) -> Dictionary:
	var version := m[0]
	var cls := -1
	var at := UNDEFINED
	var size := 0
	var dims := 0
	var dims_at := 0
	if version >= 3:
		cls = m[1]
		if cls == 0:  # compact: the bytes are in the header
			var n := m.decode_u16(2)
			return {"data": m.slice(4, 4 + n), "size": n}
		if cls == 1:
			at = _uint(m, 2, _so)
			size = _uint(m, 2 + _so, _sl)
		elif cls == 2:
			dims = m[2]
			at = _uint(m, 3, _so)
			dims_at = 3 + _so
	elif version >= 1:
		dims = m[1]
		cls = m[2]
		if cls == 1 or cls == 2:
			at = _uint(m, 8, _so)
			dims_at = 8 + _so
			if cls == 1:
				size = 1
				for i in dims:
					size *= m.decode_u32(dims_at + i * 4)
	if cls == 1:
		if at == UNDEFINED:
			return {"data": PackedByteArray(), "size": 0}
		return {"offset": _base + at, "size": size}
	if cls == 2:
		# Chunk dimensions; the last is the element size. Byte datasets are 1-D, so a chunk
		# is a run of bytes and the dataset size is the dataspace's single dimension.
		if dims != 2 or m.decode_u32(dims_at + 4) != 1:
			errors.append("Dataset %s is not a 1-D byte array" % name)
			return {}
		size = _dataspace_size(space)
		var chunks := []
		if at != UNDEFINED and size > 0:
			_chunk_btree(at, dims, chunks)
		chunks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var covered := 0
		for c: Array in chunks:
			covered = maxi(covered, mini(size, c[0] + c[2]))
		if not errors.is_empty():
			return {}
		if covered < size:
			errors.append("Dataset %s is missing chunks (%d of %d bytes)" % [name, covered, size])
			return {}
		return {"chunks": chunks, "size": size}
	errors.append("Dataset %s uses a storage layout that is not supported" % name)
	return {}


## Elements in a 1-D dataspace message (versions 1 and 2).
func _dataspace_size(space: PackedByteArray) -> int:
	if space.size() < 8:
		return 0
	var version := space[0]
	var rank := space[1]
	if rank != 1:
		return 0
	var p := 8 if version == 1 else 4
	return _uint(space, p, _sl)


## Collects [dataset offset, file offset, bytes] for every chunk under a v1 chunk B-tree.
## Keys: chunk size (u32), filter mask (u32), then one u64 offset per dimension.
func _chunk_btree(addr: int, dims: int, out: Array) -> void:
	var head := _raw(addr, 8 + 2 * _so)
	if head.slice(0, 4).get_string_from_ascii() != "TREE" or head[4] != 1:
		errors.append("Bad HDF5 chunk B-tree node at %d" % addr)
		return
	var level := head[5]
	var used := head.decode_u16(6)
	var key_size := 8 + 8 * dims
	var body := _raw(addr + 8 + 2 * _so, used * (key_size + _so) + key_size)
	for i in used:
		var k := i * (key_size + _so)
		var child := _uint(body, k + key_size, _so)
		if level > 0:
			_chunk_btree(child, dims, out)
			continue
		if body.decode_u32(k + 4) != 0:
			errors.append("HDF5 chunk at %d is filtered (compressed); not supported" % child)
			return
		out.append([body.decode_s64(k + 8), _base + child, body.decode_u32(k)])


# --- bytes -----------------------------------------------------------------------------------------

func _raw(addr: int, n: int) -> PackedByteArray:
	if n <= 0:
		return PackedByteArray()
	_f.seek(_base + addr)
	return _f.get_buffer(n)


static func _uint(b: PackedByteArray, p: int, n: int) -> int:
	if p + n > b.size():
		return UNDEFINED
	match n:
		2:
			return b.decode_u16(p)
		4:
			var v := b.decode_u32(p)
			return UNDEFINED if v == 0xFFFFFFFF else v
		_:
			return b.decode_s64(p)  # all ones -> -1 == UNDEFINED


static func _cstring(b: PackedByteArray, at: int) -> String:
	var end := at
	while end < b.size() and b[end] != 0:
		end += 1
	return b.slice(at, end).get_string_from_utf8()
