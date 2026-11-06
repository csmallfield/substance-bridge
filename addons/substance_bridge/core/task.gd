@tool
extends RefCounted
## Runs a Callable on a worker thread and emits `finished` on the main thread with its
## return value. Keep a reference to the task until `finished` fires.
##
## The work must not touch the scene tree, EditorInterface or EditorSettings; pass it a
## settings snapshot instead (settings.gd).

signal finished(result: Variant)

var _thread := Thread.new()


func start(work: Callable) -> Error:
	return _thread.start(_run.bind(work))


func is_running() -> bool:
	return _thread.is_started()


func _run(work: Callable) -> void:
	var result: Variant = work.call()
	_finish.call_deferred(result)


func _finish(result: Variant) -> void:
	_thread.wait_to_finish()
	finished.emit(result)
