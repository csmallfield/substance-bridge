"""numpy backend with the same names as sbsfunc, so layout code can be previewed without cooking."""
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
