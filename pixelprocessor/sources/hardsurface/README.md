# Hard-surface study: alphas as maths (JRO Vol. 1, 2 and 3)

The JRO Hard Surface Alphas Vol. 1 (`D:\07_resources\JRO\JRO_Alphas_HardSurface_Vol.1`) served as reference only:
326 16-bit TIFFs, read in place and never copied or sampled. Shapes are rebuilt with `pplib.decals` (2D outlines)
and `pplib.relief` (edge profiles, pockets, rims and fills) as resolution-independent height.

- `sheets.py` writes lit contact sheets per category (`sheets/`) and `index.json`.
- `compare.py` writes `compare.png`: reference | maths | maths at 64 px, plus a centre cross-section of both (yellow
  = reference, cyan = maths).
- `item_sheet.py` puts all rebuilt items in one sheet, rendered in numpy or cooked. The cooked result is identical
  to numpy (mean difference 0.0000).

**Private:** `items.py` recreates specific alphas from a commercial pack, so it stays here. Only the generic
`pplib.relief` goes in the public repo.

## How the alphas are built

**Format:** heights 0..1 on a black background. `_in` and `_out` only say how ZBrush should stamp them; the data is
positive height either way.

| category | count | families | maths |
|---|---|---|---|
| BaseShapes | 71 | rim outlines, raised plates (pill, round, trapezoid), recesses with soft walls, framed recesses with corner lugs, truss frames | `rim`, `plate` + `soft` / `rounded`, `set_to`, `side` polygons |
| Bolts | 49 | round and hex heads (a hard rim easing into a dish) × drive (slot, cross, square, hex, torx, pin), rivets, pins | `dish` under a `soft` outline, drive by `set_to` |
| Vents | 85 | louvres, expanded-metal mesh, waffle grids, slot patterns, perforations, bolted frames, skewed extrusions | `louvres`, `wavy_mesh`, `waffle`, `slats`, `holes_grid`, frames with bolt holes |
| Containers & Doors | 31 | door outlines with hinges, hatches, caps, notched panels | `rim`, hinge bars, `set_to` |
| Handles | 25 | U and D grabs in pockets, recessed grips, flush pulls | outlined round bars over a pocket plate |
| Connectors | 24 | link plates with eyes, clips, sockets, tapered tabs | rounded rects, `inset` eyes |
| Misc | 16 | straps with buckles, portholes with clamps, lamps | rings, `dish` glass, radial clamps |
| Cables & pipes | 11 | bent tubes and cable runs | (not yet: `pplib.seams.thread` / `shapes.cylinder` along curves) |
| Stickers | 11 | flat decals | `pplib.decals` |
| UI & Panels | 3 | screen and panel layouts | (not yet) |

## Rebuilt so far (18)

- base01, base03, base14, base27
- bolt01, bolt04, bolt12, bolt16, bolt22
- vent12, vent14, vent15, vent18, vent20
- handle08, connector06, door05, window03

The weakest matches:
- vent18: the reference frame is a trapezoid.
- vent14: the reference block is a skewed extrusion fading downward.
- handle08: the U is a different shape.

## Test object

The JRO preview sphere (in the pack's `JRO_PreviewSphere` folder) is now `SDB/test/preview_sphere_mesh.res`. It
stands in `rock_test.tscn` as PreviewSphere, at x = -0.68, scale 0.013. Mesh Painted Metal renders on it from
Bridge-path bakes (`mesh_painted_metal/sphere_bakes`). Those bakes match the pack's own: curvature correlates at
0.97, AO at 0.87.


## Vol. 2

`D:/07_resources\JRO\JRO_Alphas_HardSurface_Vol.2` has 395 16-bit TIFFs, again read in place.
- `sheets_vol2.py` writes `vol2/sheets/`.
- `items_vol2.py` holds the rebuilds, private like `items.py`.
- `ITEMS=items_vol2 OUT=vol2/compare.png python compare.py` writes the comparison.
- `item_sheet_vol2.py` cooks them all; the result is identical to numpy.

New in Vol. 2:
- **Armor:** plates with rivets along the outline.
- **Disks and engines, Mechanical:** stacked blocks.
- **UI and panels:** dials with tick arcs, battery bars, notched boards.
- **Tiling fillers.**
- **Damaged metal.**

For these, `pplib.relief` gained `rivets_circle`, `rivets_segment`, `rivets_polygon`, `rivets_rect` and `tube`.

**Rebuilt (14):**
- armor01, armor04, armor06, armor10
- cables14, disk06
- ui17, ui18, ui21, ui26
- tiling06, mechanical07, vent68, container51

The weakest matches:
- armor10: the reference pillow fades the rivets.
- disk06: the reference spokes are outlined slots.
- mechanical07: the block layout differs.

## Noise filter (both volumes)

The user doesn't want alphas with high-frequency noise in them (grit, cast or sand-blasted fills, weathered
stickers, noisy damage). `noise_filter.py` scores every alpha in both volumes:
- **Metric:** the share of covered pixels that are tiny local maxima. Grit scores 0.08–0.17; regular grilles,
  ticks and grids stay under ~0.03.
