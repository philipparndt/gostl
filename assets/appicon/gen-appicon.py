#!/usr/bin/env python3
"""Generate the GoSTL app-icon masters as SVG.

The mark is a faceted solid — a stand-in for the triangle mesh every STL is —
with its right half switched to wireframe, mirroring the app's wireframe
toggle. Left half solid, right half see-through, one light from the upper left.

The geometry is computed rather than hand-drawn. The facet shading depends on
a single light direction, and hand-authored path data drifts out of agreement
with it as soon as anything moves.

Three masters are emitted rather than one, because a wireframe that reads at
512 px is invisible at 16 px:

    AppIcon.svg        full detail          128 px and up
    AppIcon-medium.svg heavier wire, no seams   64 px
    AppIcon-small.svg  two-tone, no fine lines  16 and 32 px

make-icns.sh maps each master onto the sizes it is drawn for.

Usage: python3 gen-appicon.py     (writes the three .svg files beside itself)
"""
import math
import pathlib

# The artwork is authored on a 200-unit square and scaled into the icon tile,
# so every stroke width below is in artboard units, not pixels.
ART = 200.0
C = ART / 2.0

CANVAS = 1024.0          # what .icns wants at the largest size
BODY = 824.0             # the tile itself; the rest is margin macOS expects
MARGIN = (CANVAS - BODY) / 2.0

CREAM = "#EDE6D2"        # the renderer's unlit-mesh colour
BLUE = "#3498DB"         # AxisColors.z
GROUND_TOP = "#1C2230"   # the dark-theme viewport, lifted slightly
GROUND_BOT = "#0C0F16"


