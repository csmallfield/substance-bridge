"""JRO hard-surface alphas Vol. 3 rebuilt as maths (pplib.decals + pplib.relief). Same conventions as items.py.
Round parts use lathe profiles fitted by fit_lathe.py. PRIVATE: recreations of a commercial pack."""
import math
import sys
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
from pplib import decals as D, relief as R, curves as C
from lathe_knots import KNOTS

PI = math.pi
V3 = '../../../JRO_Alphas_HardSurface_Vol.3/Tiff/'      # relative to the Vol. 1 Tiff/ folder


def _r(M, x, y): return M.fsqrt(x * x + y * y)
def _lathe(M, x, y, name): return R.lathe(M, _r(M, x, y), KNOTS.get(name, [(0.0, 0.0), (1.0, 0.0)]))


def a21(M, x, y, aa): return _lathe(M, x, y, 'a21')                                   # raised ring
def a24(M, x, y, aa): return _lathe(M, x, y, 'a24')                                   # stepped round boss
def a25(M, x, y, aa):
    """Ring in a ring (lathe) plus two crescent tabs left and right on the inner edge (measured): peak 1.0 at
    r 0.30-0.33 with a cliff inside, falling to the 0.5 shelf by r 0.42 (radially: the taper seen along a column
    is just the radius growing), ending in straight cuts at |y| 0.175."""
    h = _lathe(M, x, y, 'a25')
    r, a = D.polar(M, x, y)
    f = R.lathe(M, r, [(0.30, 1.0), (0.33, 1.0), (0.34, 0.94), (0.35, 0.87), (0.36, 0.80), (0.37, 0.72), (0.38, 0.65),
                       (0.39, 0.59), (0.40, 0.55), (0.41, 0.52), (0.42, 0.51)])
    w = R.soft(M, 0.175 - M.fabs(y), 0.012)                               # tabs end in straight cuts at |y| 0.175
    on = w * R.hard(M, r - 0.302, 0.004) * R.soft(M, 0.43 - r, 0.01)
    return h + M.fmax(f - h, 0.0) * on                                  # blend toward the tab only where it rises

A39_SEGS = [  # (from deg, to deg, inner r, outer r) clockwise from the top, measured
    (16.5, 57.0, 0.390, 0.475), (77.5, 118.0, 0.385, 0.475), (138.5, 225.0, 0.395, 0.605),
    (243.0, 283.5, 0.415, 0.495), (301.0, 341.0, 0.405, 0.485)]


def a39(M, x, y, aa):
    """Concentric cap (measured): a base lathe fitted to the GAPS (8th percentile), slightly tilted (+0.075 x
    inside r 0.39), and five raised ring segments; each starts with a lip (0.87) at its inner radius and decays
    0.85 / 0.78 / 0.72 / 0.70 / 0.68 / 0.66 per 0.01 outward to a cliff at its outer radius. The bottom segment
    continues into a 0.55 shelf out to r 0.605."""
    r, a = D.polar(M, x, y)
    h = _lathe(M, x, y, 'a39') + 0.075 * x * R.soft(M, 0.39 - r, 0.02)
    deg = a * (180.0 / PI)
    deg = deg - M.floor(deg / 360.0) * 360.0                            # 0..360 clockwise from the top
    for a0, a1, ri, ro in A39_SEGS:
        knots = [(0.0, 0.87), (0.01, 0.85), (0.02, 0.78), (0.03, 0.72), (0.04, 0.70), (0.05, 0.68), (0.06, 0.66),
                 (0.08, 0.63)]
        if ro > 0.55:
            knots = knots[:-1] + [(0.08, 0.65), (0.09, 0.61), (0.10, 0.57), (0.11, 0.55), (0.30, 0.55)]
        seg = R.lathe(M, r - ri, knots)
        ang_in = R.hard(M, (M.fmin(deg - a0, a1 - deg)) * (PI / 180.0) * r, 0.004)
        on = ang_in * R.hard(M, r - ri, 0.004) * R.soft(M, ro - r, 0.012)
        h = h + (seg - h) * on
    return h



