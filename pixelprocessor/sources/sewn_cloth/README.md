# Sewn Cloth

Woven fabric panels sewn together, built entirely from maths: no bitmaps, so it's resolution independent
(`sewn_cloth.sbsar`, also in `D:\04_projects\SDB\library\`). The seams come from `../seam_study/seam_lib.py`. They
were rebuilt from the JRO SeamStitch brushes, which served as measured reference only.


## Design

- **Weave:** plain (1/1) or 3/1 warp-faced twill (denim). Warp and weft are round threads going over and under;
  a warp mask colours them separately.
- **Panels:** 3 strips across the tile, each split into 1–3 pieces by Seed. Some panels have the weave turned 90°.
- **Seams:** every panel boundary carries the same seam style, so the cloth reads as one garment:
  - Workwear: double topstitch.
  - Overlock: zigzag.
  - Hand Repair: ladder.
  - Decorative: herringbone.
- **Seam detail:** each seam sits on a V groove, with the seam allowance pressed to one side and small puckers
  pulled along it.
- **Shading:**
  - warp and weft colours, panel tones and optional patchwork fabrics;
  - stitch-thread colour;
  - fading on raised seams and folds;
  - dirt and fibre fuzz;
  - soft drape wrinkles from library noise.

## Parameters (25)

- **Layout:** Seed.
- **Seams:** Seam Style, Seam Width, Pucker.
- **Fabric:** Weave, Thread Count, Weave Depth, Rotated Panels, Wrinkles.
- **Colour:** Warp, Weft, Patchwork, Patch B, Patch C, Panel Tone, Stitch Thread.
- **Wear:** Fade, Dirt, Dirt Colour, Fuzz, Roughness.
- **Output:** Normal Intensity, Normal Format.

Presets: Indigo Denim, Black Denim, Khaki Canvas, Army Patchwork (overlock), Repaired Linen (ladder), Decorative
Wool (herringbone).

## Checks

- **Bridge check:** passes. 25 params, 6 presets; 2048 renders in 3.2 s; the live sse2 render at 256 takes 0.46 s.

## Limits

- **Thread Count must suit the output size.** 176 threads at 2048 is about 12 px per thread. At 512 the weave turns
  to a shimmer: lower Thread Count or render bigger.
- **Clean up close:** the threads are perfectly regular, with no slubs or per-thread colour variation, so close up
  it looks a bit clean and synthetic.
- **Rows only:** the seams follow straight panel boundaries. Curved seams (darts, pockets) aren't done.
- **Missing seam types:** the puckered and torn seam types from the brush pack aren't in `seam_lib` yet.
