"""Building Facade: a tileable, modular facade. Pick the base material (precast panels, board-formed concrete, brick,
render, stone panels, metal panels, mosaic tiles) and tune the window arrangement: ribbons, punched windows, grouped
bays between piers, curtain walls, balconies; mullions, transoms, frames, sills, spandrel panels, railings; interiors
with curtains, blinds and lit rooms; weathering streaks. Layout maths: facade_layout.py (three Pixel Processors).
"""
import sys, os
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sbsgen import Package, Expr, F, F4, I1, B, GRAY, COLOR, clamp01, tofloat, vec2, select, pick, eq
from sbsops import Ops
import sbsfunc as M
import facade_layout as L

pkg = Package('building_facade')
g = pkg.graph('building_facade', 'Building Facade', category='Architecture', author='Claude',
              description='A tileable modular building facade: choose the wall material and tune the window '
                          'arrangement (ribbon, punched, grouped bays, curtain wall, balconies), frames, interiors '
                          'and weathering.',
              tags='building;facade;architecture;windows;city;concrete;brick;panels;curtain wall;tileable',
              physicalSize='2000 2000 50')
op = Ops(g, debug='--debug' in sys.argv)


def slider(ident, label, default, group, desc='', vmin=0.0, vmax=1.0, step=0.01):
    return g.param(ident, label, F(default), group, vmin=vmin, vmax=vmax, step=step, desc=desc)


def count(ident, label, default, group, vmin, vmax, desc=''):
    return tofloat(g.param(ident, label, I1(default), group, vmin=vmin, vmax=vmax, step=1, desc=desc))


def toggle(ident, label, default, group, desc=''):
    return select(g.param(ident, label, B(default), group, widget='buttons', desc=desc), 1.0, 0.0)


def colour(ident, label, rgb, group, desc=''):
    return g.param(ident, label, F4(*rgb, 1), group, widget='color', desc=desc)


def gate(amount):
    return clamp01(amount * 10.0)


# --- controls ------------------------------------------------------------------------------------------------------
MAT_I = g.param('material', 'Base Material', I1(0), 'Material', widget='dropdownlist',
                options='0;' + ';'.join('%d;%s' % (i, n) for i, n in enumerate(L.MATERIALS)),
                desc='The wall material: its surface pattern, colour, roughness and grain.')
MAT = tofloat(MAT_I)
WALL = colour('wall_tint', 'Wall Tint', (1.0, 1.0, 1.0), 'Material', 'Multiplies the material colour (white = as is).')
ACCENT = colour('accent_color', 'Bands & Piers', (0.82, 0.8, 0.76), 'Material', 'Colour of slab bands and piers.')
ACCENT_AMT = slider('accent_amount', 'Bands & Piers Accent', 0.0, 'Material',
                    '0 = bands and piers in the wall material, 1 = in the accent colour.')
PANEL_C = slider('panel_cols', 'Panel Columns', 1.0, 'Material', 'Panels (or boards / 6) per bay.', 0.25, 4.0)
PANEL_R = slider('panel_rows', 'Panel Rows', 2.0, 'Material', 'Panel rows per floor.', 1.0, 6.0)
BRICK_R = slider('brick_rows', 'Brick Courses', 36.0, 'Material',
                 'Brick courses per floor (a real 3 m floor is about 40). Mosaic tiles are two courses.', 8.0, 60.0, 1.0)
BRICK_L = slider('brick_ratio', 'Brick Length', 3.0, 'Material', 'Brick length in course heights (about 3 for a '
                 'standard brick, 2 for squarish, 4-5 for Roman / long format).', 1.5, 6.0)
JOINT = slider('joint_width', 'Joint Width', 0.6, 'Material', vmin=0.1, vmax=2.0)
JOINT_D = slider('joint_depth', 'Joint Depth', 0.5, 'Material')
VAR = slider('unit_variation', 'Unit Variation', 0.5, 'Material', 'Colour variation between panels, bricks, tiles.')
ROUGH = slider('wall_roughness', 'Wall Roughness', 0.8, 'Material')

SEED = tofloat(g.param('seed', 'Seed', I1(0), 'Layout', vmin=0, vmax=300, step=1, desc='Interiors, curtains, lights.'))
GROUPS = count('groups', 'Lanes', 3, 'Layout', 1, L.MAXL, 'Vertical lanes across the tile, split by piers. '
               'Each lane takes window type A, B or C from the Lane Pattern.')
PATTERN = tofloat(g.param('lane_pattern', 'Lane Pattern', I1(0), 'Layout', widget='dropdownlist',
                          options='0;' + ';'.join('%d;%s' % (i, n) for i, (n, _) in enumerate(L.PATTERNS)),
                          desc='Window type per lane, repeating across. Use a lane count that is a multiple of the '
                               'pattern length so the tile wraps cleanly. Random picks per lane from the Seed.'))
FLOORS = count('floors', 'Floors', 5, 'Layout', 1, 30, 'Floors down the tile.')
SPECIAL = count('special_every', 'Special Floor Every', 0, 'Layout', 0, 10, 'Every Nth floor uses the Special Floor '
                'Type in all lanes (0 = off): attic, mechanical or podium rows. Use a floor count that is a multiple.')
