# pplib: maths for Pixel Processor layouts

Reusable, resolution-independent building blocks for Substance Pixel Processor layouts. Everything is maths, with no
bitmaps. Every function takes the backend `M` first, so the same code runs two ways:

- `import sbsfunc as M`: builds a Substance function graph, so you can cook it into a Pixel Processor.
- `from pplib import npfunc as M`: computes whole numpy arrays, for previews in seconds.

`demo.py` uses every module. `python demo.py out.png` renders it in numpy, and `python ../build.py demo.py` cooks the
same function into Substance.

## Modules

| module | what | from |
|---|---|---|
| `shapes` | inside-positive SDFs (box, chamfered and round boxes, disc, ring, capsule, segment, convex polygon, hexagon, chamfered union); height+class stacking (`HC`, `Classes.tag`, `up`, `over`, `down`, `cut`, `paint`, `cylinder`, `comb`, `mix`, `slab`, `pocket`); hashes (`hashk`), lattices (`lat`, `wrap`), `table` lookups; layouts (`superblock_slots`, `hex_cell`) | wall panel, techno grid, hex plate |
| `seams` | seams in seam space (u across, v along): `plain`, `running_double`, `herringbone`, `ladder`, `zigzag`, `staples`, `clip_seam`, `teeth`; parts: `v_groove`, `shoulders`, `step`, `thread` (round threads, with coverage via `take_threads()`), `hole`, `rbox`, `plate` | seam study, sewn cloth |
| `weave` | plain or warp-faced twill weave, round warp and weft threads, plus a warp mask | sewn cloth |
| `decals` | flat 2D icons and decal graphics as SDFs in icon space (-1..1): booleans (`union`, `inter`, `sub`, `outline`, `grow`, `gap`), anti-aliased `fill`, folds (`radial` n-fold, `polar` with a built-in atan2, `rot`, `repeat`), primitives (`circle`, `ring`, rounded `rect`, `chamfer_rect`, `polygon`, `triangle`, `star`, `sector`, `seg`, `bar`, `chevron`, `arrow_head`, `side`, `halfplane`) | decal study |
| `relief` | hard-surface bas-relief from 2D outlines (pair with `decals`): edge profiles (`hard`, `chamfer`, `rounded`, `soft`, `cove`, `dish`, `dome`), parts (`plate`, `rim`, `groove`, `inset`, `raise_to`, `set_to`), fills (`louvres`, `slats`, `waffle`, `wavy_mesh`, `holes_grid`), `min_width` against aliasing | hard-surface study |
| `curves` | `soft_ramp` (45° S-bends with rounded corners), its slope, `soft_max` / `soft_min` | concrete ribbons |
| `npfunc` | the numpy backend (same names as `sbsfunc`), plus `sample_gray` over `SAMPLERS` | |

## Rules that keep layouts working

- **Tiling:** every repeat must divide the tile. Hash wrapped indices (`M.mod(i, N)`).
- **Distances:** in tile units, inside-positive. Bevel widths are distances too, so shapes stay crisp at any
  resolution.
- **No Python `if` on values:** use `M.sel`, `M.b01(...)` weights or `onehot` + `mix`.
- **Seeds won't match:** the numpy preview and the cooked graph give different hash layouts for the same seed (the
  GPU's `sin`). Precompute choices in Python when an exact match matters.
- **Outputs clamp to 0..1** in the Pixel Processor.
