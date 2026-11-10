"""JRO hard-surface alphas rebuilt as maths with pplib.decals + pplib.relief. Each item(M, x, y, aa) returns height
0..1 in alpha space (x, y in -1..1, y down; aa = one pixel). PRIVATE: recreations of a commercial pack.
ITEMS: name -> (function, reference path under Tiff/, cross-section row in -1..1 for compare.py)."""
import math
import sys
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
from pplib import decals as D, relief as R

PI = math.pi


# --- base shapes ----------------------------------------------------------------------------------------------------------
def base01(M, x, y, aa):
    """Thin raised line around a chamfered rectangle (measured): centred at |x| 0.750, |y| 0.832, corner chamfer
    0.142 with rounding; peak ~0.88; asymmetric profile: half height at 0.021 outside, 0.011 inside."""
    from pplib import curves as C
    ax, ay = M.fabs(x), M.fabs(y)
    d = C.soft_min(M, C.soft_min(M, 0.75 - ax, 0.832 - ay, 0.01), (0.75 + 0.832 - 0.142 - ax - ay) * 0.70710678, 0.015)
    w = M.sel(M.lt(d, 0.0), 0.021 / 0.41, 0.011 / 0.41)
    q = R.cl(M, M.fabs(d) / w)
    k = 1.0 - q * q
    return 0.88 * k * k * k

def base03(M, x, y, aa):
    """Raised pill (measured): half sizes 0.92 x 0.305 at half height, fully rounded ends, flat top 1.0, an S edge
    about 0.10 wide centred on the outline."""
    d = D.rect(M, x, y, 0.92, 0.305, rad=0.305)
    return R.soft(M, d + 0.05, 0.10)

def base14(M, x, y, aa):
    """Round boss with a low outer ring step."""
    h = R.plate(M, D.circle(M, x, y, 0.82), 0.16, 0.05, R.soft)
    return R.raise_to(M, h, D.circle(M, x, y, 0.6), 1.0, 0.12, R.soft)


def base27(M, x, y, aa):
    """Trapezoid plate inside a thin outline with rounded ear corners (measured). Plate: flat 1.0, half width
    0.575 + 0.078 y about x = -0.008, y -0.577..0.571, S edge ~0.05 wide. Outline: peak 0.52, half width
    0.773 + 0.103 y, y -0.754..0.780, ears of radius 0.06 at its corners, asymmetric profile (wide outside)."""
    from pplib import curves as C
    xc = x + 0.008
    k1 = math.hypot(1.0, 0.078)
    plate = C.soft_min(M, (0.565 + 0.078 * y - M.fabs(xc)) / k1, C.soft_min(M, y + 0.587, 0.581 - y, 0.01), 0.04)
    h = R.soft(M, plate + 0.036, 0.05)
    k2 = math.hypot(1.0, 0.103)
    tr = M.fmin((0.773 + 0.103 * y - M.fabs(xc)) / k2, M.fmin(y + 0.754, 0.780 - y))
    ears = None
    for cx, cy in ((-0.68, -0.738), (0.68, -0.738), (-0.835, 0.762), (0.835, 0.762)):
        e = D.circle(M, xc, y, 0.058, cx, cy)
        ears = e if ears is None else M.fmax(ears, e)
    d = C.soft_max(M, tr, ears, 0.03)
    w = M.sel(M.lt(d, 0.0), 0.022 / 0.41, 0.012 / 0.41)
    q = R.cl(M, M.fabs(d) / w)
    kk = 1.0 - q * q
    return M.fmax(h, 0.52 * kk * kk * kk)

def _round_head(M, x, y, r=0.86):
    d = D.circle(M, x, y, r)
    return d, R.soft(M, d, 0.07) * R.dish(M, d, 0.84, r * 0.85) * 0.86


def bolt01(M, x, y, aa):
    """Round head (a dish in alpha terms) with a straight slot."""
    d, h = _round_head(M, x, y)
    slot = D.rect(M, x, y, 0.12, 0.62, rad=0.12)
    return R.set_to(M, h, slot, 1.0, 0.02, R.soft)