SPECIAL_T = tofloat(g.param('special_type', 'Special Floor Type', I1(2), 'Layout', widget='dropdownlist',
                            options='0;0;Type A;1;Type B;2;Type C'))
PIER = slider('pier_width', 'Pier Width', 0.35, 'Layout', 'Width of the piers between groups (in bays).', 0.0, 2.0)
PIER_D = slider('pier_depth', 'Pier Depth', 0.3, 'Layout', 'How far the piers stand out.')
BAND = slider('band_height', 'Slab Band', 0.18, 'Layout', 'Height of the band at each floor (share of a floor).',
              0.0, 0.9)
BAND_D = slider('band_depth', 'Band Depth', 0.3, 'Layout', 'How far the slab bands stand out.')
TYPES = {}
for t, lab, d in (('a', 'A', dict(bays=3, w=0.8, h=0.75, top=0.12, mull=1, transom=0.0, style=0)),
                  ('b', 'B', dict(bays=2, w=0.55, h=0.75, top=0.12, mull=0, transom=0.0, style=0)),
                  ('c', 'C', dict(bays=2, w=1.0, h=1.0, top=0.0, mull=2, transom=0.5, style=0))):
    grp = 'Window Type ' + lab
    TYPES[t + '_bays'] = count(t + '_bays', 'Bays', d['bays'], grp, 1, 10, 'Width of a type-%s lane in bays.' % lab)
    TYPES[t + '_w'] = slider(t + '_width', 'Window Width', d['w'], grp, 'Share of a bay; 1 = continuous ribbon.', 0.1, 1.0)
    TYPES[t + '_h'] = slider(t + '_height', 'Window Height', d['h'], grp, 'Share of the floor below the band.', 0.05, 1.0)
    TYPES[t + '_top'] = slider(t + '_top', 'Window Top', d['top'], grp, 'Gap from the band down to the window head.', 0.0, 0.9)
    TYPES[t + '_mull'] = count(t + '_mullions', 'Mullions', d['mull'], grp, 0, 6, 'Vertical bars per window.')
    TYPES[t + '_transom'] = slider(t + '_transom', 'Transom', d['transom'], grp, 'Height of a horizontal bar (0 = none).', 0.0, 0.95)
    TYPES[t + '_style'] = tofloat(g.param(t + '_style', 'Style', I1(d['style']), grp, widget='dropdownlist',
                                          options='0;' + ';'.join('%d;%s' % (i, n) for i, n in enumerate(L.STYLES)),
                                          desc='Windows, balconies (railings), spandrel band (dark panels between '
                                               'windows) or a blank wall lane.'))
VAR_W = slider('width_variation', 'Width Variation', 0.0, 'Variation', 'Per window width jitter (not on ribbons).')
VAR_H = slider('height_variation', 'Height Variation', 0.0, 'Variation', 'Per window height jitter.')
ODD = slider('odd_windows', 'Odd Narrow Windows', 0.0, 'Variation', 'Share of windows at half width without mullions.')
OPEN = slider('open_windows', 'Open Windows', 0.05, 'Variation', 'Share of panes left open (dark, no reflection).')
MULL_W = slider('mullion_width', 'Mullion Width', 0.8, 'Windows', vmin=0.2, vmax=3.0)
FRAME_W = slider('frame_width', 'Frame Width', 0.35, 'Windows', vmin=0.05, vmax=1.5)
RECESS = slider('recess', 'Recess', 0.5, 'Windows', 'Depth of the glass behind the wall face.')
SILL = toggle('sills', 'Sills', True, 'Windows')
FRAME_C = colour('frame_color', 'Frame Colour', (0.22, 0.22, 0.23), 'Windows')
FRAME_M = slider('frame_metal', 'Frame Metallic', 0.6, 'Windows', 'Anodised aluminium (1) or painted (0).')
SPAN_C = colour('spandrel_color', 'Spandrel Colour', (0.08, 0.1, 0.12), 'Windows')

AC = slider('ac_units', 'AC Units', 0.0, 'AC Units', 'Share of windows with an air-conditioning unit.')
AC_POS = tofloat(g.param('ac_position', 'AC Position', I1(2), 'AC Units', widget='dropdownlist',
                         options='0;' + ';'.join('%d;%s' % (i, n) for i, n in enumerate(L.AC_POS)),
                         desc='In the lower pane, hung on the wall below the window, or a mix.'))
AC_SIZE = slider('ac_size', 'AC Size', 1.0, 'AC Units', vmin=0.5, vmax=2.0)
AC_C = colour('ac_color', 'AC Colour', (0.78, 0.78, 0.76), 'AC Units')

GROUND = toggle('ground_floor', 'Ground Floor', False, 'Ground Floor', 'A taller ground floor at the bottom of the tile, '
                'with its own doors and windows. The texture then tiles horizontally only (use it as a trim / base).')
