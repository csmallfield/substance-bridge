# Substance Bridge: validated commands

Exact command lines that ran successfully on the work machine. These are the plugin's
command templates. Anything not marked **verified** has not been run here yet.

Machine: Windows 11 Pro, RTX 3080. Validated 2026-11-06.

## Tools

| Tool | Path | Version |
|---|---|---|
| `sbsrender` | `C:\Program Files\Allegorithmic\Substance Designer\sbsrender.exe` | 11.1.2 (build 4593, commit 0x0a3b2baa) |
| `sbscooker` | `C:\Program Files\Allegorithmic\Substance Designer\sbscooker.exe` | 11.1.2 (build 4593, commit 0x0a3b2baa) |
| `sbsbaker` | `C:\Program Files\Allegorithmic\Substance Automation Toolkit\sbsbaker.exe` | 2018.2.0 (build 263, commit 0x7373c63e) |
| 7-Zip | `C:\Program Files\7-Zip\7z.exe` | 26.00 (x64) |

Engines in `Substance Designer\plugins\engines\`: `substance_d3d11pc_blend.dll` (GPU) and
`substance_sse2_blend.dll` (CPU).

`--version` works on `sbsrender` and `sbscooker` and prints `version 11.1.2 (build 4593 commit 0x0a3b2baa)`.

SAT 2018.2 is the newest Automation Toolkit available without an enterprise licence. Use it only
for `sbsbaker`, and keep using Designer 11.1.2's `sbsrender`/`sbscooker`. SAT also ships its own
2018-era `sbsrender`, `sbscooker`, `sbsmutator` and `sbsupdater`, plus `axftools` and `mdltools`.

## Failure detection (applies to every tool)

All three tools **exit 0 on many real failures**. The tool runner must also check that the
expected output files exist and scan stderr for these:

| Tool | Situation | stderr | Exit |
|---|---|---|---|
| sbsrender | unknown image input id / input not set | `Image input "<id>" has not been set.` | 0 |
| sbsrender | image file missing | `Could not load image "<path>"` | 0 |
| sbsrender | output folder missing | `Result cannot be saved to ...` | 303 |
| sbsbaker | `*-from-mesh` with no high-poly | `No high poly scene given.` (as a WARNING), no file written | 0 |
| sbsbaker | unsupported mesh format (glTF/GLB) | `[ERROR][SBSBaker]Error: Scene "<path>" couldn't be loaded` | 0 |

Rule: the job fails if any `[ERROR]` line appears, if any of the warnings above appears, or if an
expected output file is missing.

## 1. Describe a graph (verified)

```
sbsrender info <file.sbsar>
```

Output, one graph per `GRAPH-URL` block:

```
GRAPH-URL pkg://PL_Gen_Edging01
  INPUT $outputsize INTEGER2
  INPUT $randomseed INTEGER1
  INPUT EdgingWidth FLOAT1
  INPUT ambient_occlusion IMAGE
  INPUT curvature IMAGE
  OUTPUT basecolor baseColor
  OUTPUT output
```

`INPUT <id> <type>`: the types are `FLOAT1..4`, `INTEGER1..4`, `STRING` and `IMAGE`.
`OUTPUT <id> <usage>`: the usage is empty when the output has none, and `UNKNOWN` also occurs.
Exit code is 0. This gives no labels, ranges or defaults, so use the XML (section 5).

## 2. Render (verified)

Output folders must exist before the render. `sbsrender` does not create them: it exits with
**303** and prints `Result cannot be saved to ...`.

### Template

```
sbsrender render
  --input <file.sbsar>
  [--input-graph <pkg://graph>]              # only if the sbsar has several graphs
  --engine d3d11pc                           # GPU; sse2 for CPU
  --output-path <existing dir>
  --output-name {outputNodeName}             # also {inputName} {inputGraphUrl} {colorspace}
  --output-format tga | exr | png
  [--output-bit-depth 8 | 16 | 16f | 32f]
  [--png-format-compression best_speed]
  --set-value $outputsize@<log2w>,<log2h>    # 10,10 = 1K, 11,11 = 2K
  --set-value $randomseed@<int>
  --set-value <id>@<value>                   # float: 0.9  color: 0.1,0.1,0.12  int/bool: 1
  --set-entry <image_input_id>@<abs path to image>
  [--use-preset <preset label>]
```

### Verified example: values, seed, 2K (tarmac sample)

```
"C:\Program Files\Allegorithmic\Substance Designer\sbsrender.exe" render
  --input "C:\Program Files\Allegorithmic\Adobe Substance 3D for Maya\2022\sbsars\tarmac.sbsar"
  --engine d3d11pc
  --output-path <dir>
  --output-name "{inputGraphUrl}_{outputNodeName}"
  --set-value "$outputsize@11,11"
  --set-value "$randomseed@42"
  --set-value tarmac_damage@0.9
  --set-value "asphalt_color@0.1,0.1,0.12"
  --set-value normal_format@1
```

