"""pplib.curves: smooth ramps and bends (from concrete_ribbons).

soft_ramp(M, t, P, R): 0 -> 1 over t in 0..P at 45 degrees with rounded corners of size ~R (a hyperbolic ramp, smooth
everywhere, no kinks). Sum ramps to build lines that jog sideways (S-bends) and still tile.
soft_ramp_slope: its derivative (for tilting things along the curve).
soft_max / soft_min: rounded max / min of two fields (fillets instead of sharp creases), k = blend width.
"""


def _r(M, t, R): return 0.5 * (t + M.fsqrt(t * t + R * R))
def _d(M, t, R): return 0.5 * (1.0 + t / M.fsqrt(t * t + R * R))


def soft_ramp(M, t, P, R):
    return (_r(M, t, R) - _r(M, t - P, R)) / P


def soft_ramp_slope(M, t, P, R):
    return (_d(M, t, R) - _d(M, t - P, R)) / P


def soft_max(M, a, b, k):
    d = a - b
    return 0.5 * (a + b + M.fsqrt(d * d + k * k))


def soft_min(M, a, b, k):
    d = a - b
    return 0.5 * (a + b - M.fsqrt(d * d + k * k))