G_H = slider('ground_height', 'Ground Height', 1.5, 'Ground Floor', 'In upper-floor heights.', 0.8, 3.5)
G_BAYS = count('ground_bays', 'Ground Bays', 6, 'Ground Floor', 1, 16, 'Bays across the ground floor.')
G_DOORS = slider('door_share', 'Doors', 0.3, 'Ground Floor', 'Share of ground bays that are doors.')
G_WINS = slider('window_share', 'Shop Windows', 0.55, 'Ground Floor', 'Share of ground bays that are windows; '
                'the rest are blank wall.')
G_CLUSTER = count('door_grouping', 'Grouping', 1, 'Ground Floor', 1, 4, 'Bays decided together: 2 makes pairs of '
                  'doors / windows, 3 triples. Use a bay count that is a multiple.')
G_MIX = slider('bay_variation', 'Bay Variation', 0.3, 'Ground Floor', '0 = groups are uniform, 1 = every bay decides '
               'on its own.')
G_DOUBLE = slider('double_doors', 'Double Doors', 0.3, 'Ground Floor')
G_GLAZED = slider('glazed_doors', 'Glazed Doors', 0.5, 'Ground Floor', 'Share of doors with glass leaves (the rest '
                  'are solid panelled doors).')
G_DW = slider('door_width', 'Door Width', 0.4, 'Ground Floor', 'Share of a bay (single door).', 0.15, 0.6)
G_DH = slider('door_height', 'Door Height', 0.7, 'Ground Floor', 'Share of the ground floor below the band.', 0.3, 1.0)
G_FAN = toggle('fanlights', 'Fanlights', True, 'Ground Floor', 'Glazing above doors up to the window head.')
G_WW = slider('shop_window_width', 'Window Width', 0.8, 'Ground Floor', vmin=0.2, vmax=1.0)
G_WH = slider('shop_window_height', 'Window Height', 0.75, 'Ground Floor', vmin=0.2, vmax=1.0)
G_WT = slider('shop_window_top', 'Window Top', 0.08, 'Ground Floor', vmax=0.6)
G_MULL = count('shop_mullions', 'Window Mullions', 2, 'Ground Floor', 0, 6)
G_TR = slider('shop_transom', 'Window Transom', 0.2, 'Ground Floor', vmax=0.95)
G_BAND = slider('ground_band', 'Ground Band', 0.12, 'Ground Floor', 'Fascia band at the top of the ground floor.', 0.0, 0.5)
G_BAND_D = slider('ground_band_depth', 'Ground Band Depth', 0.4, 'Ground Floor')
G_PIER = slider('ground_pier', 'Ground Pier Width', 0.15, 'Ground Floor', vmax=0.8)
G_PIER_D = slider('ground_pier_depth', 'Ground Pier Depth', 0.3, 'Ground Floor')
G_ACC = slider('ground_accent', 'Ground Accent', 0.6, 'Ground Floor', 'Ground walls in the Ground Colour (0 = wall material).')
G_COL = colour('ground_color', 'Ground Colour', (0.45, 0.43, 0.4), 'Ground Floor', 'A darker stone / render base.')
DOOR_C = colour('door_color', 'Door Colour', (0.12, 0.16, 0.14), 'Ground Floor', 'Solid door leaves.')

GLASS_C = colour('glass_tint', 'Glass Tint', (0.2, 0.32, 0.38), 'Glass', 'Colour of reflected sky in the glass.')
REFL = slider('reflection', 'Reflection', 0.3, 'Glass', 'Sky reflection over the interior.')
REFL_V = slider('reflection_variation', 'Reflection Variation', 0.4, 'Glass', 'Per pane: some catch more sky.')
CURT = slider('curtains', 'Curtains', 0.45, 'Interior', 'Share of windows with curtains.')
BLIND = slider('blinds', 'Blinds', 0.2, 'Interior', 'Share of windows with blinds.')
LIT = slider('lit', 'Lit Windows', 0.12, 'Interior', 'Share of rooms with the lights on.')
COLF = slider('colourful', 'Colourful Curtains', 0.3, 'Interior')
LIGHT_C = colour('light_color', 'Light Colour', (1.0, 0.75, 0.45), 'Interior')
LIGHT_I = slider('light_intensity', 'Light Intensity', 1.5, 'Interior', vmax=8.0)

GRIME = slider('grime', 'Grime', 0.35, 'Weathering', 'Dirt in joints and corners.')
STREAKS = slider('streaks', 'Streaks', 0.4, 'Weathering', 'Dirt running down from sills and bands.')
STAINS = slider('stains', 'Stains', 0.15, 'Weathering', 'Large blotchy discolouration.')
DIRT_C = colour('dirt_color', 'Dirt Colour', (0.18, 0.16, 0.13), 'Weathering')

AO_STRENGTH = slider('ao_strength', 'AO Strength', 1.0, 'Output', vmin=0.2, vmax=3.0)
NORMAL = g.param('normal_intensity', 'Normal Intensity', F(6.0), 'Output', vmin=0, vmax=20, step=0.1)
NORMAL_FORMAT = g.param('normal_format', 'Normal Format', I1(0), 'Output', widget='dropdownlist',
                        options='0;0;DirectX;1;OpenGL', desc='DirectX (Substance default) or OpenGL (Godot, Blender).')

