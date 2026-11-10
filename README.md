# Substance Bridge

Private Godot 4.7 editor plugin (`addons/substance_bridge`). Pick a mesh and a material graph,
set its parameters in the Inspector, and get a material built and applied without leaving the
editor. Two texture backends share the same Inspector, previews, variants, batch rendering and
material builder:

- **Substance**: renders `.sbsar` files with Adobe's command-line tools. For mesh-adaptive graphs
  it bakes mesh maps from the selected mesh, with `sbsbaker` or with the **native baker** (AO,
  curvature, position and world normal in Godot itself; choose per material with *Baker*).
- **Noise Lab**: native Godot rebuilds of Substance noises and Grunge Maps, from
  sd-mm-noise-lab (`D:\01_github\sd-mm-noise-lab`). Don't publish (see that repo's README).

`docs/validated-commands.md` lists every tool command line this is built on, with timings and the
failure modes the plugin guards against.

## Setup

1. Tools (paths are in Editor Settings > Substance Bridge; these are the defaults):
   - `sbsrender` from Substance Designer: `C:/Program Files/Allegorithmic/Substance Designer/`
   - `sbsbaker` from the Substance Automation Toolkit 2018.2:
     `C:/Program Files/Allegorithmic/Substance Automation Toolkit/`
   - 7-Zip: `C:/Program Files/7-Zip/7z.exe` (reads the parameter metadata inside `.sbsar` files)
2. Noise Lab (optional): link its generators into this project. The junction is git-ignored, and
   without it the Noise Lab backend reports itself unavailable.

   ```bat
   mklink /J noiselab D:\01_github\sd-mm-noise-lab\godot\noiselab
   ```

   The generators render on the GPU through the editor window, so keep the editor visible
   (not minimised) while a noise renders; a render that cannot draw times out after 60 s.
   Live previews use the generator's passes_per_frame (sd-mm-noise-lab, Nov 2026) to render
   more passes per frame; an older noise lab still works, at about half the live update rate.

## Use

In the Substance Bridge dock (top-right, beside the Inspector):

- **Create and Apply to Selected**: choose an `.sbsar` or a noise, select MeshInstance3D nodes, click.
  Mesh-adaptive graphs bake their mesh maps from the first selected mesh.
- Edit the parameters in the Inspector. Each change updates the material **live** in memory
  (Noise Lab: about 0.15 s at 512; `.sbsar`: `sbsrender` at 256 with the CPU engine, about
  0.7 s), then the maps are rendered at the preview size and imported after a 1.5 s pause.
- The **Substance Preview** bottom panel shows every output in 2D (tile, channel, zoom).
- The Inspector's **Material Slots** group routes outputs to material slots: source (Auto, None or
  any output), strength, invert and a min/max remap, baked per slot.
- **Tiling** (Inspector): UV scale and offset, set on the material with no re-render.
- **Projection** (Inspector): planar, triplanar, cylindrical or spherical, baked into the mesh's
  own UVs (good for auto-generated UVs) after **Bake from Selected Mesh**. Axis, tile size,
  repeats, sharpness, offset, rotation, Fit to Mesh; normal maps are re-oriented to the mesh's
  tangent space. Live edits are projected too (about 0.1-0.3 s for all maps on the GPU).
- **Render Final**, **Make Seed Variants** (one per selected mesh), **Render All** (every material,
  any size, optional re-bake).
- **Detach Material**: copies the current material out of the bridge into `<folder>/<name>/`
  (default `res://materials`; never overwrites, a second detach gets `<name>_2`) as a
  ShaderMaterial with its own `.gdshader`, written for the features the material uses (tiling,
  alpha, normal strength, AO, emission, parallax). The copy has no link to the graph, so
  re-rendering never touches it and it can be committed. It replaces the bridge material on the
  selected meshes that use it (with none selected: every mesh in the open scene that uses it;
  undoable). **Pack AO/roughness/metallic into ORM** merges those maps into one
  (R = AO, G = roughness, B = metallic) when at least two are present. **Optimize textures**
  writes emission and ORM (or AO, roughness and metallic) at half resolution and normal maps as
  8-bit PNGs without alpha; albedo and height are copied as they are. Either way the maps import
  VRAM compressed, so in game this saves memory only on the halved maps; the 8-bit normal just
  makes the source file smaller (4K normal: 79 MB to 13 MB). Detach after Render Final: it copies
  the maps at the size they were rendered.

