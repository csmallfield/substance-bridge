"""Radial profiles (height vs radius, averaged over all angles) of round references against the maths version.
python radial.py name ... -> radial.png and a printed table of ring peaks/steps."""
import os, sys, importlib
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
from pplib import npfunc as M, relief as R
SRC = 'D:/07_resources/JRO/JRO_Alphas_HardSurface_Vol.1/JRO_HSAlphas_Vol01_Tiff/Tiff/'
N = 1024


def radial(a, nb=400):
    t = (np.arange(N) + 0.5) / N * 2 - 1
    x, y = np.meshgrid(t, t)
    r = np.sqrt(x * x + y * y).ravel()
    b = np.clip((r * nb).astype(int), 0, nb * 2)
    s = np.bincount(b, a.ravel(), nb * 2 + 1); c = np.bincount(b, None, nb * 2 + 1)
    return (s / np.maximum(c, 1))[:nb]


def lookup(name):
    for mod in ('items', 'items_vol2'):
        m = importlib.import_module(mod)
        if name in m.ITEMS:
            return m.ITEMS[name]


if __name__ == '__main__':
    W, Hh = 800, 180
    S = Image.new('RGB', (W, Hh * len(sys.argv[1:])), (20, 20, 20)); d = ImageDraw.Draw(S)
    for k, name in enumerate(sys.argv[1:]):
        fn, path, _ = lookup(name)
        ref = np.asarray(Image.open(SRC + path).resize((N, N), Image.BILINEAR)).astype(float) / 65535
        R.min_width(3.0 / N)
        t = (np.arange(N) + 0.5) / N * 2 - 1; x, y = np.meshgrid(t, t)
        mth = np.clip(fn(M, x, y, 2.0 / N), 0, 1)
        pr, pm = radial(ref), radial(mth)
        y0 = k * Hh
        d.text((4, y0 + 2), name + '  (x: radius 0..1, yellow ref, cyan maths)', fill=(255, 255, 255))
        for p, col in ((pr, (255, 200, 60)), (pm, (60, 220, 255))):
            d.line([(i * W / len(p), y0 + Hh - 10 - 150 * v) for i, v in enumerate(p)], fill=col, width=2)
        np.save('radial_%s.npy' % name, pr)
    S.save('radial.png')