P = dict(groups=GROUPS, pattern=PATTERN, floors=FLOORS, seed=SEED, pier=PIER, band=BAND, frame=FRAME_W,
         mullion_w=MULL_W, sill_on=SILL, material=MAT, joint=JOINT, joint_depth=JOINT_D, panel_cols=PANEL_C,
         panel_rows=PANEL_R, brick_rows=BRICK_R, brick_ratio=BRICK_L, band_depth=BAND_D, pier_depth=PIER_D,
         recess=RECESS, special=SPECIAL, special_type=SPECIAL_T, var_w=VAR_W, var_h=VAR_H, odd=ODD, open_w=OPEN,
         ac=AC, ac_pos=AC_POS, ac_size=AC_SIZE, ground_on=GROUND, g_height=G_H, g_bays=G_BAYS, g_cluster=G_CLUSTER,
         g_mix=G_MIX, g_doors=G_DOORS, g_windows=G_WINS, g_double=G_DOUBLE, g_glazed=G_GLAZED, g_band=G_BAND,
         g_band_depth=G_BAND_D, g_pier=G_PIER, g_pier_depth=G_PIER_D, g_door_w=G_DW, g_door_h=G_DH, g_win_w=G_WW,
         g_win_h=G_WH, g_win_top=G_WT, g_mull=G_MULL, g_transom=G_TR, g_fanlight=G_FAN, **TYPES)
Q = dict(curtains=CURT, blinds=BLIND, lit=LIT, colourful=COLF, lit_r=M.c(0.12), lit_g=M.c(0.1), lit_b=M.c(0.08))


def chan(img, k):
    w = [0.0, 0.0, 0.0, 0.0]
    w[k] = 1.0
    return g.filter('grayscaleconversion', {'input1': img}, out=GRAY, fmt=3, channelsweights=F4(*w))


def pp_color(a, b, c, d, fmt=3):
    v = Expr('vector4', 2048, args={'componentsin': Expr('vector3', 1024, args={
        'componentsin': vec2(a, b), 'componentslast': M.c(0.0) * 0.0 + c}), 'componentslast': M.c(0.0) * 0.0 + d})
    return g.filter('pixelprocessor', out=COLOR, fmt=fmt, colorswitch=B(True), perpixel=v)


# --- layout: height / class / random / aux, interiors, streaks ------------------------------------------------------------
x, y = M.pos()
h, c, rnd, aux, wv, strk, opf, wk, gf = L.facade(M, x, y, P)
LAY = pp_color(h, (c + 0.5) / L.NCLS, rnd, aux)
H, CLS, RND, AUX = chan(LAY, 0), chan(LAY, 1), chan(LAY, 2), chan(LAY, 3)
x, y = M.pos()
h2, c2, rnd2, aux2, wv2, strk2, opf2, wk2, gf2 = L.facade(M, x, y, P)
ir, ig, ib, glow = L.interior(M, rnd2, aux2, wv2, Q, gf2)
INTC = pp_color(M.clamp(ir), M.clamp(ig), M.clamp(ib), M.c(1.0), fmt=2)   # alpha 1: RGBA blends composite by alpha
x, y = M.pos()
h4, c4, rnd4, aux4, wv4, strk4, opf4, wk4, gf4 = L.facade(M, x, y, P)
GLOW = g.filter('pixelprocessor', out=GRAY, fmt=2, colorswitch=B(False),
                perpixel=M.clamp(L.interior(M, rnd4, aux4, wv4, Q, gf4)[3]))
x, y = M.pos()
h3, c3, rnd3, aux3, wv3, strk3, opf3, wk3, gf3 = L.facade(M, x, y, P)
SO = pp_color(M.clamp(strk3), M.clamp(opf3), M.c(0.0), M.c(1.0), fmt=2)
STRK, OPENM = chan(SO, 0), chan(SO, 1)

height = op.lv(H, fmt=True)
op.debug('height', height)


def cls(name):
    i = L.CID[name]
    lo, hi = i / L.NCLS, (i + 1) / L.NCLS
    return op.blend(op.lv(CLS, in_lo=lo, in_hi=lo + 1e-4, fmt=True),
                    op.lv(CLS, in_lo=hi, in_hi=hi + 1e-4, out_lo=1.0, out_hi=0.0, fmt=True), op.MUL, fmt=True)


CM = {n: op.blur(cls(n), 0.25, fmt=True) for n in L.CLASSES}


def any_of(*names):
    m = CM[names[0]]
    for n in names[1:]:
        m = op.blend(CM[n], m, op.MAX, fmt=True)
    return m


WALLM = any_of('wall', 'band', 'pier', 'sill', 'ground')
ACC = any_of('band', 'pier', 'sill')
GLASS = CM['glass']
FRAMES = any_of('frame', 'railing')

# --- noises -----------------------------------------------------------------------------------------------------
def noise(pkg_, seed, **kw):
    return op.auto_levels(op.noise(pkg_, seed_offset=seed, **kw))


