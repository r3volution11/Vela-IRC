#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Vela icon concepts: writes every concept (and the alternate colourways of
# the two finalists) as
#   <dir>/<id>.icon   an Icon Composer document (background fill, glow layer,
#                     V layer(s), optional accent layer)
#   <dir>/<id>.svg    a flat, self-contained SVG of the same artwork on the
#                     macOS 26 icon shape (no Liquid Glass)
#
#   python3 -I concepts.py <concepts-dir>
#
# Or one Icon Composer document, for installing a concept (design/app-icon/
# build.sh writes Vela/AppIcon.icon and the Dock-icon alternates this way):
#
#   python3 -I concepts.py --icon <letter> <colourway> <out.icon>
#
# Or the website's favicon, Glint's V and star without the tile
# (scripts/export-icon.sh writes website/public/favicon.svg this way, and
# rasterizes the flat version into the PNG and ICO favicons):
#
#   python3 -I concepts.py --favicon <favicon.svg> <flat.svg>
#
# Canvas: the 1024-point icon body (Icon Composer's canvas), y grows down.
import json
import math
import os
import shutil
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C = 512.0  # horizontal centre

# --------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def mul(a, k): return (a[0] * k, a[1] * k)
def unit(v):
    l = math.hypot(*v)
    return (v[0] / l, v[1] / l)
def mx(p): return (2 * C - p[0], p[1])          # mirror about the centre line
def meet(p1, d1, p2, d2):                        # intersection of two lines
    det = d1[0] * -d2[1] - d1[1] * -d2[0]
    rx, ry = p2[0] - p1[0], p2[1] - p1[1]
    s = (rx * -d2[1] - ry * -d2[0]) / det
    return (p1[0] + d1[0] * s, p1[1] + d1[1] * s)
DOWN = (0.0, 1.0)
ACROSS = (1.0, 0.0)
def f(p): return f"{p[0]:.1f} {p[1]:.1f}"
def poly(pts): return "M " + " L ".join(f(p) for p in pts) + " Z"

# --------------------------------------------------------------------------
# The macOS 26 icon shape, measured from ictool's own mask (one corner,
# 1024 canvas). Corner curve runs ~330 pt along each edge.
# --------------------------------------------------------------------------
_PROFILE = [85.51,83.36,81.28,79.24,77.23,75.26,73.32,71.42,69.60,67.78,65.94,64.13,62.40,60.78,59.06,57.42,55.89,54.25,52.83,51.24,49.88,48.38,47.03,45.74,44.30,43.05,41.85,40.61,39.29,38.13,37.02,35.94,34.88,33.82,32.79,31.78,30.79,29.82,28.87,27.92,26.99,26.07,25.17,24.37,23.71,22.90,22.04,21.23,20.68,19.94,19.12,18.59,17.94,17.16,16.75,16.03,15.45,14.96,14.27,13.92,13.22,12.92,12.24,11.95,11.36,11.00,10.66,10.07,9.89,9.28,9.01,8.79,8.19,7.99,7.79,7.23,7.02,6.90,6.49,6.10,5.99,5.87,5.48,5.13,5.01,4.95,4.77,4.36,4.12,4.02,3.98,3.89,3.69,3.35,3.14,3.04,3.00,2.97,2.90,2.78,2.56,2.30,2.15,2.07,2.02,2.00,1.98,1.94,1.86,1.75,1.58,1.36,1.22,1.12,1.06,1.02,1.00,0.99,0.97,0.93,0.87,0.79,0.67,0.50,0.34,0.22,0.15,0.09,0.06,0.03,0.02]

def _corner():
    ys = [70 + 2 * i for i in range(len(_PROFILE))]
    xs = list(_PROFILE)
    # light smoothing of the anti-aliasing noise
    sm = [sum(xs[max(0, i - 3):i + 4]) / len(xs[max(0, i - 3):i + 4]) if i > 20 else xs[i] for i in range(len(xs))]
    sm[-1] = 0.0
    steep = [(x, y) for x, y in zip(sm, ys) if y >= x]          # below the diagonal
    steep.sort(key=lambda p: -p[1])                              # from the left edge upward
    shallow = [(y, x) for (x, y) in reversed(steep)]             # mirrored across the diagonal
    return steep + shallow                                       # (0,~330) ... (~330,0)

