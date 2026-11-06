@tool
extends RefCounted
## Outcome of one external tool run: command, exit code, captured output and the
## errors/warnings the runner found in it.

var exe := ""
var args := PackedStringArray()
var exit_code := -1
var stdout := ""
var stderr := ""
var duration_ms := 0
## Anything that makes the run a failure. Empty means success.
var errors := PackedStringArray()
## "[WARNING]" lines that did not match a fatal pattern.
var warnings := PackedStringArray()


func is_ok() -> bool:
	return errors.is_empty()


func fail(message: String) -> void:
	errors.append(message)


## The command as it would be typed in a terminal (for logs and bug reports).
func command_line() -> String:
	var parts := PackedStringArray([_quote(exe)])
	for a in args:
		parts.append(_quote(a))
	return " ".join(parts)


func summary() -> String:
	return "%s: exit %d in %.2f s%s" % [
		exe.get_file(), exit_code, duration_ms / 1000.0, "" if is_ok() else " (FAILED)"]


static func _quote(s: String) -> String:
	return "\"%s\"" % s if s.contains(" ") else s
