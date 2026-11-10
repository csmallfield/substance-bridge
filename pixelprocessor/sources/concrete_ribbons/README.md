# Concrete Ribbons

A square, tileable (both directions) cast-concrete relief panel matched to `reference.jpg` (reading in
`ANALYSIS.md`). Light concrete ribbons step one column sideways in rounded 45-degree bends; the panel joints are the
ribbon edges, and straight diagonal cut joints split the strips into panels. Weathering, water stains,
efflorescence, wetness and mould are all controllable.

Outputs: base colour, normal, roughness, metallic (0), AO, height. Render square (`--size 11` = 2048).

## Layout (`ribbon_layout.py`, one Pixel Processor)

- **Joint chains:** each chain runs down a column line and S-bends one column to the left (45 degrees, rounded), again
  and again. A line is a joint only from when a chain lands on it until it leaves, so pieces are one or two columns
  wide. Six columns per tile. The bend schedule closes up over the tile, so it tiles vertically.
- **Cut joints:** one straight down-right 45-degree joint per strip, between two vertical joints (T-junctions).
- **Relief per piece:** a low ribbon along the left joint, a lit step face, and a high plane that leans back to the
  next joint. The step is the same chain looked up 1.7 columns higher and shifted 0.5 column right, so after each
  bend the ribbon flares into the wide "bottle" shoulder.
- **Variation** picks one of 8 precomputed bend schedules. All 8 are in `variations.png`.

## Parameters (27)

| Group | Parameters |
|---|---|
| Layout | Variation (0-7), Joint Width |
| Concrete | Concrete, Tone Variation (per piece), Mottling, Grain, Aggregate, Pinholes, Roughness, Joint Colour |
| Weathering | Weathering (blotches, eroded surface), Edge Wear (chipped crisp edges), Dirt, Dirt Colour |
| Water | Water Stains, Stain Length, Stain Colour, Efflorescence (white lime streaks), Wetness |
| Mould | Mould, Mould Colour, Mould Colour 2 (older, darker growth) |
| Output | AO Strength, Normal Intensity, Normal Format |

- **Water stains** start only on lines that face up: the joints and the crisp step edges, minus their own copy 2 px
  higher, so vertical joints don't streak. The stains are smeared downward by ten shifted copies, broken into thin
  vertical runs, and a faint rain wash is added over the whole surface.
- **Mould** grows in damp places: creases, joints and the stain trails, broken up by cloud and crystal noise.

## Presets (10, `presets_sheet.png`)

Fresh Cast, Weathered, Rain Stained, Wet Rain, Lime Bleed, Mouldy, Derelict, Warm Sandstone, Charcoal, White Precast.
Godot raking-light shots are in `shots/` (`weathered_*`, `rain_stained_*`, `mouldy_*`).

## Build

```bat
python np_preview.py out.png [--var 3]                    (numpy: reference | one tile | 2x2 tiled, lit clay)
python <skill>/scripts/build.py concrete_ribbons.py --size 11 --set normal_format@1
python <skill>/scripts/build.py concrete_ribbons.py --size 10 --debug && python measure.py   (mask percentiles)
<godot 4.7 console> --headless --path D:/04_projects/SDB --script D:/04_projects/substance_experiments/concrete_ribbons/bridge_check.gd
```

Bridge check: PASS. It has 27 parameters, 6 outputs and 10 presets. A 2048 render takes about 3.7 s at defaults and
about 2.9 s per preset (RTX 3080).

## Limits

- The layout is fixed per Variation; the column count (6) and the bend shape are constants in `ribbon_layout.py`.
- A line's run must fit the wrap window of `chain()`: L < 1 - 2.7 P (enforced in `schedule()`).
- The relief is deliberately shallow (heights 0.32-0.6). Turn Normal Intensity up for a stronger look.