def a22(M, x, y, aa):
    """Ring with a cross (measured): floor 0.43; four arms with flat tops |across| < 0.03 sloping 0.71 -> 0.61 from
    r 0.14 to 0.31, chamfered down to the floor by 0.05 across and by r 0.37 at the ends; an OCTAGONAL centre
    plateau 0.97 (apothem 0.098) chamfered down over 0.04."""
    h = _lathe(M, x, y, 'a22')
    ax, ay = M.fabs(x), M.fabs(y)
    along, across = M.fmax(ax, ay), M.fmin(ax, ay)
    top = R.lathe(M, along, [(0.0, 0.73), (0.14, 0.71), (0.31, 0.61), (0.33, 0.58), (0.36, 0.46), (0.37, 0.43)])
    arm = top - (top - 0.43) * R.cl(M, (across - 0.03) / 0.02)
    octo = M.fmax(M.fmax(ax, ay), (ax + ay) * 0.70710678)
    centre = 0.97 - 0.54 * R.cl(M, (octo - 0.098) / 0.04)
    inner = M.fmax(arm, centre) * R.soft(M, 0.42 - M.fsqrt(x * x + y * y), 0.01)   # cross only inside the ring
    return M.fmax(h, inner)

def a40(M, x, y, aa):
    """Screw cap (measured): a cap plateau 1.0 (r < 0.32) sloping to 0.50 at r 0.48, a cliff into a valley (0.16 at
    r 0.56) and an outer ring (0.35 at r 0.66). Across the cap a SUNK channel |y| < 0.165: floor 0.32, sides rising
    0.39-0.62 toward its edge, and the floor ramps up toward the cap rim (0.32 + 0.83 (r - 0.30))."""
    r = M.fsqrt(x * x + y * y)
    cap = R.lathe(M, r, [(0.0, 1.0), (0.32, 1.0), (0.34, 0.96), (0.36, 0.84), (0.38, 0.73), (0.40, 0.64), (0.42, 0.59),
                         (0.44, 0.56), (0.46, 0.52), (0.48, 0.50), (0.50, 0.34), (0.52, 0.25), (0.54, 0.18),
                         (0.56, 0.16), (0.58, 0.18), (0.60, 0.22), (0.62, 0.26), (0.64, 0.31), (0.66, 0.35),
                         (0.68, 0.23), (0.70, 0.16), (0.72, 0.10), (0.74, 0.07), (0.76, 0.04), (0.78, 0.02), (0.82, 0.0)])
    ay = M.fabs(y)
    side = R.lathe(M, ay, [(0.0, 0.32), (0.05, 0.32), (0.08, 0.39), (0.10, 0.47), (0.12, 0.51), (0.14, 0.55),
                           (0.16, 0.62)])
    ramp = 0.32 + M.fmax(r - 0.30, 0.0) * 0.83
    chan = M.fmax(side, ramp)
    inside = R.hard(M, 0.165 - ay, 0.004) * R.soft(M, 0.49 - r, 0.01)
    return cap + (chan - cap) * inside

def a82(M, x, y, aa):
    """Porthole flange (measured): lathe profile plus six raised lugs on the inner rim (r 0.532) at +-34.5, +-91 and
    +-146.5 degrees: each a capsule (radius 0.047) stretched 0.02 toward the centre, flat top 0.93, a stepped hole
    (0.75 ring to r 0.028, 0.63 to r 0.016)."""
    h = _lathe(M, x, y, 'a82')
    for deg in (34.5, -34.5, 91.0, -91.0, 146.5, -146.5):
        t = deg * PI / 180.0
        ux, uy = math.sin(t), -math.cos(t)                              # outward direction of this lug
        cx, cy = 0.532 * ux, 0.532 * uy
        px, py = x - cx, y - cy
        along = px * ux + py * uy                                       # + outward
        across = -px * uy + py * ux
        ac = M.fmin(M.fmax(along, -0.02), 0.0)                          # capsule spine from -0.02 to 0
        dist = M.fsqrt((along - ac) * (along - ac) + across * across)
        body = 0.047 - dist
        c = M.fsqrt(px * px + py * py)
        top = R.lathe(M, c, [(0.0, 0.63), (0.015, 0.63), (0.018, 0.75), (0.026, 0.75), (0.03, 0.93)])
        on = R.soft(M, body + 0.006, 0.012)
        h = h + (M.fmax(top, h) - h) * on
    return h

