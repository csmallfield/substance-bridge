"""Techno Grid layout (square, tiles both ways, alpha = everything drawn).

Back to front, each on its own lattice (see ANALYSIS.md):
  rods (32 lines), beams (8 lines), modules (8x8 cells in 2x2 superblocks, 9 types),
  pipes (horizontal 12 lanes x 10 segments, vertical 10 lanes x 12 segments), cables (6 sagging + 3 vertical groups).
Height 0 = transparent. Every hash takes the Seed, so each seed is a different layout.
`M` is numpy (npfunc) or sbsfunc; x, y in 0..1 (y down).
"""
R2 = 0.70710678
IDS = dict(none=0, rod=1, beam=2, plate=3, plate_dark=4, detail=5, grille=6, brass=7, tank=8, fin=9,
           grating=10, louvre=11, panel=12, panel_alt=13, pipe=14, pipe_alt=15, flange=16, clamp=17,
           valve=18, gbox=19, cable=20, cable_alt=21, tie=22, light=23, bolt=24, chip=25, cap=26)
ID_SCALE = 32.0
_S = [0.0]          # seed (float or Expr), set by layout()


class HC:
    __slots__ = ('h', 'c')

    def __init__(self, h, c):
        self.h, self.c = h, c


def hs(M, a, b, salt):
    return M.hash2(a, b, salt + _S[0] * 0.6180)


def tag(cls, r):
    return (IDS[cls] + 0.1 + 0.8 * r) * (1.0 / ID_SCALE)


def cl(M, x): return M.fmin(M.fmax(x, 0.0), 1.0)
def rnd(M, x): return M.floor(x + 0.5)
def lat(M, p, per): return (M.frac(p / per + 0.5) - 0.5) * per
def prof(M, d, r): return M.fsqrt(M.fmax(1.0 - (d / r) * (d / r), 0.0))
def w01(M, T, t): return M.b01(M.gt(T, t - 0.5)) * M.b01(M.lt(T, t + 0.5))


def up(M, A, d, level, cls, r, bev=0.0008):
    """Raise to `level` inside d > 0 (never lowers)."""
    new = cl(M, d / bev) * level
    return HC(M.fmax(A.h, new), M.sel(M.gt(new, A.h), tag(cls, r), A.c))


def over(M, A, d, level, cls=None, r=0.5, bev=0.0008):
    """Set to `level` inside d > 0 (raises or lowers)."""
    t = cl(M, d / bev)
    c = A.c if cls is None else M.sel(M.gt(t, 0.5), tag(cls, r), A.c)
    return HC(A.h + (level - A.h) * t, c)


def cut(M, A, d, bev=0.0005):
    """Make a hole (transparent) inside d > 0."""
    return HC(A.h * (1.0 - cl(M, d / bev)), A.c)


def cyl(M, A, dist, r, level, amp, cls, rr, bev=0.0006):
    return up(M, A, r - dist, level + amp * prof(M, dist, r), cls, rr, bev)


def comb(M, A, B):
    return HC(M.fmax(A.h, B.h), M.sel(M.gt(B.h, A.h), B.c, A.c))


def mix(M, parts):
    """parts: [(weight, HC)] with exactly one weight 1 per pixel."""
    h = None
    c = None
    for w, P in parts:
        h = w * P.h if h is None else h + w * P.h
        c = w * P.c if c is None else c + w * P.c
    return HC(h, c)


def box(M, u, v, a, b): return M.fmin(a - M.fabs(u), b - M.fabs(v))


def cbox(M, u, v, a, b, ch):
    au, av = M.fabs(u), M.fabs(v)
    return M.fmin(a - au, b - av, (a + b - ch - au - av) * R2)


