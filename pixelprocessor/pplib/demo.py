"""pplib demo: one test pattern using every module, previewed in numpy (python demo.py out.png) and buildable as a
Pixel Processor graph (python ../build.py demo.py --size 10 cooks demo.sbs: the same function in Substance)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from pplib import shapes as Sh, seams as Se, weave as W, curves as C


def pattern(M, x, y, seed=0.0):
    K = Sh.Classes(['bg', 'plate', 'hex', 'pipe', 'seam', 'cloth'], 16.0)
    A = Sh.HC(M.c(0.1) if hasattr(M, 'c') else 0.1, K.tag('bg'))
    # left half: slot plates with chamfered slabs and a hex inlay
    s = Sh.superblock_slots(M, x, y, 4.0, seed)
    d = Sh.cbox(M, s['u'], s['v'], s['a'] - 0.006, s['b'] - 0.006, 0.02)
    A = Sh.slab(M, A, M.fmin(d, 0.5 - x), 0.45, K.tag('plate', Sh.hashk(M, s['id'], 0.0, 3.0, seed)))
    du, dv, i, j = Sh.hex_cell(M, x, y, 14, 16)
    A = Sh.over(M, A, M.fmin(Sh.hexagon(M, du, dv, 0.022), M.fmin(d - 0.03, 0.5 - x)), 0.36, K.tag('hex'))
    # right half top: a pipe that S-bends (soft ramps), with a flange ring
    yc = 0.25 + 0.12 * C.soft_ramp(M, x - 0.62, 0.12, 0.03)
    dist = M.fabs(y - yc)
    A = Sh.cylinder(M, A, M.sel(M.gt(x, 0.5), dist, 1.0), 0.03, 0.5, 0.18, K.tag('pipe'))
    # right half middle: two seams
    for k, (fn, P) in enumerate(((Se.herringbone, 1 / 7.94), (Se.clip_seam, 1 / 3.98))):
        u = y - (0.55 + 0.15 * k)
        h = fn(M, u / 0.25, x / 0.25, P) * 0.25 + 0.3
        on = M.b01(M.gt(x, 0.5)) * M.b01(M.lt(M.fabs(u), 0.06))
        A = Sh.HC(A.h + (h - A.h) * on, M.sel(M.gt(on, 0.5), K.tag('seam'), A.c))
    # bottom right: weave
    wh, warp = W.weave(M, x, y, 128.0, 1.0, 0.0)
    on = M.b01(M.gt(x, 0.5)) * M.b01(M.gt(y, 0.86))
    A = Sh.HC(A.h + (0.3 + 0.03 * wh - A.h) * on, M.sel(M.gt(on, 0.5), K.tag('cloth', warp), A.c))
    return A.h, A.c


if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1].endswith('.png'):
    import numpy as np
    from PIL import Image
    from pplib import npfunc as M
    n = 1024
    t = (np.arange(n) + 0.5) / n
    x, y = np.meshgrid(t, t)
    H, Cc = pattern(M, x, y)
    gy, gx = np.gradient(H)
    lam = np.clip(0.55 - (gx + gy) * n * 0.6, 0, 1)
    Image.fromarray((np.clip(0.15 + 0.85 * lam, 0, 1) * 255).astype(np.uint8)).save(sys.argv[1])
    print('numpy ok', H.min(), H.max())
else:
    from sbsgen import Package, B, COLOR, GRAY
    from sbsops import Ops
    import sbsfunc as M
    pkg = Package('pplib_demo')
    g = pkg.graph('pplib_demo', 'pplib demo')
    op = Ops(g)
    x, y = M.pos()
    h, c = pattern(M, x, y)
    pp = g.filter('pixelprocessor', out=GRAY, fmt=3, colorswitch=B(False), perpixel=M.clamp(h))
    g.output('height', 'Height', 'height', op.lv(pp, fmt=True), gray=True)
    op.finish(pkg, __file__, globals())
