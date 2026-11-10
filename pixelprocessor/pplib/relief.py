"""pplib.relief: hard-surface bas-relief (alpha-style height) from 2D outlines.

Pair it with pplib.decals: draw an outline as an inside-positive distance d (icon space -1..1), then turn it into
height with an edge PROFILE. Heights are 0..1 like a ZBrush alpha (0 = untouched surface). Combine parts with max
(raised things) or by `inset` (cut a part down into another).
Built from the JRO hard-surface alphas (Vol. 1 and 2) as REFERENCE ONLY (substance_experiments/hardsurface_study).
"""
import math


_MINW = [0.0]
_PX = [0.0]
TAPS = (-0.375, -0.125, 0.125, 0.375)


def min_width(w):
    """Set the pixel scale for anti-aliasing (call with ~1.5 pixels in icon units: 3 / size_px; Expr allowed).
    Two effects: no edge gets narrower than w, and every profile is box-filtered over one pixel (w / 1.5) across its
    edge, so curved outlines stay smooth instead of lumpy at low resolutions. 0 turns both off."""
    _MINW[0] = w
    _PX[0] = w if (isinstance(w, float) and w == 0.0) else w * (1.0 / 1.5)


def _w(M, w):
    return w if (isinstance(_MINW[0], float) and _MINW[0] == 0.0) else M.fmax(w, _MINW[0])


def _aa(M, f, d):
    """Average f over one pixel across the edge: f(d + t * px) for 4 taps (d is a distance, so this is a box filter
    perpendicular to the outline)."""
    px = _PX[0]
    if isinstance(px, float) and px == 0.0:
        return f(d)
    acc = None
    for t in TAPS:
        v = f(d + px * t)
        acc = v if acc is None else acc + v
    return acc * (1.0 / len(TAPS))


def cl(M, x, lo=0.0, hi=1.0): return M.fmin(M.fmax(x, lo), hi)
def ss(M, x): x = cl(M, x); return x * x * (3.0 - 2.0 * x)


# --- edge profiles: d = inside distance, w = edge width, returns 0 outside .. 1 on top -------------------------------------
def hard(M, d, aa):
    """Vertical wall (aa = one pixel)."""
    aa = _w(M, aa)
    return _aa(M, lambda e: cl(M, e / aa + 0.5), d)


def chamfer(M, d, w):
    """Straight bevel of width w."""
    w = _w(M, w)
    return _aa(M, lambda e: cl(M, e / w), d)


def _round_cap(M, q):
    return M.fsqrt(M.fmax(1.0 - q * q, 0.0))


def rounded(M, d, w):
    """Quarter-round (bullnose) edge of width w."""
    w = _w(M, w)
    return _aa(M, lambda e: _round_cap(M, cl(M, 1.0 - e / w)), d)


def soft(M, d, w):
    """S-curve edge (filleted top and foot) of width w."""
    w = _w(M, w)
    return _aa(M, lambda e: ss(M, e / w), d)


def cove(M, d, w):
    """Concave (cove) edge: steep at the outline, easing in."""
    w = _w(M, w)

    def f(e):
        q = cl(M, e / w)
        return 1.0 - (1.0 - q) * (1.0 - q)
    return _aa(M, f, d)


def dish(M, d, depth, w):
    """A shallow bowl falling from the edge toward the inside over width w (1 at the edge, 1 - depth inside)."""
    q = cl(M, d / w)
    return 1.0 - depth * q * q * (3.0 - 2.0 * q)


def dome(M, d, w):
    """Rising toward the inside like a cushion over width w (0 at the edge)."""
    return _aa(M, lambda e: _round_cap(M, 1.0 - cl(M, e / w)), d)


# --- building blocks -----------------------------------------------------------------------------------------------------
def plate(M, d, h, w, profile=None):
    """A raised plate of height h with an edge profile (default rounded)."""
    return h * (profile or rounded)(M, d, w)


def groove(M, d, w, depth, base):
    """A V/round groove of half width w along the outline d (subtract from base)."""
    def f(e):
        q = cl(M, M.fabs(e) / w)
        return 1.0 - q * q
    return base - depth * _aa(M, f, d)


def rim(M, d, w, h):
    """A rounded raised line of half width w along the outline."""
    w = _w(M, w)
    return h * _aa(M, lambda e: _round_cap(M, cl(M, M.fabs(e) / w)), d)


