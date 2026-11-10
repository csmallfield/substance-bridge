@tool
extends RefCounted
## LZ4 block decompression (the raw block format, no frame header). Godot's own
## PackedByteArray.decompress has no LZ4 mode; Substance Painter compresses the bitmaps it
## embeds in .spsm files with it.
##
## Copies whole literal runs and matches as slices, so the loop runs once per LZ4 sequence
## rather than once per byte.


## Decompresses src[start:] into exactly raw_size bytes. Returns an empty array if the data is
## malformed or does not decompress to raw_size.
static func decompress_block(src: PackedByteArray, start: int, raw_size: int) -> PackedByteArray:
	var out := PackedByteArray()
	var ip := start
	var end := src.size()
	while ip < end:
		var token := src[ip]
		ip += 1
		var lit := token >> 4
		if lit == 15:
			while ip < end:
				var b := src[ip]
				ip += 1
				lit += b
				if b != 255:
					break
		if lit > 0:
			if ip + lit > end:
				return PackedByteArray()
			out.append_array(src.slice(ip, ip + lit))
			ip += lit
		if ip >= end:
			break  # the last sequence has literals only
		if ip + 2 > end:
			return PackedByteArray()
		var offset := src[ip] | (src[ip + 1] << 8)
		ip += 2
		var mlen := token & 15
		if mlen == 15:
			while ip < end:
				var b := src[ip]
				ip += 1
				mlen += b
				if b != 255:
					break
		mlen += 4
		var from := out.size() - offset
		if offset == 0 or from < 0:
			return PackedByteArray()
		if offset >= mlen:
			out.append_array(out.slice(from, from + mlen))
		else:
			# Overlapping match: a repeating pattern. Each copy can take everything written so
			# far from `from`, so the run doubles per step.
			while mlen > 0:
				var n := mini(mlen, out.size() - from)
				out.append_array(out.slice(from, from + n))
				mlen -= n
		if out.size() > raw_size:
			return PackedByteArray()
	if out.size() != raw_size:
		return PackedByteArray()
	return out
