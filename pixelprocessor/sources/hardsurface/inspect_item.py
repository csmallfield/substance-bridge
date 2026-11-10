"""Careful per-item check: reference height | maths height | reference lit | maths lit | signed difference
(red = maths too high, blue = maths too low), with horizontal and vertical cross-sections through chosen rows and
columns. Prints the mean |error| and the share of pixels where depth is inverted (one raised, the other sunk
relative to the local surround).
python inspect_item.py <item> [row] [col]   (row and col in -1..1, default 0)   -> inspect/<item>.png"""
import importlib, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
from pplib import npfunc as M, relief as R
SRC = 'D:/07_resources/JRO/JRO_Alphas_HardSurface_Vol.1/JRO_HSAlphas_Vol01_Tiff/Tiff/'
N = 512
HERE = os.path.dirname(os.path.abspath(__file__))


def find(name):
    for mod in ('items', 'items_vol2', 'items_vol3'):
        m = importlib.import_module(mod)
        if name in m.ITEMS:
            return m.ITEMS[name]
    raise KeyError(name)


def ref(path, n):
    im = Image.open(SRC + path)
    a = np.asarray(im.resize((n, n), Image.BILINEAR)).astype(np.float64)
    a = a[..., 0] if a.ndim == 3 else a
    return a / (65535.0 if a.max() > 255 else 255.0)


def maths(fn, n):
    R.min_width(3.0 / n)
    t = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(t, t)
    return np.clip(fn(M, x, y, 2.0 / n), 0, 1)


def lit(a, k=6.0):
    gy, gx = np.gradient(a * k * a.shape[0] / 64.0)
    nrm = np.dstack([-gx, -gy, np.ones_like(a)]); nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    return np.clip(0.12 + 0.88 * np.clip(nrm @ np.array([-0.5, -0.5, 0.707]), 0, 1), 0, 1)


def stats(r, m):
    err = float(np.abs(r - m).mean())
    lr, lm = r - gaussian_filter(r, 12), m - gaussian_filter(m, 12)
    sig = (np.abs(lr) > 0.03) | (np.abs(lm) > 0.03)
    inv = float(((np.sign(lr) != np.sign(lm)) & (np.abs(lr) > 0.03) & (np.abs(lm) > 0.03)).sum() / max(sig.sum(), 1))
    return err, inv


def render(name, row=0.0, col=0.0, out=None):
    fn, path, _ = find(name)
    r, m = ref(path, N), maths(fn, N)
    err, inv = stats(r, m)
    d = m - r
    dimg = np.dstack([np.clip(d * 4, 0, 1), np.zeros_like(d), np.clip(-d * 4, 0, 1)]) + 0.15
    tiles = [np.dstack([r] * 3), np.dstack([m] * 3), np.dstack([lit(r)] * 3), np.dstack([lit(m)] * 3), np.clip(dimg, 0, 1)]
    W = 5 * N + 40
    S = Image.new('RGB', (W, N + 260), (18, 18, 18))
    for i, t in enumerate(tiles):
        S.paste(Image.fromarray((t * 255).astype(np.uint8)), (i * (N + 10), 20))
    dr = ImageDraw.Draw(S)
    dr.text((4, 3), '%s (%s)   ref height | maths height | ref lit | maths lit | diff (red maths high, blue low)   '
                    'mean|err| %.3f  inverted %.0f%%' % (name, os.path.basename(path), err, inv * 100), fill=(255, 255, 255))
    ri, ci = int((row * 0.5 + 0.5) * N), int((col * 0.5 + 0.5) * N)
    for i in range(5):
        dr.line([(i * (N + 10), 20 + ri), (i * (N + 10) + N, 20 + ri)], fill=(255, 60, 60))
        dr.line([(i * (N + 10) + ci, 20), (i * (N + 10) + ci, 20 + N)], fill=(60, 255, 60))
    for k, (pr, pm, lab) in enumerate(((r[ri], m[ri], 'row (red line)'), (r[:, ci], m[:, ci], 'column (green line)'))):
        x0, y0, w, h = k * (W // 2), N + 30, W // 2 - 20, 220
        dr.text((x0 + 4, y0), lab + ': yellow ref, cyan maths', fill=(200, 200, 200))
        for p, colr in ((pr, (255, 200, 60)), (pm, (60, 220, 255))):
            dr.line([(x0 + i * w / N, y0 + h - 200 * v) for i, v in enumerate(p)], fill=colr, width=2)
    os.makedirs(os.path.join(HERE, 'inspect'), exist_ok=True)
    S.save(out or os.path.join(HERE, 'inspect', name + '.png'))
    return err, inv


if __name__ == '__main__':
    name = sys.argv[1]
    row = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    col = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    e, i = render(name, row, col)
    print('%s  mean|err| %.4f  inverted %.1f%%' % (name, e, i * 100))
