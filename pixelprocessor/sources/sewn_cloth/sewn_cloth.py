"""Sewn Cloth: woven fabric panels sewn together, all maths (no bitmaps). One Pixel Processor runs cloth_layout.py:
plain or twill weave (warp / weft as round threads), panels with the weave sometimes turned, and seams from
seam_study/seam_lib.py in one style per material (workwear double topstitch, overlock zigzag, hand-repair ladder,
decorative herringbone), with puckers along them. Shading: warp / weft colours (denim), patchwork tones, stitch
thread colour, fading on raised parts, dirt, fuzz, gentle drape wrinkles (library noise).
"""
import sys, os
sys.path.insert(0, os.environ.get('SBS_SCRIPTS', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sbsgen import Package, Expr, F, F4, I1, B, GRAY, COLOR, clamp01, tofloat, vec2
from sbsops import Ops
import sbsfunc as M
import cloth_layout as K

pkg = Package('sewn_cloth')
g = pkg.graph('sewn_cloth', 'Sewn Cloth', category='Fabric', author='Claude',
              description='Woven fabric panels sewn together with mathematical seams (topstitch, overlock zigzag, '
                          'hand-repair ladder or herringbone), plain or twill weave, denim-style warp and weft colours.',
              tags='fabric;cloth;denim;canvas;seam;stitch;sewing;weave;twill;textile', physicalSize='60 60 1')
op = Ops(g, debug='--debug' in sys.argv)


def slider(ident, label, default, group, desc='', vmin=0.0, vmax=1.0):
    return g.param(ident, label, F(default), group, vmin=vmin, vmax=vmax, step=0.01, desc=desc)


def colour(ident, label, rgb, group, desc=''):
    return g.param(ident, label, F4(*rgb, 1), group, widget='color', desc=desc)


def gate(a):
    return clamp01(a * 10.0)


SEED = tofloat(g.param('seed', 'Seed', I1(0), 'Layout', vmin=0, vmax=300, step=1, desc='Panel layout.'))
STYLE = tofloat(g.param('seam_style', 'Seam Style', I1(0), 'Seams', widget='dropdownlist',
                        options='0;0;Workwear (double topstitch);1;Overlock (zigzag);2;Hand Repair (ladder);3;Decorative (herringbone)',
                        desc='One stitch style for every seam, so the cloth reads as one garment.'))
SEAM_W = slider('seam_width', 'Seam Width', 0.28, 'Seams', 'Size of seams and stitches.', 0.12, 0.5)
PUCKER = slider('pucker', 'Pucker', 0.8, 'Seams', 'Small wrinkles where the seams pull the fabric.', 0.0, 2.0)
WEAVE = tofloat(g.param('weave', 'Weave', I1(1), 'Fabric', widget='dropdownlist', options='0;0;Plain;1;Twill'))
COUNT = tofloat(g.param('thread_count', 'Thread Count', I1(176), 'Fabric', vmin=64, vmax=320, step=8,
                        desc='Threads across the tile (whole numbers keep it tiling). Higher = finer, needs more pixels.'))
WDEPTH = slider('weave_depth', 'Weave Depth', 1.0, 'Fabric', '', 0.0, 2.0)
ROTATE = slider('rotated_panels', 'Rotated Panels', 0.4, 'Fabric', 'Share of panels with the weave turned 90 degrees.')
WRINKLES = slider('wrinkles', 'Wrinkles', 0.35, 'Fabric', 'Soft drape wrinkles across the cloth.')

WARP = colour('warp_color', 'Warp', (0.07, 0.13, 0.32), 'Colour', 'The lengthwise threads (indigo for denim).')
WEFT = colour('weft_color', 'Weft', (0.42, 0.42, 0.4), 'Colour', 'The crosswise threads (off-white for denim).')
PATCH = slider('patchwork', 'Patchwork', 0.0, 'Colour', 'Panels in other fabrics.')
PATCHB = colour('patch_b_color', 'Patch B', (0.32, 0.18, 0.1), 'Colour')
PATCHC = colour('patch_c_color', 'Patch C', (0.22, 0.26, 0.16), 'Colour')
TONE = slider('panel_tone', 'Panel Tone', 0.25, 'Colour', 'Each panel a slightly different shade.')
THREAD = colour('thread_color', 'Stitch Thread', (0.72, 0.45, 0.14), 'Colour')

FADE = slider('fade', 'Fade', 0.35, 'Wear', 'Colour worn off raised seams and folds (denim fading).')
DIRT = slider('dirt', 'Dirt', 0.2, 'Wear')
DIRTC = colour('dirt_color', 'Dirt Colour', (0.18, 0.15, 0.11), 'Wear')
FUZZ = slider('fuzz', 'Fuzz', 0.4, 'Wear', 'Fibre fuzz: soft colour and roughness noise.')
ROUGH = slider('roughness', 'Roughness', 0.85, 'Wear', '', 0.3, 1.0)

NORMAL = g.param('normal_intensity', 'Normal Intensity', F(5.0), 'Output', vmin=0, vmax=20, step=0.1)
NORMAL_FORMAT = g.param('normal_format', 'Normal Format', I1(0), 'Output', widget='dropdownlist',
                        options='0;0;DirectX;1;OpenGL', desc='DirectX (Substance default) or OpenGL (Godot, Blender).')

# --- layout -----------------------------------------------------------------------------------------------------------
x, y = M.pos()
h, pr, th, warp = K.layout(M, x, y, SEED, STYLE, F=M.floor(COUNT), twill=M.sel(M.gt(WEAVE, 0.5), 1.0, 0.0),
                           seam_scale=SEAM_W, pucker=PUCKER, rotate=ROTATE, weave_depth=WDEPTH)
v4 = Expr('vector4', 2048, args={'componentsin': Expr('vector3', 1024, args={
    'componentsin': vec2(M.clamp(h + 0.4), pr), 'componentslast': M.clamp(th)}), 'componentslast': warp})
pp = g.filter('pixelprocessor', out=COLOR, fmt=3, colorswitch=B(True), perpixel=v4)


def chan(img, k):
    w = [0.0, 0.0, 0.0, 0.0]
    w[k] = 1.0
    return g.filter('grayscaleconversion', {'input1': img}, out=GRAY, fmt=3, channelsweights=F4(*w))


H, PR, TH, WA = chan(pp, 0), chan(pp, 1), chan(pp, 2), chan(pp, 3)


def noise(pkg_, seed, **kw):
    return op.auto_levels(op.noise(pkg_, seed_offset=seed, **kw))


R = (0.1, 0.9)
n_clouds = noise('clouds_2.sbs', 21)
n_big = noise('clouds_1.sbs', 22)
n_fine = noise('bnw_spots_3.sbs', 25)
n_dirt = noise('dirt_3.sbs', 23)
n_fold = noise('perlin_noise_1.sbs', 26)
n_crease = noise('creased.sbs', 27)

folds = op.blend(op.lv(n_fold, out_hi=0.6), op.lv(n_crease, out_hi=0.4), op.ADD)
folds = op.blend(op.gray(WRINKLES * 0.12), op.blur(folds, 2.0, fmt=True), op.MUL, fmt=True)
height = op.blend(folds, op.lv(H, fmt=True), op.ADD, fmt=True)
normal = g.filter('normal', {'input1': height}, out=COLOR, intensity=NORMAL, inversedy=M.gt(tofloat(NORMAL_FORMAT), 0.5))
occl = None
for blur_amt, weight in ((1.0, 0.45), (4.0, 0.3)):
    cv = op.blend(height, op.blur(height, blur_amt, fmt=True), op.SUB, fmt=True)
    cv = op.lv(cv, out_hi=weight / 0.45, fmt=True)
    occl = cv if occl is None else op.blend(cv, occl, op.MAX, fmt=True)
ao = op.lv(occl, in_lo=0.0, in_hi=0.08, out_lo=1.0, out_hi=0.45, fmt=True)

# raised parts for fading: seam ridges, allowance, fold crests
hp = op.blend(height, op.blur(height, 6.0, fmt=True), op.SUB, fmt=True)
crest = op.lv(op.blend(op.blur(height, 6.0, fmt=True), height, op.SUB, fmt=True), in_lo=0.0, in_hi=0.06, fmt=True)
fade = op.blend(crest, op.lv(n_big, in_lo=0.15, in_hi=0.85, out_lo=0.4, out_hi=1.1), op.MUL)
fade = op.lv(fade, in_lo=0.4 - FADE * 0.35, in_hi=0.8 - FADE * 0.35)
fade = op.blend(op.gray(gate(FADE) * FADE * 1.3), fade, op.MUL)
fade = op.blend(fade, op.inv(TH), op.MUL)                                   # stitch thread doesn't fade
dirt = op.lv(op.blend(op.lv(n_dirt, in_lo=0.2, in_hi=0.85), op.lv(op.inv(ao), in_hi=0.4, out_lo=0.5, out_hi=1.2), op.MUL),
             in_lo=0.6 - DIRT * 0.5, in_hi=0.85 - DIRT * 0.5)
dirt = op.blend(op.gray(gate(DIRT)), dirt, op.MUL)

# --- colour ---------------------------------------------------------------------------------------------------------------
fabric = op.lerp(op.color(WEFT), op.color(WARP), WA)                          # warp vs weft thread colours
patch_b = op.lerp(op.blend(op.color(PATCHB), op.color((1.3, 1.3, 1.3)), op.MUL), op.color(PATCHB), WA)
patch_c = op.lerp(op.blend(op.color(PATCHC), op.color((1.3, 1.3, 1.3)), op.MUL), op.color(PATCHC), WA)
pb = op.blend(op.lv(PR, in_lo=0.62, in_hi=0.63, fmt=True), op.gray(PATCH), op.MUL)
pc = op.blend(op.lv(PR, in_lo=0.82, in_hi=0.83, fmt=True), op.gray(PATCH), op.MUL)
col = op.lerp(fabric, patch_b, pb)
col = op.lerp(col, patch_c, pc)
col = op.mottle(col, PR, TONE * 0.35, (0.0, 1.0))                          # panel shades
col = op.mottle(col, n_fine, FUZZ * 0.12, R)
col = op.mottle(col, n_clouds, 0.05, R)
col = op.lerp(col, op.mottle(op.lerp(op.color(WEFT), op.color(WARP), op.gray(0.35)), n_fine, 0.1, R), fade)
col = op.lerp(col, op.mottle(op.color(THREAD), n_fine, 0.08, R), TH)
col = op.blend(op.color(DIRTC), col, op.COPY, mask=dirt, opacity=0.6)
col = op.blend(op.to_color(op.lv(ao, out_lo=0.4, fmt=True)), col, op.MUL)

rough = op.lv(n_fine, out_lo=ROUGH - 0.06 * (1.0 + FUZZ), out_hi=ROUGH + 0.04)
rough = op.lerp(rough, op.gray(ROUGH - 0.25), TH)                          # stitch thread a little shinier
rough = op.lerp(rough, op.gray(0.95), dirt)

g.output('basecolor', 'Base Color', 'baseColor', col)
g.output('normal', 'Normal', 'normal', normal)
g.output('roughness', 'Roughness', 'roughness', rough, gray=True)
g.output('metallic', 'Metallic', 'metallic', op.gray(0.0), gray=True)
g.output('ambientocclusion', 'Ambient Occlusion', 'ambientOcclusion', ao, gray=True)
g.output('height', 'Height', 'height', height, gray=True)

g.preset('Indigo Denim')
g.preset('Black Denim', warp_color=(0.03, 0.03, 0.035, 1), weft_color=(0.25, 0.25, 0.26, 1),
         thread_color=(0.5, 0.5, 0.52, 1), fade=0.5)
g.preset('Khaki Canvas', weave=1, warp_color=(0.42, 0.37, 0.24, 1), weft_color=(0.48, 0.43, 0.3, 1),
         thread_color=(0.3, 0.26, 0.16, 1), thread_count=128, fade=0.25, dirt=0.35, seam_width=0.32)
g.preset('Army Patchwork', seam_style=1, weave=0, warp_color=(0.2, 0.24, 0.13, 1), weft_color=(0.26, 0.29, 0.17, 1),
         patchwork=1.0, patch_b_color=(0.36, 0.3, 0.18, 1), patch_c_color=(0.14, 0.16, 0.1, 1),
         thread_color=(0.15, 0.15, 0.1, 1), thread_count=144, dirt=0.45, fade=0.3)
g.preset('Repaired Linen', seam_style=2, weave=0, warp_color=(0.6, 0.55, 0.45, 1), weft_color=(0.66, 0.61, 0.5, 1),
         thread_color=(0.35, 0.12, 0.08, 1), thread_count=112, fade=0.15, dirt=0.3, wrinkles=0.6, pucker=1.3)
g.preset('Decorative Wool', seam_style=3, weave=1, warp_color=(0.32, 0.05, 0.05, 1), weft_color=(0.4, 0.1, 0.08, 1),
         thread_color=(0.78, 0.66, 0.3, 1), thread_count=96, weave_depth=1.5, fade=0.1, fuzz=0.8, seam_width=0.34)
op.finish(pkg, __file__, globals())