def a89(M, x, y, aa):
    """Dish screw (measured): the dish lathe profile, tilted (lower at the top, +0.13 y); inside r 0.175 a low bowl
    (0.06) with a RAISED cross of tent ridges (0.35 at r 0.11, base half width 0.025), like a91's screw."""
    r = M.fsqrt(x * x + y * y)
    h = _lathe(M, x, y, 'a89') + 0.13 * y * R.soft(M, 0.5 - r, 0.06)
    bowl = R.lathe(M, r, [(0.0, 0.06), (0.05, 0.06), (0.08, 0.10), (0.10, 0.13), (0.12, 0.17), (0.14, 0.23),
                          (0.155, 0.29), (0.17, 0.36)])
    top = R.lathe(M, r, [(0.0, 0.24), (0.05, 0.27), (0.11, 0.35), (0.14, 0.33), (0.16, 0.28)])
    across = M.fmin(M.fabs(x), M.fabs(y))
    tent = top - (top - bowl) * R.cl(M, across / 0.025)
    screw = M.fmax(bowl, tent * R.soft(M, 0.165 - r, 0.006))
    return h + (screw - h) * R.soft(M, 0.172 - r, 0.003)

def a98(M, x, y, aa):
    """Fan (measured): the lathe profile carries the hub, the raised blade disc (1.0, r 0.165-0.485) and the outer
    rings; four curved GAPS are sunk into the disc to 0.77, each 29 degrees wide, centred at 25 + 90k degrees at the
    hub and sweeping clockwise by 18 degrees x ((r - 0.18) / 0.28)^2 toward the rim."""
    h = _lathe(M, x, y, 'a98')
    r, a = D.polar(M, x, y)
    t = R.cl(M, (r - 0.18) / 0.28)
    centre = (25.0 + 18.0 * t * t) * (PI / 180.0)
    w = PI / 2.0
    da = a - centre
    da = da - M.floor(da / w + 0.5) * w                                # angle to the nearest gap centre
    gap = (14.5 * PI / 180.0 - M.fabs(da)) * r                         # tangential distance inside the gap
    gap = C.soft_min(M, gap, C.soft_min(M, r - 0.165, 0.485 - r, 0.03), 0.04)   # rounded gap corners
    return R.set_to(M, h, gap, 0.77, 0.014, R.soft)

def a15(M, x, y, aa):
    """Ring boss on two arms (measured): the arms only exist OUTSIDE the ring: flat tops at 1.0, |y| < 0.09, round
    ends at |x| 0.785, a soft foot (0.5 falling to 0 over 0.05). The ring and its low centre boss are a lathe
    profile fitted to the reference."""
    ax = M.fabs(x)
    d = 0.09 - M.fsqrt(M.fmax(ax - 0.695, 0.0) ** 2 + y * y)          # capsule ending at x = 0.785
    qo = R.cl(M, -d / 0.05)
    arm = R.hard(M, d, 0.004) + 0.5 * (1.0 - qo) * (1.0 - qo) * (1.0 - R.hard(M, d, 0.004))
    r = M.fsqrt(x * x + y * y)
    arm = arm * R.soft(M, r - 0.395, 0.006)                          # no bar inside the ring
    return M.fmax(_lathe(M, x, y, 'a15'), arm)

