@tool
extends RefCounted
## Editor settings for Substance Bridge.
##
## Tool paths live in Editor Settings (they are per machine); the output folder is a
## project setting (it is per project). Worker threads must not touch EditorSettings,
## so read everything once on the main thread with snapshot() and pass the dictionary on.

const SBSRENDER := "substance_bridge/tools/sbsrender_path"
const SBSBAKER := "substance_bridge/tools/sbsbaker_path"
const SEVEN_ZIP := "substance_bridge/tools/7zip_path"
const ENGINE := "substance_bridge/render/engine"
const OUTPUT_FOLDER := "substance_bridge/output_folder"
## Folders of .sbsar files outside the project, shown in the Substance Library tab. Per user
## (Editor Settings), so every project sees the same library.
const LIBRARY_PATHS := "substance_bridge/library/folders"

const DEFAULT_OUTPUT_FOLDER := "res://substance_bridge"

## Defaults match the validated install (docs/validated-commands.md).
const TOOL_DEFAULTS := {
	SBSRENDER: "C:/Program Files/Allegorithmic/Substance Designer/sbsrender.exe",
	SBSBAKER: "C:/Program Files/Allegorithmic/Substance Automation Toolkit/sbsbaker.exe",
	SEVEN_ZIP: "C:/Program Files/7-Zip/7z.exe",
}

## Human-readable names for the snapshot keys, used in messages.
const TOOL_LABELS := {
	"sbsrender": "sbsrender",
	"sbsbaker": "sbsbaker",
	"seven_zip": "7-Zip",
}


static func register() -> void:
	var es := EditorInterface.get_editor_settings()
	for key: String in TOOL_DEFAULTS:
		_add_editor_setting(es, key, TOOL_DEFAULTS[key], PROPERTY_HINT_GLOBAL_FILE, "*.exe")
	_add_editor_setting(es, ENGINE, "d3d11pc", PROPERTY_HINT_ENUM_SUGGESTION, "d3d11pc,sse2")
	if not es.has_setting(LIBRARY_PATHS):
		es.set_setting(LIBRARY_PATHS, PackedStringArray())
	es.set_initial_value(LIBRARY_PATHS, PackedStringArray(), false)
	es.add_property_info({
		"name": LIBRARY_PATHS,
		"type": TYPE_PACKED_STRING_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_GLOBAL_DIR],
	})

	if not ProjectSettings.has_setting(OUTPUT_FOLDER):
		ProjectSettings.set_setting(OUTPUT_FOLDER, DEFAULT_OUTPUT_FOLDER)
	ProjectSettings.set_initial_value(OUTPUT_FOLDER, DEFAULT_OUTPUT_FOLDER)
	ProjectSettings.add_property_info({
		"name": OUTPUT_FOLDER,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_DIR,
	})


static func _add_editor_setting(es: EditorSettings, key: String, default: String, hint: int, hint_string: String) -> void:
	if not es.has_setting(key):
		es.set_setting(key, default)
	es.set_initial_value(key, default, false)
	es.add_property_info({
		"name": key,
		"type": TYPE_STRING,
		"hint": hint,
		"hint_string": hint_string,
	})


## Plain-data copy of every setting the pipeline needs. Safe to hand to worker threads.
static func snapshot() -> Dictionary:
	var es := EditorInterface.get_editor_settings()
	return {
		"sbsrender": String(es.get_setting(SBSRENDER)),
		"sbsbaker": String(es.get_setting(SBSBAKER)),
		"seven_zip": String(es.get_setting(SEVEN_ZIP)),
		"engine": String(es.get_setting(ENGINE)),
		"output_folder": String(ProjectSettings.get_setting(OUTPUT_FOLDER, DEFAULT_OUTPUT_FOLDER)),
		"cache_dir": ProjectSettings.globalize_path("user://substance_bridge"),
	}


static func library_folders() -> PackedStringArray:
	return PackedStringArray(EditorInterface.get_editor_settings().get_setting(LIBRARY_PATHS))


static func set_library_folders(folders: PackedStringArray) -> void:
	EditorInterface.get_editor_settings().set_setting(LIBRARY_PATHS, folders)


## Returns one message per configured tool path that does not point at a file.
static func missing_tools(config: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	for key: String in TOOL_LABELS:
		var path: String = config.get(key, "")
		if path.is_empty() or not FileAccess.file_exists(path):
			problems.append("%s not found at \"%s\" (Editor Settings > Substance Bridge)" % [TOOL_LABELS[key], path])
	return problems
