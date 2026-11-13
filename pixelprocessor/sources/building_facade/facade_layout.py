"""Building facade layout as maths (same code for numpy previews and the Pixel Processors).

Tile = GROUPS x BAYS_PER_GROUP bays across and FLOORS floors down (so it always tiles). x, y in 0..1, y down.
Per floor: a slab band at the top (projecting), the window zone (head at win_top, height win_h), wall/spandrel below.
Per group: piers at both ends (projecting pilasters), windows between them; within a group each bay holds a window of
width win_w (1 = continuous ribbon, split only by mullions). Windows: frame, n vertical mullions, optional transom,
optional railing bar, a sill ledge, recessed glass. Wall surface pattern by material (panels, boards, bricks, tiles).

facade(M, x, y, P) -> (height, cls, rnd, aux)
  cls  = class index (CLASSES), rnd = per element random (window, panel, brick) 0..1,
  aux  = interior helper: u within the glass pane (0..1) for windows, else the wall pattern's per-unit random 2.
"""
import math
from pplib import rocks as _K

CLASSES = ['wall', 'joint', 'band', 'pier', 'frame', 'glass', 'spandrel', 'railing', 'sill', 'door', 'ac',
           'ground']
CID = {n: i for i, n in enumerate(CLASSES)}
NCLS = 16.0          # class ids are stored as (id + 0.5) / NCLS

# material index (dropdown order) -> wall pattern kind
MATERIALS = ['Precast Panels', 'Board-formed Concrete', 'Brick', 'Render', 'Stone Panels', 'Metal Panels',
             'Mosaic Tiles']


def cl(M, x, lo=0.0, hi=1.0):
    return M.fmin(M.fmax(x, lo), hi)


def ss(M, e):
    e = cl(M, e)
    return e * e * (3.0 - 2.0 * e)


def is_(M, v, k):
    """1 where the (float) dropdown value v == k."""
    return M.b01(M.gt(v, k - 0.5)) * M.b01(M.lt(v, k + 0.5))


def box(M, u, v, u0, u1, v0, v1):
    """Signed distance (positive inside) to the axis box [u0, u1] x [v0, v1] (inside only matters: min of sides)."""
    return M.fmin(M.fmin(u - u0, u1 - u), M.fmin(v - v0, v1 - v))


def hsh(M, a, b, k):
    return M.hash2(a, b, k)


# lane patterns: lane k gets type seq[k % len(seq)] (0 = A, 1 = B, 2 = C); the last entry is random by seed
PATTERNS = [('All A', [0]), ('A B', [0, 1]), ('A B A', [0, 1, 0]), ('A A B', [0, 0, 1]), ('B A B', [1, 0, 1]),
            ('A B B A', [0, 1, 1, 0]), ('A B C B', [0, 1, 2, 1]), ('A B C B A', [0, 1, 2, 1, 0]),
            ('A C A B', [0, 2, 0, 1]), ('Random', None)]
MAXL = 12
TYPE_KEYS = ['bays', 'w', 'h', 'top', 'mull', 'transom', 'style']
STYLES = ['Windows', 'Balcony', 'Spandrel Band', 'Blank Wall']
AC_POS = ['In Window', 'Below Window', 'Mixed']


def pick3(M, t, a, b, c):
    return a * is_(M, t, 0.0) + b * is_(M, t, 1.0) + c * is_(M, t, 2.0)


def lane_types(M, P):
    """Type (0/1/2) and width (bays) of each of MAXL lanes, active flags, from the lane pattern."""
    pat, seed = P['pattern'], P['seed']
    out = []
    for k in range(MAXL):
        t = 0.0
        for pi, (_, seq) in enumerate(PATTERNS):
            if seq is None:
                rt = M.floor(hsh(M, M.c(float(k)), 3.0, seed + 13.0) * 2.999)
                t = t + is_(M, pat, float(pi)) * rt
            else:
                t = t + is_(M, pat, float(pi)) * float(seq[k % len(seq)])
        w = pick3(M, t, P['a_bays'], P['b_bays'], P['c_bays'])
        act = M.b01(M.lt(float(k), P['groups'] - 0.5))
        out.append((t, w, act))
    return out


