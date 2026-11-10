"""pplib.weave: woven threads (from sewn_cloth).

weave(M, x, y, F, twill, swap) -> (height 0..1, warp mask). F threads per tile (a whole number keeps it tiling;
aim for 10+ px per thread at the render size). twill: 0 plain 1/1, 1 warp-faced 3/1 twill (denim; warp covers
~68 %); swap 1 turns the weave 90 degrees (float or Expr). Warp and weft are round threads (sin profiles) that
rise where they pass over and sink where they pass under.
"""


def weave(M, x, y, F, twill=1.0, swap=0.0):
    X = swap * y + (1.0 - swap) * x
    Y = swap * x + (1.0 - swap) * y
    gx, gy = X * F, Y * F
    ix, iy = M.floor(gx), M.floor(gy)
    fx, fy = gx - ix - 0.5, gy - iy - 0.5
    plain_over = M.mod(ix + iy, 2.0)
    twill_over = M.b01(M.lt(M.mod(ix + iy, 4.0), 3.0))
    over = twill * twill_over + (1.0 - twill) * plain_over
    sg = over * 2.0 - 1.0
    across_x = M.fsin((0.5 - M.fabs(fx)) * 3.14159)
    across_y = M.fsin((0.5 - M.fabs(fy)) * 3.14159)
    warp = M.fsqrt(across_y) * (0.62 + 0.38 * sg * across_x)
    weft = M.fsqrt(across_x) * (0.62 - 0.38 * sg * across_y)
    return M.fmax(warp, weft), M.b01(M.gt(warp, weft))
