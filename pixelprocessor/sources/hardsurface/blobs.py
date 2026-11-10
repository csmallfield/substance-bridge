"""Blob centroids above a threshold (optionally relative to the local surround): python blobs.py item thr [rel]"""
import sys
import numpy as np
import inspect_item as T
from scipy import ndimage
name, thr = sys.argv[1], float(sys.argv[2]); rel = len(sys.argv) > 3
fn, p, _ = T.find(name); a = T.ref(p, 2048)
m = (a - ndimage.uniform_filter(a, 61) > thr) if rel else (a > thr)
lab, n = ndimage.label(m)
t = lambda i: (i + 0.5) / 1024 - 1
out = []
for c, A, mx in zip(ndimage.center_of_mass(m, lab, range(1, n + 1)), ndimage.sum(m, lab, range(1, n + 1)),
                    ndimage.maximum(a, lab, range(1, n + 1))):
    if A > 150: out.append((round(t(c[1]), 3), round(t(c[0]), 3), round(float(np.sqrt(A / np.pi) / 1024), 4), round(float(mx), 2)))
print(len(out)); print(out)
