"""pplib.relief: hard-surface bas-relief (alpha-style height) from 2D outlines.

Pair it with pplib.decals: draw an outline as an inside-positive distance d (icon space -1..1), then turn it into
height with an edge PROFILE. Heights are 0..1 like a ZBrush alpha (0 = untouched surface). Combine parts with max
(raised things) or by `inset` (cut a part down into another).
Built from the JRO hard-surface alphas (Vol. 1) as REFERENCE ONLY (substance_experiments/hardsurface_study).
"""
import math


_MINW = [0.0]


def min_width(w):
    """Set the narrowest edge any profile may have (call with ~1.5 pixels in icon units: 3 / size_px; Expr allowed).
    Keeps bevels thinner than a pixel from aliasing at low resolutions."""
    _MINW[0] = w


def _w(M, w):
    return w if (isinstance(_MINW[0], float) and _MINW[0] == 0.0) else M.fmax(w, _MINW[0])


def cl(M, x, lo=0.0, hi=1.0): return M.fmin(M.fmax(x, lo), hi)
def ss(M, x): x = cl(M, x); return x * x * (3.0 - 2.0 * x)


# --- edge profiles: d = inside distance, w = edge width, returns 0 outside .. 1 on top -------------------------------------
def hard(M, d, aa): aa = _w(M, aa); return cl(M, d / aa + 0.5)            # vertical wall (aa = one pixel)
def chamfer(M, d, w): w = _w(M, w); return cl(M, d / w)                                # straight 45-ish bevel
def rounded(M, d, w):
    """Quarter-round (bullnose) edge of width w."""
    w = _w(M, w)
    q = cl(M, 1.0 - d / w)
    return M.fsqrt(M.fmax(1.0 - q * q, 0.0))


def soft(M, d, w): w = _w(M, w); return ss(M, d / w)                                    # S-curve edge (filleted top and foot)


def cove(M, d, w):
    """Concave (cove) edge: steep at the outline, easing in."""
    w = _w(M, w)
    q = cl(M, d / w)
    return 1.0 - (1.0 - q) * (1.0 - q)


def dish(M, d, depth, w):
    """A shallow bowl falling from the edge toward the inside over width w (1 at the edge, 1 - depth inside)."""
    q = cl(M, d / w)
    return 1.0 - depth * q * q * (3.0 - 2.0 * q)


def dome(M, d, w):
    """Rising toward the inside like a cushion over width w (0 at the edge)."""
    q = cl(M, d / w)
    return M.fsqrt(M.fmax(1.0 - (1.0 - q) * (1.0 - q), 0.0))


# --- building blocks -----------------------------------------------------------------------------------------------------
def plate(M, d, h, w, profile=None):
    """A raised plate of height h with an edge profile (default rounded)."""
    return h * (profile or rounded)(M, d, w)


def groove(M, d, w, depth, base):
    """A V/round groove of half width w along the outline d (subtract from base)."""
    q = cl(M, M.fabs(d) / w)
    return base - depth * (1.0 - q * q)


def rim(M, d, w, h):
    """A rounded raised line of half width w along the outline."""
    w = _w(M, w)
    q = cl(M, M.fabs(d) / w)
    return h * M.fsqrt(M.fmax(1.0 - q * q, 0.0))


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