def facade(M, x, y, P):
    """See the module docstring. Lanes: P['groups'] lanes across, each of type A/B/C (P['pattern']) with its own bay
    count, window size, mullions, transom and style; every P['special'] floors the floor uses type P['special_type']."""
    F = P['floors']
    seed = P['seed']
    lanes = lane_types(M, P)
    starts, cum = [], 0.0
    for t, w, act in lanes:
        starts.append(cum)
        cum = cum + w * act
    T = cum                                                  # bays across the tile
    gon, gh = P['ground_on'], P['g_height']                  # ground floor at the bottom of the tile (floors tall)
    U = F + gon * gh                                         # floor units down the tile
    BW, FH = 1.0 / T, 1.0 / U
    bx, fy = x * T, y * U
    in_ground = gon * M.b01(M.gt(fy, F))
    bay, flo = M.floor(bx), M.floor(fy)
    u, v = bx - bay, fy - flo
    # which lane: count lane starts at or below bx
    L = 0.0
    for k in range(1, MAXL):
        L = L + M.b01(M.gt(bx, starts[k] - 1e-4)) * lanes[k][2]
    l_start, NB, ty = 0.0, 0.0, 0.0
    for k, (t, w, act) in enumerate(lanes):
        sel_k = is_(M, L, float(k))
        l_start, NB, ty = l_start + sel_k * starts[k], NB + sel_k * w, ty + sel_k * t
    gu = bx - l_start                                         # 0..NB within the lane (bay units)
    bay_m, flo_m = M.mod(bay, T), M.mod(flo, F)
    # special floors (horizontal lanes): every `special` floors use type `special_type`
    sp = P['special']
    is_sp = M.b01(M.gt(sp, 0.5)) * is_(M, M.mod(flo_m, M.fmax(sp, 1.0)), 0.0)
    ty_w = ty + (P['special_type'] - ty) * is_sp              # the type that sets the window
    TP = {k: pick3(M, ty_w, P['a_' + k], P['b_' + k], P['c_' + k]) for k in TYPE_KEYS[1:]}
    style = TP['style']
    # per window variation
    wkey = _K.hash12(M, bay_m + seed * 37.0, flo_m, 21.0)
    wk2 = M.frac(wkey * 17.31 + 0.13)
    wk3 = M.frac(wkey * 41.77 + 0.71)
    odd = M.b01(M.lt(wk2, P['odd']))
    ww0 = TP['w']
    ribbon = M.b01(M.gt(ww0, 0.995))
    ww = ww0 * (1.0 + (1.0 - ribbon) * (P['var_w'] * (wkey - 0.5) * 0.5 - odd * 0.5))
    ww = cl(M, ww, 0.05, 1.0)
    mull_n = TP['mull'] * (1.0 - odd * (1.0 - ribbon))
    wh = cl(M, TP['h'] * (1.0 + P['var_h'] * (wk3 - 0.5) * 0.4), 0.05, 1.0)

    # --- distances in tile units -------------------------------------------------------------------------------
    pier = P['pier'] * 0.5                                   # half pier width, bay units (at each lane edge)
    d_pier = M.fmin(gu, NB - gu) * BW                        # distance to the lane edge
    in_pier = M.b01(M.lt(d_pier, pier * BW))
    band_h = P['band']                                       # slab band height, floor units
    in_band = M.b01(M.lt(v, band_h))
    w_top = band_h + (1.0 - band_h) * TP['top']
    w_bot = M.fmin(w_top + wh * (1.0 - band_h), 1.0)
    half = ww * 0.5
    du = (half - M.fabs(u - 0.5)) * BW                       # >0 inside the window column
    du = M.sel(M.gt(ribbon, 0.5), (d_pier - pier * BW), M.fmin(du, d_pier - pier * BW))
    dv = M.fmin(v - w_top, w_bot - v) * FH
    d_win = M.fmin(du, dv)                                   # >0 inside the opening
    blank = is_(M, style, 3.0)
    in_win = M.b01(M.gt(d_win, 0.0)) * (1.0 - in_band) * (1.0 - in_pier) * (1.0 - blank)
    P = dict(P, mullions=mull_n, transom=TP['transom'], railing=is_(M, style, 1.0), spandrel=is_(M, style, 2.0) * 1.0)
    BT = T

    # --- window internals ----------------------------------------------------------------------------------------
    fw = P['frame'] * 0.01                                   # frame width, tile units
    # mullions: per bay n vertical bars (bay boundaries in a ribbon get a mullion too), transom at a height fraction
    nm = P['mullions']
    wu = M.sel(M.gt(ribbon, 0.5), u, (u - (0.5 - half)) / M.fmax(ww, 0.01))      # 0..1 across this window
    seg = wu * (nm + 1.0)
    d_mul = M.fabs(seg - M.floor(seg + 0.5)) / (nm + 1.0) * M.sel(M.gt(ribbon, 0.5), BW, ww * BW)
    d_mul = M.sel(M.gt(nm, 0.5), d_mul, 9.0)
    d_bayb = M.fmin(u, 1.0 - u) * BW                         # ribbon: bay boundary mullion
    d_mul = M.fmin(d_mul, M.sel(M.gt(ribbon, 0.5), d_bayb, 9.0))
    wv = (v - w_top) / M.fmax(w_bot - w_top, 0.01)           # 0..1 down the window
    d_tr = M.sel(M.gt(P['transom'], 0.01), M.fabs(wv - P['transom']) * (w_bot - w_top) * FH, 9.0)
    d_bar = M.fmin(d_mul, d_tr) - fw * 0.5 * P['mullion_w']
    in_frame = M.b01(M.lt(d_win, fw)) + M.b01(M.lt(d_bar, 0.0))
    in_frame = cl(M, in_frame) * in_win
    # railing: a bar across the lower part of the window plus thin balusters
    rail_on = M.b01(M.gt(P['railing'], 0.5))
    d_rail = M.fabs(wv - 0.62) * (w_bot - w_top) * FH - fw * 0.55
    bal = M.fabs(M.frac(x * BT * 14.0) - 0.5) / (BT * 14.0) - fw * 0.12
    in_rail = rail_on * in_win * cl(M, M.b01(M.lt(d_rail, 0.0)) + M.b01(M.lt(bal, 0.0)) * M.b01(M.gt(wv, 0.62)))
    in_glass = in_win * (1.0 - in_frame) * (1.0 - in_rail)
    # sill ledge below the window
    d_sill = M.fmin(du + fw * 1.5, (w_bot - v) * FH + fw * 1.6)
    in_sill = M.b01(M.gt(d_sill, 0.0)) * M.b01(M.gt(v, w_bot)) * (1.0 - in_band) * (1.0 - in_pier) * P['sill_on']

    # --- spandrel: the wall within a group between windows, as a dark glass / metal panel ---------------------------
    in_zone = (1.0 - in_band) * (1.0 - in_pier) * M.b01(M.gt(du, 0.0)) * (1.0 - in_win)
    in_span = in_zone * M.b01(M.gt(P['spandrel'], 0.5)) * (1.0 - in_sill)

    # --- wall pattern by material -------------------------------------------------------------------------------
    mat = P['material']
    jw = P['joint'] * 0.001                                  # joint half width, tile units
    # panels (precast / stone / metal): cols per bay, rows per floor, running offset per row for stone
    pc, pr = P['panel_cols'], P['panel_rows']
    px_ = x * BT * pc
    py_ = y * U * pr
    prow = M.floor(py_)
    stone = is_(M, mat, 4.0)
    px_ = px_ + stone * 0.5 * M.mod(prow, 2.0)
    pcol = M.floor(px_)
    d_pan = M.fmin(M.fmin(px_ - pcol, 1.0 - (px_ - pcol)) / (BT * pc), M.fmin(py_ - prow, 1.0 - (py_ - prow)) / (U * pr))
    r_pan = hsh(M, M.mod(pcol, BT * pc), M.mod(prow, M.floor(U * pr + 0.5)), seed + 3.0)
    # brick: courses (running bond), sized in the square texture: course height = 1 / (floors * courses), brick
    # length = brick_ratio course heights; counts rounded so the tile still tiles
    cr = M.floor(P['brick_rows'] + 0.5)                      # courses per floor
    ncr = M.floor(U * cr + 0.5)                              # courses down the tile
    nbx = M.fmax(M.floor(ncr / P['brick_ratio'] + 0.5), 1.0)   # bricks across the tile
    by = y * ncr
    brow = M.floor(by)
    bxx = x * nbx + 0.5 * M.mod(brow, 2.0)
    bcol = M.floor(bxx)
    d_bri = M.fmin(M.fmin(bxx - bcol, 1.0 - (bxx - bcol)) / nbx, M.fmin(by - brow, 1.0 - (by - brow)) / ncr)
    r_bri = hsh(M, M.mod(bcol, nbx), M.mod(brow, ncr), seed + 5.0)
    # mosaic: square tiles two courses high, same count across and down
    nt = M.fmax(M.floor(ncr * 0.5 + 0.5), 1.0)
    tx_, ty_ = x * nt, y * nt
    d_tile = M.fmin(M.fabs(M.frac(tx_) - 0.5), M.fabs(M.frac(ty_) - 0.5))
    d_tile = (0.5 - d_tile) / nt
    r_tile = hsh(M, M.mod(M.floor(tx_), nt), M.mod(M.floor(ty_), nt), seed + 7.0)
    # board-formed concrete: vertical board lines + a horizontal lift line per floor
    bw_ = P['panel_cols'] * 6.0
    bdx = x * BT * bw_
    d_brd = M.fmin(M.fabs(M.frac(bdx) - 0.5), 0.5)
    d_brd = (0.5 - d_brd) / (BT * bw_)
    r_brd = hsh(M, M.mod(M.floor(bdx), BT * bw_), flo_m, seed + 9.0)
    # choose by material
    panelish = is_(M, mat, 0.0) + stone + is_(M, mat, 5.0)
    d_j = (panelish * d_pan + is_(M, mat, 2.0) * d_bri + is_(M, mat, 6.0) * d_tile + is_(M, mat, 1.0) * d_brd
           + is_(M, mat, 3.0) * 9.0)
    r_u = panelish * r_pan + is_(M, mat, 2.0) * r_bri + is_(M, mat, 6.0) * r_tile + is_(M, mat, 1.0) * r_brd
    jwm = jw * (1.0 - is_(M, mat, 2.0) * 0.45 - is_(M, mat, 1.0) * 0.6 - is_(M, mat, 6.0) * 0.6)   # fine mortar
    joint = 1.0 - ss(M, (d_j - jwm) / (jwm * 0.8 + 1e-5))
    joint = joint * (1.0 - in_win) * (1.0 - in_span) * (1.0 - in_sill)          # cladding: also on bands and piers

    # --- AC units: a box with fins, in the lower pane or hung below the window -------------------------------------
    ac_on = M.b01(M.lt(M.frac(wkey * 3.37 + 0.5), P['ac'])) * (1.0 - blank) * (1.0 - in_ground)
    ap = P['ac_pos']
    below = is_(M, ap, 1.0) + is_(M, ap, 2.0) * M.b01(M.gt(M.frac(wkey * 5.13 + 0.2), 0.5))
    side = M.sel(M.gt(M.frac(wkey * 2.31 + 0.7), 0.5), 1.0, -1.0)
    aw, ah = 0.13 * P['ac_size'], 0.075 * P['ac_size']        # half sizes, bay / floor units
    acx = 0.5 + side * M.fmax(half - aw - 0.05, 0.0)
    acy = M.sel(M.gt(below, 0.5), w_bot + ah + 0.015, w_bot - ah - 0.01)
    d_ac = M.fmin((aw - M.fabs(u - acx)) * BW, (ah - M.fabs(v - acy)) * FH)
    in_ac = M.b01(M.gt(d_ac, 0.0)) * ac_on * (1.0 - in_pier) * (1.0 - in_band)
    fin = M.fabs(M.frac((v - acy) / (ah * 0.28)) - 0.5)
    h_ac = 0.5 + 0.07 + 0.012 * ss(M, d_ac / 0.0015) - 0.008 * ss(M, (0.18 - fin) / 0.1) * M.b01(M.gt(u - acx, -aw * 0.3))
    ac_streak = M.b01(M.lt(M.fabs(u - acx), aw * 0.8)) * M.b01(M.gt(v, acy + ah)) * ac_on * \
        cl(M, 1.0 - (v - acy - ah) / 0.5) * (1.0 - in_ground)

    # --- ground floor: its own bays (door / window / blank), clusters, band, piers ----------------------------------
    vg = cl(M, (fy - F) / M.fmax(gh, 0.01))                  # 0 at the top of the ground floor, 1 at the street
    FHg = gh * FH
    gb = P['g_bays']
    gx = x * gb
    gbay = M.floor(gx)
    gu_ = gx - gbay
    BWg = 1.0 / gb
    K = P['g_cluster']
    ncl = M.fmax(M.floor(gb / K + 0.5), 1.0)
    cid = M.mod(M.floor(gbay / K), ncl)
    rkc = _K.hash12(M, cid + seed * 37.0, 5.0, 31.0)
    rbb = _K.hash12(M, M.mod(gbay, gb) + seed * 37.0, 7.0, 33.0)
    rk = rkc + (rbb - rkc) * P['g_mix']                      # 0 = whole clusters alike, 1 = every bay its own
    is_door = M.b01(M.lt(rk, P['g_doors']))
    is_gwin = M.b01(M.lt(rk, P['g_doors'] + P['g_windows'])) * (1.0 - is_door)
    double = M.b01(M.lt(M.frac(rbb * 9.71 + 0.3), P['g_double'])) * is_door
    glazed = M.b01(M.lt(M.frac(rbb * 3.37 + 0.6), P['g_glazed']))
    gband = P['g_band']
    in_gband = M.b01(M.lt(vg, gband))
    gpier = P['g_pier'] * 0.5
    d_gp = M.fmin(gu_, 1.0 - gu_) * BWg
    in_gpier = M.b01(M.lt(d_gp, gpier * BWg))
    inner = M.fmax(1.0 - 2.0 * gpier - 0.04, 0.05)
    dw = M.fmin(P['g_door_w'] * (1.0 + double * 0.8), inner)
    door_top = 1.0 - P['g_door_h'] * (1.0 - gband)
    gw_top = gband + (1.0 - gband) * P['g_win_top']
    gw_bot = M.fmin(gw_top + P['g_win_h'] * (1.0 - gband), 1.0)
    du_d = (dw * 0.5 - M.fabs(gu_ - 0.5)) * BWg
    d_door = M.fmin(du_d, (vg - door_top) * FHg)
    fan = P['g_fanlight'] * M.b01(M.lt(gw_top, door_top - 0.03))
    d_fan = M.fmin(du_d, M.fmin(vg - gw_top, door_top - vg) * FHg)
    gww = M.fmin(P['g_win_w'], inner)
    d_gw = M.fmin((gww * 0.5 - M.fabs(gu_ - 0.5)) * BWg, M.fmin(vg - gw_top, gw_bot - vg) * FHg)
    d_open = is_door * M.fmax(d_door, M.sel(M.gt(fan, 0.5), d_fan, -1.0)) + is_gwin * d_gw - (1.0 - is_door - is_gwin)
    in_gopen = M.b01(M.gt(d_open, 0.0)) * (1.0 - in_gband) * (1.0 - in_gpier)
    wid = M.sel(M.gt(is_door, 0.5), dw, gww)
    nmg = M.sel(M.gt(is_door, 0.5), double, P['g_mull'])
    gseg = (gu_ - (0.5 - wid * 0.5)) / M.fmax(wid, 0.01) * (nmg + 1.0)
    d_gm = M.sel(M.gt(nmg, 0.5), M.fabs(gseg - M.floor(gseg + 0.5)) / (nmg + 1.0) * wid * BWg, 9.0)
    gwv = (vg - gw_top) / M.fmax(gw_bot - gw_top, 0.01)
    d_gt = M.sel(M.gt(is_door, 0.5), M.sel(M.gt(fan, 0.5), M.fabs(vg - door_top) * FHg, 9.0),
                 M.sel(M.gt(P['g_transom'], 0.01), M.fabs(gwv - P['g_transom']) * (gw_bot - gw_top) * FHg, 9.0))
    fwg = fw * 1.3
    d_door_leaf_edge = M.fmin(du_d, (vg - door_top) * FHg)
    in_gframe = cl(M, M.b01(M.lt(d_open, fwg)) + M.b01(M.lt(d_gm - fwg * 0.5, 0.0)) + M.b01(M.lt(d_gt - fwg * 0.5, 0.0)))
    in_gframe = in_gframe * in_gopen
    in_leaf = is_door * M.b01(M.gt(d_door, 0.0)) * (1.0 - glazed) * (1.0 - in_gframe) * in_gopen
    in_gglass = in_gopen * (1.0 - in_gframe) * (1.0 - in_leaf)
    # door leaf: two raised panels (an upper and a lower) inside each leaf
    leaf_u = M.frac(gseg)
    leaf_v = (vg - door_top) / M.fmax(1.0 - door_top, 0.01)
    pan_d = M.fmin(M.fmin(leaf_u - 0.18, 0.82 - leaf_u) * wid / (nmg + 1.0) * BWg,
                   M.fmin(M.fabs(leaf_v - 0.3) - 0.04, 0.0) * 0.0 + M.fmin(leaf_v - 0.08, 0.92 - leaf_v) * (1.0 - door_top) * FHg)
    pan_split = M.fabs(leaf_v - 0.42) * (1.0 - door_top) * FHg - fw * 0.6
    in_panel = M.b01(M.gt(pan_d, 0.0)) * M.b01(M.gt(pan_split, 0.0))
    g_rec = rec_g = P['recess'] * 0.2
    gbase = 0.5
    hg_band = gbase + P['g_band_depth'] * 0.15 * ss(M, M.fmin(vg, gband - vg) * FHg / 0.0015)
    hg_pier = gbase + P['g_pier_depth'] * 0.15 * ss(M, (gpier * BWg - d_gp) / 0.0015)
    hg_open = M.sel(M.gt(in_gframe, 0.5), gbase - rec_g * 0.7 + 0.012,
                    M.sel(M.gt(in_leaf, 0.5), gbase - rec_g * 0.6 + 0.01 * in_panel, gbase - rec_g))
    h_g = gbase
    h_g = M.sel(M.gt(in_gopen, 0.5), h_g + (hg_open - h_g) * ss(M, d_open / 0.0018), h_g)
    h_g = M.sel(M.gt(in_gband, 0.5), M.fmax(hg_band, h_g), h_g)
    h_g = M.sel(M.gt(in_gpier, 0.5), M.fmax(hg_pier, h_g), h_g)

    # --- heights -----------------------------------------------------------------------------------------------
    base = 0.5
    bev = 0.0015
    groove = joint * P['joint_depth'] * 0.04
    h_wall = base
    h_band = base + P['band_depth'] * 0.15 * ss(M, M.fmin(v, band_h - v) * FH / bev)
    h_pier = base + P['pier_depth'] * 0.15 * ss(M, (pier * BW - d_pier) / bev)
    rec = P['recess'] * 0.2
    h_glass = base - rec
    h_frame = base - rec * 0.75 + 0.012 * (1.0 - ss(M, (d_win - fw) / (fw * 0.6 + 1e-5)) * 0.4)
    h_rail = base - rec * 0.4
    h_sill = base + 0.03 * ss(M, d_sill / bev)
    h_span = base - rec * 0.35
    # reveal: walls slope into the opening over a tiny distance
    reveal = ss(M, d_win / (bev * 1.2))
    h = h_wall
    h = M.sel(M.gt(in_span, 0.5), h_span, h)
    h = M.sel(M.gt(in_sill, 0.5), M.fmax(h_sill, h), h)
    h_open = M.sel(M.gt(in_frame, 0.5), h_frame, M.sel(M.gt(in_rail, 0.5), h_rail, h_glass))
    h = M.sel(M.gt(in_win, 0.5), h + (h_open - h) * reveal, h)
    h = M.sel(M.gt(in_band, 0.5), M.fmax(h_band, h), h)
    h = M.sel(M.gt(in_pier, 0.5), M.fmax(h_pier, h), h)
    h = M.sel(M.gt(in_ac, 0.5), h_ac, h)
    h = M.sel(M.gt(in_ground, 0.5), h_g, h)
    g_wall = in_ground * (1.0 - in_gopen)
    up_wall = (1.0 - in_ground) * (1.0 - in_ac)
    h = h - groove * M.fmax(g_wall, up_wall)

    # --- class, random, aux --------------------------------------------------------------------------------------
    c = M.c(float(CID['wall']))
    c = M.sel(M.gt(in_span, 0.5), float(CID['spandrel']), c)
    c = M.sel(M.gt(in_sill, 0.5), float(CID['sill']), c)
    c = M.sel(M.gt(in_glass, 0.5), float(CID['glass']), c)
    c = M.sel(M.gt(in_frame, 0.5), float(CID['frame']), c)
    c = M.sel(M.gt(in_rail, 0.5), float(CID['railing']), c)
    c = M.sel(M.gt(in_band, 0.5), float(CID['band']), c)
    c = M.sel(M.gt(in_pier, 0.5), float(CID['pier']), c)
    c = M.sel(M.gt(in_ac, 0.5), float(CID['ac']), c)
    cg = M.c(float(CID['ground']))
    cg = M.sel(M.gt(in_gglass, 0.5), float(CID['glass']), cg)
    cg = M.sel(M.gt(in_leaf, 0.5), float(CID['door']), cg)
    cg = M.sel(M.gt(in_gframe, 0.5), float(CID['frame']), cg)
    cg = M.sel(M.gt(in_gband, 0.5), float(CID['band']), cg)
    cg = M.sel(M.gt(in_gpier, 0.5), float(CID['pier']), cg)
    c = M.sel(M.gt(in_ground, 0.5), cg, c)
    c = M.sel(M.gt(joint * M.fmax(g_wall * (1.0 - in_gband) * (1.0 - in_gpier), up_wall), 0.5), float(CID['joint']), c)
    win_key = _K.hash12(M, bay_m + seed * 37.0, flo_m, 1.0)      # exact, evenly spread (the sine hash clumped)
    # in a ribbon a whole group-floor may share curtains; keep per bay (each pane is a room segment)
    rnd = M.sel(M.gt(in_win, 0.5), win_key, r_u)
    rnd = M.sel(M.gt(in_ground, 0.5), M.sel(M.gt(in_gopen, 0.5), rbb, r_u), rnd)
    # pane coordinates for interiors: u across the pane between mullions, v down the window
    pane_u = seg - M.floor(seg)
    aux = M.sel(M.gt(in_win, 0.5), pane_u, wv * 0.0 + r_u)
    aux = M.sel(M.gt(in_ground, 0.5), M.sel(M.gt(in_gopen, 0.5), M.frac(gseg), r_u), aux)
    wv = M.sel(M.gt(in_ground, 0.5), M.sel(M.gt(is_door, 0.5), (vg - gw_top) / M.fmax(1.0 - gw_top, 0.01), gwv), wv)
    # dirt streaks: run down from window sills (and from band undersides), uneven per narrow column
    colk = hsh(M, M.mod(M.floor(x * BT * 22.0), BT * 22.0), flo_m, seed + 11.0)
    below_w = M.b01(M.gt(du, -fw)) * M.b01(M.gt(v, w_bot)) * (1.0 - in_pier)
    fall_w = cl(M, 1.0 - (v - w_bot) / (0.25 + 0.6 * colk))
    below_b = M.b01(M.gt(v, band_h)) * M.b01(M.gt(band_h, 0.01))
    fall_b = cl(M, 1.0 - (v - band_h) / (0.1 + 0.35 * colk)) * 0.6
    streak = M.fmax(below_w * fall_w * fall_w, below_b * fall_b * fall_b) * (0.3 + 0.7 * colk) * (1.0 - in_win)
    streak = M.fmax(streak * (1.0 - in_ground), ac_streak * ac_streak * 1.2) * (1.0 - in_ac)
    openf = M.b01(M.lt(M.frac(wkey * 7.13 + 0.37), P['open_w'])) * in_glass * (1.0 - in_ground) * (1.0 - in_ac)
    return h, c, rnd, aux, wv, streak, openf, wkey, in_ground