# ============================================================================================== rods + beams
def rods(M, x, y, amount=0.38):
    A = HC(0.0, 0.0)
    N = 32.0
    for ax in (0, 1):
        u, v = (x, y) if ax == 0 else (y, x)
        s = 10.0 * ax
        k = rnd(M, u * N)
        du = (u * N - k) / N
        km = M.mod(k, N)
        seg = M.mod(M.floor(v * 8.0), 8.0)
        on = M.b01(M.gt(hs(M, km, 0.0, 1 + s), 1.0 - amount)) * M.b01(M.gt(hs(M, km, seg, 2 + s), 0.3)) \
            * M.b01(M.gt(M.mod(k, 4.0), 0.5))                                      # beam lines are not rods
        r = 0.0015 + 0.0017 * hs(M, km, 0.0, 3 + s)
        lvl = 0.12 + 0.1 * hs(M, km, seg, 4 + s)
        dist = M.fabs(du)
        d = M.sel(M.gt(on, 0.5), r - dist, -1.0)
        A = up(M, A, d, lvl + 0.035 * prof(M, dist, r), 'rod', hs(M, km, seg, 5 + s), 0.0005)
    return A


def beams(M, x, y, amount=0.72):
    A = HC(0.0, 0.0)
    N = 8.0
    for ax in (0, 1):
        u, v = (x, y) if ax == 0 else (y, x)
        s = 10.0 * ax
        k = rnd(M, u * N)
        du = (u * N - k) / N
        km = M.mod(k, N)
        seg = M.mod(M.floor(v * N), N)
        on = M.b01(M.gt(hs(M, km, seg, 21 + s), 1.0 - amount))
        w = 0.0032 + 0.0022 * hs(M, km, 0.0, 22 + s)
        lvl = 0.27 + 0.04 * hs(M, km, seg, 23 + s)
        dist = M.fabs(du)
        d = M.sel(M.gt(on, 0.5), w - dist, -1.0)
        rr = hs(M, km, seg, 24 + s)
        B = up(M, HC(0.0, 0.0), d, lvl, 'beam', rr, 0.0009)
        B = over(M, B, M.fmin(d, w * 0.38 - dist), lvl - 0.03, None, 0.5, 0.0005)   # channel down the middle
        # bolts along the flanges
        bp = lat(M, v, 0.03125)
        bd = 0.0011 - M.fsqrt(bp * bp + (dist - w * 0.7) * (dist - w * 0.7))
        B = up(M, B, M.fmin(bd, d), lvl + 0.012, 'bolt', rr, 0.0004)
        A = comb(M, A, B)
    return A


# ================================================================================================== modules
def m_grille(M, u, v, a, b, lvl, rr, U, V, LA, SA):
    d = box(M, u, v, a, b)
    A = up(M, HC(0.0, 0.0), d, lvl, 'plate', rr, 0.001)
    f = 0.0055 + 0.003 * rr
    inner = d - f
    p = 0.0045 + 0.004 * M.frac(rr * 7.0)
    w = 0.0009 + 0.0004 * M.frac(rr * 13.0)
    dbar = w - M.fmin(M.fabs(lat(M, u, p)), M.fabs(lat(M, v, p)))
    t = cl(M, inner / 0.0007)
    mesh = (lvl - 0.035) * cl(M, dbar / 0.0004)
    cls = M.sel(M.gt(rr, 0.5), tag('brass', rr), tag('grille', rr))
    return HC(A.h * (1.0 - t) + mesh * t, M.sel(M.gt(t, 0.5), cls, A.c))


def m_machine(M, u, v, a, b, lvl, rr, U, V, LA, SA):
    d = box(M, u, v, a, b)
    A = up(M, HC(0.0, 0.0), d, lvl, 'plate', rr, 0.0012)
    ins = 0.008
    A = up(M, A, cbox(M, u, v, a - ins, b - ins, 0.006), lvl + 0.07, 'plate_dark', rr, 0.0025)
    # hatch at one end
    R = M.fmin(SA - ins, LA * 0.42) * 0.62
    du = U + (LA - ins) * 0.45
    dh = M.fsqrt(du * du + V * V)
    A = over(M, A, M.fmin(R - dh, 0.0011 - M.fabs(dh - R * 0.82)), lvl + 0.05, None, 0.5, 0.0005)
    A = up(M, A, R * 0.6 - dh, lvl + 0.085 + 0.03 * prof(M, dh, R * 0.6), 'cap', rr, 0.0006)
    # valve wheel at the other end
    Rw = M.fmin(SA - ins, LA * 0.42) * 0.7
    dw_u = U - (LA - ins) * 0.45
    dwh = M.fsqrt(dw_u * dw_u + V * V)
    rim = 0.0016 - M.fabs(dwh - Rw)
    spokes = M.fmin(0.0011 - M.fmin(M.fabs(dw_u), M.fabs(V)), Rw - dwh)
    hub = Rw * 0.25 - dwh
    A = up(M, A, M.fmax(rim, spokes, hub), lvl + 0.13, 'valve', rr, 0.0004)
    # corner bolts on the base plate
    qx = M.fabs(u) - (a - 0.0042)
    qy = M.fabs(v) - (b - 0.0042)
    A = up(M, A, 0.0021 - M.fsqrt(qx * qx + qy * qy), lvl + 0.02, 'bolt', rr, 0.0004)
    # indicator light near a block corner
    lx = u - (a - ins - 0.007)
    ly = v + (b - ins - 0.0055)
    A = over(M, A, box(M, lx, ly, 0.0032, 0.0014), lvl + 0.075, 'light', rr, 0.0003)
    return A