def squircle_path(size=1024.0, ox=0.0, oy=0.0):
    k = size / 1024.0
    c = _corner()
    tl = [(x, y) for x, y in c]
    tr = [(1024 - y, x) for x, y in c]
    br = [(1024 - x, 1024 - y) for x, y in c]
    bl = [(y, 1024 - x) for x, y in c]
    pts = tl + tr + br + bl
    return "M " + " L ".join(f"{ox + x * k:.2f} {oy + y * k:.2f}" for x, y in pts) + " Z"

# --------------------------------------------------------------------------
# Palette. Hex values from the current icon (design/app-icon/README.md,
# Vela/AppIcon.icon/icon.json, gen/sails.py), extended with harmonious
# deeper/lighter steps where a concept needs them.
# ramp: lightest -> deepest. The default ramp is the right sail's stops plus
# the left arm's deepest blue and one deeper step.
# --------------------------------------------------------------------------
COLORWAYS = {
    "vela": dict(
        title="Vela (default)",
        bg=("#03050D", "#09122B"), bg_dark=("#020309", "#070E23"),
        ramp=["#B4FAF4", "#66E6EE", "#34C6E6", "#2296DA", "#1A6FB8"],
        glow="#34C6E6", glow_op=0.55, bloom="#1D5A9A", bloom_op=0.40,
        star=("#FFFFFF", "#DBFFFF"), mono=False),
    "midnight": dict(
        title="Midnight",
        bg=("#010208", "#060B1E"), bg_dark=("#000105", "#04081A"),
        ramp=["#F2FFFD", "#DBFFFF", "#9EFAFF", "#5FB8E8", "#3A78D0"],
        glow="#9EFAFF", glow_op=0.22, bloom="#1A2F6E", bloom_op=0.30,
        star=("#FFFFFF", "#DBFFFF"), mono=False),
    "sunrise": dict(
        title="Sunrise",
        bg=("#070A1C", "#1B1438"), bg_dark=("#04060F", "#120D27"),
        ramp=["#FFF1C9", "#FFC98A", "#FF9A6B", "#F2667A", "#C9467E"],
        glow="#FF9A6B", glow_op=0.36, bloom="#7A2E5C", bloom_op=0.34,
        star=("#FFF6DC", "#FFC98A"), mono=False),     # warm, like the V's point
    "graphite": dict(
        title="Graphite",
        bg=("#16181C", "#2A2D33"), bg_dark=("#0D0E11", "#1C1E22"),
        ramp=["#FFFFFF", "#ECEFF3", "#C9D0D8", "#9AA4B0", "#737D8A"],
        glow="#DCE2E8", glow_op=0.16, bloom="#5A6270", bloom_op=0.22,
        star=("#FFFFFF", "#ECEFF3"), mono=False),
    "paper": dict(
        title="Paper",
        bg=("#FBFCFE", "#E2E9F2"), bg_dark=("#FBFCFE", "#E2E9F2"),
        ramp=["#34C6E6", "#2296DA", "#1A6FB8", "#0A3E7A", "#09122B"],
        glow="#34C6E6", glow_op=0.20, bloom="#9ED8F2", bloom_op=0.40,
        star=("#1A6FB8", "#0A3E7A"), mono=False),     # deep, like the V's tops
    "vivid": dict(
        title="Vivid",
        bg=("#2AB4EA", "#1E50D6"), bg_dark=("#1C8FCB", "#173CA8"),
        ramp=["#FFFFFF", "#F2FFFD", "#E8FFFC", "#D2F4FA", "#BFE8F6"],
        glow="#0A1E5C", glow_op=0.30, bloom="#B4FAF4", bloom_op=0.30,
        star=("#FFFFFF", "#FFFFFF"), mono=False),
}
MONO = ["#FFFFFF", "#F6F8FA", "#EEF1F4", "#E2E7EC", "#D4DAE1"]   # Clear/Tinted V