DEFAULTS = dict(groups=3.0, floors=5.0, seed=0.0, pier=0.35, band=0.18, frame=0.35, mullion_w=0.8, sill_on=1.0,
                material=0.0, joint=0.6, joint_depth=0.5, panel_cols=1.0, panel_rows=2.0, brick_rows=36.0,
                brick_ratio=3.0, band_depth=0.3, pier_depth=0.3, recess=0.5, pattern=0.0, special=0.0,
                special_type=2.0, var_w=0.0, var_h=0.0, odd=0.0, open_w=0.05,
                a_bays=3.0, a_w=0.8, a_h=0.75, a_top=0.12, a_mull=1.0, a_transom=0.0, a_style=0.0,
                b_bays=2.0, b_w=0.6, b_h=0.75, b_top=0.12, b_mull=0.0, b_transom=0.0, b_style=0.0,
                c_bays=2.0, c_w=1.0, c_h=1.0, c_top=0.0, c_mull=2.0, c_transom=0.5, c_style=0.0,
                ac=0.0, ac_pos=2.0, ac_size=1.0, ground_on=0.0, g_height=1.5, g_bays=6.0, g_cluster=1.0,
                g_mix=0.3, g_doors=0.3, g_windows=0.55, g_double=0.3, g_glazed=0.5, g_band=0.12,
                g_band_depth=0.4, g_pier=0.15, g_pier_depth=0.3, g_door_w=0.4, g_door_h=0.7,
                g_win_w=0.8, g_win_h=0.75, g_win_top=0.08, g_mull=2.0, g_transom=0.2, g_fanlight=1.0)


