#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Vela "Horizon Sail" — writes the glass sail SVGs that form the V.

Two asymmetric glass panels meet at a single point that rests on the glowing
horizon, exactly where the sun is rising:

  left  - a slim, taut panel with straight, mast-like edges;
  right - a broad sail whose outer edge (leech) bellies out, filled by solar
          wind, and whose top edge (head) is pulled slightly hollow so it
          ends in a sharp, flying clew.

Both are lit from below by the sunrise: bright aqua-white at the point,
deepening to cyan/azure at the top, with a bright rim along the inner edges
that face the notch.  Faint sheen bands and two seams follow the right
panel's belly so it reads as a billowing membrane.

Also writes *-mono.svg (bright neutral fills used for the Clear/Tinted
appearances) and gen/derived.json (point, notch and ray direction, read by
gen/space.swift so the sun and ray stay under the V).

Usage: python3 -I gen/sails.py <Assets dir> [params.json]
"""
import json, math, os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HERE = os.path.dirname(os.path.abspath(__file__))
PARAMS = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "params.json")
P = json.load(open(PARAMS))

PT0 = tuple(P["point"])
SCALE, SHIFT = P["scale"], P["shiftX"]


def tf(p):
    """Scale about the nominal point, then shift horizontally."""
    return (PT0[0] + (p[0] - PT0[0]) * SCALE + SHIFT, PT0[1] + (p[1] - PT0[1]) * SCALE)


B = tf(PT0)                       # the V's point (shared by both panels)
N = tf(P["notch"])                # notch vertex (inner edges meet)
TLo, TLi = tf(P["left"]["outerTop"]), tf(P["left"]["innerTop"])
R = P["right"]
TRi, HC, TRo = tf(R["head"]), tf(R["headCtrl"]), tf(R["clew"])
BL1, BL2 = tf(R["belly1"]), tf(R["belly2"])
FIL = P.get("fillet", 10) * SCALE
SEAMS = P.get("seams", True)


def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
def unit(v):
    n = math.hypot(*v); return (v[0] / n, v[1] / n)
def toward(a, b, d):
    u = unit((b[0] - a[0], b[1] - a[1])); return (a[0] + u[0] * d, a[1] + u[1] * d)
def quad(a, c, b, t):
    u = 1 - t
    return (u*u*a[0] + 2*u*t*c[0] + t*t*b[0], u*u*a[1] + 2*u*t*c[1] + t*t*b[1])
def cubic(a, c1, c2, b, t):
    u = 1 - t
    return tuple(u**3*a[i] + 3*u*u*t*c1[i] + 3*u*t*t*c2[i] + t**3*b[i] for i in (0, 1))
def f(p): return f"{p[0]:.1f} {p[1]:.1f}"
def stops(lst):
    return "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in lst)


# ---- outlines -------------------------------------------------------------
# left: point -> outer top -> inner top -> notch (all straight, small fillets)
a1, a2 = toward(TLo, B, FIL), toward(TLo, TLi, FIL)
b1, b2 = toward(TLi, TLo, FIL), toward(TLi, N, FIL)
LEFT_D = (f"M {f(B)} L {f(a1)} Q {f(TLo)} {f(a2)} L {f(b1)} Q {f(TLi)} {f(b2)} "
          f"L {f(N)} Z")
# right: notch -> head (inner top) -> hollow head edge -> clew -> belly -> point
h1, h2 = toward(TRi, N, FIL), toward(TRi, HC, FIL)
k1, k2 = toward(TRo, HC, FIL * 0.45), toward(TRo, BL1, FIL * 0.45)   # clew stays sharp
RIGHT_D = (f"M {f(N)} L {f(h1)} Q {f(TRi)} {f(h2)} Q {f(HC)} {f(k1)} "
           f"Q {f(TRo)} {f(k2)} C {f(BL1)} {f(BL2)} {f(B)} Z")

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'


def rim_sliver(bottom, top, inside, w_top, w_bot, gid, a_bot=0.95, a_top=0.45):
    """Thin bright wedge along an inner edge, brightest near the sun (bottom)."""
    d = unit((top[0] - bottom[0], top[1] - bottom[1]))
    n = (-d[1], d[0])
    if (inside[0] - top[0]) * n[0] + (inside[1] - top[1]) * n[1] < 0:
        n = (-n[0], -n[1])
    t0 = toward(top, bottom, FIL * 1.6)
    p3 = (t0[0] + n[0] * w_top, t0[1] + n[1] * w_top)
    p4 = (bottom[0] + n[0] * w_bot, bottom[1] + n[1] * w_bot)
    grad = (f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{bottom[0]:.1f}" y1="{bottom[1]:.1f}" '
            f'x2="{t0[0]:.1f}" y2="{t0[1]:.1f}">' +
            stops([(0, "#FFFFFF", a_bot), (0.5, "#E8FFFC", (a_bot + a_top) / 2), (1, "#FFFFFF", a_top)]) +
            '</linearGradient>')
    return grad, f'<path d="M {f(bottom)} L {f(t0)} L {f(p3)} L {f(p4)} Z" fill="url(#{gid})"/>'


# ---- right panel: billow shading -------------------------------------------
TOPR = lerp(TRi, TRo, 0.5)
BC = (B[0] - 180 * SCALE, B[1] - 280 * SCALE)     # centre of the belly bands
BR = 600 * SCALE                                   # radius reaching the leech
seams_defs, seams = "", ""
if SEAMS:
    for k, (t, bow) in enumerate(((0.38, 34), (0.72, 58))):
        H = quad(TRi, HC, TRo, t)
        start = lerp(N, B, 0.45)
        mid = lerp(start, H, 0.5)
        ctrl = (mid[0] + bow * SCALE, mid[1] + bow * 0.25 * SCALE)
        s0 = lerp(start, H, 0.10)
        seams_defs += (f'<linearGradient id="s{k}" gradientUnits="userSpaceOnUse" x1="{s0[0]:.1f}" y1="{s0[1]:.1f}" '
                       f'x2="{H[0]:.1f}" y2="{H[1]:.1f}">' +
                       stops([(0, "#FFFFFF", 0.0), (0.3, "#E6FFFC", 0.20), (0.8, "#E6FFFC", 0.22), (1, "#FFFFFF", 0.08)]) +
                       '</linearGradient>')
        seams += f'<path d="M {f(s0)} Q {f(ctrl)} {f(H)}" fill="none" stroke="url(#s{k})" stroke-width="3"/>'

r_rim = rim_sliver(N, TRi, TRo, 6.0, 3.0, "rim")

right = HEAD + f'''<defs>
<linearGradient id="body" gradientUnits="userSpaceOnUse" x1="{B[0]:.1f}" y1="{B[1]:.1f}" x2="{TOPR[0]:.1f}" y2="{TOPR[1]:.1f}">{stops([
    (0, "#B4FAF4", 1), (0.16, "#66E6EE", 1), (0.5, "#34C6E6", 1), (0.82, "#24A8DE", 1), (1, "#2AA2E0", 1)])}</linearGradient>
<radialGradient id="billow" gradientUnits="userSpaceOnUse" cx="{BC[0]:.1f}" cy="{BC[1]:.1f}" r="{BR:.1f}">{stops([
    (0, "#0A3E7A", 0), (0.40, "#0A3E7A", 0.0), (0.50, "#0A3E7A", 0.26), (0.63, "#0A3E7A", 0.0),
    (0.72, "#E8FFFC", 0.0), (0.81, "#E8FFFC", 0.38), (0.90, "#E8FFFC", 0.0), (1, "#062C66", 0.30)])}</radialGradient>
<radialGradient id="sun" gradientUnits="userSpaceOnUse" cx="{B[0]:.1f}" cy="{B[1] + 20:.1f}" r="{430 * SCALE:.1f}">{stops([
    (0, "#F2FFFD", 0.60), (0.35, "#BFF8F6", 0.22), (1, "#BFF8F6", 0)])}</radialGradient>
{r_rim[0]}
{seams_defs}
</defs>
<path d="{RIGHT_D}" fill="url(#body)"/>
<path d="{RIGHT_D}" fill="url(#billow)"/>
<path d="{RIGHT_D}" fill="url(#sun)"/>
{seams}
{r_rim[1]}
</svg>
'''

# ---- left panel: slim, taut, slightly cooler ------------------------------
TOPL = lerp(TLo, TLi, 0.5)
l_rim = rim_sliver(N, TLi, TLo, 5.0, 2.5, "rim")
left = HEAD + f'''<defs>
<linearGradient id="body" gradientUnits="userSpaceOnUse" x1="{B[0]:.1f}" y1="{B[1]:.1f}" x2="{TOPL[0]:.1f}" y2="{TOPL[1]:.1f}">{stops([
    (0, "#A6F6F0", 1), (0.18, "#4AD4E6", 1), (0.58, "#22ACDC", 1), (1, "#2296DA", 1)])}</linearGradient>
<linearGradient id="taut" gradientUnits="userSpaceOnUse" x1="{TLi[0]:.1f}" y1="{TLi[1]:.1f}" x2="{TLo[0]:.1f}" y2="{TLo[1]:.1f}">{stops([
    (0, "#E8FFFC", 0.20), (0.5, "#E8FFFC", 0.0), (1, "#062C66", 0.18)])}</linearGradient>
<radialGradient id="sun" gradientUnits="userSpaceOnUse" cx="{B[0]:.1f}" cy="{B[1] + 20:.1f}" r="{430 * SCALE:.1f}">{stops([
    (0, "#F2FFFD", 0.55), (0.35, "#BFF8F6", 0.20), (1, "#BFF8F6", 0)])}</radialGradient>
{l_rim[0]}
</defs>
<path d="{LEFT_D}" fill="url(#body)"/>
<path d="{LEFT_D}" fill="url(#taut)"/>
<path d="{LEFT_D}" fill="url(#sun)"/>
{l_rim[1]}
</svg>
'''


# ---- mono versions for Clear / Tinted appearances --------------------------
def mono(d, a, b, extra_defs="", extra=""):
    return HEAD + f'''<defs>
<linearGradient id="m" gradientUnits="userSpaceOnUse" x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}">{stops([
    (0, "#FFFFFF", 1), (0.55, "#F2F4F6", 1), (1, "#DCE2E8", 1)])}</linearGradient>
{extra_defs}
</defs>
<path d="{d}" fill="url(#m)"/>
{extra}
</svg>
'''


mono_billow = (f'<radialGradient id="mb" gradientUnits="userSpaceOnUse" cx="{BC[0]:.1f}" cy="{BC[1]:.1f}" r="{BR:.1f}">' + stops([
    (0, "#8A96A8", 0), (0.40, "#8A96A8", 0), (0.50, "#8A96A8", 0.16), (0.62, "#8A96A8", 0),
    (0.82, "#FFFFFF", 0.4), (0.92, "#FFFFFF", 0), (1, "#8A96A8", 0.18)]) + '</radialGradient>')
right_mono = mono(RIGHT_D, B, TOPR, mono_billow + seams_defs, f'<path d="{RIGHT_D}" fill="url(#mb)"/>{seams}')
left_mono = mono(LEFT_D, B, TOPL)

os.makedirs(OUT, exist_ok=True)
for name, s in (("sail-right.svg", right), ("sail-left.svg", left),
                ("sail-right-mono.svg", right_mono), ("sail-left-mono.svg", left_mono)):
    with open(os.path.join(OUT, name), "w") as fh:
        fh.write(s)

# ---- derived geometry for the background + balance report -----------------
dl = unit((TLi[0] - N[0], TLi[1] - N[1]))
dr = unit((TRi[0] - N[0], TRi[1] - N[1]))
ray = unit((dl[0] + dr[0], dl[1] + dr[1]))       # notch bisector, pointing up



def poly_right_for_json(n=24):
    pts = [N, TRi] + [quad(TRi, HC, TRo, i / n) for i in range(1, n + 1)]
    return pts + [cubic(TRo, BL1, BL2, B, i / n) for i in range(1, n + 1)]


json.dump({"point": list(B), "notch": list(N), "rayDir": list(ray),
           "limbTop": P["limbTop"], "planetRadius": P["planetRadius"],
           # outlines, so the background keeps stars out from behind the glass
           "outlines": [[list(p) for p in poly_right_for_json()], [list(p) for p in (B, TLo, TLi, N)]]},
          open(os.path.join(HERE, "derived.json"), "w"), indent=2)


def poly_right(n=80):
    pts = [N, TRi] + [quad(TRi, HC, TRo, i / n) for i in range(1, n + 1)]
    pts += [cubic(TRo, BL1, BL2, B, i / n) for i in range(1, n + 1)]
    return pts


def centroid(pts):
    A = cx = cy = 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
        c = x0 * y1 - x1 * y0
        A += c; cx += (x0 + x1) * c; cy += (y0 + y1) * c
    return A / 2, cx / (3 * A), cy / (3 * A)


ar, rx, ry = centroid(poly_right())
al, lx, ly = centroid([B, TLo, TLi, N])
ar, al = abs(ar), abs(al)
allpts = poly_right() + [B, TLo, TLi, N]
xs, ys = [p[0] for p in allpts], [p[1] for p in allpts]
print(f"bbox x {min(xs):.0f}-{max(xs):.0f} (w {max(xs)-min(xs):.0f} = {100*(max(xs)-min(xs))/1024:.1f}%), "
      f"y {min(ys):.0f}-{max(ys):.0f}; bbox centre x {(min(xs)+max(xs))/2:.0f}; "
      f"area centroid x {(ar*rx + al*lx)/(ar+al):.0f}; point x {B[0]:.0f}; area R/L {ar/al:.2f}")
