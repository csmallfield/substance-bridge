"""Print a reference's height along a row or column at fine steps, plus detected peaks and plateau levels, so
profiles can be measured instead of eyeballed. python profile_points.py <item> row|col <pos> [from] [to]"""
import sys
import numpy as np
from scipy.signal import find_peaks
import inspect_item as T
name, axis, pos = sys.argv[1], sys.argv[2], float(sys.argv[3])
lo = float(sys.argv[4]) if len(sys.argv) > 4 else -1.0
hi = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
N = 2048
fn, path, _ = T.find(name)
a = T.ref(path, N)
i = int((pos * 0.5 + 0.5) * N)
p = a[i] if axis == 'row' else a[:, i]
t = (np.arange(N) + 0.5) / N * 2 - 1
m = (t >= lo) & (t <= hi)
pk, _ = find_peaks(p, prominence=0.02)
print('peaks:', ' '.join('%.3f@%.3f' % (p[k], t[k]) for k in pk if m[k]))
vk, _ = find_peaks(-p, prominence=0.02)
print('valleys:', ' '.join('%.3f@%.3f' % (p[k], t[k]) for k in vk if m[k]))
g = np.abs(np.gradient(p))
flat = g < 2e-4
print('samples:', ' '.join('%.3f:%.3f' % (t[k], p[k]) for k in range(0, N, 32) if m[k]))