# --------------------------------------------------------------------------
# Concepts. Each returns a dict:
#   pieces: list of (layer, path d, paint) ; paint = name of a gradient
#   accent: optional (path d) drawn in its own layer
#   silhouette: list of path d used for the glow
#   notes: construction numbers for the README
# Paints are resolved per colourway in paint_defs().
# --------------------------------------------------------------------------
def arm_frame(W, T, B, t, bottom_half):
    """Left arm of a symmetric V. Outer edge from (C-W/2, T) to (C-bottom_half, B)."""
    OL = (C - W / 2, T)
    BL = (C - bottom_half, B)
    d = unit(sub(BL, OL))
    slope = d[0] / d[1]
    h = t / d[1]                     # horizontal stroke width
    IL = (OL[0] + h, T)
    crotch = meet(IL, d, (C, 0), DOWN)
    return OL, BL, d, slope, h, IL, crotch

def chamfer_45(OL, slope, k):
    """45-degree cut at the outer top corner: k along the top edge."""
    u = k / (1 + slope)
    return (OL[0] + u * slope, OL[1] + u), (OL[0] + k, OL[1])

def concept_chamfer(W=604, T=250, B=790, t=150, flat=84, k=74):
    OL, BL, d, slope, h, IL, crotch = arm_frame(W, T, B, t, flat / 2)
    c0, c1 = chamfer_45(OL, slope, k)
    pts = [c1, IL, crotch, mx(IL), mx(c1), mx(c0), mx(BL), BL, c0]
    d_ = poly(pts)
    return dict(pieces=[("v", d_, "body")], silhouette=[d_],
                notes=dict(width=W, height=B - T, stroke=t, angle=math.degrees(math.atan(slope)),
                           chamfer=k, flat=flat, notch=crotch[1]))

def concept_facet(W=604, T=246, B=806, t=156, k=58):
    BV = (C, B)
    OL, _, d, slope, h, IL, crotch = arm_frame(W, T, B, t, 0)
    c0, c1 = chamfer_45(OL, slope, k)
    ML = (OL[0] + h / 2, T)                          # ridge starts mid-terminal
    R = meet(ML, d, (C, 0), DOWN)                    # ridges meet on the axis
    LO = [c0, c1, ML, R, BV]
    LI = [ML, IL, crotch, R]
    RI = [mx(IL), mx(ML), R, crotch]
    RO = [mx(ML), mx(c1), mx(c0), BV, R]
    sil = poly([c1, IL, crotch, mx(IL), mx(c1), mx(c0), BV, c0])
    return dict(pieces=[("v", poly(LO), "f_lo"), ("v", poly(LI), "f_li"),
                        ("v", poly(RI), "f_ri"), ("v", poly(RO), "f_ro")],
                silhouette=[sil], mono_single=sil,
                notes=dict(width=W, height=B - T, stroke=t, angle=math.degrees(math.atan(slope)),
                           chamfer=k, ridge=R[1], notch=crotch[1]))

def concept_bars(W=664, T=246, B=812, t=150, k=46, gap=18):
    BV = (C, B)
    OL = (C - W / 2, T)
    d = unit(sub(BV, OL))                    # left bar runs down-right
    nL = (d[1], -d[0])                       # into the left bar (up-right)
    # inner top corner sits on y = T; the cap is square to the bar
    ITL = meet(add(BV, mul(nL, t)), d, (0, T), ACROSS)
    OTL = sub(ITL, mul(nL, t))
    aL, bL = add(OTL, mul(d, k)), add(OTL, mul(nL, k))
    xs = C - gap / 2                         # the seam between the bars
    Y = meet(add(BV, mul(nL, t)), d, (xs, 0), DOWN)
    Z = meet(BV, d, (xs, 0), DOWN)
    left = [bL, ITL, Y, Z, aL]
    right = [mx(p) for p in reversed(left)]
    crotch = meet(add(BV, mul(nL, t)), d, (C, 0), DOWN)
    return dict(pieces=[("bar-right", poly(right), "bar_front"), ("bar-left", poly(left), "bar_back")],
                silhouette=[poly(left), poly(right)],
                notes=dict(width=W, height=B - T, stroke=t, angle=math.degrees(math.atan(d[0] / d[1])),
                           chamfer=k, gap=gap, notch=crotch[1], cap_drop=t * d[0]))

