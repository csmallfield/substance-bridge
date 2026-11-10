"""Mesh Painted Metal: a simple painted steel material driven by maps BAKED FROM THE TARGET OBJECT.

The five image inputs are not textures to author: the Substance Bridge bakes them from the mesh the material is
applied to (Bake from Selected Mesh) and plugs them in by usage:
  ambientOcclusion -> cavity dirt          curvature -> edge wear (convex) and dirt (concave)
  thickness        -> thin parts wear more  normalWS  -> dust on up-facing surfaces, streak direction
  position         -> grime gathering low, rust streaks running down in object space, seam-free 3D noise
A View dropdown shows each baked map and each mask on the object itself.
Paint over primer over bare steel; rust in cavities, around chips and in streaks.
"""
import sys, os
sys.path.insert(0, os.environ.get('SBS_SCRIPTS', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')))
from sbsgen import Package, Expr, F, F3, F4, I1, B, GRAY, COLOR, clamp01, tofloat, eq, select
from sbsops import Ops
import sbsfunc as M

pkg = Package('mesh_painted_metal')
g = pkg.graph('mesh_painted_metal', 'Mesh Painted Metal', category='Metal', author='Claude',
              description='Painted steel whose wear comes from maps BAKED FROM THE TARGET OBJECT (AO, curvature, '
                          'thickness, world normal, position). Apply it with the Substance Bridge and it bakes them '
                          'from the selected mesh: edge wear on its convex edges, dirt in its cavities, dust on its '
                          'up-facing surfaces, rust streaks running down it. View shows each baked map and mask.',
              tags='metal;painted;paint;steel;mesh;baked;curvature;ambient occlusion;thickness;edge wear;rust;dust;prop',
              physicalSize='100 100 100')
op = Ops(g, debug='--debug' in sys.argv)

MESH_GROUP = 'From Target Object (baked mesh maps)'
BAKED = ' Baked by the Substance Bridge from the mesh this material is applied to (Bake from Selected Mesh); ' \
        'not a texture to paint.'

# --- the target object's baked maps ------------------------------------------------------------------------------------
T_AO = g.image_input('ambient_occlusion', 'Target AO (baked)', 'ambientOcclusion', MESH_GROUP,
                     'Ambient occlusion of the target object: drives cavity dirt and rust.' + BAKED)
T_CURV = g.image_input('curvature', 'Target Curvature (baked)', 'curvature', MESH_GROUP,
                       'Curvature of the target object (0.5 flat, brighter convex, darker concave): convex edges wear, '
                       'concave creases collect dirt.' + BAKED)
T_THICK = g.image_input('thickness', 'Target Thickness (baked)', 'thickness', MESH_GROUP,
                        'Thickness of the target object (dark = thin): thin parts such as handles and wheels wear '
                        'through to bright steel.' + BAKED)
T_NRM = g.image_input('world_normal', 'Target World Normal (baked)', 'normalWS', MESH_GROUP,
                      'World-space normal of the target object (green = up): dust settles on up-facing surfaces; '
                      'streaks run down vertical ones.' + BAKED, gray=False)
T_POS = g.image_input('position', 'Target Position (baked)', 'position', MESH_GROUP,
                      'Position on the target object (its bounding box as 0..1, green = height): grime gathers '
                      'low, rust streaks run downward, and noise is 3D so it has no UV seams.' + BAKED, gray=False)


def slider(ident, label, default, group, desc='', vmin=0.0, vmax=1.0):
    return g.param(ident, label, F(default), group, vmin=vmin, vmax=vmax, step=0.01, desc=desc)


def colour(ident, label, rgb, group, desc=''):
    return g.param(ident, label, F4(*rgb, 1), group, widget='color', desc=desc)


def gate(amount):
    return clamp01(amount * 10.0)


VIEWS = ['Final Material', 'Target Curvature', 'Target AO', 'Target Thickness', 'Target World Normal',
         'Target Position', 'Mask: Edge Wear', 'Mask: Cavity Dirt', 'Mask: Top Dust', 'Mask: Low Grime',
         'Mask: Rust', 'Mask: Thin Parts']
VIEW = tofloat(g.param('view', 'View', I1(0), 'View', widget='dropdownlist',
                       options='0;' + ';'.join('%d;%s' % (i, v) for i, v in enumerate(VIEWS)),
                       desc='Final Material, or show a map baked from the target object, or one of the masks it '
                            'drives, as the base colour on the object.'))

PAINT = colour('paint_color', 'Paint', (0.13, 0.26, 0.2), 'Paint')
PAINT_R = slider('paint_roughness', 'Paint Roughness', 0.45, 'Paint')
PRIMER = colour('primer_color', 'Primer', (0.3, 0.3, 0.31), 'Paint', 'Shows where the paint is worn thin (grey, or red oxide).')
STEEL = colour('steel_color', 'Bare Steel', (0.56, 0.56, 0.57), 'Paint')
STEEL_R = slider('steel_roughness', 'Steel Roughness', 0.3, 'Paint')
PEEL = slider('orange_peel', 'Orange Peel', 0.4, 'Paint', 'Fine paint texture in the normal.')

EDGE = slider('edge_wear', 'Edge Wear', 0.5, 'Edge Wear (target curvature)',
              'Paint worn off the target object\'s convex edges.')
EDGE_W = slider('edge_width', 'Edge Width', 0.5, 'Edge Wear (target curvature)',
                'How far wear reaches from the edges: higher includes softer curvature.')
BREAK = slider('edge_breakup', 'Breakup', 0.6, 'Edge Wear (target curvature)', 'Chipped, broken edge instead of a clean line.')
THIN = slider('thin_wear', 'Thin Parts Wear', 0.5, 'Edge Wear (target curvature)',
              'Extra wear and polish on the thin parts of the target object (from its baked thickness).')

DIRT = slider('dirt', 'Cavity Dirt', 0.5, 'Dirt and Dust (target AO, normal, position)',
              'Dirt in the target object\'s cavities and concave creases.')
DIRTC = colour('dirt_color', 'Dirt Colour', (0.07, 0.06, 0.05), 'Dirt and Dust (target AO, normal, position)')
LOW = slider('low_grime', 'Low Grime', 0.4, 'Dirt and Dust (target AO, normal, position)',
             'Grime gathering on the lower part of the target object.')
LOW_H = slider('low_grime_height', 'Low Grime Height', 0.3, 'Dirt and Dust (target AO, normal, position)',
               'How high up the object the grime reaches.')
DUST = slider('dust', 'Top Dust', 0.35, 'Dirt and Dust (target AO, normal, position)',
              'Dust on the target object\'s up-facing surfaces.')
DUSTC = colour('dust_color', 'Dust Colour', (0.42, 0.39, 0.34), 'Dirt and Dust (target AO, normal, position)')

RUST = slider('rust', 'Rust', 0.3, 'Rust (target AO, normal, position)', 'Rust in cavities and blooming from chips.')
STREAKS = slider('rust_streaks', 'Rust Streaks', 0.4, 'Rust (target AO, normal, position)',
                 'Streaks running down the target object\'s vertical surfaces.')
STREAK_L = slider('streak_length', 'Streak Length', 0.4, 'Rust (target AO, normal, position)')
RUSTC = colour('rust_color', 'Rust Colour', (0.2, 0.085, 0.035), 'Rust (target AO, normal, position)')

NOISE_SCALE = slider('noise_scale', 'Noise Scale', 0.5, 'Output', '3D noise scale on the object (position based).')
NORMAL = g.param('normal_intensity', 'Normal Intensity', F(3.0), 'Output', vmin=0, vmax=20, step=0.1)
NORMAL_FORMAT = g.param('normal_format', 'Normal Format', I1(0), 'Output', widget='dropdownlist',
                        options='0;0;DirectX;1;OpenGL', desc='DirectX (Substance default) or OpenGL (Godot, Blender).')

# --- maps as greys at 16 bit --------------------------------------------------------------------------------------------
curv = op.lv(T_CURV, fmt=True)
ao = op.lv(T_AO, fmt=True)
thick = op.lv(T_THICK, fmt=True)
pos_y = op.channel(T_POS, 1)
nrm_y = op.channel(T_NRM, 1)


def noise3d(scale, seed, rough=1.0, lo=1, hi=7):
    n = g.inst('3d_perlin_noise.sbs', '3D_perlin_noise_fractal', {'position': T_POS}, outs=[('output', GRAY)], fmt=True,
               seed_offset=seed, scale=scale * (0.4 + 1.2 * NOISE_SCALE), min_level=I1(lo), max_level=I1(hi),
               roughness=F(rough))
    return op.auto_levels(n)


n_big = noise3d(3.0, 11)
n_mid = noise3d(9.0, 12)
n_fine = noise3d(28.0, 13, 1.2, 2, 7)
n_chip = noise3d(9.0, 14, 1.2, 2, 7)
R = (0.1, 0.9)

# --- masks (every one built from the target object's maps) --------------------------------------------------------------
convex = op.lv(curv, in_lo=0.61 - 0.07 * EDGE_W, in_hi=0.69 - 0.07 * EDGE_W, fmt=True)
concave = op.lv(curv, in_lo=0.36, in_hi=0.5, out_lo=1.0, out_hi=0.0, fmt=True)
cavity_ao = op.lv(ao, in_lo=0.5, in_hi=0.95, out_lo=1.0, out_hi=0.0, fmt=True)
thin = op.lv(thick, in_lo=0.15, in_hi=0.55, out_lo=1.0, out_hi=0.0, fmt=True)

# edge wear: convex edges, widened on thin parts, broken up by 3D chip noise
edge_src = convex
brk = op.lv(n_chip, in_lo=0.15, in_hi=0.85)
edge_src = op.blend(op.lv(brk, out_lo=1.0 - BREAK, out_hi=1.0), edge_src, op.MUL, fmt=True)
edge_wear = op.lv(edge_src, in_lo=0.62 - EDGE * 0.45, in_hi=0.8 - EDGE * 0.45)
edge_wear = op.blend(op.gray(gate(EDGE)), edge_wear, op.MUL)
edge_wear = op.blend(op.lv(thin, out_lo=1.0, out_hi=0.15), edge_wear, op.MUL)        # thin parts polish instead (below)
# thin parts (target thickness): worn smooth to bright steel by handling, strongest where also convex
polish = op.blend(op.lv(thin, in_lo=0.2, in_hi=0.8), op.lv(convex, out_lo=0.45, out_hi=1.0), op.MUL)
polish = op.blend(op.lv(n_big, in_lo=0.1, in_hi=0.8, out_lo=0.55, out_hi=1.1), polish, op.MUL)
polish = op.lv(polish, in_lo=0.75 - THIN * 0.6, in_hi=0.95 - THIN * 0.6)
polish = op.blend(op.gray(gate(THIN)), polish, op.MUL)
op.debug('polish', polish)
to_steel = op.lv(edge_src, in_lo=0.82 - EDGE * 0.4, in_hi=0.95 - EDGE * 0.4)             # worn through the primer
to_steel = op.blend(edge_wear, to_steel, op.MUL)
op.debug('edge_wear', edge_wear)

# cavity dirt: AO and concave curvature
dirt_src = op.blend(cavity_ao, op.lv(concave, out_hi=0.8), op.MAX)
dirt_src = op.blend(op.lv(n_mid, in_lo=0.1, in_hi=0.8, out_lo=0.45, out_hi=1.2), dirt_src, op.MUL)
dirt = op.lv(dirt_src, in_lo=0.5 - DIRT * 0.4, in_hi=0.8 - DIRT * 0.4)
dirt = op.blend(op.gray(gate(DIRT)), dirt, op.MUL)

# low grime: height on the object
low_src = op.lv(pos_y, in_lo=0.0, in_hi=0.02 + LOW_H * 0.6, out_lo=1.0, out_hi=0.0, fmt=True)
low_src = op.blend(op.lv(n_big, in_lo=0.1, in_hi=0.85, out_lo=0.5, out_hi=1.15), low_src, op.MUL)
low = op.lv(low_src, in_lo=0.45 - LOW * 0.35, in_hi=0.75 - LOW * 0.35)
low = op.blend(op.gray(gate(LOW)), low, op.MUL)

# top dust: world normal pointing up, less on edges that wear
up = op.lv(nrm_y, in_lo=0.78, in_hi=0.97, fmt=True)
dust_src = op.blend(op.lv(n_mid, in_lo=0.15, in_hi=0.8, out_lo=0.35, out_hi=1.1), up, op.MUL)
dust_src = op.blend(op.lv(cavity_ao, out_lo=1.0, out_hi=1.35), dust_src, op.MUL)
dust = op.lv(dust_src, in_lo=0.6 - DUST * 0.5, in_hi=0.85 - DUST * 0.5)
dust = op.blend(op.gray(gate(DUST)), dust, op.MUL)
dust = op.blend(op.lv(edge_wear, out_lo=1.0, out_hi=0.3), dust, op.MUL)

# rust streaks: a Pixel Processor reading the baked position and normal, streaks in object space
x, y = M.pos()
pc = M.sample_color(0, x, y, 1)
nc = M.sample_color(1, x, y, 1)
px, py, pz = M.swz(pc, 0), M.swz(pc, 1), M.swz(pc, 2)
nx, ny, nz = M.swz(nc, 0) * 2.0 - 1.0, M.swz(nc, 1) * 2.0 - 1.0, M.swz(nc, 2) * 2.0 - 1.0
vert = M.clamp(1.0 - M.fabs(ny) * 1.8)
ax_, az_ = M.fabs(nx), M.fabs(nz)
wx = ax_ / (ax_ + az_ + 1e-4)
side = M.sel(M.gt(nx * 1.0 + nz * 0.37, 0.0), 0.0, 0.5)              # opposite faces get different streaks
hcoord = wx * pz + (1.0 - wx) * px + side
K = 70.0
hc = hcoord * K + 0.6 * M.fsin(py * 23.0 + M.floor(hcoord * K) * 1.7) * 0.25
cell = M.floor(hc)
f = M.frac(hc) - 0.5
r1, r2, r3, r4 = M.hash2(cell, 1.0, 5.0), M.hash2(cell, 2.0, 5.0), M.hash2(cell, 3.0, 5.0), M.hash2(cell, 4.0, 5.0)
density = STREAKS
present = M.b01(M.lt(r1, density))
wid = 0.12 + 0.35 * r2
line = M.clamp(1.0 - M.fabs(f) / wid)
y0 = 0.3 + 0.75 * r3
L = (0.08 + 0.8 * STREAK_L) * (0.35 + 0.65 * r4)
t = (y0 - py) / L
fade = M.clamp(1.0 - t) * M.b01(M.gt(t, 0.0)) * M.clamp(t * 8.0)
streak_v = present * line * fade * vert * M.b01(M.gt(M.swz(pc, 3), 0.5))
streak_pp = g.filter('pixelprocessor', {'input': T_POS, 'input:1': T_NRM}, out=GRAY, fmt=True, colorswitch=B(False),
                     perpixel=streak_v)
streaks = op.blend(op.lv(n_fine, in_lo=0.2, in_hi=0.8, out_lo=0.4, out_hi=1.0), op.blur(streak_pp, 0.4, fmt=True), op.MUL)
streaks = op.blend(op.gray(gate(STREAKS)), streaks, op.MUL)
op.debug('streaks', streaks)

# rust: cavities, blooming around chips, plus streaks
rust_cav = op.blend(op.lv(n_big, in_lo=0.15, in_hi=0.85, out_lo=0.3, out_hi=1.1), cavity_ao, op.MUL)
bloom = op.blend(to_steel, op.blur(to_steel, 2.5, fmt=True), op.SUB, fmt=True)        # a ring around chips, not on them
bloom = op.lv(bloom, in_lo=0.01, in_hi=0.15)
bloom = op.blend(op.lv(thin, out_lo=1.0, out_hi=0.2), bloom, op.MUL)                 # polished thin parts don't rust
rust_src = op.blend(rust_cav, op.blend(bloom, op.lv(n_chip, in_lo=0.2, in_hi=0.8), op.MUL), op.MAX)
rust = op.lv(rust_src, in_lo=0.6 - RUST * 0.45, in_hi=0.8 - RUST * 0.45)
rust = op.blend(op.gray(gate(RUST)), rust, op.MUL)
rust = op.blend(op.lv(streaks, out_hi=0.85), rust, op.MAX)
op.debug('rust', rust)

# --- colour, roughness, metallic, height ------------------------------------------------------------------------------
paint_c = op.mottle(op.mottle(op.color(PAINT), n_big, 0.06, R), n_fine, 0.04, R)
primer_c = op.mottle(op.color(PRIMER), n_fine, 0.12, R)
steel_c = op.mottle(op.mottle(op.color(STEEL), n_fine, 0.1, R), n_mid, 0.08, R)
rust_c = op.mottle(op.mottle(op.color(RUSTC), n_fine, 0.35, R), n_big, 0.2, R)
col = op.lerp(paint_c, primer_c, edge_wear)
col = op.lerp(col, steel_c, to_steel)
col = op.lerp(col, op.mottle(op.color(STEEL), n_mid, 0.06, R), polish)                 # polished thin parts
col = op.lerp(col, rust_c, rust)
col = op.blend(op.color(DIRTC), col, op.COPY, mask=low, opacity=0.8)
col = op.blend(op.color(DIRTC), col, op.COPY, mask=dirt, opacity=0.85)
col = op.lerp(col, op.mottle(op.color(DUSTC), n_fine, 0.12, R), dust)

rg = op.gray
rough = op.lv(n_mid, out_lo=PAINT_R - 0.05, out_hi=PAINT_R + 0.05)
rough = op.lerp(rough, rg(0.6), edge_wear)
rough = op.lerp(rough, op.lv(n_fine, out_lo=STEEL_R - 0.08, out_hi=STEEL_R + 0.08), to_steel)
rough = op.lerp(rough, op.lv(n_big, out_lo=STEEL_R - 0.08, out_hi=STEEL_R - 0.04), polish)
rough = op.lerp(rough, op.lv(n_fine, out_lo=0.72, out_hi=0.92), rust)
rough = op.lerp(rough, rg(0.85), low)
rough = op.lerp(rough, rg(0.88), dirt)
rough = op.lerp(rough, rg(0.95), dust)

metallic = op.blend(rust, op.blend(to_steel, polish, op.MAX), op.SUB)
metallic = op.blend(dirt, metallic, op.SUB)
metallic = op.blend(dust, metallic, op.SUB)

# height: paint layer thickness (chips are shallow pits) + orange peel; normal from it (detail only: the mesh's own
# shape comes from its geometry)
height = op.lv(edge_wear, out_lo=0.5, out_hi=0.44, fmt=True)                             # paint is thin: shallow chips
height = op.lerp(height, rg(0.4), to_steel, fmt=True)
height = op.lerp(height, rg(0.47), polish, fmt=True)                                    # worn smooth
height = op.blend(op.lv(rust, out_hi=0.08), height, op.ADD, fmt=True)
peel = op.lv(n_fine, out_hi=0.03 * PEEL)
peel = op.blend(op.inv(op.blend(polish, to_steel, op.MAX)), peel, op.MUL)              # no paint texture on bare steel
n_src = op.blend(peel, height, op.ADD, fmt=True)
normal = g.filter('normal', {'input1': n_src}, out=COLOR, intensity=NORMAL, inversedy=M.gt(tofloat(NORMAL_FORMAT), 0.5))

# --- View: show a baked map or a mask on the object ---------------------------------------------------------------------
def heat(m):
    """Grey mask -> black-to-orange so masks read on the object."""
    return op.lerp(op.color((0.02, 0.02, 0.025)), op.color((1.0, 0.55, 0.12)), m)


views = [None, op.to_color(curv), op.to_color(ao), op.to_color(thick), T_NRM, T_POS, heat(edge_wear), heat(dirt),
         heat(dust), heat(low), heat(rust), heat(op.blend(op.lv(thin, out_hi=0.5), polish, op.MAX))]
is_final = op.gray(select(eq(VIEW, 0.0), 1.0, 0.0))
shown = col
for k in range(1, len(views)):
    shown = op.lerp(shown, views[k], op.gray(select(eq(VIEW, float(k)), 1.0, 0.0)))
not_final = op.inv(is_final)
rough_out = op.lerp(rough, rg(0.8), not_final)
metal_out = op.lerp(metallic, rg(0.0), not_final)
normal_out = op.lerp(normal, op.color((0.5, 0.5, 1.0)), not_final)

g.output('basecolor', 'Base Color', 'baseColor', shown)
g.output('normal', 'Normal', 'normal', normal_out)
g.output('roughness', 'Roughness', 'roughness', rough_out, gray=True)
g.output('metallic', 'Metallic', 'metallic', metal_out, gray=True)
g.output('ambientocclusion', 'Ambient Occlusion', 'ambientOcclusion', ao, gray=True)
g.output('height', 'Height', 'height', height, gray=True)


# --- presets ------------------------------------------------------------------------------------------------------------
def look(name, paint, **kw):
    g.preset(name, paint_color=(*paint, 1), **kw)


look('Industrial Green', (0.13, 0.26, 0.2))
look('Fresh Paint', (0.13, 0.26, 0.2), edge_wear=0.12, thin_wear=0.0, dirt=0.15, low_grime=0.1, dust=0.1, rust=0.0,
     rust_streaks=0.0, paint_roughness=0.35)
look('Safety Yellow', (0.62, 0.45, 0.04), edge_wear=0.6, dirt=0.55, low_grime=0.5, dust=0.4, rust=0.25,
     rust_streaks=0.3, primer_color=(0.3, 0.3, 0.3, 1))
look('Fire Red', (0.45, 0.04, 0.03), edge_wear=0.45, rust=0.35, rust_streaks=0.45, paint_roughness=0.35,
     primer_color=(0.32, 0.32, 0.33, 1))
look('Navy Grey', (0.24, 0.27, 0.3), primer_color=(0.34, 0.14, 0.09, 1), edge_wear=0.55, dirt=0.4, dust=0.25, rust=0.45, rust_streaks=0.6,
     streak_length=0.6)
look('Abandoned', (0.2, 0.3, 0.33), edge_wear=0.85, edge_width=0.75, thin_wear=0.8, dirt=0.8, low_grime=0.75,
     low_grime_height=0.45, dust=0.7, rust=0.8, rust_streaks=0.85, streak_length=0.75, paint_roughness=0.7)
look('Debug: Curvature', (0.13, 0.26, 0.2), view=1)
look('Debug: Edge Wear Mask', (0.13, 0.26, 0.2), view=6)
op.finish(pkg, __file__, globals())