- **Flagged:** above 0.05, plus the DamageMetal and Stickers categories by hand (their weathering sits under the
  threshold) and Tiling03.
- **Exempt:** UI&Panels61, a fine clean grid whose crossings count as peaks.

The result is `noise.json` and `vol2/noise_flagged.png`. **85 of 721** are flagged: all of Vol. 1's Stickers;
in Vol. 2, all of DamageMetal, 37 of 119 Vents (the gritty frames), 5 of 8 Disks and 5 of 7 Tiling fillers, plus
a few others. Use only unflagged alphas as references. Rebuilds avoid grit; tiling04 was dropped because its seams
are noisy.


## Vol. 3

`D:/07_resources/JRO/JRO_Alphas_HardSurface_Vol.3/Tiff` has one flat folder: 128 16-bit height alphas
(`_in` / `_out`), 125 of them with an 8-bit mask (`_M` / `_m`) that marks the part's footprint.
- `sheets_vol3.py` shows each alpha with its mask in the corner (`vol3/sheets/`) and scores it for noise
  (`vol3/index.json`).

**Noise:** the peak metric flags none. By eye, Alpha53, 54 and 55 have wrinkled-leather texture and Alpha13 has
cloth folds, so leave those four out too.

**Families:** round caps and bosses, screw heads in dishes and cushions, latches and clasps, hinges, flanges with
eyes, buckles and straps, quilted or roped panels, and a fan.

**Rebuilt (15), redone one at a time after review** (2026-11-10). The first pass had inverted depth and wrong
shapes. Each item was then measured with `profile_points.py` (heights along rows and columns) and checked with
`inspect_item.py` (signed difference, cross-sections, depth-inversion share):

| item | mean error | inverted | what was wrong |
|---|---|---|---|
| a21, a22, a24 | <= 0.002 | 0 % | a22: cross arms slope outward, octagonal centre |
| a25 | 0.004 | 0.6 % | missing crescent tabs (straight cuts, radial taper) |
| a39 | 0.008 | 0.5 % | five raised ring segments; base refitted from the gaps |
| a40 | 0.004 | 0.4 % | the bar is a SUNK channel across a 1.0 cap |
| a82 | 0.007 | 0.8 % | six raised lugs with stepped holes, not slots |
| a89 | 0.005 | 0 % | the cross is RAISED in a low bowl (was inverted); dish tilted |
| a98 | 0.007 | 0.4 % | four curved gaps sunk into a 1.0 disc, not raised blades |
| a15 | 0.005 | 1.4 % | the arms stop at the ring |
| a90 | 0.014 | 0 % | flat-ended lobes with circular scallops; round funnel; raised cross |
| a91 | 0.016 | 3.3 % | low bowl with RAISED cross (was inverted); cliff edge; low eyes |
| a93 | 0.006 | 0.5 % | octagonal hinge, rounded trough knuckle, ring screws (not holes) |
| a62 | 0.012 | 0.7 % | diamond cushion with long end fades, sharp-rimmed screw bowl |
| a34 | 0.009 | 0 % | plate with two thin lines and a lower field (was an empty frame) |

The cooked sheet (`item_sheet_vol3.py`) is still identical to numpy.

## Vol. 1 and 2 redone the same way (2026-11-10)

Every Vol. 1 and Vol. 2 item was redone one at a time from measurements (region edges, folded or angular-median
profiles about the measured centre), then checked with `inspect_item.py`. Before the redo most had 10-45 %
inverted depth.

| set | worst mean error | worst inverted | notes |
|---|---|---|---|
| Vol. 1 (18) | 0.034 (vent18) | 5 % (window03) | most <= 0.015 |
| Vol. 2 (14) | 0.028 (ui17) | 8 % (disk06) | most <= 0.012 |
| Vol. 3 (15) | 0.016 (a91) | 3.3 % (a91) | |

What the Vol. 2 redo found:
- **ui26** is a flat 1.0 plate with five holes cut right through. It has a filleted notch (r 0.105) bottom left
  and a step bottom right (was 0.23 error).
- **tiling06** has fourteen flat-topped boards per tile (period 1/7, centres at -1 + (k + 0.551)/7), with one
  folded edge profile (was 0.38).
- **mechanical07** is an "in" alpha. The floor is HIGH (0.6, sloping down to the right). The hinge, knuckles and
  draw bar are pressed into it, and each region's height is a measured profile along x (was 0.14).
- **vent68**'s three spokes are slots CUT through the disc (0, 120 and 240 degrees). They are not raised bars.
  The centre is at (0.0068, 0.0038) (was 0.041).
- **container51** has a thin ridge outline (gentle inside, sharp outside, chamfer slope 1.17). A thin seam steps
  round a trapezoid notch, and the tabs are flat 0.16 plates with an edge ridge (was 0.064).

All three cooked sheets (`item_sheet*.py`) are identical to numpy (mean difference 0.0000).