def squircle(n=5.0, r=100.0, steps=192):
    """Superellipse |x/r|^n + |y/r|^n = 1 — the continuous-corner shape macOS
    uses, as opposed to a rounded rect's circular corners."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = math.copysign(abs(ct) ** (2.0 / n), ct) * r
        y = math.copysign(abs(st) ** (2.0 / n), st) * r
        pts.append((C + x, C + y))
    return "M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + "Z"


def shade(hexcol, factor):
    """Multiply a hex colour toward black (factor < 1) or white (factor > 1)."""
    h = hexcol.lstrip("#")
    rgb = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    if factor <= 1:
        out = [v * factor for v in rgb]
    else:
        out = [v + (255 - v) * (factor - 1) for v in rgb]
    return "#" + "".join(f"{max(0, min(255, int(round(v)))):02X}" for v in out)


def poly(pts, fill):
    d = " ".join(f"{x:.2f},{y:.2f}" for x, y in pts)
    return f'<polygon points="{d}" fill="{fill}"/>'


def path(pts, close=True, **kw):
    d = "M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + ("Z" if close else "")
    attrs = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in kw.items())
    return f'<path d="{d}" {attrs}/>'


R = 70.0                 # ball radius, in artboard units
LIGHT = (-0.5, -0.78)    # upper-left


def ring_points():
    outer = [(C + R * math.cos(math.radians(a)), C + R * math.sin(math.radians(a)))
             for a in range(-90, 270, 60)]
    r2 = R * 0.50
    inner = [(C + r2 * math.cos(math.radians(a)), C + r2 * math.sin(math.radians(a)))
             for a in range(-60, 300, 60)]
    return outer, inner


def lit(face, lo, span):
    """Shade a facet by the angle between its outward direction and the light."""
    mx = sum(p[0] for p in face) / 3 - C
    my = sum(p[1] for p in face) / 3 - C
    n = math.hypot(mx, my) or 1
    d = (mx / n) * LIGHT[0] + (my / n) * LIGHT[1]
    return shade(CREAM, lo + span * max(0.0, (d + 1) / 2))


def solid_half(seams=True):
    """The left half of the ball: faceted and lit."""
    outer, inner = ring_points()
    out = []
    for i in range(6):
        for f in ([outer[i], outer[(i + 1) % 6], inner[i]],
                  [outer[i], inner[i], inner[(i - 1) % 6]]):
            out.append(poly(f, lit(f, 0.42, 0.80)))
    for i in range(6):
        f = [inner[i], inner[(i + 1) % 6], (C, C)]
        out.append(poly(f, lit(f, 0.86, 0.30)))
    if seams:
        for i in range(6):
            out.append(path([outer[i], inner[i]], close=False, stroke="#0F1219",
                            stroke_opacity="0.13", stroke_width="1.2"))
            out.append(path([outer[i], inner[(i - 1) % 6]], close=False,
                            stroke="#0F1219", stroke_opacity="0.13",
                            stroke_width="1.2"))
        out.append(path(inner, stroke="#0F1219", stroke_opacity="0.13",
                        stroke_width="1.2", fill="none"))
    return "\n".join(out)


def wire_half(w_outer, w_inner, spokes=True, rings=2):
    """The right half: the same solid, drawn as edges only.

    Widths are the width you actually see. SVG strokes straddle their path,
    so an outline stroked on the silhouette would stand half its width proud
    of it, while the solid half is filled flush to the same line — the two
    halves would then meet at the seam with the wireframe visibly the larger
    shape. The group is clipped to the silhouette and the strokes doubled, so
    the outer edge of the drawn line lands exactly on the outer edge of the
    fill and both halves describe one hexagon.
    """
    outer, inner = ring_points()
    out = [path(outer, stroke=BLUE, stroke_width=w_outer * 2, fill="none",
                stroke_linejoin="round")]
    if rings > 1:
        out.append(path(inner, stroke=BLUE, stroke_opacity="0.78",
                        stroke_width=w_inner, fill="none",
                        stroke_linejoin="round"))
    if spokes:
        for i in range(6):
            out.append(path([outer[i], inner[i]], close=False, stroke=BLUE,
                            stroke_opacity="0.78", stroke_width=w_inner,
                            fill="none"))
            out.append(path([outer[i], inner[(i - 1) % 6]], close=False,
                            stroke=BLUE, stroke_opacity="0.78",
                            stroke_width=w_inner, fill="none"))
    return f'<g clip-path="url(#ball)">{"".join(out)}</g>'


def artwork(detail):
    if detail == "full":
        left, right = solid_half(), wire_half(2.4, 2.0)
    elif detail == "medium":
        left, right = solid_half(seams=False), wire_half(5.0, 5.0)
    else:
        # 16 and 32 px. The facets stay — they are the mark — but the spokes
        # go: a stroke heavy enough to survive here is also heavy enough that
        # six radial lines close the gaps and the half fills in as a solid
        # crescent, which loses the only thing the right half is there to say.
        left, right = solid_half(seams=False), wire_half(8.0, 7.0, spokes=False)
    return (f'<g clip-path="url(#half-left)">{left}</g>'
            f'<g clip-path="url(#half-right)">{right}</g>')


def master(detail):
    sc = BODY / ART
    ball = " ".join(f"{x:.2f},{y:.2f}" for x, y in ring_points()[0])
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!-- Generated by assets/appicon/gen-appicon.py — do not edit by hand. -->
<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS:.0f}" height="{CANVAS:.0f}"
     viewBox="0 0 {CANVAS:.0f} {CANVAS:.0f}">
  <defs>
    <clipPath id="tile"><path d="{squircle()}"/></clipPath>
    <clipPath id="half-left"><rect x="0" y="0" width="{C}" height="{ART}"/></clipPath>
    <clipPath id="half-right"><rect x="{C}" y="0" width="{C}" height="{ART}"/></clipPath>
    <clipPath id="ball"><polygon points="{ball}"/></clipPath>
    <linearGradient id="ground" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{GROUND_TOP}"/>
      <stop offset="1" stop-color="{GROUND_BOT}"/>
    </linearGradient>
    <filter id="tileShadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="{CANVAS * 0.012:.1f}" stdDeviation="{CANVAS * 0.014:.1f}"
                    flood-color="#000000" flood-opacity="0.30"/>
    </filter>
  </defs>
  <g transform="translate({MARGIN:.1f},{MARGIN:.1f}) scale({sc:.6f})" filter="url(#tileShadow)">
    <g clip-path="url(#tile)">
      <rect x="0" y="0" width="{ART}" height="{ART}" fill="url(#ground)"/>
      {artwork(detail)}
    </g>
  </g>
</svg>
'''


if __name__ == "__main__":
    here = pathlib.Path(__file__).parent
    for detail, name in (("full", "AppIcon.svg"),
                         ("medium", "AppIcon-medium.svg"),
                         ("small", "AppIcon-small.svg")):
        (here / name).write_text(master(detail))
        print(f"wrote {name}")