The **Substance** main-screen tab (next to 3D, Script, AssetLib) is a library of `.sbsar` folders
outside the project (Folders > Add Folder; stored in Editor Settings, shared by every project).
Sphere thumbnails are cached in each folder's `.thumbnails` (or the editor cache for read-only
folders) and re-rendered only for edited files. Selecting a file shows an orbitable 512 preview
(sphere, cube, plane) with its metadata, mesh inputs, parameters and outputs; **Use for New
Material** or the dock's **Library** button puts its path in the dock. Files are referenced in
place, never copied.

Library folders can also hold Substance Painter smart materials (`.spsm`). The bridge reads them
(`addons/substance_bridge/spsm/`) but cannot render them yet: the library shows their layer stack
(fills, masks, filters, blends), the mesh maps their generators need and the graphs and bitmaps
inside, with Painter's own stored preview as the thumbnail when there is one (else a sphere in the
stack's flat base values). *Use for New Material* is disabled for them. An `.spsm` is HDF5 holding
the layer stack (`preset.bin`, a tagged binary format), the embedded `.sbsar` graphs (they render
with `sbsrender` as they are) and bitmaps (Qt header plus raw or LZ4 pixels).

Generated textures and materials go to `res://substance_bridge/<name>/` and are git-ignored; the
`<name>_graph.tres` settings next to them are tracked, because everything else is regenerated
from them.

## Tests

From the project folder (`<godot>` is the 4.7 console executable):

```bat
<godot> --headless --path . --script res://addons/substance_bridge/tests/runner_check.gd
<godot> --headless --path . --script res://addons/substance_bridge/tests/backend_check.gd
<godot> --headless --path . --script res://addons/substance_bridge/tests/obj_check.gd
<godot> --headless --path . --script res://addons/substance_bridge/tests/bake_check.gd
<godot> --headless --path . --script res://addons/substance_bridge/tests/routing_check.gd
<godot> --headless --path . --script res://addons/substance_bridge/tests/spsm_check.gd   (set SUBSTANCE_BRIDGE_SPSM to a folder of .spsm files for the file checks)
<godot> --path . --script res://addons/substance_bridge/tests/native_bake_check.gd   (windowed: native baker vs sbsbaker)
```

The editor self-test (`tests/selftest.gd`) drives the dock end to end. Set
`SUBSTANCE_BRIDGE_SELFTEST` to `tarmac.sbsar`, and optionally `SUBSTANCE_BRIDGE_SELFTEST_MESH`
(a mesh-adaptive `.sbsar`) and `SUBSTANCE_BRIDGE_SELFTEST_NOISE` (e.g. `grunge_014`), then run the
editor with `--log-file <temp>/selftest.log`. Run it windowed to catch editor-UI errors and for the
Noise Lab part (headless has no GPU), ideally on a copy of the project.

The projection test (`tests/projection_test.gd`) runs the same way with
`SUBSTANCE_BRIDGE_PROJECTION` set to `tarmac.sbsar`: plane identity for colour and normal maps,
every projection on a box and a sphere, then the dock flow and tiling (it removes its material).

The detach test (`tests/detach_test.gd`) runs the same way with `SUBSTANCE_BRIDGE_DETACH=1`, windowed
so its shaders really compile: ORM packing, every shader variant, and four detaches of a fake
material, with and without ORM and Optimize textures. Everything it writes goes under
`res://_detach_test` and is removed afterwards.

The library test (`tests/library_test.gd`) runs the same way with `SUBSTANCE_BRIDGE_LIBRARY` set to
a scratch folder of `.sbsar` files in subfolders, including `tarmac.sbsar` and a mesh-driven
graph, plus optionally two `.spsm` files (one with a stored Painter preview, one without). It points the library at that folder for the run and restores your folders afterwards.