def a90(M, x, y, aa):
    """Four-lobed knob (all measured): flat-ended lobes on the axes (0.58), concave circular waists on the
    diagonals (0.453). Inside: a sharp lip (0.73) at the outline, a 0.65 plateau, then a ROUND funnel down to a
    0.17 floor at r 0.26 with two thin rings (r 0.14, 0.20); a dished centre with a RAISED cross of narrow ridges
    (0.27 at r 0.10). Outside: a soft skirt decaying from 0.6 to 0 over ~0.25."""
    r = M.fsqrt(x * x + y * y)
    # outline fitted to 10 measured rays: a square (half 0.58) with circular scallops (radius 0.799, centres on the
    # diagonals 1.252 out), joined with a small rounding
    ax, ay = M.fabs(x), M.fabs(y)
    k = 1.252 / 1.41421356
    scallop = M.fsqrt((ax - k) * (ax - k) + (ay - k) * (ay - k)) - 0.799
    d = C.soft_min(M, C.soft_min(M, 0.598 - ax, 0.598 - ay, 0.02), scallop + 0.012, 0.03)
    funnel = R.lathe(M, r, [(0.0, 0.0), (0.05, 0.02), (0.08, 0.06), (0.10, 0.10), (0.12, 0.15), (0.135, 0.21),
                            (0.14, 0.22), (0.15, 0.17), (0.19, 0.17), (0.20, 0.25), (0.21, 0.17), (0.25, 0.17),
                            (0.26, 0.18), (0.28, 0.22), (0.30, 0.28), (0.34, 0.41), (0.38, 0.54), (0.42, 0.655)])
    q = R.cl(M, d / 0.03)
    lip = 0.65 + 0.11 * (1.0 - q) * (1.0 - q)
    inner = M.fmax(funnel, lip * R.soft(M, r - 0.40, 0.04) + funnel * (1.0 - R.soft(M, r - 0.40, 0.04)))
    inner = M.fmax(funnel, M.fmin(inner, lip))
    arm = R.lathe(M, r, [(0.0, 0.18), (0.04, 0.20), (0.10, 0.27), (0.125, 0.23), (0.135, 0.20)])
    across = M.fmin(M.fabs(x), M.fabs(y))
    ridge = (arm - 0.2 * R.cl(M, across / 0.03)) * R.soft(M, 0.135 - r, 0.005)
    inner = M.fmax(inner, ridge)
    qo = R.cl(M, -d / 0.26)
    q1 = 1.0 - qo
    foot = 0.6 * q1 * q1 * M.fsqrt(q1)                                # (1 - q)^2.5
    return foot + (inner - foot) * R.hard(M, d, 0.004)

