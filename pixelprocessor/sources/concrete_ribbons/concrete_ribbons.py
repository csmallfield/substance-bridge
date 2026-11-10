"""Concrete Ribbons: cast-concrete relief panels (square, tiles both ways) from reference.jpg (see ANALYSIS.md).
Layout: ribbon_layout.py in one Pixel Processor (height, piece id, piece random, joint mask). Joint chains step one
column left in rounded 45-degree bends, straight cut joints run down-right, and each piece has a light ribbon, a lit
step face and a leaning plane.
Treatment: concrete (tone, grain, aggregate, pinholes, per-piece tone), weathering (patches, dirt, chipped edges),
water stains running down from the joints and ledges (dark streaks and lime efflorescence), wetness, and mould in the
damp places.
"""
import sys, os
sys.path.insert(0, os.environ.get('SBS_SCRIPTS', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sbsgen import Package, Expr, F, F2, F4, I1, B, GRAY, COLOR, clamp01, tofloat, vec2
from sbsops import Ops
import sbsfunc as M
import ribbon_layout as K

pkg = Package('concrete_ribbons')
g = pkg.graph('concrete_ribbons', 'Concrete Ribbons', category='Concrete', author='Claude',
              description='Cast-concrete relief panels: ribbons that step sideways in rounded 45 degree bends, cut by '
                          'panel joints. Weathering, water stains, efflorescence, wetness and mould. Tiles both ways.',
              tags='concrete;relief;panel;wall;architecture;weathering;water stains;mould;tileable',
              physicalSize='300 300 5')
op = Ops(g, debug='--debug' in sys.argv)


def slider(ident, label, default, group, desc='', vmin=0.0, vmax=1.0):
    return g.param(ident, label, F(default), group, vmin=vmin, vmax=vmax, step=0.01, desc=desc)


def colour(ident, label, rgb, group, desc=''):
    return g.param(ident, label, F4(*rgb, 1), group, widget='color', desc=desc)


def gate(amount):
    return clamp01(amount * 10.0)


# --- controls --------------------------------------------------------------------------------------------------
VAR = tofloat(g.param('variation', 'Variation', I1(0), 'Layout', vmin=0, vmax=K.VARIANTS - 1, step=1,
                      desc='Eight joint layouts (where each joint bends and where the panels are cut).'))
JOINTW = slider('joint_width', 'Joint Width', 0.0016, 'Layout', 'Half-width of the joints (tile units).',
                vmin=0.0006, vmax=0.004)

CONC = colour('concrete_color', 'Concrete', (0.46, 0.46, 0.45), 'Concrete')
TONE = slider('tone_variation', 'Tone Variation', 0.35, 'Concrete', 'How much the cast pieces differ in tone.')
MOTTLE = slider('mottling', 'Mottling', 0.4, 'Concrete', 'Cloudy tone variation from the pour.')
GRAIN = slider('grain', 'Grain', 0.5, 'Concrete', 'Fine sand grain in colour and relief.')
AGG = slider('aggregate', 'Aggregate', 0.3, 'Concrete', 'Light and dark aggregate specks.')
PINS = slider('pinholes', 'Pinholes', 0.4, 'Concrete', 'Air bubbles in the cast face.')
ROUGH = slider('roughness', 'Roughness', 0.82, 'Concrete')
JOINTC = colour('joint_color', 'Joint Colour', (0.1, 0.1, 0.1), 'Concrete')

WEATHER = slider('weathering', 'Weathering', 0.3, 'Weathering', 'Darkened, blotchy, eroded surface.')
EDGE = slider('edge_wear', 'Edge Wear', 0.25, 'Weathering', 'Chipped crisp edges.')
DIRT = slider('dirt', 'Dirt', 0.3, 'Weathering', 'Dirt in the joints, coves and corners.')
DIRTC = colour('dirt_color', 'Dirt Colour', (0.2, 0.18, 0.15), 'Weathering')

STAINS = slider('water_stains', 'Water Stains', 0.4, 'Water', 'Dark streaks running down from the joints and edges.')
STAINL = slider('stain_length', 'Stain Length', 0.5, 'Water', 'How far the streaks run down.')
STAINC = colour('stain_color', 'Stain Colour', (0.22, 0.21, 0.19), 'Water')
EFFLO = slider('efflorescence', 'Efflorescence', 0.0, 'Water', 'White lime streaks under the joints.')
WET = slider('wetness', 'Wetness', 0.0, 'Water', 'Rain-wet surface: darker and glossy, wettest in the streaks.')

MOULD = slider('mould', 'Mould', 0.1, 'Mould', 'Mould and algae in damp places: joints, coves, stain trails.')
MOULDC = colour('mould_color', 'Mould Colour', (0.12, 0.15, 0.08), 'Mould')
MOULDC2 = colour('mould_color_2', 'Mould Colour 2', (0.05, 0.06, 0.05), 'Mould', 'The darker, older growth.')

AO_STRENGTH = slider('ao_strength', 'AO Strength', 1.0, 'Output', vmin=0.2, vmax=3.0)
AO_RANGE = 0.05 / AO_STRENGTH
NORMAL = g.param('normal_intensity', 'Normal Intensity', F(6.0), 'Output', vmin=0, vmax=20, step=0.1)
NORMAL_FORMAT = g.param('normal_format', 'Normal Format', I1(0), 'Output', widget='dropdownlist',
                        options='0;0;DirectX;1;OpenGL', desc='DirectX (Substance default) or OpenGL (Godot, Blender).')

# --- layout: one Pixel Processor (height, piece id, piece random, joint mask) -----------------------------------------
x, y = M.pos()
h, pid, rnd, jm = K.ribbons(M, x, y, var=VAR, joint=JOINTW)
v = Expr('vector4', 2048, args={'componentsin': Expr('vector3', 1024, args={
    'componentsin': vec2(h, pid), 'componentslast': rnd}), 'componentslast': jm})
img = g.filter('pixelprocessor', out=COLOR, fmt=3, colorswitch=B(True), perpixel=v)


def chan(k):
    w = [0.0, 0.0, 0.0, 0.0]
    w[k] = 1.0
    return g.filter('grayscaleconversion', {'input1': img}, out=GRAY, fmt=3, channelsweights=F4(*w))


H, PID, RND, JM = chan(0), chan(1), chan(2), chan(3)
JOINTS = op.blur(JM, 0.3, fmt=True)


def noise(pkg_, seed, **kw):
    return op.auto_levels(op.noise(pkg_, seed_offset=seed, **kw))


def vstreak(src, amount=40.0):
    """Vertical motion blur (dirmotionblur angle 0.25 = vertical)."""
    return op.auto_levels(g.filter('dirmotionblur', {'input1': src}, out=GRAY, fmt=True, intensity=F(amount),
                                   mblurangle=F(0.25)))


R = (0.1, 0.9)
n_clouds = noise('clouds_2.sbs', 21)
n_big = noise('clouds_1.sbs', 22)
n_dirt = noise('dirt_3.sbs', 23)
n_grunge = noise('grunge_map_007.sbs', 24)
n_fine = noise('bnw_spots_3.sbs', 25)
n_spots = noise('bnw_spots_2.sbs', 26)
n_grain = noise('perlin_noise_1.sbs', 27)
n_moist = noise('moisture_noise.sbs', 28)
n_crys = noise('crystal_1.sbs', 29)
n_agg = noise('bnw_spots_1.sbs', 30)
n_pin = noise('bnw_spots_3.sbs', 31)
v_streak = vstreak(noise('bnw_spots_2.sbs', 32), 120.0)
v_fine = vstreak(noise('bnw_spots_3.sbs', 33), 60.0)

# --- height and normal -----------------------------------------------------------------------------------------------
height = op.lv(H, fmt=True)
pin_dots = g.inst('tile_generator.sbs', 'tile_generator', outs=[('TileGenerator', GRAY)], fmt=True, seed_offset=31,
                  Nb_X=I1(64), Nb_Y=I1(64), Pattern_Type=I1(3), Scale=F(0.14), ScaleVariation=F(0.7),
                  Position_Random=F2(1.0, 1.0), RandomMask=PINS * -0.6 + 0.9)   # evenly scattered air bubbles
pins = op.blend(op.lv(pin_dots, in_lo=0.3, in_hi=0.6), op.lv(n_pin, in_lo=0.2, in_hi=0.6, out_lo=0.3), op.MUL)
pins = op.blend(op.gray(gate(PINS)), pins, op.MUL)
agg = op.lv(n_agg, in_lo=0.75 - AGG * 0.2, in_hi=0.85 - AGG * 0.2)
erosion = op.blend(op.lv(n_grunge, in_lo=0.3, in_hi=0.9), op.gray(WEATHER), op.MUL)
fine = op.blend(op.lv(n_fine, out_hi=0.5), op.lv(n_grain, out_hi=0.5), op.ADD)
fine = op.blend(op.gray(0.3 + GRAIN * 0.7), fine, op.MUL)
fine = op.blend(op.lv(erosion, out_hi=0.6), fine, op.ADD)
relief = op.blend(op.gray(0.004), fine, op.MUL, fmt=True)
relief = op.blend(op.blend(op.gray(0.012), pins, op.MUL, fmt=True), relief, op.SUB, fmt=True)
relief = op.blend(op.lv(op.blur(n_clouds, 4.0), out_hi=0.006, fmt=True), relief, op.ADD, fmt=True)   # slight waviness
n_src = op.blend(relief, op.blur(height, 0.3, fmt=True), op.ADD, fmt=True)
normal = g.filter('normal', {'input1': n_src}, out=COLOR, intensity=NORMAL, inversedy=M.gt(tofloat(NORMAL_FORMAT), 0.5))

def shift(img_, dy):
    """Move an image down by dy (tile units). A positive Transformation offset moves the image UP."""
    return g.filter('transformation', {'input1': img_}, out=GRAY, fmt=True, offset=vec2(M.c(0.0), dy * -1.0))


# --- AO: cavity over three scales ---------------------------------------------------------------------------------------
occl = None
for blur_amt, weight in ((2.0, 0.4), (6.0, 0.3), (16.0, 0.2)):
    cv = op.blend(height, op.blur(height, blur_amt, fmt=True), op.SUB, fmt=True)
    cv = op.lv(cv, out_hi=weight / 0.4, fmt=True)
    occl = cv if occl is None else op.blend(cv, occl, op.MAX, fmt=True)
    if blur_amt == 6.0:
        tight = occl                                   # the small scales only: creases, not broad coves
ao = op.lv(occl, in_lo=0.0, in_hi=AO_RANGE, out_lo=1.0, out_hi=0.35, fmt=True)
ao = op.blend(op.lv(JOINTS, out_lo=1.0, out_hi=0.45), ao, op.MUL, fmt=True)
op.debug('ao', ao)
cavity = op.lv(tight, in_lo=0.0, in_hi=AO_RANGE * 0.6, fmt=True)
op.debug('cavity', cavity)

# --- edges: crisp top edges (height above its blur) and ledges -------------------------------------------------------------
hp = op.blend(op.blur(height, 1.2, fmt=True), height, op.SUB, fmt=True)
edges = op.lv(hp, in_lo=0.004, in_hi=0.02, fmt=True)
op.debug('edges', edges)


# water sources: the joints, the crisp edges, and the step tops; streaks run downward from them
src = op.blend(op.lv(JOINTS, out_hi=0.8), op.lv(edges, out_hi=1.0), op.MAX, fmt=True)
src = op.blend(shift(src, M.c(0.004)), src, op.SUB, fmt=True)        # keep only lines that face up (not vertical runs)
src = op.lv(src, in_hi=0.6, fmt=True)
src = op.blend(src, op.lv(n_spots, in_lo=0.1, in_hi=0.6, out_lo=0.2), op.MUL, fmt=True)
src = g.filter('dirmotionblur', {'input1': op.blur(src, 1.0, fmt=True)}, out=GRAY, fmt=True, intensity=F(6.0),
               mblurangle=F(0.25))                                       # fill between the shifted copies
src = op.lv(src, in_hi=0.25, fmt=True)
op.debug('src', src)
trail = src
STEPS = 10
for i in range(1, STEPS + 1):
    s_ = shift(src, (STAINL * 0.9 + 0.1) * (0.025 * i))
    s_ = op.lv(s_, out_hi=1.0 - i / (STEPS + 1.0), fmt=True)
    trail = op.blend(s_, trail, op.MAX, fmt=True)
trail = op.lv(op.blur(trail, 1.5, fmt=True), in_hi=0.35, fmt=True)
op.debug('trail', trail)
lines = op.lv(v_fine, in_lo=0.35, in_hi=0.75)                                        # thin vertical runs
wash = op.blend(op.lv(v_streak, in_lo=0.4, in_hi=0.9), op.lv(n_big, in_lo=0.3, in_hi=0.8), op.MUL)   # faint rain wash
stain_f = op.blend(op.lv(trail, out_hi=1.0), op.lv(wash, out_hi=0.35), op.MAX)
stain_f = op.blend(stain_f, op.lv(lines, out_lo=0.12, out_hi=1.0), op.MUL)
op.debug('stain_f', stain_f)
stain = op.lv(stain_f, in_lo=0.4 - STAINS * 0.3, in_hi=0.8 - STAINS * 0.3)
stain = op.blend(op.gray(gate(STAINS)), stain, op.MUL)
op.debug('stain', stain)
efflo = op.blend(op.lv(trail, in_lo=0.1, in_hi=0.6), op.lv(lines, in_lo=0.3, in_hi=1.0), op.MUL)
op.debug('efflo_f', efflo)
efflo = op.lv(efflo, in_lo=0.35 - EFFLO * 0.3, in_hi=0.7 - EFFLO * 0.3)
efflo = op.blend(op.gray(gate(EFFLO)), efflo, op.MUL)
op.debug('efflo', efflo)

# weathering: blotchy darkening, dirt in cavities and joints, chipped edges
blotch = op.blend(op.lv(n_big, in_lo=0.3, in_hi=0.8), op.lv(n_grunge, in_lo=0.2, in_hi=0.9, out_lo=0.3), op.MUL)
blotch = op.blend(op.gray(WEATHER), op.lv(blotch, in_lo=0.1, in_hi=0.7), op.MUL)
dirt = op.blend(op.blend(cavity, op.lv(JOINTS, out_hi=0.8), op.MAX), op.lv(n_dirt, in_lo=0.1, in_hi=0.8, out_lo=0.3), op.MUL)
op.debug('dirt_f', dirt)
dirt = op.lv(dirt, in_lo=0.35 - DIRT * 0.3, in_hi=0.5 - DIRT * 0.3)
dirt = op.blend(op.gray(gate(DIRT)), dirt, op.MUL)
op.debug('dirt', dirt)
chips = op.blend(op.lv(n_spots, out_hi=0.6), op.lv(n_grunge, out_hi=0.4), op.ADD)        # weighted sum, not a product
chips = op.blend(op.lv(op.blur(edges, 0.8, fmt=True), in_lo=0.05, in_hi=0.4), chips, op.MUL)
op.debug('chips_f', chips)
chips = op.lv(chips, in_lo=0.75 - EDGE * 0.4, in_hi=0.85 - EDGE * 0.4)
chips = op.blend(op.gray(gate(EDGE)), chips, op.MUL)
op.debug('chips', chips)

# mould: damp places (joints, coves, low in the stain trails), broken up by growth noise
damp = op.blend(op.lv(cavity, out_hi=0.9), op.lv(JOINTS, out_hi=0.9), op.MAX)
damp = op.blend(op.lv(trail, out_hi=0.7), damp, op.MAX)
damp = op.blend(op.lv(n_moist, in_lo=0.2, in_hi=0.8, out_lo=0.35, out_hi=1.0), damp, op.MUL)
growth = op.blend(op.lv(n_clouds, in_lo=0.2, in_hi=0.8, out_hi=0.6), op.lv(op.blur(n_crys, 2.0), in_lo=0.2, in_hi=0.8, out_hi=0.4), op.ADD)
mould_f = op.blend(op.lv(damp, out_hi=0.75), op.lv(growth, out_hi=0.25), op.ADD)
mould_f = op.blend(op.lv(n_big, in_lo=0.1, in_hi=0.7, out_lo=0.5, out_hi=1.0), mould_f, op.MUL)
op.debug('mould_f', mould_f)
mould = op.lv(mould_f, in_lo=0.45 - MOULD * 0.35, in_hi=0.57 - MOULD * 0.35)
mould = op.blend(op.gray(gate(MOULD)), mould, op.MUL)
op.debug('mould', mould)
mould_old = op.blend(mould, op.lv(mould_f, in_lo=0.55 - MOULD * 0.35, in_hi=0.7 - MOULD * 0.35), op.MUL)

wet = op.blend(op.gray(WET), op.blend(op.gray(0.55), op.lv(stain_f, out_lo=0.0, out_hi=0.45), op.ADD), op.MUL)

# --- colour --------------------------------------------------------------------------------------------------------------
col = op.mottle(op.color(CONC), RND, TONE * 0.18, (0.0, 1.0))                          # per piece
col = op.mottle(col, n_clouds, MOTTLE * 0.1, R)
col = op.mottle(col, n_big, MOTTLE * 0.06, R)
col = op.mottle(col, n_fine, 0.02 + GRAIN * 0.05, R)
col = op.mottle(col, n_grain, GRAIN * 0.04, R)
col = op.blend(op.color((0.78, 0.77, 0.74)), col, op.COPY, mask=agg, opacity=AGG * 0.6)            # light aggregate
col = op.blend(op.color((0.2, 0.2, 0.2)), col, op.COPY,
               mask=op.lv(n_agg, in_lo=0.0, in_hi=0.05 + AGG * 0.1, out_lo=1.0, out_hi=0.0), opacity=AGG * 0.4)
col = op.blend(op.color((0.12, 0.12, 0.12)), col, op.COPY, mask=pins, opacity=0.7)
col = op.blend(op.color((0.3, 0.29, 0.27)), col, op.MUL, mask=blotch, opacity=0.6)          # weathered patches
col = op.lerp(col, op.mottle(op.color(DIRTC), n_fine, 0.2, R), op.blend(dirt, op.gray(0.85), op.MUL))
col = op.lerp(col, op.mottle(op.color((0.68, 0.67, 0.64)), n_fine, 0.1, R), op.blend(chips, op.gray(0.8), op.MUL))
col = op.lerp(col, op.mottle(op.color(STAINC), n_clouds, 0.15, R), op.blend(stain, op.gray(0.85), op.MUL))
col = op.lerp(col, op.mottle(op.color((0.7, 0.69, 0.66)), n_fine, 0.12, R), op.blend(efflo, op.gray(0.45), op.MUL))
col = op.lerp(col, op.color(JOINTC), op.lv(JOINTS, in_hi=0.6))
mould_c = op.lerp(op.mottle(op.color(MOULDC), n_crys, 0.3, R), op.color(MOULDC2), mould_old)
col = op.lerp(col, op.mottle(mould_c, n_fine, 0.25, R), mould)
col = op.blend(op.color((0.55, 0.55, 0.55)), col, op.MUL, mask=wet, opacity=0.8)              # darker when wet
ao_col = op.lv(ao, out_lo=0.45, fmt=True)
col = op.blend(op.to_color(ao_col), col, op.MUL, opacity=0.5)

# --- roughness / metallic -----------------------------------------------------------------------------------------------
rg = op.gray
rough = op.lv(n_fine, out_lo=ROUGH - 0.05, out_hi=ROUGH + 0.05)
rough = op.blend(op.lv(erosion, out_hi=0.08), rough, op.ADD)
rough = op.lerp(rough, rg(0.95), pins)
rough = op.lerp(rough, rg(0.92), op.blend(chips, rg(0.8), op.MUL))
rough = op.lerp(rough, rg(0.9), dirt)
rough = op.lerp(rough, op.lv(n_fine, out_lo=0.72, out_hi=0.82), stain)
rough = op.lerp(rough, rg(0.95), efflo)
rough = op.lerp(rough, op.lv(n_crys, out_lo=0.7, out_hi=0.9), mould)
rough = op.lerp(rough, rg(0.95), JOINTS)
rough = op.lerp(rough, op.lv(n_moist, out_lo=0.12, out_hi=0.3), wet)                     # wet sheen
metallic = rg(0.0)

g.output('basecolor', 'Base Color', 'baseColor', col)
g.output('normal', 'Normal', 'normal', normal)
g.output('roughness', 'Roughness', 'roughness', rough, gray=True)
g.output('metallic', 'Metallic', 'metallic', metallic, gray=True)
g.output('ambientocclusion', 'Ambient Occlusion', 'ambientOcclusion', ao, gray=True)
g.output('height', 'Height', 'height', height, gray=True)


# --- presets ---------------------------------------------------------------------------------------------------------------
def look(name, conc, **kw):
    g.preset(name, concrete_color=(*conc, 1), **kw)


look('Fresh Cast', (0.50, 0.50, 0.50), weathering=0.0, edge_wear=0.05, dirt=0.05, water_stains=0.0, efflorescence=0.0,
     mould=0.0, tone_variation=0.25)
look('Weathered', (0.46, 0.46, 0.45))
look('Rain Stained', (0.46, 0.46, 0.45), weathering=0.45, dirt=0.45, water_stains=0.85, stain_length=0.8, mould=0.25)
look('Wet Rain', (0.46, 0.46, 0.45), weathering=0.4, dirt=0.4, water_stains=0.7, wetness=0.85, mould=0.3)
look('Lime Bleed', (0.44, 0.44, 0.43), weathering=0.35, water_stains=0.4, efflorescence=0.8, stain_length=0.7)
look('Mouldy', (0.42, 0.42, 0.40), weathering=0.6, dirt=0.55, water_stains=0.75, mould=0.85, stain_length=0.7,
     edge_wear=0.4)
look('Derelict', (0.40, 0.39, 0.38), weathering=0.9, edge_wear=0.8, dirt=0.85, water_stains=0.9, stain_length=1.0,
     efflorescence=0.35, mould=0.7, tone_variation=0.5)
look('Warm Sandstone', (0.55, 0.50, 0.42), aggregate=0.45, weathering=0.2, water_stains=0.3,
     stain_color=(0.3, 0.25, 0.2, 1), dirt_color=(0.3, 0.24, 0.17, 1))
look('Charcoal', (0.17, 0.17, 0.18), joint_color=(0.04, 0.04, 0.04, 1), aggregate=0.5, weathering=0.3,
     water_stains=0.35, efflorescence=0.15, stain_color=(0.12, 0.12, 0.12, 1), roughness=0.75)
look('White Precast', (0.62, 0.62, 0.60), weathering=0.1, water_stains=0.35, dirt=0.25, tone_variation=0.15,
     pinholes=0.6, mould=0.1)
op.finish(pkg, __file__, globals())