def bolt04(M, x, y, aa):
    d, h = _round_head(M, x, y)
    cross = D.union(M, D.rect(M, x, y, 0.15, 0.62, rad=0.15), D.rect(M, x, y, 0.62, 0.15, rad=0.15))
    return R.set_to(M, h, cross, 1.0, 0.03, R.soft)


def bolt12(M, x, y, aa):
    """Torx: a six-lobed star with round notches and a pin hole."""
    d, h = _round_head(M, x, y)
    star = D.grow(M, D.star(M, x, y, 6, 0.62, 0.36), 0.0)
    star = D.sub(M, star, D.circle(M, x, y, 0.15))
    return R.set_to(M, h, star, 1.0, 0.02, R.soft)


def _hex_head(M, x, y, knots):
    """Hex bolt head (measured): a hexagon (apothem 0.84, vertices on x) whose height is a raised RIM profile of
    the inside distance from its edge, falling to a 0 floor about 0.22 in."""
    d = D.polygon(M, x, y, 6, 0.97, PI / 6)
    return d, R.lathe(M, d, [(-0.02, 0.0)] + knots)

def bolt16(M, x, y, aa):
    """Hex head + raised cross (arms half width 0.12, reach 0.56, soft edge ~0.06, round ends)."""
    d, h = _hex_head(M, x, y, [(0.0, 0.02), (0.02, 0.14), (0.04, 0.47), (0.06, 0.77), (0.08, 0.80), (0.10, 0.68),
                               (0.12, 0.51), (0.14, 0.33), (0.16, 0.19), (0.18, 0.09), (0.20, 0.04), (0.22, 0.01),
                               (0.24, 0.0)])
    cross = D.union(M, D.rect(M, x, y, 0.12, 0.56, rad=0.12), D.rect(M, x, y, 0.56, 0.12, rad=0.12))
    return M.fmax(h, R.soft(M, cross + 0.03, 0.06))

def bolt22(M, x, y, aa):
    """Hex head + raised centre hexagon (circumradius 0.32, vertices on x, soft edge ~0.06)."""
    d, h = _hex_head(M, x, y, [(0.0, 0.04), (0.02, 0.29), (0.04, 0.70), (0.06, 0.85), (0.08, 0.76), (0.10, 0.60),
                               (0.12, 0.42), (0.14, 0.26), (0.16, 0.14), (0.18, 0.06), (0.20, 0.02), (0.22, 0.0)])
    core = D.polygon(M, x, y, 6, 0.32, PI / 6)
    return M.fmax(h, R.soft(M, core + 0.04, 0.06))

VENT12 = [(-0.006, -0.683), (-0.3275, -0.340), (0.3175, -0.340), (-0.6665, 0.018), (-0.0105, 0.018),
          (0.6395, 0.018), (-0.328, 0.359), (0.3175, 0.359), (-0.006, 0.719)]      # measured slot centres


def vent12(M, x, y, aa):
    """Nine raised slots in a diamond (all measured): half size 0.239 x 0.101, round ends, flat top 1.0,
    S edge ~0.045 wide centred on the outline."""
    h = None
    for cx, cy in VENT12:
        e = R.soft(M, D.rect(M, x, y, 0.239, 0.101, cx, cy, rad=0.101) + 0.0225, 0.045)
        h = e if h is None else M.fmax(h, e)
    return h

def vent15(M, x, y, aa):
    """Perforation pattern (measured by blob centroids): a centre dot, 8 dots at r 0.429 (from 0 degrees), 12 dots
    at r 0.770 (from 0 degrees); each dot radius 0.095 at half height, flat top, S edge ~0.06."""
    def dots(px, py):
        return R.soft(M, D.circle(M, px, py, 0.095) + 0.03, 0.06)
    h = dots(x, y)
    for n, rr in ((8, 0.429), (12, 0.770)):
        px, py = D.radial(M, x, y, n, mirror=False)
        h = M.fmax(h, dots(px, py + rr))
    return h

