@tool
extends RefCounted
## What a backend produced: texture files keyed by usage. This is the only thing the
## material builder reads, so any backend that fills it gets the same material.

## Usage -> absolute file path. Usages follow Substance naming: "baseColor", "normal",
## "roughness", "metallic", "ambientOcclusion", "emissive", "height", ...
var maps := {}
## Every output the backend wrote: [{id, label, usages, path}], including unmapped ones.
var outputs: Array[Dictionary] = []
## Convention of the normal map in `maps`: "opengl" (Godot's) or "directx" (needs a Y flip).
var normal_convention := "directx"
var errors := PackedStringArray()
var warnings := PackedStringArray()
## Command lines that were run, for the log.
var commands := PackedStringArray()
var duration_ms := 0


func is_ok() -> bool:
	return errors.is_empty() and not maps.is_empty()
