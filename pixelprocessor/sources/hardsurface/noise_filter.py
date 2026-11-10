"""Flag alphas with high-frequency NOISE (grit, cast or sand-blasted texture, noisy damage), not fine regular detail.
Per alpha at 1024: peaks = share of covered pixels that are tiny local maxima (3x3 max of a 0.5 px blur, standing
> 0.008 above a 1.5 px blur). Grit is a field of such peaks (0.08-0.17); regular grilles, ticks and grids stay under
~0.03 because their maxima are ridges, not points. noisy = peaks > 0.05, plus by hand: the DamageMetal and Stickers categories (weathered by design, their texture
sits below the threshold) and MANUAL_NOISY, minus MANUAL_CLEAN.
python noise_filter.py -> noise.json {file: {peaks, noisy}}, vol2/noise_flagged.png, vol2/noise_kept_band.png"""
import glob, json, os
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, maximum_filter
ROOTS = {'vol1': 'D:/07_resources/JRO/JRO_Alphas_HardSurface_Vol.1/JRO_HSAlphas_Vol01_Tiff/Tiff',
         'vol2': 'D:/07_resources/JRO/JRO_Alphas_HardSurface_Vol.2/JRO_HSAlphas_Vol02_Tiff/JRO_HSAlphas_Vol02_Tiff'}


NOISY_CATEGORIES = ('DamageMetal', 'Stickers')
MANUAL_NOISY = ('vol2/Tiling-Fillers/JRO_Tiling03_in.tif',)
MANUAL_CLEAN = ('vol2/UI&Panels/JRO_UI&Panels61.tif',)       # a fine grid: its crossings count as peaks


def load(f, n):
    im = Image.open(f)
    if im.mode not in ('I;16', 'I;16B', 'I'):
        im = im.convert('L')
    a = np.asarray(im.resize((n, n), Image.BILINEAR)).astype(np.float64)
    return a / (65535.0 if a.max() > 255 else 255.0)


def score(a):
    cov = a > 0.02
    if cov.sum() < 100:
        return 0.0
    b = gaussian_filter(a, 0.5)
    pk = (b == maximum_filter(b, 3)) & (b - gaussian_filter(b, 1.5) > 0.008) & cov
    return float(pk.sum() / cov.sum())


def lit(a):
    gy, gx = np.gradient(a)
    return np.clip((0.15 + 0.85 * np.clip(0.55 - (gx + gy) * 10, 0, 1)) * (0.55 + 0.45 * a), 0, 1)


def sheet(items, path):
    C, cols = 170, 10
    rows = max(1, (len(items) + cols - 1) // cols)
    S = Image.new('L', (cols * C, rows * (C + 14)), 30); d = ImageDraw.Draw(S)
    for i, (k, v) in enumerate(items):
        vol, rel = k.split('/', 1)
        a = load(os.path.join(ROOTS[vol], rel), C - 8)
        S.paste(Image.fromarray((lit(a) * 255).astype(np.uint8)), ((i % cols) * C + 4, (i // cols) * (C + 14) + 14))
        d.text(((i % cols) * C + 4, (i // cols) * (C + 14) + 1), '%.3f %s' % (v['peaks'], rel.split('/')[-1][4:-4][:16]), fill=255)
    S.save(path)


if __name__ == '__main__':
    out = {}
    for vol, root in ROOTS.items():
        for f in sorted(glob.glob(root + '/**/*.tif', recursive=True)):
            p = score(load(f, 1024))
            k = vol + '/' + os.path.relpath(f, root).replace(chr(92), '/')
            cat = k.split('/')[1]
            out[k] = dict(peaks=round(p, 4), noisy=bool((p > 0.05 or cat in NOISY_CATEGORIES or k in MANUAL_NOISY) and k not in MANUAL_CLEAN))
    json.dump(out, open('noise.json', 'w'), indent=0)
    flagged = sorted([kv for kv in out.items() if kv[1]['noisy']], key=lambda kv: kv[1]['peaks'])
    kept = sorted([kv for kv in out.items() if not kv[1]['noisy'] and kv[1]['peaks'] > 0.015], key=lambda kv: -kv[1]['peaks'])
    print('noisy', len(flagged), 'of', len(out), '| kept with fine detail', len(kept))
    sheet(flagged, 'vol2/noise_flagged.png'); sheet(kept, 'vol2/noise_kept_band.png')