def m_tank(M, u, v, a, b, lvl, rr, U, V, LA, SA):
    A = HC(0.0, 0.0)
    R = M.fmin(SA * 0.84, LA * 0.42)
    L = LA - R * 0.35
    # saddles under the tank
    for s in (-1.0, 1.0):
        A = up(M, A, box(M, U - s * L * 0.62, V, 0.0045, SA), lvl, 'plate_dark', rr, 0.0008)
    q = M.fmax(M.fabs(U) - (L - R * 0.6), 0.0) * 1.6
    dist = M.fsqrt(V * V + q * q)
    A = cyl(M, A, dist, R, lvl + 0.04, 0.18, 'tank', rr, 0.0008)
    top = lvl + 0.04 + 0.18 * prof(M, dist, R)
    inb = M.b01(M.lt(M.fabs(U), L - R * 0.6))
    band = M.fmin(0.0013 - M.fabs(lat(M, U, 0.021)), R - M.fabs(V)) * inb - (1.0 - inb)
    A = over(M, A, band, top + 0.01, 'detail', rr, 0.0004)
    ring = M.fmin(0.0018 - M.fabs(M.fabs(U) - (L - R * 0.6)), R * 1.04 - M.fabs(V))
    A = up(M, A, ring, top + 0.012, 'flange', rr, 0.0004)
    return A


def m_fins(M, u, v, a, b, lvl, rr, U, V, LA, SA):
    d = box(M, u, v, a, b)
    A = up(M, HC(0.0, 0.0), d, lvl - 0.04, 'plate_dark', rr, 0.001)
    inner = box(M, U, V, LA - 0.004, SA - 0.004)
    fin = M.fmin(0.0011 - M.fabs(lat(M, V, 0.0055)), inner)
    endfall = cl(M, (LA - M.fabs(U)) / 0.012)
    A = up(M, A, fin, lvl + 0.02 + 0.05 * endfall, 'fin', rr, 0.0004)
    hp = M.fabs(U)
    A = cyl(M, A, hp, 0.0042, lvl + 0.06, 0.04, 'pipe_alt', rr)
    A = HC(A.h * M.b01(M.gt(SA + 0.0005 - M.fabs(V), 0.0)), A.c)
    return A


def m_grating(M, u, v, a, b, lvl, rr, U, V, LA, SA):
    d = box(M, u, v, a, b)
    A = up(M, HC(0.0, 0.0), d, lvl, 'grating', rr, 0.0008)
    inner = box(M, U, V, LA - 0.0045, SA - 0.0055)
    ladder = M.gt(rr, 0.55)
    rung = 0.0012 - M.fabs(lat(M, U, 0.0085))
    p = 0.0065
    diag = (0.0008 - M.fmin(M.fabs(lat(M, U + V, p)), M.fabs(lat(M, U - V, p)))) * 1.0
    bar = M.sel(ladder, rung, diag)
    t = cl(M, inner / 0.0006)
    fill = (lvl - 0.02) * cl(M, bar / 0.0004)
    return HC(A.h * (1.0 - t) + fill * t, A.c)


