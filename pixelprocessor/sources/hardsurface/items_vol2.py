"""JRO hard-surface alphas Vol. 2 rebuilt as maths (pplib.decals + pplib.relief). Same conventions as items.py.
PRIVATE: recreations of a commercial pack."""
import math
import sys
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
from pplib import decals as D, relief as R
from items import _edge_line

PI = math.pi
V2 = '../../../JRO_Alphas_HardSurface_Vol.2/JRO_HSAlphas_Vol02_Tiff/JRO_HSAlphas_Vol02_Tiff/'   # relative to Vol. 1 Tiff/


def _armor(M, x, y, d, rv):
    """Armor plate: a raised plate with a chamfered (soft) edge, rivets set just inside."""
    h = R.plate(M, d, 0.85, 0.07, R.soft)
    return M.fmax(h, (0.85 + 0.15 * rv) * M.b01(M.gt(rv, 0.0)))


ARMOR01_RIVETS = [(0.374, -0.866), (-0.29, -0.865), (-0.075, -0.864), (0.15, -0.862), (0.577, -0.862), (-0.516, -0.859),
                  (0.752, -0.833), (-0.736, -0.831), (-0.768, -0.635), (0.774, -0.627), (-0.771, -0.412), (0.769, -0.403),
                  (-0.774, -0.176), (0.774, -0.142), (-0.768, 0.07), (0.768, 0.104), (-0.769, 0.309), (0.767, 0.34),
                  (-0.772, 0.558), (0.767, 0.591), (0.749, 0.814), (-0.74, 0.818), (-0.271, 0.843), (-0.054, 0.843),
                  (0.38, 0.842), (0.165, 0.843), (-0.501, 0.845), (0.581, 0.851)]     # measured blob centroids


def _plate_edge(M, d):
    """Armor plate bevel (measured on armor01): 0 at the outline rising to the 0.84 top over 0.10."""
    return R.lathe(M, d, [(0.0, 0.0), (0.01, 0.12), (0.02, 0.25), (0.03, 0.36), (0.04, 0.47), (0.05, 0.57),
                          (0.06, 0.66), (0.07, 0.73), (0.08, 0.79), (0.09, 0.82), (0.10, 0.84)])


def _rivets(M, x, y, pts, r=0.036, base=0.84):
    h = None
    for cx, cy in pts:
        dd = M.fsqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
        e = R.lathe(M, dd, [(0.0, 1.0), (0.012, 0.98), (0.02, 0.94), (0.027, 0.88), (0.032, 0.80), (r, 0.0)])
        h = e if h is None else M.fmax(h, e)
    return h


def armor01(M, x, y, aa):
    """Riveted plate (measured): outline |x| 0.90, |y| 0.99 with corner chamfers (|x| + |y| = 1.797), a 0.10 wide
    bevel up to a flat 0.84 top, 28 dome rivets (peak 1.0, radius 0.036) at their measured positions."""
    ax, ay = M.fabs(x), M.fabs(y)
    d = D.rect(M, x, y, 0.90, 0.99, rad=0.14)                      # rounded corners
    return M.fmax(_plate_edge(M, d), _rivets(M, x, y, ARMOR01_RIVETS))

ARMOR04_RIVETS = [(0.013, -0.88), (-0.231, -0.879), (0.245, -0.87), (-0.444, -0.846), (0.445, -0.842), (0.558, -0.66),
                  (-0.568, -0.656), (-0.659, -0.442), (0.648, -0.442), (-0.749, -0.219), (0.738, -0.215), (-0.802, -0.004),
                  (0.798, 0.011), (0.74, 0.202), (-0.75, 0.214), (0.653, 0.422), (-0.657, 0.424), (-0.57, 0.636),
                  (0.562, 0.636), (0.453, 0.836), (-0.449, 0.844), (0.034, 0.868), (0.242, 0.869), (-0.216, 0.87)]


def armor04(M, x, y, aa):
    """Tall hexagonal plate (measured at half height: flat ends |y| 0.952, sides |x| = 0.909 - 0.415 |y|, rounded
    corners), the armor01 bevel and 24 dome rivets at their measured positions."""
    from pplib import curves as C
    ax, ay = M.fabs(x), M.fabs(y)
    k = math.hypot(1.0, 0.415)
    d = C.soft_min(M, 0.952 - ay, (0.909 - 0.415 * ay - ax) / k, 0.06) + 0.036
    return M.fmax(_plate_edge(M, d), _rivets(M, x, y, ARMOR04_RIVETS))

