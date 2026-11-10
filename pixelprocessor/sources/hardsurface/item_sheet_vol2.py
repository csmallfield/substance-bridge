"""All rebuilt hard-surface alphas in a 5 x 4 sheet: numpy (python icon_sheet.py out.png) or cooked (build.py icon_sheet.py)."""
import sys, os
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
PKG = 'item_sheet_vol2'
import items_vol2 as I
from pplib import decals as D, relief as R

NAMES = list(I.ITEMS)


def sheet(M, x, y, px, only=None):
    R.min_width(px * 9.0 * 1.5)
    i, j = M.floor(x * 5.0), M.floor(y * 4.0)
    lx, ly = (x * 5.0 - i) * 2.0 - 1.0, (y * 4.0 - j) * 2.0 - 1.0
    k = j * 5.0 + i
    out = None
    for n, name in enumerate(NAMES):
        if only is not None and n not in only:
            continue
        f = I.ITEMS[name][0](M, lx, ly, px * 10.0)
        w = M.b01(M.lt(M.fabs(k - n), 0.5))
        out = w * f if out is None else out + w * f
    return out

if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1].endswith('.png'):
    import numpy as np
    from PIL import Image
    from pplib import npfunc as M
    n = 1024
    t = (np.arange(n) + 0.5) / n
    x, y = np.meshgrid(t, t)
    np.save('sheet_np.npy', sheet(M, x, y, 1.0 / n)); print('numpy ok')
else:
    from sbsgen import Package, B, GRAY, get
    from sbsops import Ops
    import sbsfunc as M
    pkg = Package(PKG); g = pkg.graph(PKG, PKG); op = Ops(g)
    x, y = M.pos()
    size = M.swz(get('$size', 512), 0)
    # one Pixel Processor per group of items (<= ~8k function nodes each: ~19k in one rendered solid white)
    groups, cur, cnt = [], [], 0
    for n, name in enumerate(NAMES):
        k = len(I.ITEMS[name][0](M, x, y, 0.01).nodes([]))
        if cur and cnt + k > 8000:
            groups.append(cur); cur, cnt = [], 0
        cur.append(n); cnt += k
    groups.append(cur)
    total = None
    for grp in groups:
        e = M.clamp(sheet(M, x, y, 1.0 / size, only=grp))
        pp = g.filter('pixelprocessor', out=GRAY, fmt=3, colorswitch=B(False), perpixel=e)
        total = pp if total is None else op.blend(pp, total, op.ADD, fmt=3)
    g.output('height', 'Height', 'height', op.lv(total, fmt=True), gray=True)
    op.finish(pkg, __file__, globals())