def m_louvre(M, u, v, a, b, lvl, rr, U, V, LA, SA):
    d = box(M, u, v, a, b)
    A = up(M, HC(0.0, 0.0), d, lvl, 'plate', rr, 0.0009)
    inner = d - 0.0055
    p = 0.0085
    t = M.frac(U / p)
    slat = (lvl - 0.05 + 0.065 * t) * M.b01(M.lt(t, 0.78))
    k = cl(M, inner / 0.0006)
    return HC(A.h * (1.0 - k) + slat * k, M.sel(M.gt(k, 0.5), tag('louvre', rr), A.c))


def m_panel(M, u, v, a, b, lvl, rr, U, V, LA, SA):
    cls = 'panel_alt' if False else 'panel'
    d = cbox(M, u, v, a, b, 0.008)
    A = up(M, HC(0.0, 0.0), d, lvl + 0.03, cls, rr, 0.002)
    A = HC(A.h, M.sel(M.gt(rr, 0.5), tag('panel_alt', rr), A.c))
    A = over(M, A, M.fmin(d, 0.0007 - M.fabs(d - 0.0055)), lvl + 0.015, None, 0.5, 0.0004)       # border line
    us = (M.frac(rr * 5.0) - 0.5) * LA * 0.7
    A = over(M, A, M.fmin(d - 0.0055, 0.0008 - M.fabs(U - us)), lvl + 0.012, None, 0.5, 0.0004)  # split seam
    # recessed field in the bigger half
    side = M.sel(M.gt(us, 0.0), -1.0, 1.0)
    cx = (us + side * LA) * 0.5
    hw = M.fabs(side * LA - us) * 0.5 - 0.009
    rec = cbox(M, U - cx, V, hw, SA - 0.011, 0.004)
    A = over(M, A, rec, lvl + 0.005, None, 0.5, 0.0012)
    # bolts along the border, 4 per side
    bu = lat(M, U, LA * 0.5)
    by = M.fabs(V) - (SA - 0.0035)
    A = up(M, A, M.fmin(0.0016 - M.fsqrt(bu * bu + by * by), d), lvl + 0.04, 'bolt', rr, 0.0004)
    # small brass label in the other half
    lab = box(M, U - (us - side * 0.012), V - SA * 0.4, 0.007, 0.0028)
    A = up(M, A, lab, lvl + 0.035, 'brass', rr, 0.0004)
    return A


def m_manifold(M, u, v, a, b, lvl, rr, U, V, LA, SA):
    A = HC(0.0, 0.0)
    for s in (-1.0, 1.0):
        A = up(M, A, box(M, U - s * (LA - 0.004), V, 0.004, SA), lvl, 'plate_dark', rr, 0.0008)
    n = 3.0 + M.floor(M.frac(rr * 3.7) * 2.99)
    sp = 2.0 * SA / n
    k = M.fmin(M.fmax(M.floor((V + SA) / sp), 0.0), n - 1.0)
    dv = V + SA - (k + 0.5) * sp
    R = sp * 0.3
    dist = M.fabs(dv)
    A = cyl(M, A, dist, R, lvl + 0.05, 0.08, 'pipe', rr)
    fl = M.fmin(0.0014 - M.fabs(lat(M, U, 0.028)), R * 1.3 - dist)
    A = up(M, A, fl, lvl + 0.05 + 0.08 + 0.01, 'flange', rr, 0.0004)
    # one valve wheel per pipe, staggered
    wu = U - (M.frac(k * 0.37 + rr * 3.1) - 0.5) * LA * 1.2
    dw = M.fsqrt(wu * wu + dv * dv)
    Rw = sp * 0.46
    wheel = M.fmax(0.0012 - M.fabs(dw - Rw), M.fmin(0.0009 - M.fmin(M.fabs(wu), M.fabs(dv)), Rw - dw))
    A = up(M, A, wheel, lvl + 0.17, 'valve', rr, 0.0004)
    return A


