"""numpy preview of techno_layout.

python np_preview.py out.png [--w 1024] [--seed 0]   -> lit clay over a checker | 2x2 tiled | class colours
python np_preview.py out.png --stack 5               -> 5 seeds stacked back to front (deeper = darker), plus alpha
"""
import argparse, time
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
import npfunc as M
import techno_layout as L


def clay(H, k=420):
    gx = (np.roll(H, -1, 1) - np.roll(H, 1, 1)) * 0.5 * k
    gy = (np.roll(H, -1, 0) - np.roll(H, 1, 0)) * 0.5 * k
    nz = 1 / np.sqrt(gx * gx + gy * gy + 1)
    Lv = np.array([-0.55, -0.45, 0.70]); Lv /= np.linalg.norm(Lv)
    lam = np.clip(-gx * nz * Lv[0] - gy * nz * Lv[1] + nz * Lv[2], 0, 1)
    ao = np.ones_like(H)
    for s, kk in ((1.5, 1.6), (5, 0.9), (16, 0.4)):
        ao -= kk * np.clip(gaussian_filter(H, s, mode='wrap') - H, 0, None)
    return np.clip((0.18 + 0.85 * lam) * np.clip(ao, 0.25, 1) * (0.55 + 0.6 * H), 0, 1)


def run(w, seed):
    t = (np.arange(w, dtype=np.float32) + 0.5) / w
    x, y = np.meshgrid(t, t)
    return L.layout(M, x, y, seed)


def checker(w, n=32):
    i = (np.arange(w) * n // w)
    c = ((i[None, :] + i[:, None]) % 2) * 0.06 + 0.16
    return c.astype(np.float32)


def class_rgb(C, A):
    ids = np.floor(C * L.ID_SCALE).astype(int)
    rng = np.random.default_rng(3)
    pal = rng.uniform(0.25, 1.0, (40, 3)); pal[0] = 0
    rgb = pal[np.clip(ids, 0, 39)]
    return rgb * A[..., None]


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('--w', type=int, default=1024); ap.add_argument('--seed', type=float, default=0.0)
    ap.add_argument('--stack', type=int, default=0)
    a = ap.parse_args()
    w = a.w
    t0 = time.time()
    if a.stack:
        out = np.full((w, w, 3), 0.02, np.float32)
        for i in range(a.stack):
            H, C, A = run(w, a.seed + i * 17)
            lum = clay(H * (w / 1024.0)) * (0.3 + 0.7 * (i + 1) / a.stack)
            sh = gaussian_filter(A, 6, mode='wrap')                       # soft contact shadow on the layers behind
            out *= (1 - 0.45 * sh)[..., None]
            out = out * (1 - A[..., None]) + (lum[..., None] * np.array([1.0, 0.97, 0.92])) * A[..., None]
        img = np.clip(out, 0, 1)
        Image.fromarray((img * 255).astype(np.uint8)).save(a.out)
        print('%.1fs stack' % (time.time() - t0))
    else:
        H, C, A = run(w, a.seed)
        print('%.1fs h %.2f..%.2f coverage %.2f' % (time.time() - t0, H.min(), H.max(), A.mean()))
        lum = clay(H * (w / 1024.0))
        bg = checker(w)
        img = lum * A + bg * (1 - A)
        tiled = np.tile(img, (2, 2))[::2, ::2]
        ids = class_rgb(C, A).mean(-1) * 0 + 0                            # placeholder width
        rgb = np.stack([img] * 3, -1)
        gap = np.full((w, 12, 3), 0.05, np.float32)
        out = np.concatenate([rgb, gap, np.stack([tiled] * 3, -1), gap, class_rgb(C, A)], 1)
        Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(a.out)
        np.save('np_height.npy', H)