def armor06(M, x, y, aa):
    d = D.sub(M, D.circle(M, x, y, 0.98), D.circle(M, x, y, 0.5))
    rv = M.fmax(R.rivets_circle(M, x, y, 0.88, 30, 0.03), R.rivets_circle(M, x, y, 0.6, 18, 0.03))
    return _armor(M, x, y, d, rv)


ARMOR10_RIVETS = [(0.529, -0.491), (-0.427, -0.495), (-0.032, -0.49), (0.153, -0.485), (0.341, -0.485), (-0.218, -0.483),
                  (-0.62, -0.462), (0.688, -0.423), (-0.734, -0.406), (0.806, -0.326), (-0.857, -0.287), (0.885, -0.193),
                  (-0.926, -0.12), (0.923, -0.022), (-0.921, 0.062), (0.893, 0.156), (-0.857, 0.241), (0.805, 0.302),
                  (-0.736, 0.358), (0.674, 0.405), (-0.597, 0.442), (0.518, 0.457), (-0.19, 0.463), (0.005, 0.464),
                  (0.345, 0.463), (-0.397, 0.464), (0.172, 0.466)]                   # measured


def _capsule_d(M, x, y, half, r):
    """Inside distance of a horizontal capsule (straight half length `half`, radius r)."""
    return r - M.fsqrt(M.fmax(M.fabs(x) - half, 0.0) ** 2 + y * y)


def armor10(M, x, y, aa):
    """Pillowed capsule (all measured): a low band (0.165) inside an outer capsule (x 0.985, y 0.525) carrying
    small rivets (peak 0.235, r 0.026); a pillow capsule (outline x 0.90, y 0.44) rising from 0.17 to 1.0."""
    do = _capsule_d(M, x, y, 0.46, 0.525)
    base = 0.165 * R.soft(M, do + 0.005, 0.015)
    dp = _capsule_d(M, x, y, 0.46, 0.44)
    pillow = R.lathe(M, dp, [(0.0, 0.17), (0.04, 0.25), (0.08, 0.40), (0.12, 0.54), (0.16, 0.66), (0.20, 0.76),
                             (0.24, 0.84), (0.28, 0.90), (0.32, 0.94), (0.36, 0.97), (0.40, 0.99), (0.44, 1.0)])
    h = M.fmax(base, pillow * R.soft(M, dp + 0.005, 0.01))
    for cx, cy in ARMOR10_RIVETS:
        dd = M.fsqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
        h = M.fmax(h, R.lathe(M, dd, [(0.0, 0.235), (0.012, 0.225), (0.02, 0.2), (0.026, 0.165)]) *
                   R.soft(M, 0.026 - dd, 0.004))
    return h

def cables14(M, x, y, aa):
    """Pipe with two clamps (measured). The pipe (y -0.14..0.135, round ends at |x| 0.915) has a DISHED section:
    sharp 1.0 lines at y -0.10 and 0.06, sagging to 0.16 between. Each clamp (x centre +-0.3425, half width
    0.0875, y -0.245..0.215) is outlined by a 0.6 line, with a 0.28 shelf above the pipe, a 0.21 shelf below, the
    pipe section at 0.55 strength in between, and a small slot outline in the middle."""
    pipe_y = R.lathe(M, y, [(-0.145, 0.0), (-0.14, 0.03), (-0.13, 0.22), (-0.12, 0.49), (-0.11, 0.73), (-0.10, 1.0),
                            (-0.09, 0.71), (-0.08, 0.48), (-0.07, 0.36), (-0.06, 0.29), (-0.05, 0.23), (-0.04, 0.19),
                            (-0.03, 0.17), (-0.015, 0.16), (0.0, 0.18), (0.01, 0.21), (0.02, 0.26), (0.03, 0.32),
                            (0.04, 0.42), (0.05, 0.58), (0.06, 1.0), (0.07, 0.71), (0.08, 0.60), (0.09, 0.48),
                            (0.10, 0.37), (0.11, 0.27), (0.12, 0.16), (0.13, 0.04), (0.14, 0.0)])
    ends = R.soft(M, 0.915 - M.fabs(x) - M.fmax(M.fabs(y + 0.0025) - 0.06, 0.0), 0.06)
    h = pipe_y * ends
    for cx in (-0.3425, 0.3425):
        u = x - cx
        rect = D.rect(M, u, y, 0.0875, 0.23, 0.0, -0.015, rad=0.02)
        inside = R.soft(M, rect, 0.006)
        shelf = M.sel(M.lt(y, -0.09), 0.28, M.sel(M.gt(y, 0.11), 0.21, pipe_y * 0.55))
        h = h + (shelf - h) * inside
        side_dim = 0.28 + 0.72 * R.soft(M, M.fabs(y + 0.02) - 0.12, 0.03)     # the side lines sink over the pipe
        h = M.fmax(h, _edge_line(M, rect, 0.62) * side_dim)
        slot = D.rect(M, u, y, 0.035, 0.13, 0.0, -0.03, rad=0.02)
        h = M.fmax(h, R.rim(M, slot, 0.012, 0.42) * inside)
    return h

