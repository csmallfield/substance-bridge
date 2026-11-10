"""numpy preview of cloth_layout: lit clay | tiled | colour guess.  python np_preview.py out.png [--w 1024] [--seed 0] [--style 0]"""
import argparse, time
import numpy as np
from PIL import Image
import npfunc as M
import cloth_layout as L

def lit(H, k):
    gy, gx = np.gradient(H)
    nz = 1 / np.sqrt((gx * k) ** 2 + (gy * k) ** 2 + 1)
    Lv = np.array([-0.5, -0.5, 0.71])
    return np.clip(0.2 + 0.85 * (-gx * k * nz * Lv[0] - gy * k * nz * Lv[1] + nz * Lv[2]), 0, 1)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('out'); ap.add_argument('--w', type=int, default=1024)
    ap.add_argument('--seed', type=float, default=0); ap.add_argument('--style', type=float, default=0)
    a = ap.parse_args()
    t = (np.arange(a.w, dtype=np.float64) + 0.5) / a.w
    x, y = np.meshgrid(t, t)
    t0 = time.time()
    H, PR, TH, WA = L.layout(M, x, y, a.seed, a.style)
    print('%.1fs h %.2f..%.2f' % (time.time() - t0, H.min(), H.max()))
    img = lit(H, a.w * 0.35)
    pal = np.array([[0.16, 0.25, 0.42], [0.2, 0.3, 0.48], [0.13, 0.21, 0.36]])
    base = pal[np.clip((PR * 3).astype(int), 0, 2)]
    col = base * (0.7 + 0.3 * WA[..., None]) + (1 - WA[..., None]) * 0.25
    col = col * (1 - TH[..., None]) + np.array([0.75, 0.5, 0.2]) * TH[..., None]
    col = np.clip(col * (0.35 + 0.9 * img[..., None]), 0, 1)
    tiled = np.tile(img, (2, 2))[::2, ::2]
    gap = np.full((a.w, 10, 3), 0.05)
    out = np.concatenate([np.dstack([img] * 3), gap, np.dstack([tiled] * 3), gap, col], 1)
    Image.fromarray((out * 255).astype(np.uint8)).save(a.out)
    Image.fromarray((col[:a.w // 3, :a.w // 3] * 255).astype(np.uint8)).resize((a.w * 2 // 3, a.w * 2 // 3), Image.LANCZOS).save(a.out.replace('.png', '_zoom.png'))
