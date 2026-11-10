# Mesh Painted Metal

Simple painted steel whose wear comes from **maps baked from the target object**: `mesh_painted_metal.sbsar`, also in
`D:\04_projects\SDB\library\`. The five image inputs are not textures to paint. When you apply the material with the
Substance Bridge, it bakes them from the selected mesh (**Bake from Selected Mesh**) and plugs each one in by its
usage.


## Maps from the target object → what they drive

| Image input (group "From Target Object (baked mesh maps)") | Usage | Drives |
|---|---|---|
| Target AO (baked) | `ambientOcclusion` | cavity dirt, rust in cavities; passed through as the AO output |
| Target Curvature (baked) | `curvature` | edge wear on convex edges (through primer to steel), dirt in concave creases |
| Target Thickness (baked) | `thickness` | thin parts (handwheel, collar, handles) worn smooth to polished steel instead of chipped |
| Target World Normal (baked) | `normalWS` | dust on up-facing surfaces; which surfaces streaks run down |
| Target Position (baked) | `position` | grime gathering low on the object, rust streaks running down in object space, seam-free 3D noise (`3D_perlin_noise_fractal`) |

Every input, group and parameter says so in its label and description. The **View** dropdown shows each baked map
(curvature, AO, thickness, world normal, position) and each mask it drives (edge wear, cavity dirt, top dust, low
grime, rust, thin parts) as the base colour on the object itself. Two presets open straight into a debug view.


## Parameters (31)

- **View**
- **Paint:** Paint, Paint Roughness, Primer, Bare Steel, Steel Roughness, Orange Peel.
- **Edge Wear (target curvature):** Edge Wear, Edge Width, Breakup, Thin Parts Wear.
- **Dirt and Dust (target AO, normal, position):** Cavity Dirt, Dirt Colour, Low Grime, Low Grime Height, Top Dust,
  Dust Colour.
- **Rust (target AO, normal, position):** Rust, Rust Streaks, Streak Length, Rust Colour.
- **Output:** Noise Scale, Normal Intensity, Normal Format.

Outputs: base colour, normal (a detail normal: paint chips and orange peel; the shape comes from the mesh), roughness,
metallic, AO (the target's baked AO) and height.

Presets: Industrial Green, Fresh Paint, Safety Yellow, Fire Red, Navy Grey (red oxide primer), Abandoned, Debug:
Curvature, Debug: Edge Wear Mask.

## The test prop: an industrial canister

`canister_blender.py` builds it in Blender 5.0 (`blender -b -P canister_blender.py -- <out dir>`):
- a lathed body with a foot ring, two ribs, a shoulder and a neck;
- a valve with a hex collar nut, a side outlet and a handwheel on a stem;
- a protective collar ring on three posts with bolted feet;
- a bolted name plate.

It's one mesh of 8.5k vertices with one UV map (Smart UV Project, then averaged island scale, then packed), exported
as glb and obj. In the Bridge project it's `res://test/canister_mesh.res`, and it stands in `test/rock_test.tscn`
as **Canister** at x = -0.32, scale 0.25.

## Checks

- **Bridge check** (`bridge_check.gd`, headless) passes. It runs the real mesh-adaptive path:
  - describe finds five image inputs, one per usage;
  - with no mesh, the pipeline asks for "Bake from Selected Mesh";
  - `Pipeline._bake_and_render` on the canister bakes all five maps with sbsbaker in 6 s and renders 2048 in 3.5 s;
  - the live sse2 render at 256 takes 1.5 s with the cached bake;
  - all 8 presets and two View modes render in 2.7–3.8 s each.
- **Native baker:** baking AO, curvature, position and normal on the canister takes 3.9 s (windowed), with thickness
  from sbsbaker. The result looks the same; native curvature has a wider spread, so wear is a little stronger
  (`shots/sbsbaker_vs_native.png`).
- **Axis conventions** were checked against the OBJ: world normal and position use RGB = XYZ with green = up;
  position is the bounding box as 0..1 per axis; curvature 0.5 is flat and above 0.5 is convex.

## Limits

- **Streaks don't know where the chips are.** They start at random heights in object space and run down vertical
  surfaces. Their horizontal coordinate switches between X and Z by facing direction, so there's a jump at
  45-degree facings.
- **Position is normalised per axis**, so 3D noise and streaks stretch on very flat or very long objects.
- **Thickness needs sbsbaker** even with the native baker; the Bridge does this automatically.
- **Small tubes count as all edge.** Their curvature is high everywhere, which is why thin parts polish instead of
  chipping.

## Files

- `mesh_painted_metal.py`: the graph. Build with `build.py mesh_painted_metal.py --size 11 $(cat inputs.txt)`, which
  plugs in the baked maps.
- `canister_blender.py`: the prop. `canister_shot.gd` and `shot.sh` render the material on it in Godot.
- `bridge_bakes/`: maps baked exactly as the Bridge does (ObjWriter + MeshBaker).
- `native_bakes/`: the native baker's maps.
- `bridge_check.gd`: the headless Bridge check.
