@tool
extends RefCounted
## Decodes preset.bin, the layer stack inside a Substance Painter smart material (.spsm).
##
## preset.bin is a 12-byte header followed by one tagged value. Each value is a type byte and
## its data (little-endian). Objects and lists carry the absolute offset where they end, which
## is checked after every one, so a misread type is caught at once instead of producing
## garbage. Objects become Dictionaries with their class name under "@".
##
## Type bytes (all seen in real files):
##   01 float  02/03/04 vec2/3/4 float  05 int32  06/07/08 int2/3/4  09/0C/0F/15 int64  0A bool
##   0B uint32  0D 3x3 float matrix  0E 4x4 float matrix  10 string  11/13 list
##   12/14 object (flag FF = null)
## 15 appears in newer files (data version 68: 64-bit channel masks such as channelType).

const HEADER_SIZE := 12

var data: PackedByteArray
var pos := 0
var error := ""


## Decodes the whole preset. Returns {"root": Dictionary, "header": PackedByteArray,
## "error": String ("" if none)}.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var d := new()
	d.data = bytes
	d.pos = HEADER_SIZE
	var root: Variant = null
	if bytes.size() <= HEADER_SIZE:
		d.error = "preset.bin is empty"
	else:
		root = d._value(d._u8())
		if d.error.is_empty() and not root is Dictionary:
			d.error = "preset.bin does not start with an object"
		if d.error.is_empty() and d.pos != bytes.size():
			d.error = "preset.bin has %d bytes left over" % (bytes.size() - d.pos)
	return {"root": root if root is Dictionary else {}, "header": bytes.slice(0, HEADER_SIZE), "error": d.error}


func _value(type: int) -> Variant:
	if not error.is_empty():
		return null
	match type:
		0x01:
			return _f32()
		0x02:
			return Vector2(_f32(), _f32())
		0x03:
			return Vector3(_f32(), _f32(), _f32())
		0x04:
			return Vector4(_f32(), _f32(), _f32(), _f32())
		0x05:
			return _i32()
		0x06:
			return Vector2i(_i32(), _i32())
		0x07:
			return Vector3i(_i32(), _i32(), _i32())
		0x08:
			return Vector4i(_i32(), _i32(), _i32(), _i32())
		0x09, 0x0C, 0x0F, 0x15:
			return _i64()
		0x0A:
			return _u8() != 0
		0x0B:
			return _u32()
		0x0D, 0x0E:
			var m := PackedFloat32Array()
			for i in (9 if type == 0x0D else 16):
				m.append(_f32())
			return m
		0x10:
			return _string()
		0x11, 0x13:
			return _list()
		0x12, 0x14:
			return _object()
	_fail("unknown value type 0x%02x" % type, pos - 1)
	return null


func _list() -> Array:
	var end := _u32()
	var out := []
	for i in _u32():
		if not error.is_empty():
			return out
		out.append(_value(_u8()))
	if error.is_empty() and pos != end:
		_fail("list ends at %d, expected %d" % [pos, end], pos)
	return out


func _object() -> Variant:
	if _u8() == 0xFF:
		return null
	var end := _u32()
	var o := {"@": _string()}
	var fields := _u16()
	for i in fields:
		if not error.is_empty():
			return o
		var key := _string()
		o[key] = _value(_u8())
	if error.is_empty() and pos != end:
		_fail("%s ends at %d, expected %d" % [o["@"], pos, end], pos)
	return o


func _need(n: int) -> bool:
	if not error.is_empty():
		return false
	if pos + n > data.size():
		_fail("unexpected end of data", pos)
		return false
	return true


func _fail(what: String, at: int) -> void:
	if error.is_empty():
		error = "preset.bin: %s (byte %d)" % [what, at]


func _u8() -> int:
	if not _need(1):
		return 0
	pos += 1
	return data[pos - 1]


func _u16() -> int:
	if not _need(2):
		return 0
	pos += 2
	return data.decode_u16(pos - 2)


func _u32() -> int:
	if not _need(4):
		return 0
	pos += 4
	return data.decode_u32(pos - 4)


func _i32() -> int:
	if not _need(4):
		return 0
	pos += 4
	return data.decode_s32(pos - 4)


func _i64() -> int:
	if not _need(8):
		return 0
	pos += 8
	return data.decode_s64(pos - 8)


func _f32() -> float:
	if not _need(4):
		return 0.0
	pos += 4
	return data.decode_float(pos - 4)


func _string() -> String:
	var n := _u32()
	if n == 0 or not _need(n):
		return ""
	pos += n
	return data.slice(pos - n, pos).get_string_from_utf8()