R = (0.1, 0.9)
n_clouds = noise('clouds_2.sbs', 21)
n_big = noise('clouds_1.sbs', 22)
n_dirt = noise('dirt_3.sbs', 23)
n_grunge = noise('grunge_map_002.sbs', 24)
n_fine = noise('bnw_spots_3.sbs', 25)
n_pores = noise('bnw_spots_2.sbs', 26)
n_moist = noise('moisture_noise.sbs', 27)
n_wave = noise('clouds_3.sbs', 28)
brush = op.auto_levels(g.filter('dirmotionblur', {'input1': op.noise('bnw_spots_2.sbs', seed_offset=29)}, out=GRAY,
                                fmt=True, intensity=F(30.0), mblurangle=F(0.0)))
boards = op.auto_levels(g.filter('dirmotionblur', {'input1': op.noise('bnw_spots_3.sbs', seed_offset=30)}, out=GRAY,
                                 fmt=True, intensity=F(25.0), mblurangle=F(0.25)))


# --- material weights (from the dropdown) -------------------------------------------------------------------------
def mw(k):
    return select(eq(MAT_I, k), 1.0, 0.0)


def per_mat(values):
    return pick(MAT_I, [float(v) for v in values])


#                      precast  board   brick  render  stone  metal  mosaic
TINT = [(0.78, 0.75, 0.69), (0.6, 0.58, 0.55), (0.52, 0.26, 0.17), (0.84, 0.82, 0.77), (0.72, 0.67, 0.58),
        (0.55, 0.57, 0.59), (0.8, 0.79, 0.76)]
JOINT_COL = [(0.45, 0.43, 0.4), (0.4, 0.38, 0.36), (0.72, 0.7, 0.66), (0.6, 0.58, 0.54), (0.5, 0.47, 0.42),
             (0.12, 0.12, 0.13), (0.62, 0.6, 0.57)]
VAR_AMT = per_mat([0.04, 0.05, 0.22, 0.0, 0.1, 0.03, 0.05])           # per-unit tone variation
GRAIN = per_mat([0.06, 0.14, 0.12, 0.05, 0.1, 0.03, 0.03])          # surface mottling
PORES = per_mat([0.05, 0.12, 0.1, 0.06, 0.04, 0.0, 0.02])            # fine pits in the normal
METAL_W = mw(5)
BOARD_W = mw(1)
ROUGH_OFF = per_mat([0.0, 0.05, 0.05, 0.05, -0.1, -0.35, -0.3])      # metal / glazed tiles are shinier

mat_col = op.color(TINT[0])
jnt_col = op.color(JOINT_COL[0])
for k in range(1, len(TINT)):
    mat_col = op.lerp(mat_col, op.color(TINT[k]), op.gray(mw(k)))
    jnt_col = op.lerp(jnt_col, op.color(JOINT_COL[k]), op.gray(mw(k)))
wall_col = op.blend(op.color(WALL), mat_col, op.MUL)
wall_col = op.mottle(wall_col, RND, VAR * VAR_AMT * 2.0, (0.0, 1.0))
wall_col = op.mottle(wall_col, n_clouds, GRAIN, R)
wall_col = op.mottle(wall_col, n_big, GRAIN * 0.6, R)
wall_col = op.blend(op.mottle(wall_col, boards, 0.12, R), wall_col, op.COPY, mask=op.gray(BOARD_W))
wall_col = op.blend(op.mottle(wall_col, brush, 0.08, R), wall_col, op.COPY, mask=op.gray(METAL_W))
acc_col = op.mottle(op.mottle(op.color(ACCENT), n_clouds, 0.06, R), n_big, 0.04, R)
col = op.lerp(wall_col, acc_col, op.blend(ACC, op.gray(ACCENT_AMT), op.MUL))
col = op.lerp(col, op.mottle(op.blend(op.color(G_COL), wall_col, op.MUL, opacity=0.35), n_clouds, 0.06, R),
              op.blend(CM['ground'], op.gray(G_ACC), op.MUL))
col = op.lerp(col, jnt_col, CM['joint'])
col = op.lerp(col, op.mottle(op.mottle(op.color(DOOR_C), n_clouds, 0.06, R), n_wave, 0.04, R), CM['door'])
col = op.lerp(col, op.mottle(op.color(AC_C), n_fine, 0.05, R), CM['ac'])
col = op.lerp(col, op.mottle(op.color(SPAN_C), n_clouds, 0.05, R), CM['spandrel'])
col = op.lerp(col, op.mottle(op.color(FRAME_C), n_clouds, 0.05, R), FRAMES)

# glass: interior seen through, with sky reflection (per pane variation + a vertical gradient over the tile)
refl_amt = op.lv(op.blend(op.lv(RND, out_lo=1.0 - REFL_V, out_hi=1.0, fmt=True), op.lv(n_big, out_lo=0.7, out_hi=1.1),
                          op.MUL), out_lo=0.0, out_hi=1.0)