def disk06(M, x, y, aa):
    """Round plate with a hub ring and four outlined spokes."""
    h = R.plate(M, D.circle(M, x, y, 0.93), 0.35, 0.05, R.soft)
    px, py = D.radial(M, x, y, 4, mirror=False)
    spoke = D.rect(M, px, py, 0.08, 0.28, 0.0, -0.55, rad=0.04)
    tip = D.rect(M, px, py, 0.18, 0.05, 0.0, -0.78)
    shape = D.union(M, spoke, tip, D.ring(M, x, y, 0.22, 0.09))
    h = M.fmax(h, R.rim(M, shape, 0.025, 0.75))
    return M.fmax(h, R.plate(M, D.circle(M, x, y, 0.08), 0.8, 0.03, R.soft))


def _band(M, r, rc, half, edge=0.007):
    """A flat-topped ring band of half width `half` at radius rc: a sharp core plus a low skirt (0.2 at the edge,
    gone 0.03 out), as measured on ui17."""
    d = half - M.fabs(r - rc)
    core = R.soft(M, d + 0.003, edge)
    skirt = 0.2 * R.cl(M, 1.0 + d / 0.03)
    return M.fmax(core, skirt)


def _arc_on(M, deg, a0, a1, r, edge=0.006):
    """1 on the clockwise arc from a0 to a1 degrees (0 = up), straight radial cuts; deg in 0..360."""
    span = (a1 - a0) % 360.0
    rel = deg - a0
    rel = rel - M.floor(rel / 360.0) * 360.0
    inside = M.fmin(rel, span - rel) * (PI / 180.0) * r                 # tangential distance to the nearer cut
    return R.soft(M, inside + edge * 0.5, edge)


def ui17(M, x, y, aa):
    """Dial (all measured by a polar scan): a small centre ring (r 0.0875), four diagonal bars (r 0.165-0.325,
    width 0.02), an arc r 0.48 (clockwise 187..111 deg), a full ring r 0.5675, a thin full ring r 0.705, 67 ticks
    (period 3.463 deg, width ~1.3 deg, r 0.765-0.895, clockwise 209.7..80 deg) over a 0.21 band, and an outer arc
    r 0.965 (clockwise 159.5..104 deg). All bands flat-topped at 1.0."""
    r, a = D.polar(M, x, y)
    deg = a * (180.0 / PI)
    deg = deg - M.floor(deg / 360.0) * 360.0
    h = _band(M, r, 0.0865, 0.0145)
    px, py = D.radial(M, *D.rot(M, x, y, PI / 4.0), 4, mirror=False)
    h = M.fmax(h, R.soft(M, M.fmin(0.01 - M.fabs(px), M.fmin(-py - 0.165, 0.325 + py)) + 0.003, 0.006))
    h = M.fmax(h, _band(M, r, 0.48, 0.025) * _arc_on(M, deg, 187.0, 111.0, r))
    h = M.fmax(h, _band(M, r, 0.5665, 0.0265))
    h = M.fmax(h, _band(M, r, 0.704, 0.015))
    tick_arc = _arc_on(M, deg, 209.7, 79.7, r)
    tk = deg - 210.262                                                   # fitted: 67 ticks every 3.463 deg
    tk = (tk / 3.463 - M.floor(tk / 3.463 + 0.5)) * 3.463                     # degrees to the nearest tick centre
    ticks = R.soft(M, (0.62 - M.fabs(tk)) * (PI / 180.0) * r + 0.002, 0.005)
    band = _band(M, r, 0.83, 0.065)
    h = M.fmax(h, band * tick_arc * (0.21 + 0.79 * ticks))
    h = M.fmax(h, _band(M, r, 0.965, 0.02) * _arc_on(M, deg, 159.5, 104.0, r))
    return h