def _bolted_frame(M, x, y, a, b, inner_a, inner_b):
    outer = D.rect(M, x, y, a, b, rad=0.06)
    for sx in (-1, 1):
        for sy in (-1, 1):
            outer = D.union(M, outer, D.circle(M, x, y, 0.08, sx * a, sy * b))
    h = R.plate(M, outer, 0.5, 0.05, R.rounded)
    for sx in (-1, 1):
        for sy in (-1, 1):
            h = R.inset(M, h, D.circle(M, x, y, 0.035, sx * a, sy * b), 0.25, 0.02, R.soft)
    inner = D.rect(M, x, y, inner_a, inner_b, rad=0.03)
    return h, inner


VENT18_BOLTS = ((-0.663, -0.729), (0.675, -0.707), (-0.779, 0.746), (0.781, 0.746))   # fitted ring centres


def vent18(M, x, y, aa):
    """Louvre grille in a trapezoid outline (all measured): thin outline (peak 0.67, half width 0.765 + 0.104 y,
    y -0.747..0.771) with ears around four bolt rings (rim r 0.042, 0.62); a trapezoid field (half width
    0.565 + 0.078 y, y -0.578..0.572) at 0.62 carrying 8 slats: period 0.136 from y -0.494, each a steep rise to
    1.0 then a straight decay back to 0.62 over 0.10."""
    from pplib import curves as C
    k2 = math.hypot(1.0, 0.104)
    tr = M.fmin((0.765 + 0.104 * y - M.fabs(x)) / k2, M.fmin(y + 0.747, 0.771 - y))
    ears = None
    for cx, cy in VENT18_BOLTS:
        e = D.circle(M, x, y, 0.075, cx, cy)
        ears = e if ears is None else M.fmax(ears, e)
    d = C.soft_max(M, tr, ears, 0.03)
    w = M.sel(M.lt(d, 0.0), 0.022 / 0.41, 0.012 / 0.41)
    q = R.cl(M, M.fabs(d) / w)
    kk = 1.0 - q * q
    h = 0.67 * kk * kk * kk
    for cx, cy in VENT18_BOLTS:
        h = M.fmax(h, R.rim(M, D.circle(M, x, y, 0.042, cx, cy), 0.022, 0.62))
    k1 = math.hypot(1.0, 0.078)
    fd = C.soft_min(M, (0.565 + 0.078 * y - M.fabs(x)) / k1, C.soft_min(M, y + 0.578, 0.572 - y, 0.01), 0.04)
    u = M.frac((y + 0.494 + 0.034) / 0.136) * 0.136 - 0.034            # offset from the nearest slat peak
    rise = 0.62 + 0.38 * R.ss(M, (u + 0.034) / 0.034)
    fall = 0.62 + 0.38 * R.cl(M, 1.0 - u / 0.10)
    slat = M.sel(M.lt(u, 0.0), rise, fall)
    slat = 0.62 + (slat - 0.62) * R.hard(M, y + 0.528, 0.004) * R.hard(M, 0.561 - y, 0.004) * R.soft(M, fd - 0.03, 0.02)
    field = slat * R.soft(M, fd + 0.02, 0.04)
    return M.fmax(h, field)

def vent20(M, x, y, aa):
    """Waffle vent (all measured): thin rounded-rect outline (peak 0.66 at |x| 0.898, |y| 0.50), four bolt rings
    at (+-0.82, +-0.45); a raised field (half 0.725 x 0.31 at half height, base 0.67) divided into square cells
    (tops 0.99) by grooves: x pitch 0.0916 from -0.6265, y pitch 0.0932 from -0.2397."""
    from pplib import curves as C
    BOLTS = ((-0.818, -0.448), (0.821, -0.448), (-0.818, 0.451), (0.821, 0.451))
    ears = None
    for cx, cy in BOLTS:
        e = D.circle(M, x, y, 0.08, cx, cy)
        ears = e if ears is None else M.fmax(ears, e)
    ro = C.soft_max(M, D.rect(M, x, y, 0.898, 0.50, rad=0.06), ears, 0.03)
    q = R.cl(M, M.fabs(ro) / (0.019 / 0.41))
    kk = 1.0 - q * q
    h = 0.66 * kk * kk * kk
    for cx, cy in BOLTS:
        h = M.fmax(h, R.rim(M, D.circle(M, x, y, 0.042, cx, cy), 0.022, 0.62))
    fd = D.rect(M, x, y, 0.733, 0.318, rad=0.04)
    gx = M.fabs((M.frac((x + 0.6265) / 0.0916 + 0.5) - 0.5) * 0.0916)
    gy = M.fabs((M.frac((y + 0.2397) / 0.0932 + 0.5) - 0.5) * 0.0932)
    g = M.fmin(M.fmin(gx, gy), M.fmax(fd - 0.012, 0.0))              # the field edge acts as a groove too
    cells = 0.67 + 0.32 * R.ss(M, (g - 0.005) / 0.025)
    field = cells * R.soft(M, fd + 0.012, 0.035)
    return M.fmax(h, field)