def a91(M, x, y, aa):
    """Flange (all measured): a raised body (0.87) bounded by flat ends y = +-0.455 and slanted sides through
    (0.245, 0.42)-(0.53, 0.30), cut by two low round eyes (floor 0.05, radius 0.29 at x = +-0.65) that hold a thin
    ring (r 0.12). The outer edge is an alpha 'cliff': a soft foot to 0.23, a sharp step to 0.97, decaying to 0.87.
    The centre screw is a lathe profile (rim 0.93 at r 0.25, bowl, low centre 0.61) with a recessed cross."""
    ax, ay = M.fabs(x), M.fabs(y)
    outer = M.fmin(0.455 - ay, D.side(M, ax, ay, 0.245, 0.42, 0.53, 0.30, 0.0, 0.0), 0.65 - ax)
    le = M.fsqrt((ax - 0.65) * (ax - 0.65) + y * y)                 # distance to the nearer eye centre
    eye = le - 0.29                                                  # > 0 outside the eye cut
    d = M.fmin(outer, eye)
    lip = 0.97 - 0.10 * R.soft(M, d, 0.06)                           # inside: sharp lip decaying to the plateau
    foot = 0.23 * R.soft(M, d + 0.08, 0.08)                          # outside: soft foot up to the cliff
    cliff = foot + (lip - foot) * R.hard(M, d, 0.004)
    soft_edge = 0.05 + 0.82 * R.soft(M, d + 0.005, 0.05)             # where the body meets an eye: no lip, no foot
    w = R.soft(M, outer - eye, 0.03)                                 # 1 where the eye edge is the nearer one
    h = cliff + (soft_edge - cliff) * w
    # eyes: low floor with a raised rim at their outer edge and a thin ring
    in_eye = R.soft(M, -eye, 0.004) * R.soft(M, outer + 0.4, 0.01)
    eye_h = 0.05 + 0.23 * R.soft(M, le - 0.245, 0.04) * R.soft(M, 0.29 - le, 0.002)
    eye_h = M.fmax(eye_h, 0.05 + R.rim(M, le - 0.12, 0.012, 0.08))
    eye_h = M.fmax(eye_h, 0.08 * R.soft(M, 0.12 - le, 0.004))
    outside_body = R.soft(M, -outer, 0.004)
    eye_region = R.soft(M, 0.29 - le, 0.004) * (1.0 - R.soft(M, outer, 0.004) * R.soft(M, eye, 0.004))
    h = h + (M.fmax(h, eye_h) - h) * R.soft(M, 0.29 - le, 0.004) * R.soft(M, 1.0 - 0.0 * x, 1.0)
    # centre screw: a LOW bowl (0.27) rising to a sharp rim (0.92 at r 0.25), with a RAISED cross of tent-shaped
    # ridges (peak 0.75 at r 0.12, base half width 0.044) meeting at 0.61 in the middle
    r = M.fsqrt(x * x + y * y)
    bowl = R.lathe(M, r, [(0.0, 0.27), (0.07, 0.27), (0.10, 0.30), (0.14, 0.38), (0.18, 0.51), (0.21, 0.65),
                          (0.23, 0.78), (0.25, 0.92), (0.26, 0.87), (0.27, 0.85)])
    top = R.lathe(M, r, [(0.0, 0.61), (0.06, 0.65), (0.12, 0.75), (0.17, 0.73), (0.20, 0.67), (0.215, 0.66)])
    across = M.fmin(ax, ay)                                          # distance across the nearer arm
    tent = top - (top - bowl) * R.cl(M, across / 0.044)
    screw = M.fmax(bowl, tent * R.soft(M, 0.215 - r, 0.01) + bowl * (1.0 - R.soft(M, 0.215 - r, 0.01)))
    return h + (screw - h) * R.soft(M, 0.27 - r, 0.003)

def a93(M, x, y, aa):
    """Hinge (all measured): an octagonal plate at 0.838 (sides x 0.385, ends y 0.89, chamfers to x 0.18) with a thin
    raised line along its edge; six screw rings (radius 0.0875, lines peaking at 0.99, centres sunk to 0.813) at
    (0, +-0.653) and (+-0.187, +-0.306); across the middle a rounded trough |y| < 0.1 (parabolic, 0.02 at the
    bottom) for the knuckle, split by thin raised lines at x = +-0.18."""
    ax, ay = M.fabs(x), M.fabs(y)
    k = 0.025                                                      # slight corner rounding (soft min of the edge planes)
    d = C.soft_min(M, C.soft_min(M, 0.385 - ax, 0.89 - ay, k), D.side(M, ax, ay, 0.385, 0.633, 0.18, 0.89, 0.0, 0.0), k)
    h = 0.838 * R.soft(M, d + 0.045, 0.07)
    h = M.fmax(h, R.rim(M, d - 0.012, 0.011, 1.0))
    for cx, cy in ((0.0, -0.653), (0.0, 0.653), (-0.187, -0.306), (0.187, -0.306), (-0.187, 0.306), (0.187, 0.306)):
        c = D.circle(M, x, y, 0.0875, cx, cy)
        h = R.set_to(M, h, c - 0.012, 0.813, 0.004, R.soft)
        h = M.fmax(h, R.rim(M, c, 0.011, 0.99))
    trough = 0.02 + 0.82 * (y / 0.1) * (y / 0.1)
    inb = R.soft(M, 0.1 - ay, 0.01) * R.soft(M, d, 0.01)
    h = h + (M.fmin(trough, h) - h) * inb
    div = R.rim(M, ax - 0.18, 0.009, 1.0) * R.soft(M, 0.1 - ay, 0.01)
    # knuckle edge lines: the middle segment's on its lower edge, the outer segments' on their upper edge
    mid = R.soft(M, 0.18 - ax, 0.004)
    edge_y = 0.09 * mid - 0.09 * (1.0 - mid)
    lip = R.rim(M, y - edge_y, 0.009, 0.97) * R.soft(M, d, 0.01)
    return M.fmax(M.fmax(h, div), lip)