def ui18(M, x, y, aa):
    """Battery gauge (all measured): a 1.0 frame band (outer x -0.915..0.866, |y| 0.28, a terminal out to 0.912 for
    |y| < 0.14; inner x -0.815..0.766, |y| 0.215) with a low outer skirt; inside, 15 cells (|y| < 0.187) whose
    height ramps linearly from 1.0 at the left to 0 at the right (h = 1 - (x + 0.79) / 1.53), split by V grooves
    every 0.1103 from x -0.7924."""
    from pplib import curves as C
    outer = C.soft_max(M, D.rect(M, x, y, 0.8905, 0.28, -0.0245, 0.0, rad=0.03),
                       D.rect(M, x, y, 0.03, 0.14, 0.882, 0.0, rad=0.02), 0.005)
    inner = D.rect(M, x, y, 0.7905, 0.215, -0.0245, 0.0, rad=0.01)
    band = M.fmin(outer, -inner)
    core = R.soft(M, band + 0.003, 0.006)
    skirt = 0.35 * R.cl(M, 1.0 + outer / 0.035) * R.soft(M, -outer, 0.004)
    h = M.fmax(core, skirt)
    ramp = R.cl(M, 1.0 - (x + 0.79) / 1.53)
    g = M.fabs((M.frac((x + 0.7924) / 0.1103 + 0.5) - 0.5) * 0.1103)
    groove = R.ss(M, (g - 0.001) / 0.011)
    cells = ramp * groove * R.soft(M, 0.187 - M.fabs(y), 0.006) * R.soft(M, x + 0.795, 0.006) * R.soft(M, 0.766 - x, 0.006)
    return M.fmax(h, cells)

def ui21(M, x, y, aa):
    """Round boss in a ring with three bolted lugs."""
    lugs = None
    for k in range(3):
        a = 2 * PI * k / 3
        c = D.circle(M, x, y, 0.13, 0.82 * math.sin(a), -0.82 * math.cos(a))
        lugs = c if lugs is None else D.union(M, lugs, c)
    outer = D.union(M, D.circle(M, x, y, 0.82), lugs)
    h = R.plate(M, outer, 0.5, 0.05, R.soft)
    h = M.fmax(h, R.rim(M, D.circle(M, x, y, 0.72), 0.06, 0.8))
    h = M.fmax(h, 0.55 * R.dish(M, D.circle(M, x, y, 0.64), -0.3, 0.6) * R.hard(M, D.circle(M, x, y, 0.64), 0.01))
    for k in range(3):
        a = 2 * PI * k / 3
        h = R.inset(M, h, D.circle(M, x, y, 0.05, 0.86 * math.sin(a), -0.86 * math.cos(a)), 0.3, 0.02)
    return h


UI26_EDGE = [(-0.005, 0.0), (0.0, 0.52), (0.006, 0.82), (0.012, 0.93), (0.018, 0.975), (0.026, 1.0)]
UI26_HOLES = ((0.676, -0.501, 0.134, 0.086), (-0.425, -0.004, 0.133, 0.126), (0.0685, -0.0715, 0.1335, 0.0585),
              (-0.425, 0.395, 0.133, 0.126), (0.0685, 0.395, 0.1335, 0.126))


def ui26(M, x, y, aa, hole_rad=0.025):
    """A flat plate, rounded top edge, with a filleted notch bottom left, a step bottom right and five
    rounded window holes cut right through (measured)."""
    d = D.rect(M, x, y, 0.956, 0.708)
    d = D.sub(M, d, D.rect(M, x, y, 0.221, 0.35, -0.979, 0.855, rad=0.105))   # notch, filleted inner corner
    d = D.sub(M, d, D.rect(M, x, y, 0.411, 0.373, 0.789, 0.827, rad=0.01))   # step bottom right
    for (cx, cy, a, b) in UI26_HOLES:
        d = D.sub(M, d, D.rect(M, x, y, a, b, cx, cy, rad=hole_rad))
    return R.lathe(M, d, UI26_EDGE)


TILING06_EDGE = [(0.0, 1.0), (0.026, 1.0), (0.032, 0.985), (0.036, 0.946), (0.040, 0.842), (0.044, 0.683),
                 (0.048, 0.516), (0.052, 0.349), (0.056, 0.188), (0.060, 0.075), (0.064, 0.028), (0.068, 0.012),
                 (0.0714, 0.006)]


def tiling06(M, x, y, aa):
    """Fourteen flat-topped horizontal boards per tile (period 1/7), soft rounded edges; tiles vertically
    (measured: board centres at -1 + (k + 0.551) / 7)."""
    q = M.fabs(M.frac((y + 1.0) * 7.0 - 0.051) - 0.5) / 7.0
    return R.lathe(M, q, TILING06_EDGE)