def _hex_mesh_e(M, x, y, x0, dx, y0, dy):
    """Half the gap between the nearest and second-nearest point of a staggered lattice (rows every dy from y0,
    odd rows shifted by dx/2): 0 on the Voronoi edges (the grooves), growing into each cell."""
    ds = []
    k0 = M.floor((y - y0) / dy)
    for dk in (0.0, 1.0):
        k = k0 + dk
        off = M.mod(k, 2.0) * (dx * 0.5)
        ii = M.floor((x - x0 - off) / dx + 0.5)
        for di in (-1.0, 0.0, 1.0):
            px = x0 + off + (ii + di) * dx
            py = y0 + k * dy
            ds.append(M.fsqrt((x - px) * (x - px) + (y - py) * (y - py)))
    d1 = M.fmin(*ds)
    d2 = M.fmin(*[M.sel(M.gt(d, d1 + 1e-5), d, 9.0) for d in ds])
    return (d2 - d1) * 0.5


def vent14(M, x, y, aa):
    """Raised block with an expanded-metal mesh, extruded downward (all measured). Block x +-0.585,
    y -0.752..0.123; mesh cells 1.0 with grooves 0.82 on a staggered lattice (x pitch 0.1333 from -0.537, rows
    0.1182 from y -0.615, odd rows shifted half a cell) down to y 0.055, then a flat 0.80 strip. Around it a
    skirt: min(downward fade, side fade, top fade) measured along col 0 and rows."""
    ax = M.fabs(x)
    blk = M.fmin(0.585 - ax, M.fmin(y + 0.752, 0.123 - y))
    e = _hex_mesh_e(M, x, y, -0.537, 0.1333, -0.615, 0.1182)
    mesh = 0.82 + 0.18 * R.ss(M, (e - 0.004) / 0.014)
    top = M.sel(M.gt(y, 0.105), 0.80, mesh)
    down = R.lathe(M, y, [(0.123, 0.52), (0.13, 0.50), (0.16, 0.47), (0.24, 0.34), (0.32, 0.26), (0.40, 0.21),
                          (0.48, 0.17), (0.56, 0.12), (0.64, 0.08), (0.72, 0.04), (0.80, 0.02), (0.90, 0.0)])
    side = R.lathe(M, ax, [(0.585, 0.52), (0.60, 0.45), (0.62, 0.41), (0.65, 0.26), (0.70, 0.16), (0.75, 0.10),
                           (0.80, 0.03), (0.85, 0.0)])
    upper = R.lathe(M, -y, [(0.752, 0.52), (0.765, 0.15), (0.77, 0.12), (0.79, 0.09), (0.83, 0.05), (0.87, 0.02),
                            (0.92, 0.0)])
    skirt = M.fmin(M.fmin(M.sel(M.gt(y, 0.123), down, 0.52), side), M.sel(M.lt(y, -0.752), upper, 0.52))
    return skirt + (top - skirt) * R.hard(M, blk, 0.006)