# --- window interiors ----------------------------------------------------------------------------------------------
# curtain colours: mostly whites / creams / greys, some colour (scaled by `colourful`)
CURTAINS = [(0.86, 0.84, 0.8), (0.78, 0.75, 0.68), (0.62, 0.62, 0.62), (0.9, 0.88, 0.84), (0.7, 0.62, 0.5),
            (0.55, 0.15, 0.12), (0.75, 0.55, 0.15), (0.2, 0.3, 0.45), (0.35, 0.45, 0.3), (0.85, 0.7, 0.2)]


def interior(M, rnd, pu, wv, P, ground=0.0):
    """Interior seen through one pane. rnd = window random (0..1), pu = 0..1 across the pane, wv = 0..1 down.
    Returns (r, g, b, lit). Kinds by thresholds on rnd: curtains, blinds, else a room (dark, sometimes lit)."""
    k1 = M.frac(rnd * 13.17 + 0.31)          # second random from the same window
    k2 = M.frac(rnd * 71.31 + 0.77)
    k3 = M.frac(rnd * 5.913 + 0.11)
    keep = 1.0 - ground * 0.85                              # shops / doors: few curtains or blinds, more lights
    is_cur = M.b01(M.lt(rnd, P['curtains'] * keep))
    is_bli = M.b01(M.lt(rnd, (P['curtains'] + P['blinds']) * keep)) * (1.0 - is_cur)
    lit = M.b01(M.lt(k3, P['lit'] + ground * 0.35))
    # curtain: drawn from both sides to an opening of k1; vertical folds; colour from the palette
    opening = M.fmax(k1 * 1.2 - 0.25, 0.0) * 0.5            # half opening at the pane centre
    covered = M.b01(M.gt(M.fabs(pu - 0.5), opening))
    folds = 0.82 + 0.18 * M.fsin((pu * (6.0 + k2 * 8.0) + k1) * 6.2831853)
    nc = len(CURTAINS)
    ci = M.floor(M.frac(k2 * 7.77 + rnd) * (5.0 + P['colourful'] * (nc - 5.0)))
    cr, cg, cb = 0.0, 0.0, 0.0
    for i, (r_, g_, b_) in enumerate(CURTAINS):
        w = is_(M, ci, float(i))
        cr, cg, cb = cr + w * r_, cg + w * g_, cb + w * b_
    # blinds: horizontal slats, partly pulled up (k1)
    slat = 0.8 + 0.2 * M.fsin(wv * (60.0 + k2 * 40.0) * 6.2831853)
    blind_on = M.b01(M.gt(wv, k1 * 0.6))
    blr, blg, blb = 0.78 * slat, 0.78 * slat, 0.76 * slat
    # room: dark, a bit lighter towards the floor, some furniture shapes, warm when lit
    room = 0.05 + 0.05 * wv + 0.04 * M.b01(M.gt(wv, 0.55 + 0.3 * k1)) * M.b01(M.lt(M.fabs(pu - k2), 0.25))
    rr = room * (1.0 + lit * 9.0 * P['lit_r'])
    rg = room * (1.0 + lit * 9.0 * P['lit_g'])
    rb = room * (1.05 + lit * 9.0 * P['lit_b'])
    # composite: curtains / blinds in front of the room
    cur_m = is_cur * covered
    bli_m = is_bli * blind_on
    tone = 1.0 + lit * 0.5                                      # backlit fabric glows a little
    r = rr * (1.0 - cur_m - bli_m) + cur_m * cr * folds * tone * 0.8 + bli_m * blr * tone * 0.85
    g = rg * (1.0 - cur_m - bli_m) + cur_m * cg * folds * tone * 0.8 + bli_m * blg * tone * 0.85
    b = rb * (1.0 - cur_m - bli_m) + cur_m * cb * folds * tone * 0.8 + bli_m * blb * tone * 0.85
    glow = lit * (0.35 + 0.65 * (1.0 - cur_m - bli_m))           # emission: brighter where the room shows
    return r, g, b, glow


