# Building Facade

`building_facade.sbsar` is a tileable, modular building facade. You choose the wall material, then tune the window
arrangement, frames, interiors and weathering. The inspiration was five facade photos: a ribbon office, a
residential tower with grouped bays, a curtain wall, a balcony block and a brutalist slab.

**How it is built:**
- **Layout:** `facade_layout.py`, written once for numpy previews (`np_preview.py`) and the Pixel Processors. Four
  Pixel Processors evaluate it:
  - height, class, per-element random and pane coordinates;
  - the interior colour;
  - the interior glow;
  - the dirt streaks.
- **Tiling:** the tile always holds whole bays and floors (Window Groups × Bays per Group across, Floors down).
- **Shading:** the node graph does the rest, using class masks, library noises and per-material weights picked from
  the Base Material dropdown.

## Parameters (100)

| group | parameters |
|---|---|
| Material | Base Material (Precast Panels, Board-formed Concrete, Brick, Render, Stone Panels, Metal Panels, Mosaic Tiles), Wall Tint, Bands & Piers colour and Accent, Panel Columns, Panel Rows, Brick Courses (per floor, default 36), Brick Length (in course heights, default 3), Joint Width, Joint Depth, Unit Variation, Wall Roughness |
| Layout | Seed, Lanes, Lane Pattern (All A, A B, A B A, A A B, B A B, A B B A, A B C B, A B C B A, A C A B, Random), Floors, Special Floor Every, Special Floor Type, Pier Width, Pier Depth, Slab Band, Band Depth |
| Window Type A / B / C | Bays (lane width), Window Width (1 = ribbon), Window Height, Window Top, Mullions, Transom, Style (Windows, Balcony, Spandrel Band, Blank Wall) |
| Variation | Width Variation, Height Variation, Odd Narrow Windows, Open Windows |
| AC Units | AC Units (share of windows), AC Position (In Window, Below Window, Mixed), AC Size, AC Colour |
| Ground Floor | Ground Floor (toggle), Ground Height, Ground Bays, Doors, Shop Windows (the rest blank), Grouping (pairs, triples), Bay Variation, Double Doors, Glazed Doors, Door Width, Door Height, Fanlights, Window Width / Height / Top / Mullions / Transom, Ground Band and Depth, Ground Pier Width and Depth, Ground Accent, Ground Colour, Door Colour |
| Windows | Mullion Width, Frame Width, Recess, Sills, Frame Colour, Frame Metallic, Spandrel Colour |
| Glass | Glass Tint, Reflection, Reflection Variation |
| Interior | Curtains, Blinds, Lit Windows, Colourful Curtains, Light Colour, Light Intensity |
| Weathering | Grime, Streaks, Stains, Dirt Colour |
| Output | AO Strength, Normal Intensity, Normal Format |

**Lanes:**
- **Vertical:** each lane takes window type A, B or C from the Lane Pattern. A type has its own lane width in bays,
  window size and position, mullions, transom and style. Mixing types gives, for example, a curtain-wall strip
  between punched lanes, one glazed lane in a blank wall, or a balcony lane beside window lanes.
- **Horizontal:** Special Floor Every N switches every Nth floor to one type across all lanes (attic, mechanical
  or podium rows).
- **Tiling:** for a clean wrap, keep Lanes a multiple of the pattern length, and Floors a multiple of Special
  Floor Every.

**Ground floor:**
- **Layout:** when on, the bottom of the tile becomes a taller ground floor with its own bay grid. The texture then
  tiles horizontally only, so use it as a base trim.
- **Bays:** each bay is a door, a shop window or blank wall.
  - Grouping decides bays in pairs or triples.
  - Bay Variation lets single bays break from their group.
- **Doors:** single or double; glazed or solid panelled; optional fanlight up to the window head.
- **Matching:** frames, mullions and glass match the upper windows.
- **Interiors:** shop interiors have few curtains or blinds and are lit more often.

**AC units** are boxes with fins, set in the lower pane or hung below the window, each with a drip streak.

**Bricks and mosaic** are sized in the square texture: the course height comes from Floors × Courses, and the
brick length is a ratio of the course height. Counts are rounded so the tile still tiles.

**Presets (18):** Office Grid, Ribbon Office, Residential Tower, Curtain Wall, Balcony Block, Brutalist Slab,
Brick Walk-up, Metal Ribbon, Deco Lanes, Curtain Strip, Glazed Lane, Mixed Balconies, Attic Rows, Shopfront Street,
Brick Row Houses, Podium Tower, AC Block, Night Lights.

## Checks

- **Previews:** `presets_presets.png` shows all presets; `sweep.png` shows all seven materials on one layout plus
  dense, sparse and maximum extremes.
- **Bridge:** `bridge_check.gd` describes the material and renders the defaults (GPU 2048 in about 2 s), the live
  CPU path and every preset. Result: PASS.

## Limits and notes

- **Square tile:** bays and floors stretch with the counts, so set the ratio of Bays per Group × Groups to Floors
  to roughly match the building, or render non-square with `--size 11,10`.
- **Interiors are flat** (no parallax). Reflections are painted into the base colour as a sky tint; the glass also
  has low roughness for real reflections.
- **Bricks** run in stretcher bond only.  **Board-formed concrete** has vertical boards only.

**Lesson:** an RGBA Pixel Processor whose alpha carried data (the glow) made the interiors vanish, because blends
composite by alpha. Keep alpha at 1 and give the data its own grey Pixel Processor.

## Derelict variant: `building_facade_derelict.sbsar`

This variant is built from the same script: `building_facade_derelict.py` sets `VARIANT = 'derelict'` and runs
`building_facade.py`. It has every facade parameter plus a **Disrepair** group (114 parameters in all):
- **Disrepair:** a master amount (0–1.5) that scales everything below.
- **Broken Windows:** smashed panes with a jagged hole and radiating cracks; a third have lost their glass
  entirely.
- **Boarded Up:** planks over windows and doors, horizontal or vertical, some with a diagonal brace.
- **Cracks:** wandering crack lines in patches.
- **Crumbling:** render or cladding fallen away near openings and edges. Under Layer picks what shows beneath:
  rough concrete, or brick with its own joints.
- **Rot and Mould:** black-green mould in damp places (under sills, in cavities) and rot on the boards.
- **Moss:** clumps on ledges and in damp corners.
- **Ivy:** vines with leaf clusters climbing from the bottom of the tile. Ivy Height sets how far up it reaches.
- **Filth:** heavy soot and dirt all over.
- **Colours:** boards, ivy and moss.

**Presets (7):** Abandoned Office, Squatted Block, Overgrown Brick, Crumbling Render, Boarded Shops, Total Ruin,
Light Neglect.

**Check:** `bridge_check_derelict.gd` passes.

**Fix on the way:** the per-window random values came from a sine hash on small integers. They clumped, so the
Broken and Boarded sliders responded unevenly. Window keys now use the exact mod-289 hash (`pplib.rocks.hash12`),
which is evenly spread and identical on the GPU. This also reshuffles which windows get curtains in the clean
facade.
