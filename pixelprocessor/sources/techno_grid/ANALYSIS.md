# Techno Grid: brief and plan

`reference.jpg` is a mood reference, not a layout to match: a dense model-kit "greeble city". Dark sprue-like rods on
a rough orthogonal grid, ladders and catwalk gratings, mesh panels (some brass), machine blocks with hatches and valve
wheels, long thin pipes, and deep black gaps with a few warm lights far behind.

## Brief (user)

- A "techno grid" with lots of transparent negative space: alpha is part of the design.
- Square, tiles both ways.
- Lots of small modules of detailed greebles; long pipes with smooth stretches and jumbled stretches; an occasional
  panel to break it up; cables and cable bundles.
- Strong depth inside the texture. The intended use is to stack 5 or more polygons, each with a different variation,
  to build complex infrastructure. So a **Seed** must give truly different layouts, and the edge of each layer must
  read well over another one.
- A couple of material treatments.

## Layers inside one texture (back to front, each on its own lattice)

| # | Layer | Lattice | Height | Notes |
|---|---|---|---|---|
| 1 | Thin rods | 32 x 32 lines, hashed on/off per line and per 1/8 segment | 0.12-0.24 | sprue-like round rods, the back mesh |
| 2 | Main beams | 8 x 8 (module boundaries), segments hashed | 0.26-0.32 | flat bars with a centre channel; carry the modules |
| 3 | Modules | 8 x 8 cells, merged in 2x2 superblocks (2x2, 2x1, 1x2, 1x1), ~35 % empty | 0.30-0.62 | 9 types: grille, machine, tank, fins, catwalk, louvre, panel, manifold, electronics |
| 4 | Pipes | horizontal 12 lanes x 10 segments, vertical 10 lanes x 12 segments | 0.40-0.80 | singles and racks of 2-3; smooth or greeble segments (clamps, blocks, valves, junction boxes); flanges, end caps |
| 5 | Cables | 6 horizontal sagging groups (2-4 spans), 3 vertical groups | 0.35 or 0.80 | bundles of 1-5, ties and anchor clamps; some behind modules, some in front |

Everything not covered is transparent (alpha 0). All lattices divide the tile, and per-element hashes use wrapped
indices, so the texture tiles both ways. A Seed parameter is fed into every hash.

## Outputs (planned)

Base colour, normal, roughness, metallic, AO, height, opacity, and emissive (small indicator lights).

## Treatments (planned)

Dark iron model kit (the reference: near-black metal, brass mesh accents, warm lights), plus a few others such as
grey primer kit, industrial painted, rusted, clean white sci-fi. Picked as presets.