def a62(M, x, y, aa):
    """Diamond cushion (flat top 0.835) whose ends fade out over a long slope, holding a round screw: a sharp rim
    (0.97 at r 0.26), a bowl falling to 0.52 at the centre, a raised slot bar and a square nub. All measured."""
    ay = M.fsqrt(y * y + 0.25 * 0.25) - 0.25                       # |y| rounded near the equator
    hw = 0.51 - 0.7 * ay                                           # half width, fitted to 8 measured rows
    edge = R.soft(M, hw - M.fabs(x) + 0.1, 0.2)                   # S edge 0.2 wide centred on the outline
    ends = R.soft(M, 0.88 - M.fabs(y), 0.47)                      # long fade toward the tips
    body = 0.835 * edge * ends
    r = M.fsqrt(x * x + y * y)
    boss = R.lathe(M, r, [(0.0, 0.52), (0.06, 0.52), (0.10, 0.54), (0.14, 0.60), (0.18, 0.69), (0.22, 0.80),
                          (0.245, 0.92), (0.26, 0.97), (0.275, 0.90), (0.29, 0.835)])
    inside = R.soft(M, 0.29 - r, 0.004)
    h = body + (boss - body) * inside
    bar = R.soft(M, 0.035 - M.fabs(y), 0.012) * R.soft(M, 0.235 - M.fabs(x), 0.02)
    h = h + 0.12 * bar
    return R.set_to(M, h, D.rect(M, x, y, 0.05, 0.05), 0.785, 0.01, R.soft)

def a34(M, x, y, aa):
    """Rounded-rect plate (top 0.705) with two thin raised lines near its edge and a slightly lower field (0.653).
    Measured: outer edge x 0.78 / y 0.43, lines at 0.039 and 0.115 in from the edge (peaks 0.92, 0.99)."""
    d = D.rect(M, x, y, 0.778, 0.451, -0.003, 0.02, rad=0.172)        # centre (-0.003, 0.02), measured
    h = 0.705 * R.soft(M, d + 0.004, 0.04)
    h = R.set_to(M, h, d - 0.135, 0.653, 0.008, R.soft)
    h = M.fmax(h, R.rim(M, d - 0.039, 0.012, 0.92))
    return M.fmax(h, R.rim(M, d - 0.115, 0.014, 0.995))


ITEMS = dict(
    a21=(a21, V3 + 'JRO_HS_Alpha21_in.tif', 0.0), a22=(a22, V3 + 'JRO_HS_Alpha22_in.tif', 0.0),
    a24=(a24, V3 + 'JRO_HS_Alpha24_in.tif', 0.0), a25=(a25, V3 + 'JRO_HS_Alpha25_in.tif', 0.0),
    a39=(a39, V3 + 'JRO_HS_Alpha39_in.tif', 0.0), a40=(a40, V3 + 'JRO_HS_Alpha40_in.tif', 0.0),
    a82=(a82, V3 + 'JRO_HS_Alpha82_in.tif', 0.0), a89=(a89, V3 + 'JRO_HS_Alpha89_in.tif', 0.0),
    a98=(a98, V3 + 'JRO_HS_Alpha98_in.tif', 0.0), a15=(a15, V3 + 'JRO_HS_Alpha15_in.tif', 0.0),
    a90=(a90, V3 + 'JRO_HS_Alpha90_in.tif', 0.0), a91=(a91, V3 + 'JRO_HS_Alpha91_in.tif', 0.0),
    a93=(a93, V3 + 'JRO_HS_Alpha93_in.tif', 0.0), a62=(a62, V3 + 'JRO_HS_Alpha62_in.tif', 0.0),
    a34=(a34, V3 + 'JRO_HS_Alpha34_in.tif', 0.0),
)
ROUND = ['a21', 'a22', 'a24', 'a25', 'a39', 'a40', 'a82', 'a89', 'a98', 'a15']