def m_electronics(M, u, v, a, b, lvl, rr, U, V, LA, SA, mid):
    d = box(M, u, v, a, b)
    A = up(M, HC(0.0, 0.0), d, lvl - 0.03, 'plate_dark', rr, 0.001)
    q = 0.0125
    i = M.floor(u / q)
    j = M.floor(v / q)
    lu = u - (i + 0.5) * q
    lv_ = v - (j + 0.5) * q
    h1 = hs(M, i + mid * 7.0, j, 61)
    h2 = hs(M, i + mid * 7.0, j, 62)
    T = M.floor(h1 * 4.0)
    inside = d - 0.003 - M.fmax(M.fabs(lu), M.fabs(lv_)) * 0.0      # sub-cell centres inside the board
    ok = M.b01(M.gt(d - 0.0035 - q * 0.5, -q * 0.5))
    # 0 box, 1 cylinder, 2 chip with pins, 3 low block
    bxs = cbox(M, lu, lv_, q * (0.25 + 0.2 * h2), q * (0.25 + 0.2 * M.frac(h2 * 7.0)), 0.0015)
    B0 = up(M, A, M.fmin(bxs, inside), lvl + 0.01 + 0.07 * h2, 'detail', h2, 0.0006)
    dc = M.fsqrt(lu * lu + lv_ * lv_)
    B1 = cyl(M, A, dc, q * (0.25 + 0.15 * h2), lvl + 0.02, 0.06, 'cap', h2)
    chip = box(M, lu, lv_, q * 0.36, q * 0.28)
    pins = M.fmin(box(M, lu, lv_, q * 0.36, q * 0.42), 0.00045 - M.fabs(lat(M, lu, 0.0018)))
    B2 = up(M, up(M, A, pins, lvl - 0.012, 'detail', h2, 0.0003), chip, lvl + 0.0, 'chip', h2, 0.0005)
    B3 = up(M, A, cbox(M, lu, lv_, q * 0.46, q * 0.46, 0.003), lvl - 0.005 + 0.02 * h2, 'plate', h2, 0.0008)
    B = mix(M, [(w01(M, T, 0.0), B0), (w01(M, T, 1.0), B1), (w01(M, T, 2.0), B2), (w01(M, T, 3.0), B3)])
    return HC(A.h + (B.h - A.h) * ok, M.sel(M.gt(ok, 0.5), B.c, A.c))


TYPES = [m_grille, m_machine, m_tank, m_fins, m_grating, m_louvre, m_panel, m_manifold, m_electronics]
TYPE_W = [1.1, 1.3, 0.8, 0.8, 0.9, 0.8, 0.9, 0.9, 1.2]     # relative frequencies


def modules(M, x, y, empty=0.3):
    cx8, cy8 = x * 8.0, y * 8.0
    bi, bj = M.floor(cx8 * 0.5), M.floor(cy8 * 0.5)
    bim, bjm = M.mod(bi, 4.0), M.mod(bj, 4.0)
    sx, sy = cx8 - bi * 2.0, cy8 - bj * 2.0
    fx, fy = M.floor(sx), M.floor(sy)
    rb = hs(M, bim, bjm, 31)
    mf = M.b01(M.lt(rb, 0.22))
    mh = M.b01(M.lt(rb, 0.47)) - mf
    mv = M.b01(M.lt(rb, 0.70)) - mf - mh
    ms = 1.0 - mf - mh - mv
    x0 = (mv + ms) * fx
    y0 = (mh + ms) * fy
    x1 = x0 + (mf + mh) * 2.0 + (mv + ms)
    y1 = y0 + (mf + mv) * 2.0 + (mh + ms)
    mid = (bim * 2.0 + x0) * 8.0 + bjm * 2.0 + y0
    u = x - (bi * 2.0 + (x0 + x1) * 0.5) / 8.0
    v = y - (bj * 2.0 + (y0 + y1) * 0.5) / 8.0
    marg = 0.0055 + 0.0075 * hs(M, mid, 0.0, 32)
    a = (x1 - x0) / 16.0 - marg
    b = (y1 - y0) / 16.0 - marg
    lvl = 0.34 + 0.12 * hs(M, mid, 0.0, 35)
    rr = hs(M, mid, 0.0, 36)
    s = M.b01(M.gt(a, b - 1e-5))
    U, V = s * u + (1.0 - s) * v, s * v + (1.0 - s) * u
    LA, SA = s * a + (1.0 - s) * b, s * b + (1.0 - s) * a
    # weighted type pick
    tw = sum(TYPE_W)
    ht = hs(M, mid, 0.0, 34) * tw
    parts = []
    acc = 0.0
    for t, fn in enumerate(TYPES):
        w = M.b01(M.gt(ht, acc)) * M.b01(M.lt(ht, acc + TYPE_W[t])) if t < len(TYPES) - 1 else M.b01(M.gt(ht, acc))
        acc += TYPE_W[t]
        P = fn(M, u, v, a, b, lvl, rr, U, V, LA, SA, mid) if fn is m_electronics else fn(M, u, v, a, b, lvl, rr, U, V, LA, SA)
        parts.append((w, P))
    A = mix(M, parts)
    keep = M.b01(M.gt(hs(M, mid, 0.0, 33), empty))
    return HC(A.h * keep, A.c), mid