MECH07_FRAME = [(0.0, 0.06), (0.015, 0.05), (0.03, 0.046), (0.045, 0.05), (0.057, 0.062), (0.065, 0.082),
                (0.075, 0.07), (0.09, 0.056), (0.105, 0.043), (0.12, 0.03), (0.14, 0.014), (0.16, 0.005), (0.18, 0.0)]
MECH07_FLOOR = [(-0.7, 0.604), (0.22, 0.603), (0.25, 0.593), (0.28, 0.569), (0.31, 0.539), (0.71, 0.13)]
MECH07_CYL = [(-0.69, 0.15), (-0.65, 0.143), (-0.63, 0.139), (-0.612, 0.15), (-0.598, 0.19), (-0.59, 0.192),
              (-0.57, 0.174), (-0.55, 0.155), (-0.53, 0.14), (-0.51, 0.131), (-0.49, 0.124), (-0.46, 0.122),
              (-0.43, 0.126), (-0.41, 0.134), (-0.39, 0.145), (-0.37, 0.161), (-0.35, 0.183), (-0.33, 0.218),
              (-0.31, 0.27)]
MECH07_KNUCKLE = [(-0.69, 0.15), (-0.66, 0.143), (-0.63, 0.104), (-0.60, 0.076), (-0.57, 0.056), (-0.54, 0.041),
                  (-0.51, 0.032), (-0.48, 0.028), (-0.45, 0.027), (-0.42, 0.031), (-0.39, 0.039), (-0.36, 0.052),
                  (-0.33, 0.07), (-0.30, 0.096), (-0.27, 0.125), (-0.24, 0.128), (-0.12, 0.122), (-0.09, 0.109),
                  (-0.06, 0.087), (0.06, 0.082), (0.09, 0.089), (0.13, 0.12)]
MECH07_BAR = [(-0.245, 0.30), (-0.22, 0.25), (-0.19, 0.165), (-0.16, 0.097), (-0.13, 0.071), (-0.10, 0.058),
              (-0.07, 0.054), (-0.04, 0.057), (-0.01, 0.067), (0.02, 0.081), (0.05, 0.096), (0.58, 0.348)]


def mechanical07(M, x, y, aa):
    """A sunken mechanism (an "in" alpha): a high floor at 0.6 sloping down to the right, with a low hinge,
    knuckles and a draw bar pressed into it, inside a box with a soft outer rim (measured region by region;
    every region's height is a measured profile along x)."""
    def put(h, d, v, w=0.006):
        return R.set_to(M, h, d + w * 0.5, v, w)
    yc = 0.015
    ay = M.fabs(y - yc)
    box = D.rect(M, x, y, 0.695, 0.415, 0.010, 0.010, rad=0.08)
    h = R.lathe(M, M.fmax(-box, 0.0), MECH07_FRAME)
    h = put(h, box, R.lathe(M, x, MECH07_FLOOR), 0.004)
    knuckle = D.union(M, D.rect(M, x, ay, 0.225, 0.13, -0.46, 0.291, rad=0.07),
                      D.rect(M, x, ay, 0.185, 0.0845, -0.06, 0.2775, rad=0.03))
    knuckle = D.inter(M, knuckle, box)
    h = put(h, knuckle, R.lathe(M, x, MECH07_KNUCKLE) + 0.03 * R.soft(M, ay - 0.33, 0.06))
    for (c0, c1) in ((0.362, 0.392), (0.166, 0.193)):              # light pin strips either side of the tabs
        h = put(h, D.rect(M, x, ay, 0.1225, (c1 - c0) * 0.5, -0.0275, (c0 + c1) * 0.5), 0.165)
    h = put(h, D.rect(M, x, ay, 0.187, 0.161, -0.498, 0.0, rad=0.01), R.lathe(M, x, MECH07_CYL))
    bar_v = R.lathe(M, x, MECH07_BAR)
    h = put(h, D.rect(M, x, ay, 0.4065, 0.168, 0.1665, 0.0, rad=0.05), bar_v)
    h = put(h, D.rect(M, x, y - yc, 0.145, 0.089, 0.43, 0.001, rad=0.01), bar_v + 0.066, 0.02)
    strip = 0.662 + (x - 0.14) * 0.731 + (0.2 - ay) * 1.2
    h = put(h, D.rect(M, x, ay, 0.2215, 0.0355, 0.3515, 0.2025), strip)
    return h