def quad_pts(p0, c, p1, n=48):
    out = []
    for i in range(n + 1):
        s = i / n
        out.append(((1 - s) ** 2 * p0[0] + 2 * (1 - s) * s * c[0] + s * s * p1[0],
                    (1 - s) ** 2 * p0[1] + 2 * (1 - s) * s * c[1] + s * s * p1[1]))
    return out

def side(p, a, d):
    return (p[0] - a[0]) * d[1] - (p[1] - a[1]) * d[0]

def concept_sail(W=604, T=250, B=790, t=150, flat=84, k=74, belly=30, clew_rise=16, shift=-12):
    OL, BL, d, slope, h, IL, crotch0 = arm_frame(W, T, B, t, flat / 2)
    c0, c1 = chamfer_45(OL, slope, k)
    BR = mx(BL)
    ORt = (C + W / 2 + 8, T - clew_rise)              # flying clew, a touch higher
    # outer edge (leech): a quadratic bellied away from the notch
    m = mul(add(BR, ORt), 0.5)
    v = unit(sub(ORt, BR))
    n = (-v[1], v[0])
    if n[0] < 0:
        n = mul(n, -1)
    ctrl = add(m, mul(n, 2 * belly))
    N = 240
    outer, inner = [], []
    for i in range(N + 1):
        u = i / N
        pt = ((1 - u) ** 2 * BR[0] + 2 * (1 - u) * u * ctrl[0] + u * u * ORt[0],
              (1 - u) ** 2 * BR[1] + 2 * (1 - u) * u * ctrl[1] + u * u * ORt[1])
        tg = unit((2 * (1 - u) * (ctrl[0] - BR[0]) + 2 * u * (ORt[0] - ctrl[0]),
                   2 * (1 - u) * (ctrl[1] - BR[1]) + 2 * u * (ORt[1] - ctrl[1])))
        inward = (tg[1], -tg[0])                       # toward the notch
        outer.append(pt)
        inner.append(add(pt, mul(inward, t)))           # true parallel offset: even stroke
    # clip the offset edge: below by the left arm's inner edge, above by the head
    hd = unit((-h, clew_rise))
    def clip(curve, a, dd, keep_sign):
        out = []
        for i in range(len(curve)):
            sgn = side(curve[i], a, dd)
            if (sgn > 0) == keep_sign:
                out.append(curve[i])
            if i + 1 < len(curve):
                s2 = side(curve[i + 1], a, dd)
                if (sgn > 0) != (s2 > 0):
                    out.append(meet(curve[i], sub(curve[i + 1], curve[i]), a, dd))
        return out
    ref_in = add(IL, mul(d, 10))
    keep_right = side((C + 200, T + 100), IL, d) > 0
    inner = clip(inner, IL, d, keep_right)
    keep_below = side((C + 200, T + 200), ORt, hd) > 0
    inner = clip(inner, ORt, hd, keep_below)
    crotch, IRt = inner[0], inner[-1]
    pts = [c1, IL] + inner + [ORt] + list(reversed(outer[:-1])) + [BL, c0]
    pts = [(x + shift, y) for x, y in pts]
    d_ = poly(pts)
    return dict(pieces=[("v", d_, "body")], silhouette=[d_],
                notes=dict(width=W, height=B - T, stroke=t, angle=math.degrees(math.atan(slope)),
                           chamfer=k, flat=flat, belly=belly, clew_rise=clew_rise, shift=shift, notch=crotch[1]))

def star_path(cx, cy, r, waist=0.16, stretch=1.0):
    q = r * waist
    rv = r * stretch
    return (f"M {cx:.1f} {cy - rv:.1f} Q {cx + q:.1f} {cy - q:.1f} {cx + r:.1f} {cy:.1f} "
            f"Q {cx + q:.1f} {cy + q:.1f} {cx:.1f} {cy + rv:.1f} "
            f"Q {cx - q:.1f} {cy + q:.1f} {cx - r:.1f} {cy:.1f} "
            f"Q {cx - q:.1f} {cy - q:.1f} {cx:.1f} {cy - rv:.1f} Z")