def handle08(M, x, y, aa):
    """Recessed U grip (all measured). A U-shaped GROOVE (centreline: arms at x = +-0.41, bottom arc radius 0.41
    about (0, 0.15)) with a 0.035 floor, an outer lip (0.40) and a soft outer fade; inside it a raised plate
    (0.62) whose upper part rises to 1.0 (y < -0.28, ramp down to 0.62 by y -0.08). Toward the top the groove floor
    ramps up to 0.66 at y -0.52, and above that everything fades out (to 0 by y -0.85)."""
    yc = M.fmax(y, -0.49)
    ax = M.fabs(x - 0.005)
    r = M.fsqrt(x * x + (yc - 0.15) * (yc - 0.15))
    u = M.sel(M.gt(yc, 0.15), r - 0.41, ax - 0.41)                   # + outward from the groove centreline
    xs = R.lathe(M, u, [(-0.14, 0.62), (-0.12, 0.60), (-0.10, 0.40), (-0.08, 0.23), (-0.05, 0.06), (-0.03, 0.035),
                        (0.03, 0.035), (0.05, 0.07), (0.075, 0.22), (0.10, 0.40), (0.115, 0.40), (0.13, 0.32),
                        (0.16, 0.20), (0.19, 0.11), (0.22, 0.07), (0.25, 0.04), (0.28, 0.02), (0.34, 0.0)])
    floor = R.lathe(M, -yc, [(0.22, 0.035), (0.25, 0.05), (0.31, 0.08), (0.37, 0.15), (0.43, 0.28), (0.46, 0.38),
                             (0.49, 0.53), (0.52, 0.66)])
    plate = 0.62 + 0.38 * R.lathe(M, -yc, [(0.08, 0.0), (0.10, 0.03), (0.13, 0.08), (0.16, 0.24), (0.19, 0.45),
                                           (0.22, 0.66), (0.25, 0.89), (0.28, 1.0)])
    f = R.ss(M, (-u - 0.05) / 0.09)
    inner = floor + (plate - floor) * f
    outer = M.fmax(xs, floor * R.soft(M, 0.12 - u, 0.04))
    h = M.sel(M.lt(u, -0.05), inner, outer)
    cap = R.lathe(M, -y, [(0.49, 1.0), (0.52, 0.84), (0.55, 0.60), (0.58, 0.43), (0.61, 0.32), (0.64, 0.24),
                          (0.67, 0.17), (0.70, 0.12), (0.73, 0.08), (0.76, 0.04), (0.79, 0.02), (0.85, 0.0)])
    return M.fmin(h, cap)

def connector06(M, x, y, aa):
    """Link plate (all measured): a low flat bar (0.27, x +-0.665, y -0.18..0.28) between two eyes centred at
    (+-0.662, 0.046) with holes of radius 0.132. Each eye has a raised ring (0.64 at r 0.175, gone by r 0.27)
    outside the bar; inside the bar the ring becomes a collar (0.96 on the axis, a wider 0.9 shoulder off-axis)
    falling back to the bar level by r 0.25-0.30."""
    bar = 0.27 * R.soft(M, D.rect(M, x, y, 0.665, 0.23, 0.0, 0.05) + 0.015, 0.03)
    inbar = R.soft(M, D.rect(M, x, y, 0.665, 0.23, 0.0, 0.05) + 0.02, 0.03)
    h = bar
    walls = []
    for cx in (-0.662, 0.662):
        dx, dy = x - cx, y - 0.046
        r = M.fsqrt(dx * dx + dy * dy)
        ring = R.lathe(M, r, [(0.12, 0.0), (0.13, 0.02), (0.15, 0.25), (0.16, 0.50), (0.175, 0.64), (0.19, 0.58),
                              (0.21, 0.42), (0.23, 0.25), (0.25, 0.08), (0.27, 0.0)])
        c_ax = R.lathe(M, r, [(0.12, 0.0), (0.13, 0.01), (0.15, 0.18), (0.16, 0.45), (0.17, 0.79), (0.18, 0.96),
                              (0.19, 0.92), (0.20, 0.79), (0.21, 0.62), (0.22, 0.48), (0.23, 0.36), (0.24, 0.30),
                              (0.25, 0.27)])
        c_off = R.lathe(M, r, [(0.12, 0.0), (0.13, 0.01), (0.15, 0.14), (0.16, 0.36), (0.17, 0.66), (0.18, 0.86),
                               (0.19, 0.91), (0.21, 0.87), (0.23, 0.75), (0.25, 0.55), (0.27, 0.33), (0.29, 0.27)])
        w = R.cl(M, 2.0 * M.fabs(dx) * M.fabs(dy) / (r * r + 1e-6) * 1.1)       # peaks at 45 degrees
        collar = c_ax + (c_off - c_ax) * w
        side = R.soft(M, -dx * (1.0 if cx < 0 else -1.0) + 0.01, 0.02)           # the bar side of this eye only
        eye = ring + (collar - ring) * inbar * side
        eye = eye * R.soft(M, 0.32 - r, 0.02)                                    # only near this eye
        h = M.fmax(h, eye)
        walls.append(R.lathe(M, r, [(0.12, 0.0), (0.13, 0.02), (0.15, 0.25), (0.17, 0.79), (0.18, 1.0)]))
    return M.fmin(h, M.fmin(walls[0], walls[1]))