refl_amt = op.blend(op.gray(REFL * 1.4), refl_amt, op.MUL)
sky = op.mottle(op.mottle(op.blend(op.color(GLASS_C), op.color((0.7, 0.7, 0.7)), op.MUL), n_big, 0.1, R), RND, 0.15, (0.0, 1.0))
refl_amt = op.blend(OPENM, refl_amt, op.SUB)                      # open panes: no glass, no reflection
interior = op.lerp(op.blend(INTC, op.color((0.75, 0.78, 0.8)), op.MUL), op.color((0.025, 0.025, 0.03)),
                   op.lv(OPENM, out_hi=0.85))
glass_col = op.lerp(interior, sky, refl_amt)
col = op.lerp(col, glass_col, GLASS)

# --- AO, weathering ---------------------------------------------------------------------------------------------
occl = None
for blur_amt, weight in ((1.0, 0.4), (4.0, 0.3), (12.0, 0.16)):
    cv = op.blend(height, op.blur(height, blur_amt, fmt=True), op.SUB, fmt=True)
    cv = op.lv(cv, out_hi=weight / 0.4, fmt=True)
    occl = cv if occl is None else op.blend(cv, occl, op.MAX, fmt=True)
ao = op.lv(occl, in_lo=0.0, in_hi=0.06 / AO_STRENGTH, out_lo=1.0, out_hi=0.35, fmt=True)
cavity = op.lv(ao, in_lo=0.5, in_hi=0.98, out_lo=1.0, out_hi=0.0, fmt=True)
grime = op.blend(op.lv(n_dirt, in_lo=0.1, in_hi=0.8, out_lo=0.3, out_hi=1.0),
                 op.blend(cavity, CM['joint'], op.MAX), op.MUL)
grime = op.blend(op.gray(gate(GRIME)), op.lv(grime, in_lo=0.35 - GRIME * 0.3, in_hi=0.7 - GRIME * 0.3), op.MUL)
grime = op.blend(grime, any_of('wall', 'band', 'pier', 'sill', 'joint', 'spandrel', 'ground', 'door', 'ac'), op.MUL)
drips = op.auto_levels(g.filter('dirmotionblur', {'input1': op.noise('bnw_spots_1.sbs', seed_offset=31)}, out=GRAY,
                                fmt=True, intensity=F(40.0), mblurangle=F(0.25)))
streak = op.blend(op.blur(STRK, 2.5, fmt=True), op.lv(drips, in_lo=0.15, in_hi=0.85, out_lo=0.15, out_hi=1.3), op.MUL)
streak = op.blend(streak, op.lv(n_moist, in_lo=0.1, in_hi=0.8, out_lo=0.5, out_hi=1.2), op.MUL)
streak = op.blend(streak, WALLM, op.MUL)
streak = op.blend(op.gray(gate(STREAKS)), op.lv(streak, in_lo=0.55 - STREAKS * 0.5, in_hi=0.9 - STREAKS * 0.5), op.MUL)
stain = op.blend(op.lv(n_moist, in_lo=0.45, in_hi=0.85), op.lv(op.blur(n_grunge, 3.0, fmt=True), in_lo=0.2, in_hi=0.8), op.MUL)
stain = op.blend(op.gray(gate(STAINS)), op.blend(op.lv(stain, in_lo=0.6 - STAINS * 0.55, in_hi=0.85 - STAINS * 0.55),
                                                  WALLM, op.MUL), op.MUL)
dirt = op.mottle(op.color(DIRT_C), n_fine, 0.2, R)
col = op.blend(dirt, col, op.COPY, mask=grime, opacity=0.6)
col = op.blend(dirt, col, op.COPY, mask=streak, opacity=0.55)
col = op.blend(op.mottle(op.blend(op.color(DIRT_C), op.color((1.6, 1.6, 1.6)), op.MUL), n_fine, 0.1, R), col, op.COPY,
               mask=stain, opacity=0.22)
ao_col = op.lv(ao, out_lo=0.45, fmt=True)
col = op.blend(op.blend(op.to_color(ao_col), col, op.MUL), col, op.COPY, opacity=0.6)

# --- normal, roughness, metallic, emissive ------------------------------------------------------------------------
relief = op.blend(op.lv(n_pores, out_hi=1.0), op.gray(PORES * 0.004), op.MUL, fmt=True)
relief = op.blend(op.blend(op.lv(n_wave, out_hi=0.0015), relief, op.ADD, fmt=True), WALLM, op.MUL, fmt=True)
n_src = op.blend(relief, height, op.ADD, fmt=True)
normal = g.filter('normal', {'input1': n_src}, out=COLOR, intensity=NORMAL, inversedy=M.gt(tofloat(NORMAL_FORMAT), 0.5))

rg = op.gray
rough = op.lv(n_clouds, out_lo=ROUGH + ROUGH_OFF - 0.06, out_hi=ROUGH + ROUGH_OFF + 0.06)
rough = op.lerp(rough, rg(0.9), CM['joint'])
rough = op.lerp(rough, op.lv(n_clouds, out_lo=0.35, out_hi=0.45), FRAMES)
rough = op.lerp(rough, rg(0.25), CM['spandrel'])
rough = op.lerp(rough, rg(0.4), CM['door'])
rough = op.lerp(rough, rg(0.5), CM['ac'])
rough = op.lerp(rough, op.lv(n_big, out_lo=0.03, out_hi=0.1), GLASS)
rough = op.lerp(rough, rg(0.9), op.blend(OPENM, GLASS, op.MUL))
rough = op.lerp(rough, rg(0.92), op.lv(streak, out_hi=0.5))
rough = op.lerp(rough, rg(0.9), op.lv(grime, out_hi=0.6))

