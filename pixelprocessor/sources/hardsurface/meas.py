"""Quick measurements of a reference: python meas.py <item> [step]  -> row0, col0, diagonal, plus bbox of the
covered area and the height histogram peaks (plateau levels)."""
import sys
import numpy as np
import inspect_item as T
name = sys.argv[1]; st = float(sys.argv[2]) if len(sys.argv) > 2 else 0.02
fn, p, _ = T.find(name); a = T.ref(p, 2048)
def at(x, y): return a[min(2047, int((y * 0.5 + 0.5) * 2048)), min(2047, int((x * 0.5 + 0.5) * 2048))]
m = a > 0.02; ys, xs = np.where(m); t = lambda i: (i + 0.5) / 2048 * 2 - 1
print('bbox x %.3f..%.3f  y %.3f..%.3f' % (t(xs.min()), t(xs.max()), t(ys.min()), t(ys.max())))
h, e = np.histogram(a[m], 100, (0, 1)); pk = [(e[i], h[i]) for i in range(1, 99) if h[i] > h[i-1] and h[i] >= h[i+1] and h[i] > 0.01 * m.sum()]
print('levels:', ' '.join('%.2f' % v for v, _ in pk))
for lab, f in (('row0', lambda q: at(q, 0)), ('col0', lambda q: at(0, q)), ('diag', lambda q: at(q, q))):
    print(lab + ':', ' '.join('%.2f:%.2f' % (q, f(q)) for q in np.arange(-1, 1.0001, st)))