def concept_glint(W=596, T=262, B=806, t=140, k=54, star_r=56, star_y=None):
    BV = (C, B)
    OL, _, d, slope, h, IL, crotch = arm_frame(W, T, B, t, 0)
    c0, c1 = chamfer_45(OL, slope, k)
    # pointed V, the very tip trimmed flat (22 pt up each edge) so it stays crisp
    tip = 22
    tl = sub(BV, mul(d, tip))
    tr = mx(tl)
    pts = [c1, IL, crotch, mx(IL), mx(c1), mx(c0), tr, tl, c0]
    d_ = poly(pts)
    sy = star_y if star_y is not None else T + 30
    star = star_path(C, sy, star_r, 0.15, 1.18)
    return dict(pieces=[("v", d_, "body")], silhouette=[d_], accent=star,
                notes=dict(width=W, height=B - T, stroke=t, angle=math.degrees(math.atan(slope)),
                           chamfer=k, star_r=star_r, star_y=sy, notch=crotch[1]))

def concept_neon(W=600, T=262, B=780, t=96, flat=54, k=36):
    OL, BL, d, slope, h, IL, crotch = arm_frame(W, T, B, t, flat / 2)
    c0, c1 = chamfer_45(OL, slope, k)
    pts = [c1, IL, crotch, mx(IL), mx(c1), mx(c0), mx(BL), BL, c0]
    d_ = poly(pts)
    return dict(pieces=[("v", d_, "neon")], silhouette=[d_], halo=True,
                notes=dict(width=W, height=B - T, stroke=t, angle=math.degrees(math.atan(slope)),
                           chamfer=k, flat=flat, notch=crotch[1]))

CONCEPTS = [
    ("A", "chamfer", "Chamfer", concept_chamfer),
    ("B", "facet", "Facet", concept_facet),
    ("C", "bars", "Twin Bars", concept_bars),
    ("D", "sail", "Leeward", concept_sail),
    ("E", "glint", "Glint", concept_glint),
    ("F", "neon", "Neon", concept_neon),
]

# --------------------------------------------------------------------------
# Paint
# --------------------------------------------------------------------------
def lin(gid, x1, y1, x2, y2, stops):
    s = "".join(f'<stop offset="{o:g}" stop-color="{c}"/>' for o, c in stops)
    return (f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" '
            f'x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>')

def paint_defs(cw, mono, p):
    """Gradient definitions for every paint name, ids prefixed by p."""
    r = MONO if mono else cw["ramp"]
    l0, l1, l2, l3, l4 = r
    return {
        # light rises from the V's point, like the sunrise in the old icon
        "body": lin(p + "body", 512, 800, 512, 240, [(0, l0), (0.28, l1), (0.62, l2), (1, l3)]),
        "neon": lin(p + "neon", 512, 790, 512, 250, [(0, l0), (0.55, l0), (1, l1)]),
        # facets, lit from the upper left
        "f_lo": lin(p + "f_lo", 300, 250, 512, 800, [(0, l1), (1, l0)]),
        "f_li": lin(p + "f_li", 400, 250, 512, 700, [(0, l3), (1, l2)]),
        "f_ri": lin(p + "f_ri", 640, 250, 512, 700, [(0, l2), (1, l1)]),
        "f_ro": lin(p + "f_ro", 760, 250, 512, 800, [(0, l4), (1, l3)]),
        # twin bars: front bar = right sail, back bar = left arm (deeper)
        "bar_front": lin(p + "bar_front", 512, 800, 780, 250, [(0, l0), (0.35, l1), (1, l2)]),
        "bar_back": lin(p + "bar_back", 512, 760, 240, 250, [(0, l1), (0.5, l2), (1, l3)]),
    }

def svg_doc(body, defs=""):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            f'<defs>{defs}</defs>\n{body}\n</svg>\n')