When calling from PowerShell, put `$outputsize` / `$randomseed` in single quotes. Godot's
`OS.execute` passes arguments as an array, so no quoting is needed there.

### Verified example: image inputs via `--set-entry` (mesh-adaptive graph)

```
sbsrender render
  --input "D:\07_resources\JRO\Industrial_SmartMaterials\Generators\PL_ISF_Gen_Edging01.sbsar"
  --output-path <dir> --output-name {outputNodeName}
  --set-value "$outputsize@11,11"
  --set-entry ambient_occlusion@<ao.png>
  --set-entry curvature@<curvature.png>
  --set-value "$randomseed@7"
  --set-value EdgingWidth@0.5
  --set-value GrungeScratchesAmount@0.9
```

Different maps give a different output (MD5 changed). The first test used stand-in images.
Section 4b repeats it with real bakes.

**Failure modes that still exit 0.** In each of these `sbsrender` prints a warning and renders anyway:

| Cause | Warning on stderr |
|---|---|
| Image input not set, or unknown input id in `--set-entry` | `[WARNING][SBSRender]Image input "<id>" has not been set.` |
| Image file missing | `[WARNING][SBSRender]Could not load image "<path>"` |

The tool runner must scan stderr for these and fail the job, because the exit code won't
show a problem.

### JSON report (stdout)

Printed unless `--no-report` is passed. It's an array of graphs, each with an `outputs` array:

```json
[{ "identifier": "tarmac",
   "outputs": [
     { "identifier": "basecolor", "label": "Base Color", "type": "image",
       "uid": 3873044698, "usages": ["baseColor"],
       "value": "C:/.../tarmac_basecolor.png" } ] }]
```

Paths use forward slashes. Map outputs to material slots by `usages[]`, not by filename.
Usages seen: `baseColor`, `diffuse`, `normal`, `specular`, `glossiness`, `roughness`,
`metallic`, `height`, `ambientOcclusion`, `emissive`.

### Timings (RTX 3080, tarmac, 8 outputs at 2K)

| Engine | Format | Time | Size |
|---|---|---|---|
| d3d11pc | PNG default (mixed 8/16-bit) | 11.4â€“12.1 s | â€” |
| sse2 | PNG default | 12.5â€“12.6 s | â€” |
| d3d11pc | PNG 8-bit, default compression | 6.2 s | â€” |
| d3d11pc | PNG 8-bit, `best_speed` | 2.6 s | â€” |
| d3d11pc | PNG 16-bit, `--png-format-compression none` | 3.2 s | 140 MB |
| d3d11pc | TGA (8-bit) | **2.2 s** | 64 MB |
| d3d11pc | EXR | 2.7 s | 40 MB |
| sse2 | TGA | 3.3 s | 64 MB |
| sse2 | EXR | 3.6 s | 40 MB |
| d3d11pc | PNG default at 1K | 3.6 s | â€” |

PNG compression takes most of the time. With the default PNG, normal, height, roughness and
metallic come out **16-bit**; only `basecolor` is 8-bit. Suggested plugin defaults:
`--png-format-compression best_speed` (keeps 16-bit for height/normal), or TGA for fast previews.
Edging01 (2 outputs, 2K) took 0.9â€“1.7 s.

### Engine selection

`--engine d3d11pc` loads the GPU DLL (`--verbose` prints `Using GPU number 0: NVIDIA GeForce RTX 3080`
and the DLL path). `--gpu-list` appears in 11.1.2's `render --help` but doesn't work:
without an input it errors `No input specified`, and with one it just renders.

## 3. Cook `.sbs` â†’ `.sbsar` (verified for user graphs)

```
sbscooker --inputs <file.sbs> --output-path <dir>
```

| Input | Result |
|---|---|
| `JRO_SDNode_Collection_Vol.1\Example_SBS\Direction_Mask_Example.sbs` | exit 0, 0.6 s, renders 5 outputs |
| `SubstanceMastersVol2...\JRO_PaintedConcrete.sbs` (has dependencies) | exit 0, 3.5 s, renders 6 outputs |

Don't pass `--includes`: it's deprecated, and the built-in package path is detected
automatically. Use `--alias sbs://<path>` for other libraries. Library graphs from
Designer's own install still fail with error 13 (verified at home).

## 4. Bake mesh maps (verified, SAT 2018.2)

### Inspect a mesh

```
sbsbaker info <mesh>
```

This prints the entities, vertex count, UV sets (`Contained within unit square: 1`, UDIM tiles)
and submeshes (material groups). Use it to validate a mesh before baking:
`rock01.fbx` â†’ entity `rockymesh`, 38,564 verts, UV 0 in the unit square, UDIM 1001, 76,790 tris.