def vent68(M, x, y, aa):
    """Ring with a three-spoke hub."""
    h = R.rim(M, D.circle(M, x, y, 0.86), 0.09, 0.8)
    h = M.fmax(h, R.rim(M, D.circle(M, x, y, 0.46), 0.05, 0.8))
    px, py = D.radial(M, x, y, 3, mirror=False)
    h = M.fmax(h, R.plate(M, D.rect(M, px, py, 0.05, 0.22, 0.0, -0.22, rad=0.05), 0.85, 0.03, R.rounded))
    return M.fmax(h, R.plate(M, D.circle(M, x, y, 0.1), 0.9, 0.04, R.rounded))


C51_LINE = [(-0.034, 0.0), (-0.028, 0.03), (-0.024, 0.07), (-0.02, 0.14), (-0.016, 0.22), (-0.012, 0.30),
            (-0.008, 0.38), (-0.004, 0.45), (-0.0025, 0.5), (-0.001, 1.0), (0.001, 1.0), (0.0025, 0.27),
            (0.004, 0.23), (0.008, 0.165), (0.012, 0.11), (0.016, 0.07), (0.02, 0.035), (0.024, 0.012), (0.03, 0.0)]
C51_SEAM = [(-0.008, 0.0), (-0.004, 0.02), (-0.0015, 0.4), (0.0, 1.0), (0.0015, 0.6), (0.004, 0.27),
            (0.008, 0.07), (0.012, 0.01), (0.016, 0.0)]
C51_TONGUE = [(0.0, 1.0), (0.003, 0.55), (0.008, 0.49), (0.012, 0.42), (0.016, 0.36), (0.02, 0.27), (0.024, 0.20),
              (0.028, 0.14), (0.032, 0.08), (0.036, 0.04), (0.04, 0.01), (0.044, 0.0)]
C51_TAB = [(-0.006, 0.0), (0.0, 0.13), (0.004, 0.26), (0.009, 0.37), (0.013, 0.3), (0.018, 0.2), (0.025, 0.165),
           (0.035, 0.16)]
C51_TAB_OUTER = [(-0.925, 0.0), (-0.92, 0.01), (-0.91, 0.085), (-0.90, 0.16), (-0.88, 1.0)]


def container51(M, x, y, aa):
    """Octagonal door outline (thin ridge: gentle ramp inside, sharp outside, half 0.825 x 0.60, chamfers of
    slope 1.17), a thin seam across the middle that steps down round a trapezoid notch (y 0.0034 -> 0.1226 for
    |x| < 0.26), and a flat 0.16 hinge tab on each side with a ridge on its inner edges (all measured)."""
    ax = M.fabs(x - 0.001)
    ay = M.fabs(y)
    inside = M.fmin(0.8247 - ax, 0.6 - ay, 0.8678 - (ax + 1.17 * ay) * 0.64977)
    h = R.lathe(M, -inside, C51_LINE)
    # seam polyline (mirrored in x), signed: positive below the path
    sx, sy = M.fabs(x), y - 0.003
    path_y = 0.0004 + 0.1192 * M.clamp((0.262 - sx) / 0.0894)
    dist = M.fmin(-D.seg(M, sx, sy, 0.262, 0.0004, 0.56, 0.0004, 0.0),
                  -D.seg(M, sx, sy, 0.1726, 0.1196, 0.262, 0.0004, 0.0),
                  -D.seg(M, sx, sy, 0.0, 0.1196, 0.1726, 0.1196, 0.0))
    below = M.gt(sy, path_y)
    above_v = R.lathe(M, dist, C51_SEAM) + (R.lathe(M, dist, C51_TONGUE) - R.lathe(M, dist, C51_SEAM)) *         M.clamp((0.262 - sx) / 0.06)
    seam = M.sel(below, R.lathe(M, dist, C51_SEAM), above_v)
    seam = seam * M.clamp((0.575 - sx) / 0.01)
    h = M.fmax(h, seam)
    # hinge tabs
    td = D.chamfer_rect(M, M.fabs(x), y, 0.25, 0.121, 0.057, 0.805, 0.004)
    tab = M.fmin(R.lathe(M, td, C51_TAB), R.lathe(M, -M.fabs(x), C51_TAB_OUTER))
    cover = M.clamp((td + 0.006) / 0.006) * M.clamp((M.fabs(x) - 0.9) / 0.01 * -1.0 + 1.0)
    return M.fmax(h * (1.0 - cover), tab)


