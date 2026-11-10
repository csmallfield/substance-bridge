"""pplib.seams: seams as maths: resolution-independent height functions in SEAM SPACE, written against a backend `M` (npfunc for
numpy previews, sbsfunc for Pixel Processors), so the same code cooks.

  u = signed distance across the seam (tile units, 0 on the seam line), v = distance along it (tile units).
  Each seam(M, u, v, P, s) returns a height offset (0 = untouched surface, + raised, - sunk); P = repeat length,
  s = overall scale (width). Lay a seam along any line by feeding (u, v) from that line: a straight line, a panel edge
  (distance to the edge, position along it), a circle (r - R, angle * R).

Measured from the JRO SeamStitch brushes (reference only, substance_experiments/seam_study); nothing is sampled.
Used by sewn_cloth. thread() records coverage: call take_threads() after a seam to get a stitch-colour mask.
"""


def cl(M, x, lo=0.0, hi=1.0): return M.fmin(M.fmax(x, lo), hi)
def ss(M, x): x = cl(M, x); return x * x * (3.0 - 2.0 * x)            # smoothstep 0..1
def lat(M, v, P): return (M.frac(v / P + 0.5) - 0.5) * P               # -P/2..P/2 around the nearest repeat


def tube(M, d, r):
    """Round cross-section 0..1 of a thread / rod of radius r at distance d from its axis (0 outside)."""
    q = cl(M, d / r)
    return M.fsqrt(M.fmax(1.0 - q * q, 0.0))


THREADS = [None]       # thread coverage of the last seam(s) evaluated: reset with take_threads()


def take_threads():
    """Thread coverage (0..1) accumulated since the last call, then reset (for colouring stitches)."""
    t = THREADS[0]
    THREADS[0] = None
    return t


def thread(M, h, d, r, height, lift=0.0):
    """Lay a round thread over the surface h: inside radius r the height becomes max(h, lift + height * profile).
    Heights are in brush units (0 = surface, the references span about -0.25..+0.25)."""
    t = cl(M, (r - d) / (r * 0.15))
    top = lift + height * tube(M, d, r)
    THREADS[0] = t if THREADS[0] is None else M.fmax(THREADS[0], t)
    return h + (M.fmax(h, top) - h) * t


def seg(M, px, py, ax, ay, bx, by):
    """Distance from (px, py) to the segment a-b (a, b may be Exprs)."""
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy + 1e-12
    t = cl(M, ((px - ax) * dx + (py - ay) * dy) / L2)
    ex, ey = px - ax - t * dx, py - ay - t * dy
    return M.fsqrt(ex * ex + ey * ey)


def hole(M, du, dv, r, depth):
    """A needle hole: a small soft dimple."""
    d = M.fsqrt(du * du + dv * dv)
    q = cl(M, d / r)
    return -depth * (1.0 - q * q) ** 2


def rbox(M, u, v, a, b, rad):
    """Inside distance of a rounded box (half sizes a, b, corner radius rad): + inside."""
    qx, qy = M.fabs(u) - a + rad, M.fabs(v) - b + rad
    out = M.fsqrt(M.fmax(qx, 0.0) ** 2 + M.fmax(qy, 0.0) ** 2) + M.fmin(M.fmax(qx, qy), 0.0)
    return rad - out


def plate(M, d, h, bev):
    """A raised flat plate of height h with a bevel of width bev, from an inside distance d."""
    return h * ss(M, d / bev)


# --- cross profiles -------------------------------------------------------------------------------------------------------
def v_groove(M, u, w, depth):
    """Sharp V at the line, easing out to w."""
    q = cl(M, M.fabs(u) / w)
    return -depth * (1.0 - q) ** 2


def shoulders(M, u, w, h, offset):
    """Two soft puffs either side of the line (fabric pushed up by a seam), centred at +-offset, half width w."""
    q = cl(M, (M.fabs(u) - offset) / w, -1.0, 1.0)
    return h * (1.0 - q * q) ** 2


def step(M, u, h, bev):
    """One side (u < 0) higher by h, a bevelled step of width bev at the line."""
    return h * (1.0 - ss(M, u / bev + 0.5))


# --- seams (heights in brush units: groove about -0.25, threads +0.15..0.25) ---------------------------------------------
def plain(M, u, v, P, s=1.0):
    """seam_1: a sharp V seam between two puffed edges."""
    return v_groove(M, u, 0.035 * s, 0.32) + shoulders(M, u, 0.03 * s, 0.06, 0.03 * s)


def running_double(M, u, v, P, s=1.0):
    """seam_4: two rows of raised dash stitches, a soft valley between them."""
    off, r, half = 0.033 * s, 0.0105 * s, 0.38 * P
    lv_ = lat(M, v, P)
    h = shoulders(M, u, 0.03 * s, -0.05, 0.0)
    for sgn in (-1.0, 1.0):
        du = u - sgn * off
        d = M.fsqrt(du * du + M.fmax(M.fabs(lv_) - half, 0.0) ** 2)
        h = h + hole(M, du, M.fabs(lv_) - half - r * 0.3, r * 1.6, 0.12)
        h = thread(M, h, d, r, 0.24)
    return h


