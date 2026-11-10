"""Fit lathe() knots to the angular-median radial profile of round references -> lathe_knots.py (data used by
items.py / items_vol2.py). python fit_lathe.py"""
import importlib, sys
import numpy as np
from PIL import Image
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
from pplib import relief as R
SRC = 'D:/07_resources/JRO/JRO_Alphas_HardSurface_Vol.1/JRO_HSAlphas_Vol01_Tiff/Tiff/'
ROUND = ['base14', 'bolt01', 'bolt04', 'bolt12', 'window03', 'armor06', 'disk06', 'ui21', 'vent68',
         'a21', 'a22', 'a24', 'a25', 'a39', 'a40', 'a82', 'a89', 'a98', 'a15']
N, NB = 1024, 500
LOW_Q = ('a39',)          # segments cover most angles: fit the base from a low percentile (the gaps)


CENTRES = {'bolt04': (0.008, -0.01)}     # measured centres of off-centre references


def median_profile(a, q=50, c=(0.0, 0.0)):
    t = (np.arange(N) + 0.5) / N * 2 - 1
    x, y = np.meshgrid(t, t)
    x, y = x - c[0], y - c[1]
    r = np.sqrt(x * x + y * y)
    b = np.clip((r * NB).astype(int), 0, NB * 2)
    out = np.zeros(NB)
    flat_b, flat_a = b.ravel(), a.ravel()
    order = np.argsort(flat_b, kind='stable')
    sb, sa = flat_b[order], flat_a[order]
    edges = np.searchsorted(sb, np.arange(NB + 1))
    for i in range(NB):
        seg = sa[edges[i]:edges[i + 1]]
        out[i] = np.percentile(seg, q) if len(seg) else (out[i - 1] if i else 0.0)
    return out


lines = ['"""Lathe knots fitted by fit_lathe.py from the angular-median radial profile of each reference (data)."""', 'KNOTS = {']
for name in ROUND:
    for mod in ('items', 'items_vol2', 'items_vol3'):
        m = importlib.import_module(mod)
        if name in m.ITEMS:
            path = m.ITEMS[name][1]
    im = Image.open(SRC + path)
    a = np.asarray(im.resize((N, N), Image.BILINEAR)).astype(float)
    a = a[..., 0] if a.ndim == 3 else a
    a /= 65535.0 if a.max() > 255 else 255.0
    # bolts: the raised drive covers most angles near the centre, so take a low percentile to see the dish under it
    prof = median_profile(a, 15 if name.startswith('bolt') else (16 if name in LOW_Q else 50), CENTRES.get(name, (0.0, 0.0)))
    if name.startswith('bolt'):
        prof[:int(0.16 * NB)] = prof[int(0.16 * NB)]     # the drive covers every angle at the very centre
    k = R.fit_lathe(prof, rmax=1.0, tol=0.012)
    print(name, len(k), 'knots')
    lines.append('    %r: %r,' % (name, k))
lines.append('}')
open('lathe_knots.py', 'w').write('\n'.join(lines) + '\n')