def inset(M, base, d, depth, w, profile=None):
    """Cut the region d > 0 down by depth from base, with an edge profile of width w."""
    return base - depth * (profile or soft)(M, d, w)


def raise_to(M, base, d, level, w, profile=None):
    """Lift the region d > 0 to `level` (only where that is higher), edge profile width w."""
    t = (profile or soft)(M, d, w)
    return M.fmax(base, base + (level - base) * t)


def set_to(M, base, d, level, w, profile=None):
    """Set the region d > 0 to `level` (higher or lower) with an edge profile."""
    t = (profile or soft)(M, d, w)
    return base + (level - base) * t


# --- fills: patterns inside a region (return 0..1 relief of the pattern) -------------------------------------------------
def louvres(M, x, y, period, angle=0.0, lip=0.35):
    """Sloped slats (sawtooth with a rounded lip): angle turns them (radians)."""
    ca, sa = math.cos(angle), math.sin(angle)
    v = (y * ca - x * sa) / period
    t = v - M.floor(v)
    slope = t / (1.0 - lip)
    return M.sel(M.lt(t, 1.0 - lip), slope, M.fsqrt(M.fmax(1.0 - ((t - (1.0 - lip)) / lip) ** 2, 0.0)))


def slats(M, x, y, period, width=0.5, angle=0.0):
    """Rounded bars (round-top slats), width = share of the period."""
    ca, sa = math.cos(angle), math.sin(angle)
    v = (y * ca - x * sa) / period
    f = M.fabs(v - M.floor(v) - 0.5) / (width * 0.5)
    return M.fsqrt(M.fmax(1.0 - f * f, 0.0))


def waffle(M, x, y, period, wall=0.3):
    """A square grid of raised walls (wall = share of the period)."""
    fx = M.fabs(x / period - M.floor(x / period) - 0.5) * 2.0
    fy = M.fabs(y / period - M.floor(y / period) - 0.5) * 2.0
    return ss(M, (M.fmax(fx, fy) - (1.0 - wall)) / (wall * 0.6))


def wavy_mesh(M, x, y, period, angle=0.6, amp=0.25, width=0.45):
    """Expanded-metal style mesh: diagonal strands that wiggle (the JRO 'zigzag' grille)."""
    ca, sa = math.cos(angle), math.sin(angle)
    u, v = x * ca + y * sa, -x * sa + y * ca
    s = v / period + amp * M.fsin(u / period * 6.2831853)
    f = M.fabs(s - M.floor(s) - 0.5) / (width * 0.5)
    return M.fsqrt(M.fmax(1.0 - f * f, 0.0))


def holes_grid(M, x, y, period, r, stagger=True):
    """Distance field of a grid of round holes (inside-positive in the holes); stagger offsets odd rows."""
    j = M.floor(y / period + 0.5)
    off = M.mod(j, 2.0) * 0.5 * period if stagger else 0.0
    dx = (M.frac((x - off) / period + 0.5) - 0.5) * period
    dy = y - j * period
    return r - M.fsqrt(dx * dx + dy * dy)


# --- rivets along outlines and tubes (added for JRO Vol. 2) ------------------------------------------------------------
def _rivet(M, dx, dy, r):
    """A dome rivet of radius r at offset (dx, dy)."""
    dist = M.fsqrt(dx * dx + dy * dy)
    return _aa(M, lambda e: _round_cap(M, cl(M, e / r)), dist)


def rivets_circle(M, x, y, R, n, r, cx=0.0, cy=0.0, phase=0.5):
    """n dome rivets of radius r evenly on a circle of radius R (phase 0.5 = none at the top)."""
    px, py = x - cx, y - cy
    rr = M.fsqrt(px * px + py * py)
    from pplib.decals import _atan2
    a = _atan2(M, px, -py) / (2 * math.pi) * n + (0.5 - phase)
    k = M.floor(a + 0.5) - (0.5 - phase)
    ang = k / n * 2 * math.pi
    return _rivet(M, px - R * M.fsin(ang), py + R * M.fsin(ang + math.pi / 2), r)


def rivets_segment(M, x, y, ax, ay, bx, by, n, r):
    """n dome rivets of radius r evenly from a to b (python floats), ends included."""
    L = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / L, (by - ay) / L
    t = (x - ax) * ux + (y - ay) * uy
    s = L / (n - 1) if n > 1 else L
    k = cl(M, M.floor(t / s + 0.5), 0.0, float(n - 1))
    px, py = ax + ux * k * s, ay + uy * k * s
    return _rivet(M, x - px, y - py, r)


