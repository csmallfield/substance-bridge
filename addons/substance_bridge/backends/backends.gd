@tool
extends RefCounted
## Backend registry: which backend handles a source, and creating it.
##
## Sources are .sbsar paths (Substance) or "noiselab://<noise>" (the noise lab's native
## Godot generators).

const TextureBackend := preload("res://addons/substance_bridge/backends/texture_backend.gd")
const SubstanceBackend := preload("res://addons/substance_bridge/backends/substance/substance_backend.gd")
const NoiseLabBackend := preload("res://addons/substance_bridge/backends/noiselab/noiselab_backend.gd")

const SUBSTANCE := "substance"
const NOISELAB := "noiselab"


static func id_for_source(source: String) -> String:
	return NOISELAB if source.begins_with(NoiseLabBackend.SCHEME) else SUBSTANCE


## config: settings.gd snapshot().
static func create(id: String, config: Dictionary) -> TextureBackend:
	if id == NOISELAB:
		return NoiseLabBackend.new(config)
	return SubstanceBackend.new(config)


static func for_source(source: String, config: Dictionary) -> TextureBackend:
	return create(id_for_source(source), config)