# ==================================================================================================== pipes
def pipes(M, x, y, ax, NL, NS, salt, prob):
    u, v = (y, x) if ax == 0 else (x, y)            # u across lanes, v along the pipe
    j = M.floor(u * NL)
    jm = M.mod(j, NL)
    ul = u * NL - j - 0.5
    on = M.b01(M.lt(hs(M, jm, 0.0, salt), prob))
    hn = hs(M, jm, 1.0, salt)
    n = 1.0 + M.b01(M.gt(hn, 0.55)) + M.b01(M.gt(hn, 0.85))
    rl = (0.07 + 0.12 * hs(M, jm, 2.0, salt)) / (0.6 + 0.4 * n)       # radius in lane units
    sp = 2.5 * rl
    c = (hs(M, jm, 3.0, salt) - 0.5) * M.fmax(0.8 - n * sp, 0.0)
    k = M.fmin(M.fmax(rnd(M, (ul - c) / sp + (n - 1.0) * 0.5), 0.0), n - 1.0)
    dyl = ul - c - (k - (n - 1.0) * 0.5) * sp
    R = rl / NL
    dist = M.fabs(dyl) / NL
    lvl = 0.42 + 0.2 * hs(M, jm, 4.0, salt)
    amp = 0.03 + 7.0 * R
    rr = hs(M, jm, 5.0, salt)
    pcls = 'pipe_alt' if False else 'pipe'
    # segments: some missing (end caps), flanges between present ones
    s = M.floor(v * NS)
    sm = M.mod(s, NS)
    vl = v * NS - s
    son = M.b01(M.gt(hs(M, jm, sm, salt + 1), 0.12))
    pon = M.b01(M.gt(hs(M, jm, M.mod(s - 1.0, NS), salt + 1), 0.12))
    non = M.b01(M.gt(hs(M, jm, M.mod(s + 1.0, NS), salt + 1), 0.12))
    gl = 0.12 * (1.0 - pon) - 1.0 * pon
    gr = 0.88 * (1.0 - non) + 2.0 * non
    ex = M.fmax(M.fmax(gl - vl, vl - gr), 0.0) / NS
    dd = M.fsqrt(dist * dist + ex * ex)
    live = on * son
    A = cyl(M, HC(0.0, 0.0), dd, M.sel(M.gt(live, 0.5), R, 1e-6), lvl, amp, pcls, rr)
    A = HC(A.h * live, M.sel(M.gt(rr, 0.6), tag('pipe_alt', rr), A.c))
    top = lvl + amp
    # flanges at joints between present segments
    dv = M.fmin(vl, 1.0 - vl) / NS
    both = M.sel(M.lt(vl, 0.5), pon, non)
    fl = M.fmin(0.0022 - dv, R * 1.35 - dist) * both - (1.0 - both)
    A = up(M, A, M.fmin(fl, live * 2.0 - 1.0), top * 0.96 + 0.012, 'flange', rr, 0.0004)
    # greeble zones
    gz = M.b01(M.lt(hs(M, jm, sm, salt + 2), 0.5))
    NSUB = 5.0
    sub = M.floor(vl * NSUB)
    w = (vl * NSUB - sub - 0.5) / (NSUB * NS)        # tile units, centred in the sub-cell
    ht = hs(M, jm, sm * NSUB + sub, salt + 3)
    T = M.floor(ht * 6.5)
    rack = (n * sp * 0.5) / NL + R * 0.35            # half height of the rack, tile units
    ur = (ul - c) / NL                               # distance from rack centre, tile units
    zero = HC(0.0, 0.0)
    # 0 clamp bands
    band = M.fmin(0.0012 - M.fabs(M.fabs(w) - 0.0042), rack + 0.0012 - M.fabs(ur))
    G0 = up(M, zero, band, top + 0.012, 'clamp', rr, 0.0004)
    # 1 block around the rack
    hw = 0.0055 + 0.003 * M.frac(ht * 11.0)
    blk = cbox(M, w, ur, hw, rack + 0.002, 0.0025)
    G1 = up(M, zero, blk, top + 0.025, 'gbox', ht, 0.0008)
    bq = M.fsqrt((M.fabs(w) - hw + 0.0022) ** 2 + (M.fabs(ur) - rack + 0.0002) ** 2)
    G1 = up(M, G1, 0.0011 - bq, top + 0.035, 'bolt', ht, 0.0003)
    # 2 valve wheel on each pipe
    dw = M.fsqrt(w * w + dyl * dyl / (NL * NL))
    Rw = R * 1.5 + 0.0015
    wheel = M.fmax(0.0012 - M.fabs(dw - Rw), M.fmin(0.0009 - M.fmin(M.fabs(w), dist), Rw - dw), R * 0.7 - dw)
    G2 = up(M, zero, wheel, top + 0.06, 'valve', ht, 0.0004)
    # 3 junction box with a branch stub toward the lane edge
    jb = cbox(M, w, ur, 0.0045, rack + 0.0015, 0.002)
    G3 = up(M, zero, jb, top + 0.02, 'gbox', ht, 0.0006)
    side = M.sel(M.gt(M.frac(ht * 7.0), 0.5), 1.0, -1.0)
    stub_len = (0.5 - M.fabs(c)) / NL
    sd = M.fsqrt(w * w)
    stub = M.fmin(R * 0.5 - sd, M.fmin(ur * side, stub_len - ur * side))
    G3 = cyl(M, G3, sd, M.sel(M.gt(stub, 0.0), R * 0.5, 1e-6), top - 0.03, 0.03, 'pipe_alt', ht)
    G = mix(M, [(w01(M, T, 0.0), G0), (w01(M, T, 1.0), G1), (w01(M, T, 2.0), G2), (w01(M, T, 3.0), G3),
                (M.b01(M.gt(T, 3.5)), zero)])
    k_ = gz * live
    return comb(M, A, HC(G.h * k_, G.c))


