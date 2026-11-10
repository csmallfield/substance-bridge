"""Concrete ribbons (square, tiles both ways) from reference.jpg; see ANALYSIS.md. x, y in 0..1, y down.
`M` is numpy or sbsfunc.

Joint chains: every chain runs down a column line, then S-bends one column to the LEFT (45 degrees, rounded corners),
runs down that line, bends left again, and so on. Line c is a joint from the moment a chain lands on it (from line c+1,
at Y[c+1] + P) until that chain leaves it (at Y[c]); for the rest of the tile line c is empty and the piece there is
two columns wide. One leaving bend per line per tile; the lengths L[c] are scaled so the bends close up over the tile.
Straight 45-degree cut joints (down-RIGHT) split strips into panels where both lines are joints.
Relief: each piece is a low flat ribbon along its left joint, a lit step face along the same joint shifted by (A, B),
then a high plane that leans back down to the right joint (a crisp step down, the dark joint line).
"""
import random

N = 6
P = 1.0 / N
A = 0.5 * P              # ribbon width beside a straight joint
B = 1.7 * P              # the step trails the joint by this much downward
RF = 0.1 * P             # fillet radius of the bends
STEP = 0.35 * P          # width of the lit step face
RISE, BASE = 0.25, 0.35
RIB = 0.08               # ribbon rise from joint to step
DROP = 0.06              # the high plane never leans below BASE + DROP (a small step down at the next joint)
LEAN = 0.6               # lean of the high plane, height per tile unit
JOINT = 0.0016
LMAX = 1.0 - 2.7 * P
J = 4                    # sum over lines of (P + L) = J (bends close up over the tile)
ID_SCALE = 8.0


def schedule(seed=0):
    rng = random.Random(seed)
    total = J - N * P
    while True:      # a line's whole run (2P + L) must fit inside the wrap window of chain(): L < 1 - 2.55 P
        w = [rng.uniform(0.3, 1.0) for _ in range(N)]
        L = [total * v / sum(w) for v in w]
        if max(L) < LMAX and min(L) > 0.25:
            break
    Y = [0.0] * N
    # Y[c] = Y[c+1] + P + L[c]  (the chain landing on c at Y[c+1] + P stays L[c], then leaves)
    y = rng.random()
    for c in range(N - 1, -1, -1):
        Y[c] = y % 1.0
        y = y + P + L[(c - 1) % N]
    return Y, L




def choose(M, var, vals):
    """vals[var] for the Variation parameter (a float Expr or number)."""
    out = M.c(vals[0])
    for n in range(1, len(vals)):
        out = M.sel(M.lt(M.fabs(var - float(n)), 0.5), vals[n], out)
    return out


def pick(M, idx, vals):
    """vals[idx mod N] for a per-pixel integer idx."""
    i = M.mod(idx, float(N))
    out = 0.0 * i + vals[0]
    for n in range(1, N):
        out = M.sel(M.lt(M.fabs(i - n), 0.5), vals[n], out)
    return out


def sramp(M, u):
    """0 -> 1 over u in 0..P at 45 degrees, rounded corners."""
    def r(t):
        return 0.5 * (t + M.fsqrt(t * t + RF * RF))
    return (r(u) - r(u - P)) / P


def dsramp(M, u):
    def d(t):
        return 0.5 * (1.0 + t / M.fsqrt(t * t + RF * RF))
    return (d(u) - d(u - P)) / P


def chain(M, T, c, y, back=0.0):
    """The chain occupying line c: x, dx/dy, and whether line c is a joint at y. With back > 0, where that same chain
    was `back` higher up (it may have been on line c+1 or bending from c+2).
    u = 0 where the chain starts its bend from line c+1 onto c; it leaves c at u = P + L[c]."""
    y1 = pick(M, c + 1.0, T['Y'])
    lc = pick(M, c, T['L'])
    l1 = pick(M, c + 1.0, T['L'])
    u = M.mod(y - y1 + 0.5 * P, 1.0) - 0.5 * P
    on = M.b01(M.gt(u, -0.05 * P)) * M.b01(M.lt(u, 2.0 * P + lc + 0.05 * P))
    u = u - back
    s = sramp(M, u) + sramp(M, u - P - lc) + sramp(M, u + P + l1) - 1.0
    ds = dsramp(M, u) + dsramp(M, u - P - lc) + dsramp(M, u + P + l1)
    return (c + 1.0 - s) * P, -ds * P, on