def _edge_line(M, d, peak):
    """A thin raised line on an outline (measured on door05): sharp outside (gone 0.05 out), gentle inside
    (gone 0.07 in); d = inside distance."""
    out = R.lathe(M, -d, [(0.0, 1.0), (0.005, 0.73), (0.01, 0.45), (0.02, 0.17), (0.03, 0.065), (0.04, 0.026),
                          (0.05, 0.0)])
    inn = R.lathe(M, d, [(0.0, 1.0), (0.005, 0.92), (0.01, 0.70), (0.02, 0.40), (0.03, 0.26), (0.04, 0.14),
                         (0.05, 0.08), (0.06, 0.026), (0.07, 0.0)])
    return peak * M.sel(M.lt(d, 0.0), out, inn)


def door05(M, x, y, aa):
    """Door outline (all measured): a thin line on a rounded rectangle (half 0.83 x 0.84 about y 0.01, corner
    radius 0.10; peak 0.79, only 0.54 along the top). Along the top: a hinge barrel |x| < 0.43 (lips 1.0 at y -0.82
    and 0.80 at -0.685 around a 0.37 trough), knuckle blocks outlined at |x| 0.44-0.53 and corner tabs outlined at
    |x| 0.735-0.83, both down to y -0.66."""
    ax = M.fabs(x)
    d = D.rect(M, x, y, 0.83, 0.84, 0.0, 0.01, rad=0.10)
    peak = 0.79 - 0.25 * R.soft(M, -0.72 - y, 0.04)
    h = _edge_line(M, d, 1.0) * peak
    for (x0, x1, pk) in ((0.44, 0.53, 0.77), (0.735, 0.83, 0.72)):
        bd = D.rect(M, ax, y, (x1 - x0) * 0.5, 0.0825, (x0 + x1) * 0.5, -0.7475)
        h = M.fmax(h, _edge_line(M, bd, pk))
    barrel = R.lathe(M, y, [(-0.86, 0.0), (-0.84, 0.34), (-0.83, 0.83), (-0.82, 1.0), (-0.81, 0.95), (-0.80, 0.71),
                            (-0.79, 0.55), (-0.78, 0.47), (-0.77, 0.41), (-0.75, 0.37), (-0.73, 0.39), (-0.72, 0.43),
                            (-0.71, 0.50), (-0.70, 0.61), (-0.69, 0.80), (-0.68, 0.80), (-0.67, 0.51), (-0.66, 0.30),
                            (-0.65, 0.19), (-0.64, 0.12), (-0.63, 0.06), (-0.62, 0.02), (-0.61, 0.0)])
    return M.fmax(h, barrel * R.soft(M, 0.43 - ax, 0.01))

