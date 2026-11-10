"""Techno Grid: a square, tileable "greeble city" layer with lots of transparent negative space, meant to be stacked
on 5+ planes with a different Seed each (see ANALYSIS.md). Rods and beams, modules (grille, machine, tank, fins,
grating, louvre, panel, manifold, electronics), long pipes with smooth and greeble stretches, sagging cable bundles.
Layout: techno_layout.py in three Pixel Processors (frame + cables, modules, pipes), recombined with max.
Treatments: palette + painted / Bare Metal + edge wear (dry-brushed edges), grime, dust, oil leaks, patina, rust.
"""
import sys, os
sys.path.insert(0, os.environ.get('SBS_SCRIPTS', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sbsgen import Package, Expr, F, F4, I1, B, GRAY, COLOR, clamp01, tofloat, vec2
from sbsops import Ops
import sbsfunc as M
import techno_layout as K

pkg = Package('techno_grid')
g = pkg.graph('techno_grid', 'Techno Grid', category='Sci-Fi', author='Claude',
              description='A tileable techno greeble grid with transparent gaps: rods, beams, detailed modules, long '
                          'pipes and cable bundles. Stack several planes with different Seeds for deep infrastructure.',
              tags='scifi;greeble;grid;pipes;cables;modules;alpha;opacity;stack;industrial;kitbash',
              physicalSize='100 100 10')
op = Ops(g, debug='--debug' in sys.argv)


def slider(ident, label, default, group, desc='', vmin=0.0, vmax=1.0):
    return g.param(ident, label, F(default), group, vmin=vmin, vmax=vmax, step=0.01, desc=desc)


def colour(ident, label, rgb, group, desc=''):
    return g.param(ident, label, F4(*rgb, 1), group, widget='color', desc=desc)


def gate(amount):
    return clamp01(amount * 10.0)


# --- controls --------------------------------------------------------------------------------------------------
SEED = tofloat(g.param('seed', 'Seed', I1(0), 'Layout', vmin=0, vmax=300, step=1,
                       desc='A different layout per value. Use a different Seed on each stacked plane.'))
MODS = slider('modules', 'Modules', 0.58, 'Layout', 'Share of module slots that are filled.')
PIPES = slider('pipes', 'Pipes', 0.3, 'Layout', 'Share of pipe lanes in use.')
CABLES = slider('cables', 'Cables', 0.75, 'Layout', 'Share of cable bundles present.')
RODS = slider('rods', 'Rods', 0.38, 'Layout', 'Thin rods in the back mesh.')
BEAMS = slider('beams', 'Beams', 0.72, 'Layout', 'Main beams between the modules.')

FRAME = colour('frame_color', 'Frame', (0.075, 0.075, 0.08), 'Palette', 'Rods, beams and gratings.')
BODY = colour('body_color', 'Body', (0.1, 0.1, 0.105), 'Palette', 'Module plates, panels, tanks, boxes.')
BODYB = colour('body_b_color', 'Body B', (0.065, 0.065, 0.07), 'Palette', 'Raised blocks and alternate panels.')
PIPE = colour('pipe_color', 'Pipes', (0.11, 0.11, 0.115), 'Palette')
PIPEB = colour('pipe_b_color', 'Pipes B', (0.16, 0.15, 0.14), 'Palette', 'Alternate pipes and branch stubs.')
DARK = colour('dark_color', 'Dark Parts', (0.035, 0.035, 0.04), 'Palette', 'Electronics, fins, caps.')
ACCENT = colour('accent_color', 'Valves', (0.3, 0.06, 0.04), 'Palette', 'Valve wheels.')
BRASS = colour('brass_color', 'Brass', (0.7, 0.53, 0.26), 'Palette', 'Brass mesh and labels.')
CABLE = colour('cable_color', 'Cables', (0.04, 0.04, 0.042), 'Palette')
CABLEB = colour('cable_b_color', 'Cables B', (0.13, 0.11, 0.08), 'Palette', 'Some cables in each bundle.')

PAINT_R = slider('paint_roughness', 'Paint Roughness', 0.55, 'Material')
METAL_R = slider('metal_roughness', 'Metal Roughness', 0.38, 'Material')
BARE = slider('bare_metal', 'Bare Metal', 0.0, 'Material', '0 painted, 1 bare metal: metallic and brushed.')
PIPE_METAL = slider('pipe_metal', 'Metal Pipes', 0.0, 'Material', 'Pipes as polished metal in the pipe colours (copper, brass, steel).')
CAVITY = slider('cavity_darkening', 'Cavity Darkening', 0.55, 'Material')
DETAIL = slider('surface_detail', 'Surface Detail', 0.35, 'Material', 'Fine dents and waviness in the normal.')

GLOW = slider('light_intensity', 'Light Intensity', 2.0, 'Lights', vmax=8.0)
LAMP = colour('lamp_color', 'Lamps', (1.0, 0.7, 0.35), 'Lights', 'Indicator lights on the machine blocks.')

EDGE = slider('edge_wear', 'Edge Wear', 0.45, 'Wear', 'Paint worn off raised edges to bare steel (a dry-brushed look).')
SCRATCHES = slider('scratches', 'Scratches', 0.25, 'Wear')
GRIME = slider('grime', 'Grime', 0.4, 'Wear', 'Dark dirt in corners and cavities.')
DUST = slider('dust', 'Dust', 0.3, 'Wear', 'Pale dust on top ledges and in cavities.')
DUSTC = colour('dust_color', 'Dust Colour', (0.33, 0.31, 0.28), 'Wear')
LEAKS = slider('leaks', 'Oil Leaks', 0.15, 'Wear', 'Dark glossy oil around flanges, valves and boxes.')
PATINA = slider('patina', 'Patina', 0.25, 'Wear', 'Verdigris on the brass.')
RUST = slider('rust', 'Rust', 0.0, 'Wear', 'Rust in cavities and blooming out of worn edges.')
RUSTC = colour('rust_color', 'Rust Colour', (0.16, 0.075, 0.04), 'Wear')

AO_STRENGTH = slider('ao_strength', 'AO Strength', 1.0, 'Output', vmin=0.2, vmax=3.0)
AO_RANGE = 0.22 / AO_STRENGTH
NORMAL = g.param('normal_intensity', 'Normal Intensity', F(9.0), 'Output', vmin=0, vmax=20, step=0.1)
NORMAL_FORMAT = g.param('normal_format', 'Normal Format', I1(0), 'Output', widget='dropdownlist',
                        options='0;0;DirectX;1;OpenGL', desc='DirectX (Substance default) or OpenGL (Godot, Blender).')

# --- height, material ID, random: three Pixel Processors combined with max ---------------------------------------------
N_IDS = K.ID_SCALE
KW = dict(modules_amt=MODS, pipes_amt=PIPES, cables=CABLES, rods_amt=RODS, beams_amt=BEAMS)


def chan(img, k):
    w = [0.0, 0.0, 0.0, 0.0]
    w[k] = 1.0
    return g.filter('grayscaleconversion', {'input1': img}, out=GRAY, fmt=3, channelsweights=F4(*w))


parts = []
for part in K.PARTS:
    x, y = M.pos()
    A = K.layout_part(M, x, y, part, SEED, **KW)
    s = A.c * N_IDS
    idv = M.floor(s)
    r = M.clamp((s - idv - 0.1) / 0.8)
    v = Expr('vector4', 2048, args={'componentsin': Expr('vector3', 1024, args={
        'componentsin': vec2(A.h, (idv + 0.5) / N_IDS), 'componentslast': r}), 'componentslast': M.c(0.0)})
    img = g.filter('pixelprocessor', out=COLOR, fmt=3, colorswitch=B(True), perpixel=v)
    parts.append((chan(img, 0), chan(img, 1), chan(img, 2)))

H, IDM, RND = parts[0]
for hB, iB, rB in parts[1:]:
    m = op.lv(op.blend(H, hB, op.SUB, fmt=3), in_lo=0.0, in_hi=1e-5, fmt=3)        # B on top
    H = op.blend(H, hB, op.MAX, fmt=3)
    IDM = op.lerp(IDM, iB, m, fmt=3)
    RND = op.lerp(RND, rB, m, fmt=3)

height = op.lv(H, fmt=True)
ALPHA = op.lv(H, in_lo=0.0015, in_hi=0.0025, fmt=True)
op.debug('height', height)
occl = None
for blur_amt, weight in ((1.5, 0.4), (5.0, 0.3), (14.0, 0.16)):
    cv = op.blend(height, op.blur(height, blur_amt, fmt=True), op.SUB, fmt=True)
    cv = op.lv(cv, out_hi=weight / 0.4, fmt=True)
    occl = cv if occl is None else op.blend(cv, occl, op.MAX, fmt=True)
ao = op.lv(occl, in_lo=0.0, in_hi=AO_RANGE, out_lo=1.0, out_hi=0.25, fmt=True)


def cls(name):
    i = K.IDS[name]
    lo, hi = i / N_IDS, (i + 1) / N_IDS
    return op.blend(op.lv(IDM, in_lo=lo, in_hi=lo + 1e-4, fmt=True),
                    op.lv(IDM, in_lo=hi, in_hi=hi + 1e-4, out_lo=1.0, out_hi=0.0, fmt=True), op.MUL, fmt=True)


CM = {n: op.blur(cls(n), 0.3, fmt=True) for n in K.IDS if n != 'none'}


def any_of(*names):
    m = CM[names[0]]
    for n in names[1:]:
        m = op.blend(CM[n], m, op.MAX, fmt=True)
    return m


def scale(col, k):
    return op.blend(op.color((k, k, k)), col, op.MUL)


F_FRAME = any_of('rod', 'beam', 'grating')
F_BODY = any_of('plate', 'tank', 'louvre', 'panel', 'gbox')
F_BODYB = any_of('plate_dark', 'panel_alt')
F_PIPE = any_of('pipe', 'flange', 'clamp')
F_DARK = any_of('detail', 'chip', 'fin', 'cap', 'tie')
F_CABLE = CM['cable']
F_STEEL = any_of('bolt', 'grille')
METAL = any_of('bolt', 'brass', 'grille')
PAINTED = any_of('rod', 'beam', 'grating', 'plate', 'tank', 'louvre', 'panel', 'gbox', 'plate_dark', 'panel_alt',
                 'pipe', 'pipe_alt', 'flange', 'clamp', 'valve', 'detail', 'fin', 'cap')
WEARS = any_of('rod', 'beam', 'grating', 'plate', 'tank', 'louvre', 'panel', 'gbox', 'plate_dark', 'panel_alt',
               'pipe', 'pipe_alt', 'flange', 'clamp', 'valve', 'fin')

# --- noises ---------------------------------------------------------------------------------------------------------------
def noise(pkg_, seed, **kw):
    return op.auto_levels(op.noise(pkg_, seed_offset=seed, **kw))


def streaks(seed, angle):
    return op.auto_levels(g.filter('dirmotionblur', {'input1': op.noise('bnw_spots_2.sbs', seed_offset=seed)},
                                   out=GRAY, fmt=True, intensity=F(30.0), mblurangle=F(angle)))


R = (0.1, 0.9)
n_clouds = noise('clouds_2.sbs', 21)
n_big = noise('clouds_1.sbs', 22)
n_dirt = noise('dirt_3.sbs', 23)
n_grunge = noise('grunge_map_002.sbs', 24)
n_fine = noise('bnw_spots_3.sbs', 25)
stipple = noise('bnw_spots_2.sbs', 27)
n_dent = noise('bnw_spots_2.sbs', 28)
n_wave = noise('clouds_3.sbs', 29)
n_grunge2 = noise('grunge_map_007.sbs', 30)
n_moist = noise('moisture_noise.sbs', 35)
brush = streaks(26, 0.0)

# normal: height plus fine relief where the layer is
relief = op.blend(op.lv(n_wave, out_hi=0.35), op.blend(op.lv(n_fine, out_hi=0.25), op.lv(n_dent, out_hi=0.5), op.ADD),
                  op.ADD)
relief = op.blend(op.lv(ALPHA, in_lo=0.5, in_hi=0.9, fmt=True), relief, op.MUL)
relief = op.blend(op.gray(DETAIL * 0.006), relief, op.MUL, fmt=True)
n_src = op.blend(relief, op.blur(height, 0.25, fmt=True), op.ADD, fmt=True)
normal = g.filter('normal', {'input1': n_src}, out=COLOR, intensity=NORMAL, inversedy=M.gt(tofloat(NORMAL_FORMAT), 0.5))

# --- wear masks -------------------------------------------------------------------------------------------------------
hp = op.blend(op.blur(height, 1.0, fmt=True), height, op.SUB, fmt=True)
edges = op.lv(hp, in_lo=0.008, in_hi=0.04, fmt=True)
wide_edges = op.lv(op.blur(edges, 0.6, fmt=True), in_lo=0.08, in_hi=0.45, fmt=True)
chips = op.blend(op.lv(stipple, in_lo=0.4, in_hi=0.8), op.lv(n_grunge, in_lo=0.3, in_hi=0.75), op.MUL)
chips = op.lv(op.blend(chips, wide_edges, op.MUL), in_lo=0.22 - EDGE * 0.12, in_hi=0.42 - EDGE * 0.12)
edge_line = op.blend(op.lv(edges, out_hi=0.8), op.lv(n_grunge, in_lo=0.1, in_hi=0.6, out_lo=0.25, out_hi=1.0), op.MUL)
edge_wear = op.blend(op.gray(gate(EDGE) * EDGE * 1.3), op.blend(op.blend(edge_line, chips, op.MAX), WEARS, op.MUL),
                     op.MUL)
op.debug('edge_wear', edge_wear)

scr = None
for k, (rot, rv) in enumerate(((10.0, 50.0), (-75.0, 160.0), (35.0, 25.0))):
    s_ = op.lv(noise('scratches_1.sbs', 31 + k, Rotation=F(rot), Rotation_Var=F(rv)), in_lo=0.3, in_hi=0.6)
    scr = s_ if scr is None else op.blend(s_, scr, op.MAX)
scratches = op.blend(op.blend(scr, op.lv(n_big, in_lo=0.4, in_hi=0.85), op.MUL), WEARS, op.MUL)
scratches = op.blend(op.gray(SCRATCHES * 1.3), scratches, op.MUL)

cavity = op.lv(ao, in_lo=0.35, in_hi=0.95, out_lo=1.0, out_hi=0.0, fmt=True)
grime = op.blend(op.lv(n_dirt, in_lo=0.15, in_hi=0.8, out_lo=0.35, out_hi=1.0), cavity, op.MUL)
grime = op.lv(grime, in_lo=0.3 - GRIME * 0.25, in_hi=0.65 - GRIME * 0.3)
grime = op.blend(op.gray(gate(GRIME)), grime, op.MUL)
ledge = op.lv(op.blend(op.blur(height, 1.5, fmt=True), height, op.SUB, fmt=True), in_lo=0.0, in_hi=0.03, fmt=True)
dust = op.blend(op.blend(op.lv(ledge, out_hi=0.6), op.lv(cavity, out_lo=0.0, out_hi=0.8), op.MAX),
                op.lv(n_dirt, in_lo=0.1, in_hi=0.75), op.MUL)
dust = op.blend(op.lv(n_grunge2, in_lo=0.1, in_hi=0.8, out_lo=0.4), dust, op.MUL)
dust = op.lv(dust, in_lo=0.45 - DUST * 0.35, in_hi=0.75 - DUST * 0.35)
dust = op.blend(op.gray(gate(DUST)), op.blend(dust, ALPHA, op.MUL), op.MUL)
op.debug('dust', dust)
leakw = op.lv(op.blur(any_of('flange', 'valve', 'gbox', 'clamp'), 5.0, fmt=True), in_lo=0.0, in_hi=0.35, fmt=True)
leak = op.blend(leakw, op.lv(n_moist, in_lo=0.15, in_hi=0.75, out_lo=0.2, out_hi=1.3), op.MUL)
leak = op.lv(leak, in_lo=0.65 - LEAKS * 0.45, in_hi=0.8 - LEAKS * 0.45)
leak = op.blend(op.gray(gate(LEAKS)), op.blend(leak, ALPHA, op.MUL), op.MUL)
op.debug('leak', leak)
patina = op.blend(CM['brass'], op.blend(op.lv(cavity, out_lo=0.3), op.lv(n_grunge, in_lo=0.2, in_hi=0.8), op.MUL), op.MUL)
patina = op.lv(patina, in_lo=0.55 - PATINA * 0.45, in_hi=0.75 - PATINA * 0.45)
patina = op.blend(op.gray(gate(PATINA)), patina, op.MUL)
rust_field = op.blend(op.lv(n_grunge, in_lo=0.1, in_hi=0.85, out_lo=0.25, out_hi=1.0), op.lv(cavity, in_hi=0.5), op.MUL)
rust_field = op.blend(op.lv(n_dirt, in_lo=0.2, in_hi=0.8, out_lo=0.6, out_hi=1.0), rust_field, op.MUL)
rust = op.lv(rust_field, in_lo=0.45 - RUST * 0.4, in_hi=0.7 - RUST * 0.4)
spread = op.lv(op.blur(edge_wear, 3.0, fmt=True), in_lo=0.02, in_hi=0.2)
bloom = op.blend(op.lv(n_grunge, in_lo=0.2, in_hi=0.75), spread, op.MUL)
bloom = op.blend(op.lv(n_dirt, in_lo=0.1, in_hi=0.7, out_lo=0.3), bloom, op.MUL)
bloom = op.lv(bloom, in_lo=0.55 - RUST * 0.45, in_hi=0.75 - RUST * 0.45)
rust = op.blend(bloom, rust, op.MAX)
rust = op.blend(op.gray(gate(RUST)), op.blend(rust, op.blend(PAINTED, METAL, op.MAX), op.MUL), op.MUL)
op.debug('rust', rust)

# --- colour ---------------------------------------------------------------------------------------------------------------
def tone(c, a=0.08, b=0.12):
    return op.mottle(op.mottle(op.color(c), n_clouds, a, R), RND, b, (0.0, 1.0))


col = tone(FRAME, 0.1, 0.15)
for fam, c_ in ((F_BODY, tone(BODY)), (F_BODYB, tone(BODYB)), (F_PIPE, tone(PIPE, 0.08, 0.1)),
                (CM['pipe_alt'], tone(PIPEB, 0.08, 0.1)), (F_DARK, tone(DARK, 0.15, 0.2)),
                (CM['valve'], tone(ACCENT, 0.1, 0.1)),
                (F_STEEL, op.mottle(op.mottle(op.color((0.42, 0.42, 0.43)), n_clouds, 0.1, R), brush, 0.08, R)),
                (CM['brass'], op.mottle(op.color(BRASS), n_clouds, 0.15, R)),
                (F_CABLE, tone(CABLE, 0.05, 0.1)), (CM['cable_alt'], tone(CABLEB, 0.05, 0.15)),
                (CM['light'], op.color(LAMP))):
    col = op.lerp(col, c_, fam)
bare_m = op.blend(op.gray(BARE), op.blend(WEARS, op.inv(CM['valve']), op.MUL), op.MUL)
pm = op.blend(op.gray(PIPE_METAL), any_of('pipe', 'pipe_alt', 'flange', 'clamp'), op.MUL)
bare_c = op.mottle(op.mottle(op.color((0.5, 0.505, 0.51)), brush, 0.08, R), n_dirt, 0.12, R)
col = op.lerp(col, bare_c, bare_m)
col = op.lerp(col, op.mottle(op.color((0.2, 0.42, 0.34)), n_fine, 0.25, R), patina)
col = op.lerp(col, op.mottle(op.mottle(op.color(RUSTC), n_fine, 0.3, R), n_clouds, 0.2, R), rust)
worn = op.mottle(op.color((0.5, 0.5, 0.51)), n_fine, 0.15, R)                  # bare steel under the paint
primer = op.lerp(op.color((0.3, 0.3, 0.31)), worn, op.gray(BARE))
col = op.lerp(col, op.lerp(primer, worn, op.lv(chips, in_lo=0.3, in_hi=0.7)), edge_wear)
col = op.lerp(col, op.color((0.45, 0.45, 0.46)), op.blend(scratches, op.gray(0.8), op.MUL))
col = op.blend(op.color((0.03, 0.028, 0.025)), col, op.COPY, mask=grime, opacity=0.75)
col = op.lerp(col, op.mottle(op.color(DUSTC), n_fine, 0.15, R), dust)
col = op.blend(op.color((0.012, 0.011, 0.01)), col, op.COPY, mask=leak, opacity=0.85)
ao_col = op.lv(ao, out_lo=0.3, fmt=True)
col = op.blend(op.blend(op.to_color(ao_col), col, op.MUL), col, op.COPY, opacity=CAVITY)

# --- roughness / metallic / emissive / opacity ---------------------------------------------------------------------------
rg = op.gray
rough = op.lv(n_clouds, out_lo=PAINT_R - 0.06, out_hi=PAINT_R + 0.06)
rough = op.lerp(rough, op.lv(brush, out_lo=METAL_R - 0.08, out_hi=METAL_R + 0.08), op.blend(F_STEEL, bare_m, op.MAX))
rough = op.lerp(rough, op.lv(n_clouds, out_lo=0.25, out_hi=0.4), CM['brass'])
rough = op.lerp(rough, op.lv(brush, out_lo=METAL_R - 0.12, out_hi=METAL_R - 0.02), pm)
rough = op.lerp(rough, rg(0.4), F_CABLE)
rough = op.lerp(rough, rg(0.5), CM['cable_alt'])
rough = op.lerp(rough, rg(0.15), CM['light'])
rough = op.lerp(rough, rg(0.32), op.blend(edge_wear, op.lv(chips, in_lo=0.3, in_hi=0.7, out_lo=0.4), op.MUL))
rough = op.lerp(rough, rg(0.3), op.blend(scratches, rg(0.7), op.MUL))
rough = op.lerp(rough, op.lv(n_fine, out_lo=0.7, out_hi=0.9), rust)
rough = op.lerp(rough, rg(0.75), patina)
rough = op.lerp(rough, rg(0.85), grime)
rough = op.lerp(rough, rg(0.92), dust)
rough = op.lerp(rough, rg(0.08), leak)

metallic = op.blend(op.blend(METAL, bare_m, op.MAX), pm, op.MAX)
metallic = op.blend(op.blend(op.lv(chips, in_lo=0.2, in_hi=0.6, out_lo=0.5), edge_wear, op.MUL), metallic, op.MAX)
metallic = op.blend(op.blend(scratches, rg(0.9), op.MUL), metallic, op.MAX)
for m_ in (rust, patina, op.lv(grime, out_hi=0.7), dust, leak):
    metallic = op.blend(m_, metallic, op.SUB)

emis = op.lerp(op.color((0.0, 0.0, 0.0)), op.color(LAMP), CM['light'])
emis = op.blend(op.gray(GLOW), emis, op.MUL)
opacity = ALPHA

g.output('basecolor', 'Base Color', 'baseColor', col)
g.output('normal', 'Normal', 'normal', normal)
g.output('roughness', 'Roughness', 'roughness', rough, gray=True)
g.output('metallic', 'Metallic', 'metallic', metallic, gray=True)
g.output('ambientocclusion', 'Ambient Occlusion', 'ambientOcclusion', ao, gray=True)
g.output('height', 'Height', 'height', height, gray=True)
g.output('emissive', 'Emissive', 'emissive', emis)
g.output('opacity', 'Opacity', 'opacity', opacity, gray=True)
g.output('material_id', 'Material ID', 'any', IDM, gray=True, group='Masks')


# --- presets: (frame, body, body B, pipe, pipe B, dark, valves, cable, cable B) ------------------------------------------
def look(name, frame, body, bodyb, pipe, pipeb, dark, accent, cable, cableb, **kw):
    g.preset(name, frame_color=(*frame, 1), body_color=(*body, 1), body_b_color=(*bodyb, 1), pipe_color=(*pipe, 1),
             pipe_b_color=(*pipeb, 1), dark_color=(*dark, 1), accent_color=(*accent, 1), cable_color=(*cable, 1),
             cable_b_color=(*cableb, 1), **kw)


look('Dark Iron', (0.075, 0.075, 0.08), (0.1, 0.1, 0.105), (0.065, 0.065, 0.07), (0.11, 0.11, 0.115),
     (0.16, 0.15, 0.14), (0.035, 0.035, 0.04), (0.3, 0.06, 0.04), (0.04, 0.04, 0.042), (0.13, 0.11, 0.08))
look('Grey Primer', (0.36, 0.36, 0.37), (0.4, 0.4, 0.41), (0.33, 0.33, 0.34), (0.42, 0.42, 0.43), (0.3, 0.3, 0.31),
     (0.12, 0.12, 0.13), (0.38, 0.38, 0.39), (0.1, 0.1, 0.11), (0.25, 0.25, 0.26), edge_wear=0.2, grime=0.3,
     dust=0.15, leaks=0.0, patina=0.0, paint_roughness=0.7, scratches=0.1, brass_color=(0.42, 0.42, 0.43, 1),
     light_intensity=0.0)
look('Industrial', (0.32, 0.33, 0.34), (0.5, 0.38, 0.06), (0.26, 0.27, 0.28), (0.35, 0.36, 0.37), (0.15, 0.25, 0.3),
     (0.07, 0.07, 0.075), (0.55, 0.06, 0.04), (0.05, 0.05, 0.055), (0.45, 0.32, 0.05), edge_wear=0.55, grime=0.6,
     dust=0.45, leaks=0.5, paint_roughness=0.6, lamp_color=(1.0, 0.55, 0.2, 1))
look('Gunmetal', (0.3, 0.31, 0.32), (0.36, 0.37, 0.38), (0.26, 0.27, 0.28), (0.4, 0.41, 0.42), (0.45, 0.33, 0.2),
     (0.08, 0.08, 0.085), (0.3, 0.06, 0.04), (0.05, 0.05, 0.055), (0.3, 0.2, 0.1), bare_metal=1.0,
     metal_roughness=0.36, edge_wear=0.5, scratches=0.5, grime=0.6, dust=0.35, leaks=0.45, cavity_darkening=0.65,
     lamp_color=(0.35, 0.8, 1.0, 1))
look('Rusted Derelict', (0.2, 0.18, 0.16), (0.26, 0.23, 0.2), (0.18, 0.16, 0.14), (0.24, 0.21, 0.18),
     (0.3, 0.2, 0.12), (0.06, 0.05, 0.045), (0.3, 0.08, 0.04), (0.04, 0.035, 0.03), (0.18, 0.12, 0.07),
     edge_wear=0.75, scratches=0.5, grime=0.85, dust=0.75, leaks=0.6, patina=0.75, rust=0.8, light_intensity=0.4,
     paint_roughness=0.75)
look('White Station', (0.55, 0.56, 0.57), (0.72, 0.72, 0.71), (0.6, 0.62, 0.63), (0.62, 0.63, 0.64),
     (0.2, 0.45, 0.5), (0.15, 0.16, 0.18), (0.1, 0.4, 0.45), (0.12, 0.13, 0.15), (0.6, 0.6, 0.6), edge_wear=0.12,
     scratches=0.1, grime=0.15, dust=0.08, leaks=0.0, patina=0.1, paint_roughness=0.32,
     brass_color=(0.55, 0.57, 0.6, 1), lamp_color=(0.35, 0.9, 1.0, 1), light_intensity=3.0)
look('Military Green', (0.12, 0.14, 0.1), (0.2, 0.25, 0.16), (0.15, 0.18, 0.12), (0.22, 0.24, 0.19),
     (0.36, 0.3, 0.2), (0.05, 0.055, 0.045), (0.5, 0.4, 0.08), (0.05, 0.05, 0.045), (0.25, 0.22, 0.14),
     edge_wear=0.55, dust=0.6, dust_color=(0.4, 0.35, 0.27, 1), paint_roughness=0.68, lamp_color=(0.6, 1.0, 0.35, 1))
look('Black Ops', (0.03, 0.03, 0.033), (0.045, 0.045, 0.05), (0.03, 0.03, 0.033), (0.05, 0.05, 0.055),
     (0.08, 0.08, 0.09), (0.02, 0.02, 0.022), (0.5, 0.03, 0.03), (0.02, 0.02, 0.022), (0.35, 0.03, 0.03),
     edge_wear=0.25, dust=0.15, grime=0.3, paint_roughness=0.4, lamp_color=(1.0, 0.15, 0.08, 1),
     light_intensity=4.0, brass_color=(0.3, 0.3, 0.32, 1))
look('Brass Works', (0.12, 0.1, 0.08), (0.16, 0.13, 0.1), (0.1, 0.085, 0.07), (0.62, 0.45, 0.22),
     (0.55, 0.3, 0.16), (0.05, 0.04, 0.035), (0.45, 0.08, 0.04), (0.06, 0.04, 0.03), (0.35, 0.2, 0.08),
     edge_wear=0.5, patina=0.55, grime=0.6, leaks=0.4, lamp_color=(1.0, 0.6, 0.25, 1), light_intensity=3.0,
     pipe_metal=1.0, metal_roughness=0.4)
op.finish(pkg, __file__, globals())