def tables(M, var):
    T = {}
    for key, idx in (('Y', 0), ('L', 1), ('CUT', 2), ('HAS', 3)):
        T[key] = [choose(M, var, [SCHED[v][idx][c] for v in range(VARIANTS)]) for c in range(N)]
    return T


def ribbons(M, x, y, var=0.0, joint=JOINT):
    """Returns (height, piece id 0..1, piece random, joint mask)."""
    T = tables(M, var)
    k = M.floor(x / P)
    BIG = 9.0
    best_l, best_dr, best_pid, best_r = None, None, None, None
    for dc in (-1.0, 0.0, 1.0, 2.0):
        c = k + dc
        gx, gd, on = chain(M, T, c, y)
        dl = (x - gx) / M.fsqrt(1.0 + gd * gd)
        g1, gd1, _ = chain(M, T, c, y, B)
        dr = (g1 + A - x) / M.fsqrt(1.0 + gd1 * gd1)
        valid = on * M.b01(M.gt(dl, -1e-4))
        dl_left = dl + (1.0 - valid) * BIG                 # distance to this joint if it is a joint left of x
        dl_right = M.fabs(dl) + on * 0.0
        jd_c = M.fabs(dl) + (1.0 - on) * BIG
        dr_right = -dl + (1.0 - on * M.b01(M.lt(dl, 1e-4))) * BIG   # distance to this joint if it is right of x
        if best_l is None:
            best_l, best_dr, best_pid, jd, right = dl_left, dr, c, jd_c, dr_right
        else:
            better = M.lt(dl_left, best_l - 1e-4)
            tie = M.b01(M.lt(M.fabs(dl_left - best_l), 1e-4))
            best_dr = M.sel(better, dr, best_dr + tie * M.fmax(dr - best_dr, 0.0))
            best_pid = M.sel(better, c, best_pid)
            best_l = M.fmin(best_l, dl_left)
            jd = M.fmin(jd, jd_c)
            right = M.fmin(right, dr_right)
    e = -best_dr
    t = M.fmin(M.fmax(e / STEP + 1.0, 0.0), 1.0)                     # step face ends exactly at the shifted joint
    rib = RIB * M.fmin(best_l / (best_l - e + STEP + 1e-4), 1.0)     # the ribbon rises gently toward the step
    past = M.fmax(e, 0.0)
    lean = M.fmin(past * LEAN, RISE - DROP)                         # the high plane leans back toward the right joint
    h = BASE + rib + (RISE - rib) * t * t - lean                     # soft cove at the foot, crisp top edge
    # straight cut joints, down-right from line c to line c+1, where both are joints
    for dc in (0.0,):
        c = k + dc
        y0 = pick(M, c, T['CUT'])
        has = pick(M, c, T['HAS'])
        xc = x - c * P
        yd = M.mod(y - y0 - xc + 0.5, 1.0) - 0.5
        jd = M.fmin(jd, M.fabs(yd) * 0.70710678 + (1.0 - has) * BIG)
    j = M.fmax(1.0 - jd / joint, 0.0)
    h = h - 0.03 * j * j
    pw = M.mod(best_pid, float(N))
    return h, (pw + 0.5) / N, M.hash2(pw, 41.0 + var, 7.0), j


def _cuts(Y, seed=1):
    """One cut per strip (line c to c+1) where line c is a joint at y0 and line c+1 at y0 + P."""
    rng = random.Random(seed)
    cuts, has = [], []
    for c in range(N):
        a0, a1 = Y[(c + 1) % N] + P, Y[c]                      # line c is straight between these
        b0, b1 = Y[(c + 2) % N] + P - P, Y[(c + 1) % N] - P    # y0 such that y0 + P is on line c+1's straight part
        best = None
        for _ in range(200):
            t = rng.random()
            okc = ((t - a0) % 1.0) < ((a1 - a0) % 1.0) - 0.3 * P and ((t - a0) % 1.0) > 0.3 * P
            okd = ((t - b0) % 1.0) < ((b1 - b0) % 1.0) - 0.3 * P and ((t - b0) % 1.0) > 0.3 * P
            if okc and okd:
                best = t
                break
        cuts.append(best if best is not None else 0.0)
        has.append(1.0 if best is not None else 0.0)
    return cuts, has




VARIANTS = 8
SCHED = []
for _v in range(VARIANTS):
    _Y, _L = schedule(_v * 7 + 1)
    _C, _H = _cuts(_Y, _v * 7 + 2)
    SCHED.append((_Y, _L, _C, _H))
