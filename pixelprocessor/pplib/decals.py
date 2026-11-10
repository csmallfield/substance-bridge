"""pplib.decals: flat 2D icons and decal graphics as signed distance fields (resolution independent).

Icon space: (x, y) in -1..1 around the icon centre, y DOWN (like the texture). Fields are INSIDE-positive like
pplib.shapes, so: union = max, intersection = min, subtract = min(a, -b), outline = w - |d|.
Draw with fill(M, d, aa): aa = one pixel in icon units (2 / icon size in px) keeps edges crisp at any resolution.
Symmetry folds (mirror, radial, polar repeat) turn one drawn part into the whole emblem.
Built from the Futrograph icon brushes as REFERENCE ONLY (substance_experiments/decal_study); nothing is sampled.
"""
import math

PI = 3.14159265


def cl(M, x, lo=0.0, hi=1.0): return M.fmin(M.fmax(x, lo), hi)


# --- booleans and modifiers ------------------------------------------------------------------------------------------------
def union(M, *ds): return M.fmax(*ds)
def inter(M, *ds): return M.fmin(*ds)
def sub(M, a, b): return M.fmin(a, -b)
def outline(M, d, w): return w - M.fabs(d)                         # a band of half width w along the edge
def grow(M, d, r): return d + r                                     # grow (r > 0) or shrink the shape
def gap(M, d, cut_d, w): return M.fmin(d, M.fabs(cut_d) - w)         # cut a gap of half width w along cut_d's edge


def fill(M, d, aa):
    """0..1 coverage with a one-pixel anti-aliased edge (aa = pixel size in the same units as d)."""
    return cl(M, d / aa + 0.5)


# --- coordinate folds -----------------------------------------------------------------------------------------------------
def mirror_x(M, x): return M.fabs(x)
def rot(M, x, y, a): ca, sa = math.cos(a), math.sin(a); return ca * x - sa * y, sa * x + ca * y


def polar(M, x, y):
    """(r, angle) with angle in -pi..pi, 0 pointing UP (-y), increasing clockwise on screen."""
    r = M.fsqrt(x * x + y * y)
    return r, _atan2(M, x, -y)


def _atan2(M, yv, xv):
    """atan2 from basic functions (Substance function graphs have no atan2): polynomial atan, max error ~1e-4."""
    ax, ay = M.fabs(xv), M.fabs(yv)
    mn, mx = M.fmin(ax, ay), M.fmax(ax, ay)
    t = mn / (mx + 1e-9)
    s = t * t
    a = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * t + t
    a = M.sel(M.gt(ay, ax), PI / 2 - a, a)
    a = M.sel(M.lt(xv, 0.0), PI - a, a)
    return M.sel(M.lt(yv, 0.0), -a, a)


def radial(M, x, y, n, mirror=True):
    """Fold the plane into one of n wedges around the centre (wedge pointing up); with mirror, also mirrored inside
    the wedge. Draw ONE spoke pointing up (-y) and get an n-fold emblem."""
    r, a = polar(M, x, y)
    w = 2.0 * PI / n
    a = a - M.floor(a / w + 0.5) * w
    if mirror:
        a = M.fabs(a)
    return r * M.fsin(a), -r * _cos(M, a)


def _cos(M, a): return M.fsin(a + PI / 2)


def repeat(M, v, period):
    """Linear repeat: offset to the nearest multiple of period."""
    return (M.frac(v / period + 0.5) - 0.5) * period


# --- primitives (inside-positive) -----------------------------------------------------------------------------------------
def circle(M, x, y, r, cx=0.0, cy=0.0):
    dx, dy = x - cx, y - cy
    return r - M.fsqrt(dx * dx + dy * dy)


def ring(M, x, y, r, w, cx=0.0, cy=0.0): return outline(M, circle(M, x, y, r, cx, cy), w)


def rect(M, x, y, a, b, cx=0.0, cy=0.0, rad=0.0):
    """Box of half sizes a, b centred at (cx, cy), corner radius rad."""
    qx, qy = M.fabs(x - cx) - a + rad, M.fabs(y - cy) - b + rad
    return rad - (M.fsqrt(M.fmax(qx, 0.0) ** 2 + M.fmax(qy, 0.0) ** 2) + M.fmin(M.fmax(qx, qy), 0.0))