def mark_fragment(concept, cw, mono, p, layer=None):
    defs = paint_defs(cw, mono, p)
    used, paths = {}, []
    for (lyr, d_, paint) in concept["pieces"]:
        if layer is not None and lyr != layer:
            continue
        if mono and "mono_single" in concept and layer is None:
            continue
        used[paint] = defs[paint]
        paths.append(f'<path d="{d_}" fill="url(#{p}{paint})"/>')
    if mono and "mono_single" in concept and layer is None:
        # facets collapse to one shape in Clear/Tinted; a faint ridge keeps the cut
        used["body"] = defs["body"]
        paths.append(f'<path d="{concept["mono_single"]}" fill="url(#{p}body)"/>')
    return "".join(used.values()), "\n".join(paths)

def glow_fragment(concept, cw, p, blur=40):
    # CoreSVG (ictool, NSImage) applies filters on paths, not on <g>.
    def blurred(fid, op):
        return "\n".join(f'<path d="{d_}" fill="{cw["glow"]}" opacity="{op:.3f}" filter="url(#{p}{fid})"/>'
                         for d_ in concept["silhouette"])
    defs = (f'<radialGradient id="{p}bloom" gradientUnits="userSpaceOnUse" cx="512" cy="600" r="560">'
            f'<stop offset="0" stop-color="{cw["bloom"]}" stop-opacity="{cw["bloom_op"]}"/>'
            f'<stop offset="0.55" stop-color="{cw["bloom"]}" stop-opacity="{cw["bloom_op"] * 0.38:.3f}"/>'
            f'<stop offset="1" stop-color="{cw["bloom"]}" stop-opacity="0"/></radialGradient>'
            f'<filter id="{p}blur" x="-40%" y="-40%" width="180%" height="180%">'
            f'<feGaussianBlur stdDeviation="{blur}"/></filter>')
    body = f'<rect width="1024" height="1024" fill="url(#{p}bloom)"/>\n' + blurred("blur", cw["glow_op"])
    if concept.get("halo"):
        # neon: a tight, bright tube halo on top of the wide glow
        defs += (f'<filter id="{p}halo" x="-40%" y="-40%" width="180%" height="180%">'
                 f'<feGaussianBlur stdDeviation="11"/></filter>')
        body += "\n" + blurred("blur", min(1, cw["glow_op"] * 1.2)) + "\n" + blurred("halo", min(1, cw["glow_op"] * 1.9))
    return defs, body

def accent_fragment(concept, cw, mono, p):
    a, b = ("#FFFFFF", "#F2F4F6") if mono else cw["star"]
    defs = (f'<radialGradient id="{p}star" gradientUnits="userSpaceOnUse" cx="512" cy="{concept["notes"]["star_y"]}" r="60">'
            f'<stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></radialGradient>')
    return defs, f'<path d="{concept["accent"]}" fill="url(#{p}star)"/>'

def hex01(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))

