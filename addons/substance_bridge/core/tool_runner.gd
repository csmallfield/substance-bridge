@tool
extends RefCounted
## Runs an external command-line tool and captures stdout, stderr and the exit code
## separately.
##
## run() blocks until the tool exits. Call it from a worker thread (see task.gd), never
## from the editor's main thread.
##
## The Substance tools exit 0 on many real failures (docs/validated-commands.md, "Failure
## detection"), so a run also counts as failed when:
## - any stdout/stderr line contains "[ERROR]", or
## - stdout/stderr contains one of the caller's fatal_patterns.
## Callers must still check that the files they expect were written.

const ToolResult := preload("res://addons/substance_bridge/core/tool_result.gd")

const POLL_USEC := 5000
const READ_CHUNK := 65536


static func run(exe: String, args: PackedStringArray,
		fatal_patterns: PackedStringArray = PackedStringArray(),
		timeout_sec: float = 600.0) -> ToolResult:
	var r := ToolResult.new()
	r.exe = exe
	r.args = args
	if exe.is_empty() or not FileAccess.file_exists(exe):
		r.fail("Tool not found: \"%s\"" % exe)
		return r

	var start := Time.get_ticks_msec()
	# Non-blocking pipes: both are drained in one loop, so a chatty stderr can never
	# fill its buffer and stall the tool while we wait on stdout.
	var proc := OS.execute_with_pipe(exe, args, false)
	if proc.is_empty():
		r.fail("Could not start \"%s\"" % exe)
		return r

	var pid: int = proc["pid"]
	var out_pipe: FileAccess = proc["stdio"]
	var err_pipe: FileAccess = proc["stderr"]
	var out_bytes := PackedByteArray()
	var err_bytes := PackedByteArray()
	var timed_out := false

	while OS.is_process_running(pid):
		out_bytes.append_array(_drain(out_pipe))
		err_bytes.append_array(_drain(err_pipe))
		if Time.get_ticks_msec() - start > timeout_sec * 1000.0:
			OS.kill(pid)
			timed_out = true
			break
		OS.delay_usec(POLL_USEC)
	out_bytes.append_array(_drain(out_pipe))
	err_bytes.append_array(_drain(err_pipe))
	out_pipe.close()
	err_pipe.close()

	r.duration_ms = Time.get_ticks_msec() - start
	r.exit_code = OS.get_process_exit_code(pid)
	r.stdout = out_bytes.get_string_from_utf8()
	r.stderr = err_bytes.get_string_from_utf8()

	if timed_out:
		r.fail("Timed out after %.0f s and was killed" % timeout_sec)
	elif r.exit_code != 0:
		r.fail("%s exited with code %d" % [exe.get_file(), r.exit_code])
	_scan_output(r, fatal_patterns)
	return r


static func _drain(pipe: FileAccess) -> PackedByteArray:
	var all := PackedByteArray()
	while true:
		var chunk := pipe.get_buffer(READ_CHUNK)
		if chunk.is_empty():
			break
		all.append_array(chunk)
	return all


static func _scan_output(r: ToolResult, fatal_patterns: PackedStringArray) -> void:
	for line in (r.stdout + "\n" + r.stderr).split("\n", false):
		var l := line.strip_edges()
		if l.is_empty():
			continue
		var fatal := l.contains("[ERROR]")
		for pattern in fatal_patterns:
			if l.contains(pattern):
				fatal = true
				break
		if fatal:
			r.errors.append(l)
		elif l.contains("[WARNING]"):
			r.warnings.append(l)