# =================================================================================================== cables
def cable_h(M, x, y, g, G, salt):
    hn = hs(M, g, 0.0, salt)
    nsp = 2.0 + M.floor(hn * 2.99)                                   # 2..4 spans across the tile
    Yg = (g + 0.5 + 0.7 * (hs(M, g, 1.0, salt) - 0.5)) / G
    a = M.floor(x * nsp)
    t = x * nsp - a
    am, bm = M.mod(a, nsp), M.mod(a + 1.0, nsp)
    ya = Yg + 0.06 * (hs(M, g, am + 10.0, salt) - 0.5)
    yb = Yg + 0.06 * (hs(M, g, bm + 10.0, salt) - 0.5)
    sag = (0.06 + 0.12 * hs(M, g, 2.0, salt)) / nsp
    yc = ya + (yb - ya) * t + sag * 4.0 * t * (1.0 - t)
    slope = (yb - ya) * nsp + sag * 4.0 * (1.0 - 2.0 * t) * nsp
    dy = M.frac(y - yc + 0.5) - 0.5
    return _bundle(M, dy, slope, M.fmin(t, 1.0 - t) / nsp, g, salt)


def cable_v(M, x, y, g, G, salt):
    Xg = (g + 0.5 + 0.7 * (hs(M, g, 1.0, salt) - 0.5)) / G
    kw = 1.0 + M.floor(hs(M, g, 3.0, salt) * 2.99)
    ph = hs(M, g, 4.0, salt) * 6.2832
    xc = Xg + 0.006 * M.fsin(6.2832 * kw * y + ph)
    slope = 0.006 * 6.2832 * kw * M.fsin(6.2832 * kw * y + ph + 1.5708)
    dx = M.frac(x - xc + 0.5) - 0.5
    nties = 3.0 + M.floor(hs(M, g, 5.0, salt) * 3.0)
    ta = M.fabs(lat(M, y, 1.0 / nties))
    return _bundle(M, dx, slope, ta, g, salt)


