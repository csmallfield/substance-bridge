@tool
extends RefCounted
## Reads Qt QDataStream data (big-endian), as Substance Painter writes it inside .spsm files:
## the embedded .image headers, resources.toc and the .alg_meta blocks.
##
## Only the QVariant types those files use are known; anything else stops the read with an
## error (QDataStream has no lengths to skip unknown values).

const T_BOOL := 1
const T_INT := 2
const T_UINT := 3
const T_LONGLONG := 4
const T_ULONGLONG := 5
const T_DOUBLE := 6
const T_MAP := 8
const T_LIST := 9
const T_STRING := 10
const T_STRINGLIST := 11
const T_BYTEARRAY := 12

var data: PackedByteArray
var pos := 0
var error := ""


func _init(bytes: PackedByteArray = PackedByteArray(), at := 0) -> void:
	data = bytes
	pos = at


func ok() -> bool:
	return error.is_empty()


func at_end() -> bool:
	return pos >= data.size()


func u8() -> int:
	if not _need(1):
		return 0
	pos += 1
	return data[pos - 1]


func u32() -> int:
	if not _need(4):
		return 0
	var v := (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3]
	pos += 4
	return v


func i32() -> int:
	var v := u32()
	return v - 0x100000000 if v >= 0x80000000 else v


func i64() -> int:
	var hi := u32()
	var lo := u32()
	return (hi << 32) | lo


func f64() -> float:
	if not _need(8):
		return 0.0
	var b := data.slice(pos, pos + 8)
	b.reverse()
	pos += 8
	return b.decode_double(0)


## A QString: byte length (0xFFFFFFFF = null) then UTF-16BE.
func qstring() -> String:
	var n := u32()
	if n == 0xFFFFFFFF or n == 0 or not _need(n):
		return ""
	var b := data.slice(pos, pos + n)
	pos += n
	for i in range(0, n - 1, 2):  # to little-endian for get_string_from_utf16
		var t := b[i]
		b[i] = b[i + 1]
		b[i + 1] = t
	return b.get_string_from_utf16()


## A QByteArray: byte length (0xFFFFFFFF = null) then the bytes.
func qbytes() -> PackedByteArray:
	var n := u32()
	if n == 0xFFFFFFFF or n == 0 or not _need(n):
		return PackedByteArray()
	pos += n
	return data.slice(pos - n, pos)


## A QVariant: type id, null flag, value.
func qvariant() -> Variant:
	var type := u32()
	u8()  # null flag
	return value(type)


func value(type: int) -> Variant:
	match type:
		T_BOOL:
			return u8() != 0
		T_INT:
			return i32()
		T_UINT:
			return u32()
		T_LONGLONG, T_ULONGLONG:
			return i64()
		T_DOUBLE:
			return f64()
		T_STRING:
			return qstring()
		T_BYTEARRAY:
			return qbytes()
		T_MAP:
			return qmap()
		T_LIST:
			var out := []
			for i in u32():
				if not ok():
					break
				out.append(qvariant())
			return out
		T_STRINGLIST:
			var out := PackedStringArray()
			for i in u32():
				if not ok():
					break
				out.append(qstring())
			return out
	if ok():
		error = "Unknown QVariant type %d at byte %d" % [type, pos]
	return null


## A QVariantMap: count, then (QString key, QVariant value) pairs.
func qmap() -> Dictionary:
	var out := {}
	for i in u32():
		if not ok():
			break
		var k := qstring()
		out[k] = qvariant()
	return out


func _need(n: int) -> bool:
	if not ok():
		return false
	if pos + n > data.size():
		error = "Unexpected end of data at byte %d" % pos
		return false
	return true