metallic = op.blend(op.blend(op.gray(FRAME_M), FRAMES, op.MUL), op.blend(op.gray(METAL_W), WALLM, op.MUL), op.MAX)
metallic = op.blend(op.lv(op.blend(streak, grime, op.MAX), out_hi=0.8), metallic, op.SUB)

emis = op.blend(op.blend(op.color(LIGHT_C), INTC, op.MUL), op.to_color(op.blend(GLOW, GLASS, op.MUL, fmt=True)), op.MUL)
emis = op.blend(op.gray(LIGHT_I), emis, op.MUL)

g.output('basecolor', 'Base Color', 'baseColor', col)
g.output('normal', 'Normal', 'normal', normal)
g.output('roughness', 'Roughness', 'roughness', rough, gray=True)
g.output('metallic', 'Metallic', 'metallic', metallic, gray=True)
g.output('ambientocclusion', 'Ambient Occlusion', 'ambientOcclusion', ao, gray=True)
g.output('height', 'Height', 'height', height, gray=True)
g.output('emissive', 'Emissive', 'emissive', emis)
g.output('glass_mask', 'Glass Mask', 'any', GLASS, gray=True, group='Masks')


# --- presets (layouts after the reference photos, plus material variants) --------------------------------------------
g.preset('Office Grid')
g.preset('Ribbon Office', material=0, groups=1, floors=6, pier_width=0.0, band_height=0.62, sills=False, panel_cols=0.5, panel_rows=3.0, band_depth=0.08, frame_color=(0.2, 0.18, 0.16, 1), glass_tint=(0.16, 0.3, 0.3, 1), wall_tint=(1.0, 1.0, 0.97, 1), streaks=0.15, stains=0.1, curtains=0.15, blinds=0.45, a_bays=10, a_width=1.0, a_height=1.0, a_top=0.0, a_mullions=0)
g.preset('Residential Tower', material=6, groups=3, floors=8, pier_width=1.1, pier_depth=0.05, band_height=0.0, sills=False, frame_color=(0.85, 0.85, 0.83, 1), frame_metal=0.0, glass_tint=(0.12, 0.2, 0.35, 1), curtains=0.55, blinds=0.3, wall_tint=(0.95, 0.95, 0.97, 1), a_bays=4, a_width=1.0, a_height=0.62, a_top=0.18, a_mullions=0, a_transom=0.7)
g.preset('Curtain Wall', material=4, groups=8, floors=14, pier_width=0.35, pier_depth=0.4, band_height=0.0, sills=False, panel_rows=1.0, frame_color=(0.15, 0.17, 0.2, 1), glass_tint=(0.2, 0.36, 0.48, 1), reflection=0.6, curtains=0.05, blinds=0.15, wall_tint=(1.05, 1.05, 1.08, 1), streaks=0.1, stains=0.05, grime=0.15, a_bays=1, a_width=1.0, a_height=1.0, a_top=0.0, a_mullions=2, a_transom=0.5)
g.preset('Balcony Block', material=3, groups=5, floors=14, pier_width=0.18, pier_depth=0.6, band_height=0.12, band_depth=0.5, sills=False, frame_color=(0.55, 0.55, 0.55, 1), curtains=0.7, blinds=0.1, colourful=0.7, lit=0.2, streaks=0.6, grime=0.5, stains=0.5, a_bays=1, a_width=1.0, a_height=0.95, a_top=0.05, a_mullions=1, a_style=1)
g.preset('Brutalist Slab', ac_units=0.12, material=1, groups=6, floors=9, pier_width=0.12, pier_depth=0.2, band_height=0.12, band_depth=0.4, panel_cols=1.0, frame_color=(0.3, 0.3, 0.3, 1), curtains=0.6, blinds=0.2, colourful=0.8, streaks=0.65, grime=0.5, stains=0.4, width_variation=0.15, a_bays=1, a_width=1.0, a_height=0.38, a_top=0.04, a_mullions=1)
g.preset('Brick Walk-up', material=2, groups=1, floors=4, pier_width=0.0, band_height=0.0, brick_rows=36.0, frame_color=(0.88, 0.87, 0.84, 1), frame_metal=0.0, curtains=0.5, blinds=0.25, streaks=0.35, odd_windows=0.2, width_variation=0.3, a_bays=6, a_width=0.55, a_height=0.6, a_top=0.15, a_mullions=0, a_transom=0.55)
g.preset('Metal Ribbon', material=5, groups=2, floors=7, pier_width=0.2, pier_depth=0.15, band_height=0.0, sills=False, panel_cols=2.0, panel_rows=1.0, frame_color=(0.1, 0.1, 0.11, 1), spandrel_color=(0.06, 0.07, 0.08, 1), glass_tint=(0.18, 0.24, 0.28, 1), grime=0.15, streaks=0.2, stains=0.05, a_bays=6, a_width=1.0, a_height=0.6, a_top=0.1, a_mullions=1, a_style=2)
g.preset('Deco Lanes', material=4, groups=4, lane_pattern=5, floors=10, pier_width=0.3, band_height=0.0, pier_depth=0.5, panel_rows=1.0, wall_tint=(0.9, 0.82, 0.68, 1), frame_color=(0.12, 0.12, 0.12, 1), a_bays=3, a_width=0.62, a_height=0.6, a_top=0.2, a_mullions=1, b_bays=2, b_width=0.72, b_height=0.6, b_top=0.2, b_mullions=1, b_style=2)
g.preset('Curtain Strip', material=4, groups=3, lane_pattern=2, floors=8, pier_width=0.2, band_height=0.0, pier_depth=0.2, wall_tint=(0.85, 0.9, 1.0, 1), glass_tint=(0.2, 0.34, 0.45, 1), a_bays=2, a_width=0.7, a_height=0.7, a_top=0.15, a_mullions=1, a_transom=0.25, b_bays=4, b_width=1.0, b_height=1.0, b_top=0.0, b_mullions=2, b_transom=0.5)
g.preset('Glazed Lane', material=0, groups=3, lane_pattern=2, floors=12, pier_width=0.0, band_height=0.0, panel_rows=1.0, sills=False, a_bays=3, a_style=3, b_bays=1, b_width=1.0, b_height=0.5, b_top=0.0, b_mullions=2)
g.preset('Mixed Balconies', material=6, groups=4, lane_pattern=6, floors=10, pier_width=0.25, band_height=0.0, pier_depth=0.1, wall_tint=(0.45, 0.45, 0.47, 1), sills=False, a_bays=2, a_width=0.75, a_height=0.45, a_top=0.25, a_mullions=1, b_bays=1, b_width=0.4, b_height=0.45, b_top=0.25, b_mullions=0, c_bays=2, c_width=1.0, c_height=0.8, c_top=0.1, c_mullions=1, c_transom=0.0, c_style=1)
g.preset('Attic Rows', material=1, groups=1, floors=8, pier_width=0.0, band_height=0.1, special_every=4, special_type=1, a_bays=12, a_width=0.5, a_height=0.5, a_top=0.2, a_mullions=1, b_width=0.35, b_height=0.35, b_top=0.35, b_mullions=0)
g.preset('Shopfront Street', material=0, groups=3, floors=4, ground_floor=True, ground_height=1.6, ground_bays=6,
         door_share=0.35, window_share=0.6, door_grouping=1, bay_variation=0.4, glazed_doors=0.7, double_doors=0.4,
         shop_window_width=0.86, shop_window_height=0.8, shop_mullions=2, shop_transom=0.18, ground_band=0.14,
         ground_accent=0.8, ground_color=(0.22, 0.22, 0.24, 1), ac_units=0.15)
