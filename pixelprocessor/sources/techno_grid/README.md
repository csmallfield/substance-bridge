# Techno Grid

A square, tileable "greeble city" layer with lots of transparent negative space (`techno_grid.sbsar`, also in
`D:\04_projects\SDB\library\`). It's meant to be stacked: put it on 5 or more planes, each with a different
**Seed**, and you get deep, complex infrastructure. Upper planes cast real shadows into the gaps. The brief and the
plan are in `ANALYSIS.md`.


## What's in a layer (back to front)

| Layer | Detail |
|---|---|
| Rods | thin sprue-like rods on a 32-line lattice, switched on and off per line and per segment |
| Beams | flat bars with a centre channel and bolts on the 8 x 8 module grid |
| Modules | 8 x 8 cells merged into 1x1, 2x1 and 2x2 modules, with some slots left empty. Nine types: mesh grille (sometimes brass), machine block (hatch, valve wheel, indicator light, bolts), tank, heat-sink fins, catwalk grating / ladder, louvre vent, panel, pipe manifold, electronics board |
| Pipes | 12 horizontal and 10 vertical lanes; single pipes or racks of 2–3; smooth stretches or greeble stretches (clamps, blocks, valve wheels, junction boxes with branch stubs); flanges and end caps |
| Cables | sagging bundles of 1–5 (2–4 spans per tile) and wavy vertical bundles, with ties and anchor clamps; some in front of everything, some behind the modules |

Outputs: base colour, normal, roughness, metallic, AO, height, **emissive** (the indicator lights), **opacity**, and
a material ID mask. Opacity is a hard 0/1 alpha, so it works with alpha scissor.

## Parameters (36)

- **Layout:**
  - Seed (0–300): a new layout and a grid offset, so stacked planes don't line up.
  - Modules, Pipes, Cables, Rods, Beams: how much of each.
- **Palette:** Frame, Body, Body B, Pipes, Pipes B, Dark Parts, Valves, Brass, Cables, Cables B.
- **Material:** Paint Roughness, Metal Roughness, Bare Metal, Metal Pipes (pipes become polished metal in the pipe
  colours), Cavity Darkening, Surface Detail.
- **Lights:** Light Intensity, Lamps.
- **Wear:** Edge Wear (dry-brushed edges worn to steel), Scratches, Grime, Dust, Dust Colour, Oil Leaks, Patina, Rust,
  Rust Colour.
- **Output:** AO Strength, Normal Intensity, Normal Format (DirectX/OpenGL).

## Presets

Dark Iron (the reference look), Grey Primer, Industrial, Gunmetal, Rusted Derelict, White Station, Military Green,
Black Ops, Brass Works. `presets_sheet.png` shows each one as a 5-plane stack in Godot.

## Performance (RTX 3080)

- 2048 at default settings: about 3.0 s (Bridge, d3d11pc).
- Presets: 2.8–3.0 s each.
- Live CPU preview at 256: 0.66 s.

## Checks

- The Bridge check passes: 36 params, 9 outputs including emissive and opacity, 9 presets, live sse2 render.
- Tiling: across the wrap edge the height changes no more than between ordinary neighbouring columns (76th
  percentile of all column pairs).
- Extremes: every layout slider at 0 gives an empty layer; all at 1 gives 91 % coverage. Defaults give 58–72 %
  depending on the seed.

## Limits

- **The numpy preview doesn't predict cooked seeds.** The GPU's sin hash differs from numpy's, so the same seed gives
  a different (equally valid) layout once cooked. Use `np_preview.py` for style only.
- **Library noises follow `$randomseed`, not Seed.** Wear patterns repeat between stacked planes unless the random
  seed differs too. With different layouts this is hard to spot.
- **Oil Leaks above about 0.3 read as black splotches.**
- **AO is baked per layer.** In a stack, the engine supplies the shadows between planes.

## Files

- `techno_layout.py`: the layout function (numpy or Pixel Processor).
- `techno_grid.py`: the graph, built with `build.py techno_grid.py --size 11`.
- `np_preview.py`: numpy clay preview, with `--stack 5` for a stack.
- `stack_preset.sh` with `stack_shot_n.gd`: render one preset at 5 seeds and stack the planes in Godot.
  `all_stacks.sh` does every preset and `sheet.py` makes the sheet.
- `bridge_check.gd`: the headless Bridge check.
- `history/`: scratch.
