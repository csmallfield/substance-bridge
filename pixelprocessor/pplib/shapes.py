"""pplib.shapes: signed distance fields, height+class stacking, hashes and lattices for Pixel Processor layouts.

Conventions: distances are INSIDE-positive (d > 0 inside the shape), in tile units (0..1 across the tile).
Height and a material class travel together in an HC; a class is packed with a per-element random into one float
by Classes.tag(), decoded in the graph with floor(c * scale). Collected from scifi_wallpanel, techno_grid,
mesh/concrete materials.
"""
R2 = 0.70710678


# --- small maths --------------------------------------------------------------------------------------------------------
def cl(M, x, lo=0.0, hi=1.0): return M.fmin(M.fmax(x, lo), hi)
def ss(M, x): x = cl(M, x); return x * x * (3.0 - 2.0 * x)                 # smoothstep 0..1
def rnd(M, x): return M.floor(x + 0.5)
def lat(M, p, per): return (M.frac(p / per + 0.5) - 0.5) * per                # offset to the nearest multiple of per
def wrap(M, d): return M.frac(d + 0.5) - 0.5                                  # wrap a difference into -0.5..0.5
def prof(M, d, r): return M.fsqrt(M.fmax(1.0 - (d / r) * (d / r), 0.0))       # round (cylinder) profile 0..1
def onehot(M, T, t): return M.b01(M.gt(T, t - 0.5)) * M.b01(M.lt(T, t + 0.5))  # 1 where the integer T == t


def hashk(M, a, b, salt, seed=0.0):
    """0..1 random per integer (a, b); salt separates uses, seed (float or Expr) gives a new layout per value.
    Hash WRAPPED indices (M.mod(i, N)) so elements crossing the tile edge agree on both sides."""
    return M.hash2(a, b, salt + seed * 0.6180)


def table(M, k, values):
    """values[k] for an integer-valued index Expr k (a select chain; k outside clamps to the ends)."""
    v = values[-1]
    for j in range(len(values) - 2, -1, -1):
        v = M.sel(M.lt(k, j + 0.5), values[j], v)
    return v


# --- distance fields (inside-positive) ------------------------------------------------------------------------------------
def box(M, u, v, a, b):
    """Axis box centred at 0, half sizes a, b."""
    return M.fmin(a - M.fabs(u), b - M.fabs(v))


def cbox(M, u, v, a, b, ch):
    """Box with 45-degree chamfered corners (chamfer ch)."""
    au, av = M.fabs(u), M.fabs(v)
    return M.fmin(a - au, b - av, (a + b - ch - au - av) * R2)


def rbox(M, u, v, a, b, rad):
    """Box with round corners of radius rad."""
    qx, qy = M.fabs(u) - a + rad, M.fabs(v) - b + rad
    return rad - (M.fsqrt(M.fmax(qx, 0.0) ** 2 + M.fmax(qy, 0.0) ** 2) + M.fmin(M.fmax(qx, qy), 0.0))


def disc(M, u, v, r): return r - M.fsqrt(u * u + v * v)


def ring(M, u, v, r, w):
    """A ring of radius r and half width w."""
    return w - M.fabs(M.fsqrt(u * u + v * v) - r)


def capsule(M, u, v, r, half, axis=0):
    """A capsule of radius r along x (axis 0) or y (axis 1), straight half length `half`."""
    a, b = (u, v) if axis == 0 else (v, u)
    return r - M.fsqrt(M.fmax(M.fabs(a) - half, 0.0) ** 2 + b * b)


def seg(M, px, py, ax, ay, bx, by):
    """Distance (positive, NOT inside-positive) from (px, py) to the segment a-b; r - seg(...) is a capsule."""
    dx, dy = bx - ax, by - ay
    t = cl(M, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy + 1e-12))
    ex, ey = px - ax - t * dx, py - ay - t * dy
    return M.fsqrt(ex * ex + ey * ey)


def convex(M, x, y, pts):
    """Convex polygon from a list of (x, y) points (python floats, any winding)."""
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    d = None
    for a, b in zip(pts, pts[1:] + pts[:1]):
        ex, ey = b[0] - a[0], b[1] - a[1]
        L = (ex * ex + ey * ey) ** 0.5
        nx, ny = -ey / L, ex / L
        if (cx - a[0]) * nx + (cy - a[1]) * ny < 0:
            nx, ny = -nx, -ny
        s = (x - a[0]) * nx + (y - a[1]) * ny
        d = s if d is None else M.fmin(d, s)
    return d


def hexagon(M, u, v, a):
    """Pointy-top hexagon of inner radius a."""
    au, av = M.fabs(u), M.fabs(v)
    return a - M.fmax(au, M.fabs(au * 0.5 + av * 0.8660254), M.fabs(av * 0.8660254 - au * 0.5))


def chamfer_union(M, a, b, c):
    """Join two inside-positive fields with a 45-degree cut of size c in each corner."""
    return M.fmax(M.fmax(a, b), (a + b) * R2 + c)


# --- height + class stacking --------------------------------------------------------------------------------------------
class HC:
    """Height and packed class, carried together through every operation."""
    __slots__ = ('h', 'c')

    def __init__(self, h, c):
        self.h, self.c = h, c


class Classes:
    """Material classes packed with a per-element random: tag = (id + 0.1 + 0.8 r) / scale.
    In the graph: id = floor(c * scale), r = (frac(c * scale) - 0.1) / 0.8."""

    def __init__(self, names, scale=32.0):
        self.ids = {n: i for i, n in enumerate(names)}
        self.scale = float(scale)

    def tag(self, name, r=0.5):
        return (self.ids[name] + 0.1 + 0.8 * r) * (1.0 / self.scale)