g.preset('Brick Row Houses', material=2, groups=1, floors=3, a_bays=6, a_width=0.5, a_height=0.6, a_top=0.15,
         a_mullions=0, a_transom=0.55, odd_windows=0.0, ground_floor=True, ground_height=1.2, ground_bays=6,
         door_grouping=2, bay_variation=0.0, door_share=0.5, window_share=0.5, glazed_doors=0.0, double_doors=0.0,
         door_width=0.36, door_height=0.75, shop_window_width=0.5, shop_window_height=0.6, shop_window_top=0.15,
         shop_mullions=0, shop_transom=0.55, ground_band=0.06, ground_pier=0.0, ground_accent=0.0,
         frame_color=(0.88, 0.87, 0.84, 1), frame_metal=0.0, door_color=(0.08, 0.12, 0.25, 1), sills=True)
g.preset('Podium Tower', material=4, groups=3, lane_pattern=2, floors=8, pier_width=0.2, band_height=0.0,
         a_bays=2, a_width=0.7, a_height=0.7, a_top=0.15, a_mullions=1, a_transom=0.25, b_bays=4, b_width=1.0,
         b_height=1.0, b_top=0.0, b_mullions=2, b_transom=0.5, ground_floor=True, ground_height=2.2, ground_bays=4,
         door_share=0.25, window_share=0.75, double_doors=1.0, glazed_doors=1.0, door_width=0.45, door_height=0.55,
         shop_window_width=0.92, shop_window_height=0.88, shop_mullions=3, shop_transom=0.3, ground_pier=0.3,
         ground_pier_depth=0.5, ground_band=0.1, ground_accent=0.9, ground_color=(0.3, 0.3, 0.32, 1))
g.preset('AC Block', material=3, groups=1, floors=10, band_height=0.0, a_bays=12, a_width=0.6, a_height=0.4,
         a_top=0.25, a_mullions=1, ac_units=0.45, ac_position=1, wall_tint=(0.75, 0.73, 0.7, 1), streaks=0.6,
         grime=0.5, stains=0.4, curtains=0.4, blinds=0.35)
g.preset('Night Lights', lit=0.55, light_intensity=3.0, reflection=0.15, curtains=0.5, blinds=0.25)

op.finish(pkg, __file__, globals())
