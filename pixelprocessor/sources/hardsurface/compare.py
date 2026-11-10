"""Reference alpha | maths | maths at 64 px, lit the same way, with the horizontal centre cross-section of both drawn
under them (reference yellow, maths cyan). python compare.py [names...] -> compare.png"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
from pplib import npfunc as M, relief as R
import importlib; I = importlib.import_module(os.environ.get("ITEMS", "items"))

SRC = 'D:/07_resources/JRO/JRO_Alphas_HardSurface_Vol.1/JRO_HSAlphas_Vol01_Tiff/Tiff/'
N = 320


def lit(a, k):
    """Lambert shading from real normals (k = height scale in pixels). The old clipped slope shading saturated on
    round rims and made perfect circles look wobbly."""
    gy, gx = np.gradient(a * k * 4.0)
    n = np.dstack([-gx, -gy, np.ones_like(a)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    L = np.array([-0.5, -0.5, 0.707])
    return np.clip(0.12 + 0.88 * np.clip(n @ L, 0, 1), 0, 1)


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


names = sys.argv[1:] or list(I.ITEMS)
tiles = []
for name in names:
    fn, path, row = I.ITEMS[name]
    r, m, lo = ref(path, N), maths(fn, N), maths(fn, 64)
    lo = np.asarray(Image.fromarray(lo.astype(np.float32), "F").resize((N, N), Image.BICUBIC)).astype(float)
    k = 8.0
    t = Image.new('RGB', (3 * N + 20, N + 110), (25, 25, 25))
    for i, a in enumerate((r, m, lo)):
        t.paste(Image.fromarray((lit(a, k) * 255).astype(np.uint8)).convert('RGB'), (i * (N + 10), 18))
    d = ImageDraw.Draw(t)
    d.text((4, 3), '%s (%s)  reference | maths | maths at 64 px' % (name, os.path.basename(path)[4:-4]), fill=(255, 255, 255))
    yy = int((row * 0.5 + 0.5) * N)
    for i in (0, 1):
        d.line([(i * (N + 10), 18 + yy), (i * (N + 10) + N, 18 + yy)], fill=(255, 80, 80))
    for a, col in ((r, (255, 200, 60)), (m, (60, 220, 255))):
        d.line([(x * (2 * N + 10) / N, N + 100 - 80 * a[yy, x]) for x in range(N)], fill=col, width=2)
    tiles.append(t)
cols = 2
W = cols * (tiles[0].width + 10); H = ((len(tiles) + cols - 1) // cols) * (tiles[0].height + 8)
S = Image.new('RGB', (W, H), (10, 10, 10))
for i, t in enumerate(tiles):
    S.paste(t, ((i % cols) * (t.width + 10), (i // cols) * (t.height + 8)))
S.save(os.environ.get('OUT', 'compare.png')); print(S.size)
