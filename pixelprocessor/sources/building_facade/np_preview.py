"""Numpy preview of facade layouts: class colours | lit height, for several arrangement presets.
python np_preview.py out.png"""
import sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, 'C:/Users/smallfch/.claude/skills/substance-graph-authoring/scripts')
from pplib import npfunc as M
import facade_layout as L

PAL = np.array([[0.75, 0.72, 0.66], [0.4, 0.38, 0.35], [0.85, 0.83, 0.78], [0.8, 0.78, 0.74], [0.25, 0.25, 0.27],
                [0.18, 0.3, 0.38], [0.1, 0.14, 0.18], [0.5, 0.5, 0.52], [0.9, 0.88, 0.84]])
LOOKS = {
    'ground: shops + doors': dict(groups=3, floors=5, ground_on=1, g_height=1.6, g_bays=6, g_doors=0.35, g_windows=0.6,
        ac=0.3, material=0),
    'ground: door clusters, solid': dict(groups=1, floors=4, a_bays=6, a_w=0.55, a_h=0.6, a_mull=0, a_transom=0.55,
        material=2, ground_on=1, g_height=1.3, g_bays=6, g_cluster=2, g_mix=0.0, g_doors=0.5, g_windows=0.4,
        g_glazed=0.0, g_door_w=0.35, g_win_w=0.55, g_win_h=0.6, g_win_top=0.15, g_mull=0, g_pier=0.0, ac=0.35,
        ac_pos=0),
    'ground: podium, few doors': dict(groups=3, pattern=2, floors=8, ground_on=1, g_height=2.0, g_bays=4, g_doors=0.25,
        g_windows=0.75, g_double=1.0, g_glazed=1.0, g_door_w=0.45, g_win_w=0.9, g_win_h=0.85, g_mull=3,
        g_pier=0.3, material=4, b_bays=4, b_w=1.0, b_h=1.0, b_top=0.0, b_mull=2),
    'AC below windows (ref 0)': dict(groups=1, floors=10, a_bays=12, a_w=0.6, a_h=0.4, a_top=0.25, a_mull=1,
        material=3, ac=0.45, ac_pos=1, band=0.0),
}


def render(P, n=512):
    p = dict(L.DEFAULTS); p.update(P)
    p = {k: float(v) for k, v in p.items()}
    t = (np.arange(n) + 0.5) / n
    x, y = np.meshgrid(t, t)
    h, c, r, a, wv, st, op_, wk, gf = L.facade(M, x, y, p)
    return h, c.astype(int), r


def lit(h):
    gy, gx = np.gradient(h * h.shape[0] * 0.6)
    nn = np.dstack([-gx, -gy, np.ones_like(h)]); nn /= np.linalg.norm(nn, axis=2, keepdims=True)
    return np.clip(0.15 + 0.85 * (nn @ np.array([-0.5, -0.6, 0.62])), 0, 1)


if __name__ == '__main__':
    rows = []
    for name, P in LOOKS.items():
        h, c, r = render(P)
        col = PAL[np.clip(c, 0, len(PAL) - 1)] * (0.85 + 0.3 * r[..., None])
        tile = np.hstack([col, np.dstack([lit(h)] * 3), np.dstack([np.tile(lit(h), (1, 1))] * 3)[:, :0]])
        im = Image.fromarray((np.clip(tile, 0, 1) * 255).astype(np.uint8)); ImageDraw.Draw(im).text((4, 4), name, fill=(255, 0, 0))
        rows.append(np.asarray(im))
    a = np.vstack([np.hstack(rows[i:i + 2]) for i in range(0, len(rows), 2)])
    Image.fromarray(a).save(sys.argv[1] if len(sys.argv) > 1 else 'preview.png')


def interior_preview(out='interiors.png', n=512):
    p = dict(L.DEFAULTS); p.update(LOOKS['grouped (img 2)']); p = {k: float(v) for k, v in p.items()}
    q = {k: float(v) for k, v in L.IDEFAULTS.items()}
    t = (np.arange(n) + 0.5) / n; x, y = np.meshgrid(t, t)
    h, c, r, a, wv, st, op_, wk, gf = L.facade(M, x, y, p)
    c = c.astype(int)
    ir, ig, ib, gl = L.interior(M, r, a, wv, q)
    glass = (c == L.CID['glass'])[..., None]
    col = PAL[np.clip(c, 0, len(PAL) - 1)]
    img = np.where(glass, np.clip(np.dstack([ir, ig, ib]), 0, 1) * 0.85 + 0.05, col)
    Image.fromarray((img * 255).astype(np.uint8)).save(out)
