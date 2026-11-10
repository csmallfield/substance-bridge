"""Sewn Cloth layout: woven fabric panels sewn together with seams from pplib.seams (skill scripts). All maths, no bitmaps.

  - Panels: ROWS strips across the tile (row boundaries hashed but fixed per seed), each strip split into 1-3 pieces.
    Some pieces have the weave turned 90 degrees.
  - Weave: plain (1/1) or 3/1 warp-faced twill, warp and weft as round threads going over and under (warp mask for colouring).
  - Seams on every panel boundary in one STYLE (workwear double topstitch, overlock zigzag, hand-repair ladder,
    decorative herringbone), each with a plain V seam under it; fabric puckers into small wrinkles along each seam.
  - Tiles both ways (rows wrap, row splits wrap, the weave count divides the tile).
`M` is numpy (npfunc) or sbsfunc. Returns (height in about -0.4..0.4, panel tag, thread mask, warp mask).
"""
import os, sys
sys.path.insert(0, os.environ.get('SBS_SCRIPTS', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')))
from pplib import seams as S
from pplib.weave import weave

ROWS = 3
STYLES = ['workwear', 'overlock', 'hand_repair', 'decorative']
_S = [0.0]


def hs(M, a, b, salt):
    return M.hash2(a, b, salt + _S[0] * 0.618)


def cl(M, x, lo=0.0, hi=1.0): return M.fmin(M.fmax(x, lo), hi)


SEAM_FN = {'workwear': S.running_double, 'overlock': S.zigzag, 'hand_repair': S.ladder, 'decorative': S.herringbone}
SEAM_P = {'workwear': 1 / 7.04, 'overlock': 2 / 14.08, 'hand_repair': 1 / 6.94, 'decorative': 1 / 7.94}


def seam_height(M, u, v, style, scale):
    """Seam of one style at seam-space (u, v): base V seam + the style's stitches. Scale s maps brush units to tile."""
    fn = SEAM_FN[style]
    return fn(M, u / scale, v / scale, SEAM_P[style])


def layout(M, x, y, seed=0.0, style=0.0, F=176.0, twill=1.0, seam_scale=0.28, pucker=1.0, rotate=0.4, weave_depth=1.0):
    """style: an index into STYLES (float or Expr). Returns (height, panel random, thread mask, warp mask)."""
    _S[0] = seed
    # rows: boundaries at hashed positions, fixed count so the tile wraps
    bounds = []
    acc = 0.0
    ws = [0.7 + 0.6 * hs(M, float(k), 0.0, 11.0) for k in range(ROWS)]
    tot = ws[0]
    for w_ in ws[1:]:
        tot = tot + w_
    for k in range(ROWS):
        bounds.append(acc)
        acc = acc + ws[k] / tot
    # which row is this pixel in, and the nearest row boundary (signed distance)
    row = M.c(0.0) if hasattr(M, 'c') else 0.0
    for k in range(1, ROWS):
        row = row + M.b01(M.gt(y, bounds[k]))
    du_row = None
    for k in range(ROWS + 1):
        b = bounds[k] if k < ROWS else bounds[0] + 1.0
        d = y - b
        du_row = d if du_row is None else M.sel(M.lt(M.fabs(d), M.fabs(du_row)), d, du_row)
    # splits inside the row: 1-3 pieces, cut positions hashed per row; distance to the nearest cut (wrapping in x)
    nsp = 1.0 + M.floor(hs(M, row, 1.0, 12.0) * 2.999)
    off = hs(M, row, 2.0, 13.0)
    cell = x * nsp + off
    piece = M.mod(M.floor(cell), nsp)
    du_split = (M.frac(cell + 0.5) - 0.5) / nsp
    has_split = M.b01(M.gt(nsp, 1.5))
    panel = row * 4.0 + piece
    pr = hs(M, panel, 3.0, 14.0)
    swap = M.b01(M.lt(hs(M, panel, 4.0, 15.0), rotate))

    # weave
    wh, warp = weave(M, x, y, F, twill, swap)

    # seams: one style, chosen by index
    use_split = has_split * M.b01(M.lt(M.fabs(du_split), M.fabs(du_row)))
    u = M.sel(M.gt(use_split, 0.5), du_split, du_row)
    v = M.sel(M.gt(use_split, 0.5), y, x)
    sh = None
    th = None
    for i, st in enumerate(STYLES):
        S.take_threads()
        hh = seam_height(M, u, v, st, seam_scale)
        tt = S.take_threads()
        w_ = M.b01(M.lt(M.fabs(style - float(i)), 0.5))
        sh = w_ * hh if sh is None else sh + w_ * hh
        th = w_ * tt if th is None else th + w_ * tt
    # seam allowance pressed to one side: a soft step, and puckers along the seam fading away from it
    side = M.sel(M.gt(hs(M, panel, 5.0, 16.0), 0.5), 1.0, -1.0)
    allowance = 0.05 * S.ss(M, (0.06 - M.fabs(u) / seam_scale) / 0.04) * S.ss(M, (u * side) / (0.01 * seam_scale) + 0.5)
    ph = hs(M, M.floor(v * 23.0), panel, 17.0) * 6.283
    fade = cl(M, 1.0 - M.fabs(u) / (0.16 * seam_scale * 3.0))
    puck = pucker * 0.09 * M.fsin(v * 75.0 + ph * 0.3) * fade * fade * cl(M, M.fabs(u) / (0.03 * seam_scale * 3.0))
    # fabric dips under the stitches: weave amplitude falls off in the seam groove
    weave_amp = 0.028 * weave_depth * (0.55 + 0.45 * cl(M, M.fabs(u) / (0.05 * seam_scale * 3.0)))
    h = sh + allowance + puck + (wh - 0.5) * weave_amp * 2.0
    return h, pr, th, warp