### Template

```
sbsbaker <baker>
  --output-size <log2w>,<log2h>        # 11,11 = 2K
  --output-path <dir>                  # created automatically
  --output-name <name>                 # patterns: {inputName} {bakerName} {udim}
  [--output-format png|tga|exr|...]
  [--uv-set 0]
  [--use-lowdef-as-highdef true]       # needed by *-from-mesh bakers when there is no high poly
  <mesh>
```

### Verified 2K bakes of `D:\04_projects\SDB\assets\rock01.fbx`

| Map | Command (after `sbsbaker`) | Time |
|---|---|---|
| AO | `ambient-occlusion-from-mesh --use-lowdef-as-highdef true --output-size 11,11 --output-path <dir> --output-name rock01_ao <mesh>` | 3.9 s |
| AO (alt) | `ambient-occlusion-from-mesh --highdef-mesh <same mesh> ...` | 4.0 s (same result) |
| Curvature | `curvature --output-size 11,11 --output-path <dir> --output-name rock01_curvature <mesh>` | 3.3 s |
| Curvature (from mesh) | `curvature-from-mesh --use-lowdef-as-highdef true ...` | 2.3 s |
| Position | `position --output-size 11,11 --output-path <dir> --output-name rock01_position <mesh>` | 3.0 s |
| World-space normal | `normal-world-space --output-size 11,11 --output-path <dir> --output-name rock01_wsnormal <mesh>` | 3.1 s |
| UV layout | `uv-map ...` | 40.6 s (don't use in the plugin) |

All four maps together take about 13 s at 2K, run one after another. Outputs are 2048Â², written as PNG.
`--output-path` does not need to exist beforehand (unlike `sbsrender`).

Notes:
- `--use-lowdef-as-highdef true` replaces the `--highdef-mesh <same mesh>` trick from the home
  machine. Without either, `*-from-mesh` bakers write nothing and exit 0.
- `curvature-from-mesh` with low=high gives saturated noise on this rock. Plain `curvature`
  (computed from mesh normals) gives a clean, low-contrast map centred on 50 % grey. Use `curvature`
  for single-mesh bakes.
- AO uses defaults (max distance 0.1 of the bbox, 64 rays). The result is faint on this rock,
  which suits its shallow crevices.

### Mesh formats

| Format | Result |
|---|---|
| FBX 7.7 binary (FBX SDK 2020) | works |
| OBJ (Blender 5.0 export) | works (entity name is empty) |
| glTF (`.gltf` + `.bin`) | **fails**: `couldn't be loaded`, exit 0 |
| GLB | **fails**: `couldn't be loaded`, exit 0 |

Godot can't export FBX, and SAT 2018.2 can't read glTF. So the plugin should bake from the source
FBX/OBJ when the mesh came from one, and otherwise write an OBJ itself from the `ArrayMesh`
(positions, normals, UV0, triangles). That's a small GDScript writer.

Conversion used for the test (Blender, background):
`blender.exe -b --factory-startup --python convert_rock.py -- <in.fbx> <out dir>`

## 4b. Full chain: bake â†’ render (verified)

```
sbsrender render
  --input "D:\07_resources\JRO\Industrial_SmartMaterials\Generators\PL_ISF_Gen_Edging01.sbsar"
  --engine d3d11pc
  --output-path D:\04_projects\SDB\validation\render
  --output-name "edging01_{outputNodeName}"
  --png-format-compression best_speed
  --set-value "$outputsize@11,11"
  --set-value "$randomseed@7"
  --set-value EdgingWidth@0.5
  --set-value GrungeScratchesAmount@0.9
  --set-entry ambient_occlusion@D:\04_projects\SDB\validation\bakes\rock01_ao_lowashigh.png
  --set-entry curvature@D:\04_projects\SDB\validation\bakes\rock01_curv_plain.png
```

Exit 0 in **1.3 s**, with no warnings. Including bakes, the whole job takes about 15 s at 2K.

The mask follows the rock's UV island, so the baked maps really drive the graph. Visually,
Edging01 (a hard-surface edge generator) doesn't fit this rock well: plain curvature gives an
almost black mask, and from-mesh curvature gives blanket noise. Reaching the design doc's goal
("wear and dirt that follow the rock's edges and cavities") needs a graph built for organic
shapes, or curvature tuning (`curvature --details`, `curvature-from-mesh --intensity`).
That is a graph question, not a pipeline question.

## 5. Read parameter metadata from the `.sbsar` XML (verified)

An `.sbsar` is a 7z archive (LZMA, solid) containing `assemblies\content\0000\<name>.sbsasm` and
`<name>.xml`. The XML sits in a subfolder, so use `e` with `-r`:

```
"C:\Program Files\7-Zip\7z.exe" e -y -r -bso0 -bsp0 -o<dir> <file.sbsar> *.xml
```

(`x ... *.xml` without `-r` extracts nothing and still exits 0.)

### Structure

```
sbsdescription formatversion="2.1"
â”” graphs/graph  pkgurl label keywords category author primaryinput
  â”œ sbspresets/sbspreset label
  â”‚   â”” presetinput identifier type uid value
  â”œ guigroups/guigroup identifier label
  â”œ outputs/output uid identifier format width height dynamicsize [usertag]
  â”‚   â”” outputgui label group visibleif
  â”‚       â”” channels/channel names="baseColor"        â† output usage
  â”” inputs/input uid identifier type default alteroutputs [usertag]
      â”” inputgui widget label group visibleif
          â”œ guislider min max step [clamp="on"]
          â”œ guicombobox/guicomboboxitem value text
          â”” guiimage colortype format
              â”” channels/channel names="ambientOcclusion"   â† image input usage
```

The XML has **defaults** (`default="0.6"`, `"0.28,0.25,0.19"`), unlike `sbsrender info`.

`type` codes seen: `0` float, `2` float3 (color), `4` int/bool, `5` image, `8` int2 (`$outputsize`).
Expected (not yet seen): `1` float2, `3` float4, `6` string, `9`/`10` int3/int4.

`widget` values seen: `slider`, `color`, `togglebutton`, `combobox`, `image`.

`visibleif` is a small expression language on other inputs, for example
`input["painted_arrows"]==true` or `input["channel_basecolor"]||input["channel_diffuse"]`.

### Plugin implications

- **Auto-wiring baked maps:** image inputs declare a usage via `guiimage/channels/channel names`
  (`ambientOcclusion`, `curvature`, ...). Wire bakes to inputs by usage, not by identifier.
  The same pattern as outputs.
- **Normal convention:** a `normal_format` input with `usertag="$normal_map_format"` is a
  combobox (0 = DirectX, 1 = OpenGL). Godot uses OpenGL (Y+), so set it to 1 when it exists.
  Otherwise flip green in the material (not yet checked visually in Godot).
- `channel_*` toggles with `visibleif` on outputs: a disabled channel's output is still
  rendered (all 8 tarmac outputs were written), so filter by these toggles or by `--input-graph-output-usage`.

## Test assets on this machine

- Rock: `D:\04_projects\SDB\assets\rock01.fbx`. Its bakes are in `validation\bakes\`, renders in
  `validation\render\`, and glTF/OBJ conversions in `validation\mesh_formats\`.

- Mesh-adaptive: `D:\07_resources\JRO\Industrial_SmartMaterials\Generators\PL_ISF_Gen_Edging01.sbsar`
  and `PL_ISF_Gen_Edging02.sbsar` (AO + curvature inputs). No graph found yet with position or
  world-normal inputs.
- Image filters: `PL_ISF_Fil_CustomWarp01`, `PL_ISF_Fil_MaskEmboss01`, `PL_ISF_Fil_MaskToOutline01`.
- None of the 22 Maya samples or the 24 ShipHulls `.sbsar` files have image inputs.

## 6. Godot side (verified, Godot 4.7 editor, headless self-test + Movie Maker render)

- `OS.execute_with_pipe(exe, args, false)` + `OS.get_process_exit_code(pid)` captures stdout,
  stderr and the exit code separately from a worker thread. Drain both non-blocking pipes in one
  loop.
- sbsrender's real exit code for a missing output folder is **303**. (The 47 seen earlier
  was 303 mod 256, as reported by the shell wrapper.)
- Write the `.import` file **before** Godot first sees a texture. The first import then uses
  those settings (`compress/normal_map=1`, `process/normal_map_invert_y`, `compress/mode=2`).
- Once a `.import` file exists, `ResourceLoader.exists()` returns true even before anything has
  been imported. Use `EditorFileSystem.get_file_type(path)` to tell new files from known ones.
  New files need `scan()` (wait until `is_scanning()` is false); known files need
  `reimport_files()`.
- `ResourceSaver.save(..., FLAG_CHANGE_PATH)` did not set `resource_path` on a new material;
  use `take_over_path()`.
- Normal conventions:
  - tarmac's `normal_format` switch inverts green exactly (mean |G_dx + G_gl − 255| = 0.06 on 8-bit).
  - Graphs with the switch are rendered as OpenGL (Godot's convention).
  - Graphs without it are DirectX and get `normal_map_invert_y` on import.
- `rock01.fbx` imports at 0.26 m across (FBX in centimetres).

Checks: `addons/substance_bridge/tests/runner_check.gd`, `backend_check.gd` (headless `--script`),
and `selftest.gd` (headless editor with `SUBSTANCE_BRIDGE_SELFTEST=<sbsar>`).