def chamfer_rect(M, x, y, a, b, ch, cx=0.0, cy=0.0):
    ax, ay = M.fabs(x - cx), M.fabs(y - cy)
    return M.fmin(a - ax, b - ay, (a + b - ch - ax - ay) * 0.70710678)


def halfplane(M, x, y, nx, ny, off):
    """Inside where x*nx + y*ny < off (n need not be unit)."""
    L = math.hypot(nx, ny)
    return (off - (x * nx + y * ny)) / L


def polygon(M, x, y, n, r, rot_a=0.0, cx=0.0, cy=0.0):
    """Regular n-gon with circumradius r, a vertex pointing up (rot_a turns it, radians)."""
    d = None
    ap = r * math.cos(PI / n)                                          # apothem
    for k in range(n):
        a = rot_a + PI / n + 2 * PI * k / n                            # edge normal angles (from up, clockwise)
        nx, ny = math.sin(a), -math.cos(a)
        e = ap - ((x - cx) * nx + (y - cy) * ny)
        d = e if d is None else M.fmin(d, e)
    return d


def triangle(M, x, y, r, up=True, cx=0.0, cy=0.0):
    return polygon(M, x, y, 3, r, 0.0 if up else PI, cx, cy)


def side(M, x, y, ax, ay, bx, by, inx, iny):
    """Signed distance to the line a-b, positive on the side of the point (inx, iny) (python floats for a, b, in)."""
    nx, ny = -(by - ay), bx - ax
    L = math.hypot(nx, ny)
    if (inx - ax) * nx + (iny - ay) * ny < 0:
        nx, ny = -nx, -ny
    return ((x - ax) * nx + (y - ay) * ny) / L


def star(M, x, y, n, r_out, r_in):
    """n-point star with tip radius r_out and notch radius r_in, a point straight up."""
    px, py = radial(M, x, y, n)
    ix, iy = r_in * math.sin(PI / n), -r_in * math.cos(PI / n)
    return side(M, px, py, 0.0, -r_out, ix, iy, 0.0, 0.0)


def sector(M, x, y, a0, a1):
    """Inside the angle range a0..a1 (radians, 0 = up, clockwise), as a distance-like field (radius-scaled)."""
    r, a = polar(M, x, y)
    mid, half = (a0 + a1) * 0.5, (a1 - a0) * 0.5
    da = a - mid
    da = da - M.floor(da / (2 * PI) + 0.5) * 2 * PI
    return (half - M.fabs(da)) * M.fmax(r, 0.05)


def seg(M, x, y, ax, ay, bx, by, w):
    """A stroke of half width w (round caps) from a to b."""
    dx, dy = bx - ax, by - ay
    t = cl(M, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy + 1e-12))
    ex, ey = x - ax - t * dx, y - ay - t * dy
    return w - M.fsqrt(ex * ex + ey * ey)


def bar(M, x, y, ax, ay, bx, by, w):
    """A stroke of half width w with SQUARE ends from a to b."""
    dx, dy = bx - ax, by - ay
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    px, py = x - (ax + bx) * 0.5, y - (ay + by) * 0.5
    along, across = px * ux + py * uy, px * -uy + py * ux
    return M.fmin(L * 0.5 - M.fabs(along), w - M.fabs(across))


def chevron(M, x, y, w, h, t, cy=0.0):
    """An upward chevron (^) centred at (0, cy): half width w, height h, arm thickness t (measured vertically)."""
    ax = M.fabs(x)
    top = (cy - h * 0.5) + ax * (h / w)                     # outer (upper) edge of the arm at this |x|
    return M.fmin(M.fmin(y - top, top + t - y), w - ax)


def arrow_head(M, x, y, w, h, tip_y):
    """A filled triangular arrow head pointing up with its tip at tip_y, base half width w, height h."""
    k = w / h
    side = (k * (y - tip_y) - M.fabs(x)) / math.hypot(1, k)
    return M.fmin(side, tip_y + h - y)