def _bundle(M, dy, slope, tdist, g, salt):
    nc = 1.0 + M.floor(hs(M, g, 6.0, salt) * 4.99)
    rc = 0.0014 + 0.0016 * hs(M, g, 7.0, salt)
    sp = 2.15 * rc
    k = M.fmin(M.fmax(rnd(M, dy / sp + (nc - 1.0) * 0.5), 0.0), nc - 1.0)
    cs = 1.0 / M.fsqrt(1.0 + slope * slope)
    dd = M.fabs(dy - (k - (nc - 1.0) * 0.5) * sp) * cs
    front = M.gt(hs(M, g, 8.0, salt), 0.45)
    lvl = M.sel(front, 0.8, 0.36)
    ck = hs(M, k + g * 5.0, 9.0, salt)
    A = cyl(M, HC(0.0, 0.0), dd, rc, lvl, 0.03, 'cable', ck, 0.0004)
    A = HC(A.h, M.sel(M.gt(ck, 0.6), tag('cable_alt', ck), A.c))
    half = nc * sp * 0.5 * cs
    # ties along the run, a clamp block at each anchor
    tie = M.fmin(0.0011 - M.fabs(lat(M, tdist, 0.035)), half + 0.0008 - M.fabs(dy * cs))
    A = up(M, A, M.fmin(tie, M.b01(M.gt(tdist, 0.008)) * 2.0 - 1.0), lvl + 0.035, 'tie', ck, 0.0003)
    clampb = cbox(M, tdist, dy * cs, 0.0055, half + 0.003, 0.002)
    A = up(M, A, clampb, lvl + 0.04, 'gbox', ck, 0.0006)
    return A


# =================================================================================================== layout
def gated(M, A, g, salt, amount):
    on = M.b01(M.lt(hs(M, g, 11.0, salt), amount))
    return HC(A.h * on, A.c)


PARTS = ('frame', 'modules', 'pipes')


def layout_part(M, x, y, part, seed=0.0, modules_amt=0.58, pipes_amt=0.3, cables=0.75, rods_amt=0.38,
                beams_amt=0.72, n_cables=6, n_vcables=3):
    """One of PARTS (they combine exactly with max). Returns HC."""
    _S[0] = seed
    x = M.frac(x + M.floor(hs(M, 1.0, 2.0, 7) * 64.0) / 64.0)       # seed-driven offset (whole 1/64 steps) so
    y = M.frac(y + M.floor(hs(M, 3.0, 4.0, 7) * 64.0) / 64.0)       # stacked layers' grids don't line up
    if part == 'frame':
        A = comb(M, rods(M, x, y, rods_amt), beams(M, x, y, beams_amt))
        for g in range(n_cables):
            A = comb(M, A, gated(M, cable_h(M, x, y, float(g), float(n_cables), 91), float(g), 91, cables))
        for g in range(n_vcables):
            A = comb(M, A, gated(M, cable_v(M, x, y, float(g), float(n_vcables), 101), float(g), 101, cables))
        return A
    if part == 'modules':
        return modules(M, x, y, 1.0 - modules_amt)[0]
    A = pipes(M, x, y, 0, 12.0, 10.0, 71, pipes_amt)
    return comb(M, A, pipes(M, x, y, 1, 10.0, 12.0, 81, pipes_amt * 0.8))


def layout(M, x, y, seed=0.0, **kw):
    """Returns (height, class tag, alpha)."""
    A = None
    for p in PARTS:
        P = layout_part(M, x, y, p, seed, **kw)
        A = P if A is None else comb(M, A, P)
    alpha = M.b01(M.gt(A.h, 0.002))
    return A.h, A.c, alpha