ITEMS = dict(
    armor01=(armor01, V2 + 'Armor/JRO_Armor01_02_out.tif', 0.0), armor04=(armor04, V2 + 'Armor/JRO_Armor04_02_out.tif', 0.0),
    armor06=(armor06, V2 + 'Armor/JRO_Armor06_02_out.tif', 0.0), armor10=(armor10, V2 + 'Armor/JRO_Armor10_02_out.tif', 0.0),
    cables14=(cables14, V2 + 'Cables&Pipes/JRO_cables14_in.tif', 0.0), disk06=(disk06, V2 + 'Disks-Engines/JRO_Disk06_in.tif', 0.0),
    ui17=(ui17, V2 + 'UI&Panels/JRO_UI&Panels17_01.tif', 0.0), ui18=(ui18, V2 + 'UI&Panels/JRO_UI&Panels18_01.tif', 0.0),
    ui21=(ui21, V2 + 'UI&Panels/JRO_UI&Panels21_out.tif', 0.0), ui26=(ui26, V2 + 'UI&Panels/JRO_UI&Panels26_out.tif', 0.0),
    tiling06=(tiling06, V2 + 'Tiling-Fillers/JRO_Tiling06_in.tif', 0.0),
    mechanical07=(mechanical07, V2 + 'Mechanical/JRO_Mechanical07_in.tif', 0.0),
    vent68=(vent68, V2 + 'Vents/JRO_Vent68_01_in.tif', 0.0), container51=(container51, V2 + 'Containers&Doors/JRO_Container51_in.tif', 0.0),
)


# --- round items rebuilt on lathe profiles (fitted to each reference's radial profile, fit_lathe.py) -----------------------
from lathe_knots import KNOTS


def _r(M, x, y): return M.fsqrt(x * x + y * y)


def armor06(M, x, y, aa):
    h = R.lathe(M, _r(M, x, y), KNOTS['armor06'])
    rv = M.fmax(R.rivets_circle(M, x, y, 0.88, 30, 0.03), R.rivets_circle(M, x, y, 0.6, 18, 0.03))
    return M.fmax(h, (h + 0.12 * rv) * M.b01(M.gt(rv, 0.0)))


def disk06(M, x, y, aa):
    """Spoked disc (measured): the base is the fitted lathe profile (the arms follow it); on top, very thin 1.0
    lines: per arm a U cap (side lines at +-0.10 from 0.61 out to a round end at 0.775) and two angled divider
    lines from (0.40, +-0.128) to (0.60, +-0.195) in arm coordinates."""
    h = R.lathe(M, _r(M, x, y), KNOTS['disk06'])
    lines = None
    for k in range(4):
        a = k * PI / 2.0
        ca, sa = math.cos(a), math.sin(a)
        al, ac = x * ca + y * sa, -x * sa + y * ca                     # along / across this arm
        cap = D.rect(M, al, ac, 0.0825, 0.10, 0.6925, 0.0, rad=0.055)
        u = R.rim(M, cap, 0.006, 1.0) * R.soft(M, al - 0.615, 0.008)
        armh = R.lathe(M, al, [(0.27, 0.48), (0.34, 0.48), (0.35, 0.42), (0.40, 0.36), (0.45, 0.32), (0.50, 0.28),
                               (0.55, 0.24), (0.60, 0.20), (0.65, 0.16), (0.70, 0.12)])
        inarm = R.soft(M, 0.058 - M.fabs(ac), 0.01) * R.soft(M, al - 0.27, 0.01) * R.soft(M, 0.72 - al, 0.01)
        h = h + (armh - h) * inarm
        d1 = R.rim(M, D.seg(M, al, M.fabs(ac), 0.40, 0.128, 0.60, 0.195, 0.0) * -1.0, 0.006, 1.0)
        e = M.fmax(u, d1)
        lines = e if lines is None else M.fmax(lines, e)
    return M.fmax(h, lines)


