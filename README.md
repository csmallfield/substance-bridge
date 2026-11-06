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
- Edit the parameters in the Inspector; a preview re-renders shortly after each change. Noise Lab
  materials also update **live** while you drag: the maps go straight into the material in memory
  (about 0.15 s per update at 512), and the files are written and imported after a 1.5 s pause.
- **Render Final**, **Make Seed Variants** (one per selected mesh), **Render All** (every material,
  any size, optional re-bake).

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
<godot> --path . --script res://addons/substance_bridge/tests/native_bake_check.gd   (windowed: native baker vs sbsbaker)
```

The editor self-test (`tests/selftest.gd`) drives the dock end to end. Set
`SUBSTANCE_BRIDGE_SELFTEST` to `tarmac.sbsar`, and optionally `SUBSTANCE_BRIDGE_SELFTEST_MESH`
(a mesh-adaptive `.sbsar`) and `SUBSTANCE_BRIDGE_SELFTEST_NOISE` (e.g. `grunge_014`), then run the
editor with `--log-file <temp>/selftest.log`. Run it windowed to catch editor-UI errors and for the
Noise Lab part (headless has no GPU), ideally on a copy of the project.
