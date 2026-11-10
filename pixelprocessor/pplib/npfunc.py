"""pplib.npfunc: numpy backend with the same names as sbsfunc, so layout code previews without cooking.
SAMPLERS[k] = a float image stands in for Pixel Processor input k (sample_gray)."""
import numpy as np

def c(x): return np.float32(x)
def floor(x): return np.floor(x)
def fabs(x): return np.abs(x)
def frac(x): return x - np.floor(x)
def fmax(*xs):
    a = xs[0]
    for x in xs[1:]: a = np.maximum(a, x)
    return a
def fmin(*xs):
    a = xs[0]
    for x in xs[1:]: a = np.minimum(a, x)
    return a
def gt(a, b): return np.greater(a, b)
def lt(a, b): return np.less(a, b)
def sel(cnd, a, b): return np.where(cnd, a, b)
def b01(cnd): return np.where(cnd, 1.0, 0.0)
def hash2(a, b, k=0.0):
    return frac(np.sin(np.float32(a) * 12.9898 + np.float32(b) * 78.233 + k * 37.719) * 43758.5453)
def grid(n):
    t = (np.arange(n) + 0.5) / n
    return np.meshgrid(t, t)
def fsqrt(x): return np.sqrt(np.maximum(x, 0.0))
def mod(a, b): return a - np.floor(a / b) * b
def fsin(x): return np.sin(x)
def clamp(x, lo=0.0, hi=1.0): return np.clip(x, lo, hi)
def octn(a, b): return np.maximum(np.maximum(a, b), (a + b) * 0.70710678)


SAMPLERS = []


def sample_gray(index, x, y, filtering=0):
    """Bilinear sample of SAMPLERS[index] at (x, y) in 0..1 (stand-in for sbsfunc.sample_gray)."""
    img = SAMPLERS[int(index)]
    h, w = img.shape[:2]
    fx = np.clip(x * w - 0.5, 0, w - 1.001); fy = np.clip(y * h - 0.5, 0, h - 1.001)
    x0 = np.floor(fx).astype(np.int64); y0 = np.floor(fy).astype(np.int64)
    tx, ty = fx - x0, fy - y0
    a = img[y0, x0] * (1 - tx) + img[y0, x0 + 1] * tx
    b = img[y0 + 1, x0] * (1 - tx) + img[y0 + 1, x0 + 1] * tx
    return a * (1 - ty) + b * ty