def window03(M, x, y, aa):
    """Porthole: a rounded ring around a glass dish, four clamps."""
    h = R.rim(M, D.circle(M, x, y, 0.62), 0.07, 0.85)
    h = M.fmax(h, 0.62 * R.hard(M, D.circle(M, x, y, 0.56), 0.01) * R.dish(M, D.circle(M, x, y, 0.56), 0.55, 0.5))
    px, py = D.radial(M, x, y, 4)
    clamp = D.rect(M, px, py, 0.05, 0.08, 0.0, -0.62)
    return M.fmax(h, R.plate(M, clamp, 1.0, 0.03, R.rounded))


ITEMS = dict(
    base01=(base01, 'BaseShapes/JRO_Base01.tif', 0.0), base03=(base03, 'BaseShapes/JRO_Base03.tif', 0.0),
    base14=(base14, 'BaseShapes/JRO_Base14_in.tif', 0.0), base27=(base27, 'BaseShapes/JRO_Base27_in.tif', 0.0),
    bolt01=(bolt01, 'Bolts/JRO_Bolts01_in.tif', 0.0), bolt04=(bolt04, 'Bolts/JRO_Bolts04_in.tif', 0.0),
    bolt12=(bolt12, 'Bolts/JRO_Bolts12_in.tif', 0.0), bolt16=(bolt16, 'Bolts/JRO_Bolts16_in.tif', 0.0),
    bolt22=(bolt22, 'Bolts/JRO_Bolts22_in.tif', 0.0), vent12=(vent12, 'Vents/JRO_Vent12_in.tif', 0.0),
    vent15=(vent15, 'Vents/JRO_Vent15_in.tif', 0.0), vent18=(vent18, 'Vents/JRO_Vent18_02_in.tif', 0.0),
    vent20=(vent20, 'Vents/JRO_Vent20_03_in.tif', 0.0), vent14=(vent14, 'Vents/JRO_Vent14_01_in.tif', -0.2),
    handle08=(handle08, 'Handles/JRO_Handle08_in.tif', 0.0), connector06=(connector06, 'Connectors/JRO_Connector06_in.tif', 0.0),
    door05=(door05, 'Containers&Doors/JRO_Container_05_in.tif', 0.0), window03=(window03, 'Misc/JRO_Window03_in.tif', 0.0),
)


# --- round items rebuilt on lathe profiles (fitted to each reference's radial profile, fit_lathe.py) -----------------------
from lathe_knots import KNOTS


def _r(M, x, y): return M.fsqrt(x * x + y * y)


def base14(M, x, y, aa):
    return R.lathe(M, _r(M, x, y), KNOTS['base14'])


def bolt01(M, x, y, aa):
    h = R.lathe(M, _r(M, x, y), KNOTS['bolt01'])
    return R.set_to(M, h, D.rect(M, x, y, 0.12, 0.62, rad=0.12), 1.0, 0.03, R.soft)


def bolt04(M, x, y, aa):
    """Round head (lathe, centred at (0.008, -0.01) as measured) with a raised cross: arms half width 0.13 at
    half height, reach 0.585 (x) / 0.575 (y), soft edge ~0.06."""
    xs, ys = x - 0.008, y + 0.01
    h = R.lathe(M, _r(M, xs, ys), KNOTS['bolt04'])
    cross = D.union(M, D.rect(M, xs, ys, 0.125, 0.575, rad=0.125), D.rect(M, xs, ys, 0.585, 0.125, rad=0.125))
    return M.fmax(h, R.soft(M, cross + 0.025, 0.06))

def bolt12(M, x, y, aa):
    h = R.lathe(M, _r(M, x, y), KNOTS['bolt12'])
    star = D.sub(M, D.star(M, x, y, 6, 0.62, 0.36), D.circle(M, x, y, 0.15))
    return R.set_to(M, h, star, 1.0, 0.03, R.soft)


def window03(M, x, y, aa):
    h = R.lathe(M, _r(M, x, y), KNOTS['window03'])
    px, py = D.radial(M, x, y, 4)
    return M.fmax(h, R.plate(M, D.rect(M, px, py, 0.05, 0.08, 0.0, -0.62), 0.9, 0.03, R.rounded))


for _n in ('base14', 'bolt01', 'bolt04', 'bolt12', 'window03'):
    ITEMS[_n] = (globals()[_n],) + ITEMS[_n][1:]
