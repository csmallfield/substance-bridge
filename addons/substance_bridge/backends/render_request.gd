@tool
extends RefCounted
## What to render: a source plus parameter values. Backend-agnostic.

const GraphDescription := preload("res://addons/substance_bridge/backends/graph_description.gd")

## Backend source, e.g. an absolute .sbsar path.
var source := ""
## Optional; when null the backend describes the source itself.
var description: GraphDescription = null
## Parameter id -> value (float, int, bool, Color, Vector2/3/4 or String).
var values := {}
## Image input id -> absolute image path (baked mesh maps etc.).
var image_inputs := {}
## Output size as powers of two: (10, 10) = 1024 x 1024.
var size_log2 := Vector2i(10, 10)
var random_seed := 0
## Absolute folder the backend writes its maps to (created if missing).
var output_dir := ""
## Normal map convention to ask the backend for when the graph can switch ("opengl" for Godot).
var normal_convention := "opengl"