def fill_spec(pair, appearance=None):
    a, b = (hex01(x) for x in pair)
    v = {"linear-gradient": [
            "display-p3:%.5f,%.5f,%.5f,1.00000" % a,
            "display-p3:%.5f,%.5f,%.5f,1.00000" % b],
         "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 0.78}}}
    d = {"value": v}
    if appearance:
        d = {"appearance": appearance, "value": v}
    return d

# --------------------------------------------------------------------------
# Writers
# --------------------------------------------------------------------------
GLASS = {  # per concept: is the V Liquid Glass, and the group's glass settings
    "default": dict(glass=True, translucency=0.0, specular=True, shadow=("layer-color", 0.5)),
    "neon": dict(glass=False, translucency=0.0, specular=False, shadow=("none", 0.5)),
}

def write_icon(path, concept, cw, key):
    if os.path.exists(path):
        shutil.rmtree(path)
    assets = os.path.join(path, "Assets")
    os.makedirs(assets)
    layers_front = []
    g = GLASS.get(key, GLASS["default"])
    if "accent" in concept:
        for mono in (False, True):
            dfs, body = accent_fragment(concept, cw, mono, "s")
            open(os.path.join(assets, "accent-mono.svg" if mono else "accent.svg"), "w").write(svg_doc(body, dfs))
        layers_front.append({"name": "accent", "glass": g["glass"],
                             "image-name-specializations": [{"value": "accent.svg"},
                                                            {"appearance": "tinted", "value": "accent-mono.svg"}]})
    names = []
    for (lyr, _, _) in concept["pieces"]:
        if lyr not in names:
            names.append(lyr)
    for lyr in names:
        for mono in (False, True):
            dfs, body = mark_fragment(concept, cw, mono, "m", layer=lyr if len(names) > 1 else None)
            open(os.path.join(assets, f"{lyr}-mono.svg" if mono else f"{lyr}.svg"), "w").write(svg_doc(body, dfs))
        layers_front.append({"name": lyr, "glass": g["glass"],
                             "image-name-specializations": [{"value": f"{lyr}.svg"},
                                                            {"appearance": "tinted", "value": f"{lyr}-mono.svg"}]})
    dfs, body = glow_fragment(concept, cw, "g")
    open(os.path.join(assets, "glow.svg"), "w").write(svg_doc(body, dfs))
    doc = {
        "groups": [
            {"layers": layers_front,
             "shadow": {"kind": g["shadow"][0], "opacity": g["shadow"][1]},
             "translucency": {"enabled": g["translucency"] > 0, "value": g["translucency"]},
             "specular": g["specular"], "lighting": "individual"},
            {"layers": [{"name": "glow", "glass": False, "image-name": "glow.svg",
                         "hidden-specializations": [{"appearance": "tinted", "value": True}],
                         "opacity-specializations": [{"value": 1.0}, {"appearance": "dark", "value": 0.85}]}],
             "shadow": {"kind": "none", "opacity": 0.5},
             "translucency": {"enabled": False, "value": 0.5}},
        ],
        "supported-platforms": {"squares": ["macOS"]},
        "fill-specializations": [fill_spec(cw["bg"]), fill_spec(cw["bg_dark"], "dark")],
    }
    json.dump(doc, open(os.path.join(path, "icon.json"), "w"), indent=2)

def write_flat_svg(path, concept, cw, title):
    """Self-contained flat SVG on the 1024 macOS grid (824-pt body, 100-pt margin)."""
    k = 824 / 1024
    defs = [f'<clipPath id="shape"><path d="{squircle_path()}"/></clipPath>',
            lin("bg", 512, 0, 512, 1024 * 0.78, [(0, cw["bg"][0]), (1, cw["bg"][1])]),
            '<filter id="drop" x="-20%" y="-20%" width="140%" height="140%">'
            '<feGaussianBlur stdDeviation="14"/></filter>']
    gd, gb = glow_fragment(concept, cw, "g")
    md, mb = mark_fragment(concept, cw, False, "m")
    defs += [gd, md]
    acc = ""
    if "accent" in concept:
        ad, ab = accent_fragment(concept, cw, False, "s")
        defs.append(ad)
        acc = ab
    body = (f'<title>Vela icon concept: {title}</title>\n'
            f'<path d="{squircle_path(824, 100, 108)}" fill="#000" opacity="0.30" filter="url(#drop)"/>\n'
            f'<g transform="translate(100 100) scale({k:.6f})">\n'
            f'<g clip-path="url(#shape)">\n<rect width="1024" height="1024" fill="url(#bg)"/>\n{gb}\n</g>\n'
            f'{mb}\n{acc}\n</g>')
    open(path, "w").write(svg_doc(body, "".join(defs)))

# --------------------------------------------------------------------------
# Website favicon: Glint's V and star with no tile, on the browser's own tab
# colour. Bolder than the icon so it holds up at 16 px: a thicker stroke and a
# bigger, fuller star, which still clears the arms. The box puts the V's top
# edge on a whole pixel at 16 and 32 px, and the V is 15/16 of the width.
# --------------------------------------------------------------------------
FAVICON = dict(
    stroke=150, star_r=64, star_waist=0.28, star_stretch=1.15,
    # (V point, V top, star)
    light=("#1A6FB8", "#0A3E7A", "#1A6FB8"),   # Paper's deep blues, for light tabs
    dark=("#B4FAF4", "#34C6E6", "#FFFFFF"),    # the Vela V and star, for dark tabs
    # PNG and ICO can't follow the browser's appearance: one mid blue from
    # both ramps, about 3:1 or better against white and dark-grey tabs.
    flat=("#2296DA", "#1D7FC8", "#2296DA"),
)

def favicon_svg(adaptive):
    fv = FAVICON
    v = concept_glint(t=fv["stroke"])["pieces"][0][1]
    nums = [float(n) for n in v.replace("M", " ").replace("L", " ").replace("Z", " ").split()]
    xs, ys = nums[0::2], nums[1::2]
    side = (max(xs) - min(xs)) * 16 / 15
    x0, y0 = C - side / 2, min(ys) - side / 16
    r, stretch = fv["star_r"], fv["star_stretch"]
    star = star_path(C, max(292.0, y0 + r * stretch + 0.5), r, fv["star_waist"], stretch)

    def grad(gid, pair):
        return lin(gid, 512, max(ys), 512, min(ys), [(0, pair[0]), (1, pair[1])])
    if adaptive:
        light, dark = fv["light"], fv["dark"]
        defs = grad("l", light) + grad("d", dark)
        style = (f'<style>.v{{fill:url(#l)}}.s{{fill:{light[2]}}}'
                 f'@media (prefers-color-scheme:dark){{.v{{fill:url(#d)}}.s{{fill:{dark[2]}}}}}</style>')
        paths = f'<path class="v" d="{v}"/><path class="s" d="{star}"/>'
    else:
        flat = fv["flat"]
        defs, style = grad("f", flat), ""
        paths = f'<path d="{v}" fill="url(#f)"/><path d="{star}" fill="{flat[2]}"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:.2f} {y0:.2f} {side:.2f} {side:.2f}">'
            f'{style}<defs>{defs}</defs>{paths}</svg>\n')