def rivets_polygon(M, x, y, pts, spacing, r):
    """Dome rivets along a closed polygon (list of (x, y) python floats), about `spacing` apart, one at each corner."""
    h = None
    for a, b in zip(pts, pts[1:] + pts[:1]):
        n = max(2, int(round(math.hypot(b[0] - a[0], b[1] - a[1]) / spacing)) + 1)
        e = rivets_segment(M, x, y, a[0], a[1], b[0], b[1], n, r)
        h = e if h is None else M.fmax(h, e)
    return h


def rivets_rect(M, x, y, a, b, spacing, r, cx=0.0, cy=0.0):
    """Dome rivets around a rectangle of half sizes a, b."""
    return rivets_polygon(M, x - cx, y - cy, [(-a, -b), (a, -b), (a, b), (-a, b)], spacing, r)


def tube(M, x, y, ax, ay, bx, by, r):
    """A round bar (pipe, rod) from a to b with flat ends: 0..1 cylinder profile."""
    L = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / L, (by - ay) / L
    px, py = x - (ax + bx) * 0.5, y - (ay + by) * 0.5
    along, across = px * ux + py * uy, -px * uy + py * ux
    cap = _aa(M, lambda e: _round_cap(M, cl(M, M.fabs(e) / r)), across)
    return cap * _aa(M, lambda e: cl(M, e / (_PX[0] if not (isinstance(_PX[0], float) and _PX[0] == 0.0) else 1e-4) + 0.5),
                     L * 0.5 - M.fabs(along))



# --- lathe profiles (round parts) ----------------------------------------------------------------------------------------
def lathe(M, r, knots):
    """Height of a round part from its radial profile: knots = [(r0, h0), (r1, h1), ...] with increasing r (python
    floats), h0 inside r0 and the last height outside. Between knots a monotone cubic (Fritsch-Carlson Hermite), so
    slopes are continuous: no creases or terraces in the shading, exact circles at any resolution, box-filtered over
    a pixel like the other profiles. Fit knots to a reference with fit_lathe() (numpy only)."""
    rs = [k[0] for k in knots]
    hs = [k[1] for k in knots]
    n = len(knots)
    sl = [(hs[i + 1] - hs[i]) / max(rs[i + 1] - rs[i], 1e-6) for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        m[i] = 0.0 if sl[i - 1] * sl[i] <= 0 else 2.0 / (1.0 / sl[i - 1] + 1.0 / sl[i])   # harmonic mean: monotone
    m[0], m[-1] = 0.0, 0.0                                                                   # flat at the centre and outside

    def f(rr):
        h = hs[0]
        for i in range(n - 1):
            dx = max(rs[i + 1] - rs[i], 1e-6)
            if hs[i + 1] == hs[i] and m[i] == 0.0 and m[i + 1] == 0.0:
                continue
            t = cl(M, (rr - rs[i]) / dx)
            t2, t3 = t * t, t * t * t
            seg = (2 * t3 - 3 * t2 + 1) * hs[i] + (t3 - 2 * t2 + t) * dx * m[i] + (-2 * t3 + 3 * t2) * hs[i + 1]                 + (t3 - t2) * dx * m[i + 1]
            h = h + (seg - hs[i])                    # 0 before the segment, hs[i+1] - hs[i] after it: cumulative
        return h
    return _aa(M, f, r)


def fit_lathe(profile, rmax=1.0, tol=0.006, median=None):
    """Knots for lathe() from a sampled radial profile (numpy array of heights at radii 0..rmax), simplified with
    Douglas-Peucker to `tol`. Use the angular MEDIAN of a reference as the profile so spokes, clamps and rivets
    (which cover few angles) drop out and can be drawn separately."""
    import numpy as np
    n = len(profile)
    rs = np.linspace(0.0, rmax, n)
    keep = [0, n - 1]

    def dp(i, j):
        if j <= i + 1:
            return
        seg = profile[i] + (profile[j] - profile[i]) * (rs[i:j + 1] - rs[i]) / (rs[j] - rs[i])
        err = np.abs(profile[i:j + 1] - seg)
        k = int(np.argmax(err))
        if err[k] > tol:
            keep.append(i + k)
            dp(i, i + k)
            dp(i + k, j)
    dp(0, n - 1)
    return [(round(float(rs[k]), 4), round(float(profile[k]), 4)) for k in sorted(set(keep))]