def ui21(M, x, y, aa):
    """Bolted round boss, centred at (0, 0.12) (measured): a dome (1.0 at the centre) falling to a groove at r 0.68,
    a rounded ring (0.81 at r 0.755) gone by r 0.87, and three lugs every 120 degrees (centres 0.98 from the
    middle, radius 0.15: a 0.55 boss, a step, a 0.36 rim) tied to the ring by wide 0.41 webs."""
    cy = 0.12
    r = M.fsqrt(x * x + (y - cy) * (y - cy))
    h = R.lathe(M, r, [(0.0, 1.0), (0.20, 1.0), (0.28, 0.99), (0.34, 0.98), (0.40, 0.96), (0.46, 0.92), (0.50, 0.89),
                       (0.55, 0.82), (0.60, 0.73), (0.65, 0.59), (0.67, 0.51), (0.68, 0.44), (0.69, 0.50), (0.70, 0.62),
                       (0.71, 0.71), (0.72, 0.76), (0.73, 0.79), (0.75, 0.81), (0.76, 0.81), (0.78, 0.79), (0.80, 0.70),
                       (0.81, 0.62), (0.82, 0.53), (0.83, 0.43), (0.84, 0.31), (0.85, 0.20), (0.86, 0.06), (0.87, 0.0)])
    for lx, ly in ((0.0, -0.83), (0.808, 0.623), (-0.808, 0.623)):             # measured lug centres
        dl = M.fsqrt((x - lx) * (x - lx) + (y - ly) * (y - ly))
        lug = R.lathe(M, dl, [(0.0, 0.55), (0.06, 0.55), (0.07, 0.50), (0.09, 0.47), (0.10, 0.40), (0.12, 0.36),
                              (0.13, 0.31), (0.14, 0.24), (0.15, 0.14), (0.155, 0.0)])
        neck = 0.41 * R.soft(M, 0.16 - D.seg(M, x, y, lx * 0.7, cy + (ly - cy) * 0.7, lx * 0.93, cy + (ly - cy) * 0.93, 0.0) * -1.0, 0.04)
        h = M.fmax(h, M.fmax(lug, neck))
    return h


VENT68_C = (0.0068, 0.0038)
VENT68_R = [(0.0, 0.372), (0.048, 0.371), (0.052, 0.359), (0.056, 0.324), (0.060, 0.301), (0.064, 0.27),
            (0.068, 0.227), (0.072, 0.166), (0.076, 0.102), (0.080, 0.049), (0.084, 0.017), (0.088, 0.005),
            (0.094, 0.0), (0.146, 0.0), (0.148, 0.004), (0.152, 0.014), (0.156, 0.037), (0.160, 0.081),
            (0.164, 0.149), (0.168, 0.239), (0.172, 0.341), (0.176, 0.452), (0.180, 0.572), (0.184, 0.697),
            (0.188, 1.0), (0.404, 1.0), (0.408, 0.687), (0.412, 0.586), (0.416, 0.488), (0.420, 0.401),
            (0.424, 0.312), (0.428, 0.233), (0.432, 0.164), (0.436, 0.107), (0.440, 0.063), (0.444, 0.032),
            (0.448, 0.014), (0.452, 0.005), (0.458, 0.0), (0.510, 0.0), (0.516, 0.004), (0.520, 0.011),
            (0.524, 0.028), (0.528, 0.068), (0.532, 0.14), (0.536, 0.242), (0.540, 0.348), (0.544, 0.427),
            (0.548, 0.454), (0.552, 0.391), (0.556, 0.26), (0.560, 0.124), (0.564, 0.05), (0.568, 0.024),
            (0.572, 0.013), (0.580, 0.004), (0.592, 0.0), (0.800, 0.0), (0.812, 0.004), (0.820, 0.011),
            (0.824, 0.019), (0.828, 0.036), (0.832, 0.079), (0.836, 0.193), (0.840, 0.459), (0.844, 0.668),
            (0.848, 0.696), (0.852, 0.611), (0.856, 0.473), (0.860, 0.324), (0.864, 0.189), (0.868, 0.099),
            (0.872, 0.047), (0.876, 0.026), (0.884, 0.012), (0.896, 0.005), (0.92, 0.0)]
VENT68_SLOT = [(0.0, 0.01), (0.03, 0.015), (0.035, 0.03), (0.04, 0.075), (0.045, 0.15), (0.05, 0.38),
               (0.055, 0.59), (0.06, 0.81), (0.065, 1.0)]


def vent68(M, x, y, aa):
    """A disc with a sunk hub and a groove ring, three straight slots (0, 120, 240 degrees) cut from the hub
    groove out through the rim, and two thin rings around it (measured about the true centre)."""
    dx, dy = x - VENT68_C[0], y - VENT68_C[1]
    h = R.lathe(M, M.fsqrt(dx * dx + dy * dy), VENT68_R)
    for deg in (0.0, 120.0, 240.0):
        c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        along = c * dx + s * dy
        u = M.sel(M.gt(along, 0.09), M.fabs(c * dy - s * dx), 1.0)
        h = M.fmin(h, R.lathe(M, u, VENT68_SLOT))
    return h


for _n in ('armor06', 'disk06', 'ui21', 'vent68'):
    ITEMS[_n] = (globals()[_n],) + ITEMS[_n][1:]