def write_favicon(path, flat_path):
    """favicon.svg follows the browser's light or dark mode; flat_path is for rasterizing."""
    open(path, "w").write(favicon_svg(True))
    open(flat_path, "w").write(favicon_svg(False))

def main():
    only = os.environ.get("ONLY")
    manifest = []
    for letter, key, title, fn in CONCEPTS:
        if only and letter not in only:
            continue
        concept = fn()
        d = os.path.join(OUT, f"{letter}-{key}")
        os.makedirs(d, exist_ok=True)
        cw = COLORWAYS["vela"]
        write_icon(os.path.join(d, f"{letter}-{key}.icon"), concept, cw, key)
        write_flat_svg(os.path.join(d, f"{letter}-{key}.svg"), concept, cw, f"{letter} {title}")
        manifest.append(dict(id=f"{letter}-{key}", letter=letter, title=title, dir=d,
                             notes={k2: round(v, 1) if isinstance(v, float) else v for k2, v in concept["notes"].items()}))
    finalists = os.environ.get("FINALISTS", "")
    for letter, key, title, fn in CONCEPTS:
        if letter not in finalists:
            continue
        concept = fn()
        d = os.path.join(OUT, "alternates", f"{letter}-{key}")
        os.makedirs(d, exist_ok=True)
        for cwkey, cw in COLORWAYS.items():
            name = f"{letter}-{key}-{cwkey}"
            write_icon(os.path.join(d, name + ".icon"), concept, cw, key)
            write_flat_svg(os.path.join(d, name + ".svg"), concept, cw, f"{letter} {title}, {cw['title']}")
    json.dump(manifest, open(os.path.join(OUT, "src", "manifest.json"), "w"), indent=2)
    json.dump({k: v["title"] for k, v in COLORWAYS.items()},
              open(os.path.join(OUT, "src", "colorways.json"), "w"), indent=2)
    for m in manifest:
        print(m["id"], m["notes"])

def write_one(letter, cwkey, path):
    """Writes one concept in one colourway as an Icon Composer document."""
    for L, key, _title, fn in CONCEPTS:
        if L == letter:
            write_icon(path, fn(), COLORWAYS[cwkey], key)
            return
    raise SystemExit(f"unknown concept {letter!r}")

if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "--icon":
        write_one(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) == 4 and sys.argv[1] == "--favicon":
        write_favicon(sys.argv[2], sys.argv[3])
    else:
        main()
