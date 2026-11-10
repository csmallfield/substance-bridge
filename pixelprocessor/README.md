# Pixel Processor library and material sources

The maths behind the procedural `.sbsar` files in `../library`. Everything here is resolution-independent functions:
no bitmaps, and no third-party brush art.

- **`pplib/`** holds the reusable building blocks: shapes and SDFs, height+class stacking, seams and stitches,
  weaves and smooth curves. Each function runs in numpy for previews or builds a Substance Pixel Processor function
  graph for cooking. See `pplib/README.md`.
- **`sources/<material>/`** holds the layout, graph script, numpy preview and notes for:
  - `concrete_ribbons`
  - `techno_grid`
  - `sewn_cloth`
  - `mesh_painted_metal`, which also includes the Blender script for the test canister.

## Running

- **numpy previews and layouts** run from this folder as they are. They need Python with numpy and Pillow (scipy
  for some previews); `pplib` is found at `../../pplib`.
- **Cooking a graph script** (`<material>.py`) also needs the Substance Automation Toolkit and the `.sbs`
  generator (`sbsgen.py`, `sbsops.py`, `sbsfunc.py`, `build.py`). The generator isn't in this repo; point
  `SBS_SCRIPTS` at its folder.
- **Reference images:** previews that compare against a reference image expect a `reference.jpg`, which isn't
  included.