def up(M, A, d, level, c=None, bev=0.0008):
    """Raise to `level` inside d > 0 (never lowers). c = a tag for the raised part (or None to keep)."""
    new = cl(M, d / bev) * level
    return HC(M.fmax(A.h, new), A.c if c is None else M.sel(M.gt(new, A.h), c, A.c))


def over(M, A, d, level, c=None, bev=0.0008):
    """Set to `level` inside d > 0 (raises or lowers): painter's order."""
    t = cl(M, d / bev)
    return HC(A.h + (level - A.h) * t, A.c if c is None else M.sel(M.gt(t, 0.5), c, A.c))


def down(M, A, d, level, c=None, bev=0.0008):
    """Lower to `level` inside d > 0 (never raises): grooves, pockets."""
    t = cl(M, d / bev)
    return HC(M.fmin(A.h, A.h + (level - A.h) * t), A.c if c is None else M.sel(M.gt(t, 0.5), c, A.c))


def cut(M, A, d, bev=0.0005):
    """Make a hole (height 0, i.e. transparent where alpha = height > 0) inside d > 0."""
    return HC(A.h * (1.0 - cl(M, d / bev)), A.c)


def paint(M, A, d, c):
    """Change the class inside d > 0, keep the height (decals, labels)."""
    return HC(A.h, M.sel(M.gt(d, 0.0), c, A.c))


def cylinder(M, A, dist, r, level, amp, c=None, bev=0.0006):
    """A round bar / pipe / thread: dist = distance from its axis, top = level + amp at the centre."""
    return up(M, A, r - dist, level + amp * prof(M, dist, r), c, bev)


def comb(M, A, B):
    """Max-combine two HC layers (B's class where B is higher)."""
    return HC(M.fmax(A.h, B.h), M.sel(M.gt(B.h, A.h), B.c, A.c))


def mix(M, parts):
    """parts: [(weight, HC)] with exactly one weight 1 per pixel (e.g. onehot of a hashed type)."""
    h = c = None
    for w, P in parts:
        h = w * P.h if h is None else h + w * P.h
        c = w * P.c if c is None else c + w * P.c
    return HC(h, c)


def slab(M, A, d, level, c, bev=0.0035, border=0.008, step=-0.012, line=True):
    """A layered plate: wide chamfer, a border band with an inset line, then a step to the field."""
    A = up(M, A, d, level, c, bev)
    if line:
        A = down(M, A, M.fmin(d - bev, 0.0006 - M.fabs(d - border * 0.55)), level - 0.014, None, 0.0004)
    return HC(A.h + step * cl(M, (d - border) / 0.0013), A.c)


def pocket(M, A, d_feature, margin=0.003, depth=0.025, bev=0.0014, c=None):
    """Cut a recess around a feature's outline (grown by margin) before drawing the feature in it."""
    return HC(A.h - depth * cl(M, (d_feature + margin) / bev),
              A.c if c is None else M.sel(M.gt(d_feature + margin, 0.0), c, A.c))


# --- layouts --------------------------------------------------------------------------------------------------------------
def superblock_slots(M, x, y, n, seed=0.0, salt=31.0, probs=(0.25, 0.5, 0.75)):
    """An n x n grid (n even) merged in 2x2 superblocks into one 2x2, two 2x1, two 1x2 or four 1x1 slots.
    Returns dict(u, v: slot-local centred coords; a, b: half sizes; id: unique slot id; full/hor/ver/single flags).
    Tiles both ways."""
    cx, cy = x * n, y * n
    bi, bj = M.floor(cx * 0.5), M.floor(cy * 0.5)
    sx, sy = cx - bi * 2.0, cy - bj * 2.0
    fx, fy = M.floor(sx), M.floor(sy)
    rb = hashk(M, M.mod(bi, n / 2.0), M.mod(bj, n / 2.0), salt, seed)
    mf = M.b01(M.lt(rb, probs[0]))
    mh = M.b01(M.lt(rb, probs[1])) - mf
    mv = M.b01(M.lt(rb, probs[2])) - mf - mh
    ms = 1.0 - mf - mh - mv
    x0, y0 = (mv + ms) * fx, (mh + ms) * fy
    x1 = x0 + (mf + mh) * 2.0 + (mv + ms)
    y1 = y0 + (mf + mv) * 2.0 + (mh + ms)
    return dict(u=x - (bi * 2.0 + (x0 + x1) * 0.5) / n, v=y - (bj * 2.0 + (y0 + y1) * 0.5) / n,
                a=(x1 - x0) / (2.0 * n), b=(y1 - y0) / (2.0 * n),
                id=(M.mod(bi, n / 2.0) * 2.0 + x0) * 2.0 * n + M.mod(bj, n / 2.0) * 2.0 + y0,
                full=mf, hor=mh, ver=mv, single=ms)


def hex_cell(M, x, y, nx, ny):
    """Nearest centre on a pointy-top hex lattice that tiles in a square: nx = 2 mod 4, ny = nx + 2 rows.
    Returns (du, dv, i, j) offset to the centre (tile units) and wrapped cell indices."""
    ph, pv = 1.0 / nx, 1.0 / ny
    best = None
    for k in (0.0, 1.0):
        j = M.floor(y / pv - 0.5) + k
        off = M.mod(j, 2.0) * 0.5
        i = rnd(M, x / ph - off)
        du, dv = x - (i + off) * ph, y - (j + 0.5) * pv
        d2 = du * du + dv * dv
        if best is None:
            best = (du, dv, i, j, d2)
        else:
            nearer = M.lt(d2, best[4])
            best = tuple(M.sel(nearer, n_, o_) for n_, o_ in zip((du, dv, i, j, d2), best))
    return best[0], best[1], M.mod(best[2], float(nx)), M.mod(best[3], float(ny))