def herringbone(M, u, v, P, s=1.0):
    """seam_17: a V seam with diagonal thread stitches rising out to both sides, the right row half a stitch lower."""
    h = v_groove(M, u, 0.06 * s, 0.3) + shoulders(M, u, 0.06 * s, 0.05, 0.06 * s)
    r, reach, rise = 0.0085 * s, 0.13 * s, 0.32 * P
    for sgn, ph in ((-1.0, 0.0), (1.0, 0.1)):
        lv_ = lat(M, v - ph * P, P)
        uu = u * sgn
        h = h + hole(M, uu - reach - r * 0.4, lv_ + rise * 0.5, r * 2.0, 0.14)
        d = seg(M, uu, lv_, 0.006 * s, rise * 0.5, reach, -rise * 0.5)
        h = thread(M, h, d, r, 0.26)
    return h


def ladder(M, u, v, P, s=1.0):
    """seam_23: a V seam crossed by straight stitches, a needle hole at each end."""
    h = v_groove(M, u, 0.05 * s, 0.3) + shoulders(M, u, 0.045 * s, 0.06, 0.045 * s)
    r, reach = 0.009 * s, 0.075 * s
    lv_ = lat(M, v, P)
    for sgn in (-1.0, 1.0):
        h = h + hole(M, u - sgn * (reach + r * 0.5), lv_, r * 2.0, 0.16)
    d = seg(M, u, lv_, -reach, 0.0, reach, 0.0)
    return thread(M, h, d, r, 0.24)


def zigzag(M, u, v, P, s=1.0):
    """seam_22: one thread zigzagging across a V seam."""
    h = v_groove(M, u, 0.06 * s, 0.28) + shoulders(M, u, 0.05 * s, 0.06, 0.06 * s)
    r, reach = 0.011 * s, 0.065 * s
    lv_ = lat(M, v, P)
    for sgn, vv in ((1.0, 0.0), (-1.0, 0.5 * P), (-1.0, -0.5 * P)):
        h = h + hole(M, u - sgn * (reach + r * 0.5), lv_ - vv, r * 1.8, 0.14)
    d = M.fmin(seg(M, u, lv_, -reach, -0.5 * P, reach, 0.0), seg(M, u, lv_, reach, 0.0, -reach, 0.5 * P))
    return thread(M, h, d, r, 0.26)


def staples(M, u, v, P, s=1.0):
    """seam_24: bevelled metal staples across a V seam, pressing the surface in around them."""
    h = v_groove(M, u, 0.06 * s, 0.3) + shoulders(M, u, 0.07 * s, 0.05, 0.07 * s)
    lv_ = lat(M, v, P)
    d = rbox(M, u, lv_, 0.17 * s, 0.1 * P, 0.012 * s)
    h = h - 0.08 * (1.0 - ss(M, (d + 0.012 * s) / (0.012 * s))) * M.b01(M.lt(d, 0.0))   # pressed-in rim
    t = ss(M, d / (0.003 * s))
    top = 0.22 + 0.04 * ss(M, d / (0.02 * s))
    return h + (top - h) * t


def clip_seam(M, u, v, P, s=1.0):
    """scifi_seam_01: a stepped panel seam held by bevelled clips, each with a bolt."""
    h = step(M, u, 0.35, 0.012 * s) - 0.15 + v_groove(M, u, 0.008 * s, 0.15)
    lv_ = lat(M, v, P)
    d = rbox(M, u - 0.02 * s, lv_, 0.13 * s, 0.17 * P, 0.012 * s)
    t = ss(M, d / (0.008 * s))
    h = h + (0.38 - h) * t
    bolt_u, br = u - 0.06 * s, 0.03 * s
    db = M.fsqrt(bolt_u * bolt_u + lv_ * lv_)
    inside = M.b01(M.gt(d, 0.0))
    h = h - 0.06 * (1.0 - ss(M, M.fabs(db - br) / (0.003 * s))) * inside
    return h + 0.08 * ss(M, (br * 0.75 - db) / (0.006 * s)) * inside


def teeth(M, u, v, P, s=1.0):
    """scifi_seam_03: two plates meeting in interlocking square teeth, rails either side."""
    lv_ = M.frac(v / P)
    side = M.sel(M.lt(lv_, 0.5), 1.0, -1.0)                             # which plate owns the centre strip here
    a = 0.045 * s
    gap = 0.004 * s
    h = 0.3 * ss(M, (0.24 * s - M.fabs(u)) / (0.03 * s)) - 0.1          # the raised band
    centre = M.b01(M.lt(M.fabs(u), a))
    cut_v = M.fmin(M.fabs(lv_ - 0.5), M.fmin(lv_, 1.0 - lv_)) * P        # tooth ends across the strip
    line = M.fmin(M.fabs(M.fabs(u) - a) + (1.0 - centre) * 0.0, cut_v + (1.0 - centre))
    own = M.b01(M.gt(side * u, 0.0))                                      # the strip half facing its own plate
    h = h - 0.1 * centre * (1.0 - own)                                    # the far plate's tooth sits lower
    h = h - 0.22 * (1.0 - ss(M, line / gap))
    for uu in (-0.17 * s, -0.2 * s, 0.17 * s, 0.2 * s):                  # rails
        h = h - 0.15 * (1.0 - ss(M, M.fabs(u - uu) / (0.005 * s)))
    return h


SEAMS = dict(plain=(plain, 'seam_1', 1 / 7.0), running_double=(running_double, 'seam_4', 1 / 7.04),
             herringbone=(herringbone, 'seam_17', 1 / 7.94), ladder=(ladder, 'seam_23', 1 / 6.94),
             zigzag=(zigzag, 'seam_22', 2 / 14.08), staples=(staples, 'seam_24', 1 / 4.08),
             clip_seam=(clip_seam, 'scifi_seam_01', 1 / 3.98), teeth=(teeth, 'scifi_seam_03', 1 / 3.0))
