@tool
extends RefCounted
## Backend registry: which backend handles a source, and creating it.
##
## Sources are .sbsar paths (Substance), .spsm paths (Painter smart materials) or
## "noiselab://<noise>" (the noise lab's native Godot generators).

const TextureBackend := preload("res://addons/substance_bridge/backends/texture_backend.gd")
const SubstanceBackend := preload("res://addons/substance_bridge/backends/substance/substance_backend.gd")
const NoiseLabBackend := preload("res://addons/substance_bridge/backends/noiselab/noiselab_backend.gd")
const SpsmBackend := preload("res://addons/substance_bridge/backends/spsm/spsm_backend.gd")

const SUBSTANCE := "substance"
const NOISELAB := "noiselab"
const SPSM := "spsm"


static func id_for_source(source: String) -> String:
	if source.begins_with(NoiseLabBackend.SCHEME):
		return NOISELAB
	if source.get_extension().to_lower() == "spsm":
		return SPSM
	return SUBSTANCE


## config: settings.gd snapshot().
static func create(id: String, config: Dictionary) -> TextureBackend:
	if id == NOISELAB:
		return NoiseLabBackend.new(config)
	if id == SPSM:
		return SpsmBackend.new(config)
	return SubstanceBackend.new(config)


static func for_source(source: String, config: Dictionary) -> TextureBackend:
	return create(id_for_source(source), config)
