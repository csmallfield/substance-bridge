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
	# _finish runs inside the deferred-call flush. Resume the awaiting code on the next normal
	# frame instead: editor progress dialogs (shown by reimport_files) refuse to run during the
	# flush and spam "Do not use progress dialog ... while flushing the message queue".
	await (Engine.get_main_loop() as SceneTree).process_frame
	finished.emit(result)