IDEFAULTS = dict(curtains=0.45, blinds=0.2, lit=0.12, colourful=0.3, lit_r=0.12, lit_g=0.09, lit_b=0.05)


# --- disrepair: broken and boarded windows ----------------------------------------------------------------------------
def window_decay(M, c, rnd, aux, wv, P):
    """Per window, from its random key: boarded (planks over the whole opening, some with a diagonal brace), or broken
    (a jagged hole in each pane with cracks radiating from it; some panes gone entirely). Returns (hole, board, plank):
      hole  = 1 hole, 0.5 crack line in the remaining glass, 0 intact
      board = 1 where a board covers the opening (gaps between planks 0), plank = per plank tone / height 0..1."""
    from pplib.decals import polar
    PI2 = 6.2831853
    opening = is_(M, c, CID['glass']) + is_(M, c, CID['frame']) + is_(M, c, CID['railing']) + is_(M, c, CID['door'])
    glass = is_(M, c, CID['glass'])
    k_b = M.frac(rnd * 17.93 + 0.41)
    k_x = M.frac(rnd * 29.31 + 0.17)
    boarded = M.b01(M.lt(k_b, P['boarded']))
    broken = M.b01(M.lt(k_x, P['broken'])) * (1.0 - boarded)
    gone = M.b01(M.lt(k_x, P['broken'] * 0.35)) * broken           # a third of broken panes have no glass left
    # jagged hole: centre per window, radius jittered by angle
    k1, k2, k3 = M.frac(rnd * 7.71 + 0.3), M.frac(rnd * 3.17 + 0.6), M.frac(rnd * 11.3 + 0.9)
    cx, cy = 0.25 + 0.5 * k1, 0.2 + 0.6 * k2
    r, a = polar(M, aux - cx, (wv - cy) * 0.6)
    jag = (0.7 + 0.3 * M.fsin(a * 3.0 + k3 * PI2)) * (0.85 + 0.15 * M.fsin(a * 7.0 + k1 * 9.0)) * \
        (0.93 + 0.07 * M.fsin(a * 17.0 + k2 * 5.0))
    R0 = 0.12 + 0.3 * k3
    in_hole = M.b01(M.lt(r, R0 * jag))
    rays = M.fabs(M.frac(a / PI2 * (7.0 + 5.0 * k2) + k1) - 0.5)
    crack = M.b01(M.lt(rays, 0.03)) * M.b01(M.lt(r, R0 * 2.6)) * (1.0 - in_hole)
    hole = glass * broken * M.fmax(M.fmax(in_hole, gone), crack * 0.5 * (1.0 - gone))
    # boards: horizontal planks (some vertical), uneven, plus a diagonal brace on some
    n = 4.0 + M.floor(M.frac(rnd * 5.31 + 0.2) * 4.0)
    vert = M.b01(M.lt(M.frac(rnd * 2.73 + 0.5), 0.3))
    coord = M.sel(M.gt(vert, 0.5), aux * 2.0 + 0.03 * M.fsin(wv * 4.0 + k1 * 6.0), wv * n + 0.04 * M.fsin(aux * 3.0 + k2 * 6.0) + 0.08 * (aux - 0.5) * (k1 - 0.5))
    pid = M.floor(coord)
    pt = coord - pid
    gap = M.b01(M.lt(pt, 0.06 + 0.06 * M.frac(pid * 0.37 + k3)))
    plank = M.frac(M.fsin(pid * 12.9898 + rnd * 78.233) * 43758.5453) * 0.8 + 0.2 * (1.0 - M.fabs(pt - 0.53) * 2.0)
    brace = M.b01(M.lt(M.fabs(aux - wv), 0.07)) * M.b01(M.lt(M.frac(rnd * 3.91 + 0.1), 0.45))
    board = opening * boarded * M.fmax(1.0 - gap, brace)
    plank = M.sel(M.gt(brace, 0.5), 0.95, plank)
    return hole, board, plank
