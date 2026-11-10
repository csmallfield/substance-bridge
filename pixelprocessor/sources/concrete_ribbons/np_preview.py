"""numpy preview of ribbon_layout: reference | lit clay | lit clay tiled 2x2.  python np_preview.py out.png [--w 1024] [--var 0]"""
import argparse, time
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
import npfunc as M
import ribbon_layout as L


def clay(H, k=160):
    gx = (np.roll(H, -1, 1) - np.roll(H, 1, 1)) * 0.5 * k
    gy = (np.roll(H, -1, 0) - np.roll(H, 1, 0)) * 0.5 * k
    nz = 1 / np.sqrt(gx * gx + gy * gy + 1)
    Lv = np.array([-0.55, -0.35, 0.75]); Lv /= np.linalg.norm(Lv)
    lam = np.clip(-gx * nz * Lv[0] - gy * nz * Lv[1] + nz * Lv[2], 0, 1)
    ao = np.ones_like(H)
    for s, kk in ((2, 1.0), (8, 0.6), (24, 0.3)):
        ao -= kk * np.clip(gaussian_filter(H, s, mode='wrap') - H, 0, None)
    return np.clip(0.75 * (0.25 + 0.8 * lam) * np.clip(ao, 0.2, 1), 0, 1)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('--w', type=int, default=1024); ap.add_argument('--var', type=float, default=0.0)
    a = ap.parse_args()
    w = a.w
    t = (np.arange(w, dtype=np.float32) + 0.5) / w
    x, y = np.meshgrid(t, t)
    t0 = time.time()
    H, T, R, Jm = L.ribbons(M, x, y, a.var)
    print('%.1fs h %.2f..%.2f' % (time.time() - t0, H.min(), H.max()))
    np.save('np_height.npy', H)
    img = clay(H * (w / 1024.0))
    ref = Image.open('reference.jpg').convert('L')
    ref = np.asarray(ref.resize((int(ref.width * w / ref.height), w))).astype(np.float32) / 255
    tiled = np.tile(img, (2, 2))[::2, ::2]
    gap = np.full((w, 12), 0.1, np.float32)
    out = np.concatenate([ref, gap, img, gap, tiled], 1)
    Image.fromarray((out * 255).astype(np.uint8)).save(a.out)
