"""Renders every app icon variant Fussel can switch to (Closet > App Icon).

Usage: python3 design/render-icon-variants.py Resources/AppIcons
Needs Pillow and numpy. Produces 1024x1024 PNGs on the macOS icon grid.
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/AppIcons"
os.makedirs(OUT, exist_ok=True)

CANVAS, SHAPE, MARGIN, N = 1024, 824, 100, 5.0
SS = 2  # supersampling
FLUFF = [(50, 52, 16), (64, 52, 9), (59.9, 61.9, 9), (50, 66, 9), (40.1, 61.9, 9),
         (36, 52, 9), (40.1, 42.1, 9), (50, 38, 9), (59.9, 42.1, 9)]
EYES = [(45, 51), (55, 51)]
THETA = math.radians(-10)


def hexc(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def tf(x, y):
    cx, cy = 50, 52
    dx, dy = x - cx, y - cy
    return (cx + dx * math.cos(THETA) - dy * math.sin(THETA) + 4,
            cy + dx * math.sin(THETA) + dy * math.cos(THETA) - 6)


def squircle(size, off, steps=1440):
    a = size / 2
    c = off + a
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        pts.append((c + a * math.copysign(abs(ct) ** (2 / N), ct), c + a * math.copysign(abs(st) ** (2 / N), st)))
    return pts


class Painter:
    def __init__(self):
        self.W = CANVAS * SS
        self.k = self.W / CANVAS
        self.off = MARGIN * self.k
        self.s = SHAPE * self.k / 100
        self.img = Image.new("RGBA", (self.W, self.W), (0, 0, 0, 0))

    def X(self, v):
        return self.off + v * self.s

    def layer(self, draw_fn, color):
        m = Image.new("L", self.img.size, 0)
        draw_fn(ImageDraw.Draw(m), self)
        col = Image.new("RGBA", self.img.size, color[:3] + (0,))
        col.putalpha(m.point(lambda a: int(a * color[3] / 255)))
        self.img = Image.alpha_composite(self.img, col)

    def gradient(self, stops, angle_deg=90):
        """Vertical-ish gradient over the whole canvas. stops: [(t, hex)]"""
        W = self.W
        ys, xs = np.mgrid[0:W, 0:W].astype(np.float32) / W
        a = math.radians(angle_deg)
        t = np.clip(xs * math.cos(a) * 0 + ys * math.sin(a) + xs * math.cos(a), 0, 1) if angle_deg != 90 else ys
        out = np.zeros((W, W, 3), np.float32)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            c0 = np.array(hexc(c0)[:3], np.float32)
            c1 = np.array(hexc(c1)[:3], np.float32)
            m = (t >= t0) & (t <= t1)
            f = ((t - t0) / max(1e-6, t1 - t0))[..., None]
            out = np.where(m[..., None], c0 * (1 - f) + c1 * f, out)
        rgba = np.dstack([out, np.full((W, W), 255, np.float32)]).astype(np.uint8)
        self.img = Image.alpha_composite(self.img, Image.fromarray(rgba, "RGBA"))

    def glow(self, cx, cy, r, alpha):
        W = self.W
        ys, xs = np.mgrid[0:W, 0:W].astype(np.float32)
        d = np.sqrt((xs - self.X(cx)) ** 2 + (ys - self.X(cy)) ** 2) / (r * self.s)
        a = np.clip(1 - d, 0, 1) ** 1.5 * alpha
        rgba = np.zeros((W, W, 4), np.uint8)
        rgba[..., :3] = 255
        rgba[..., 3] = (a * 255).astype(np.uint8)
        self.img = Image.alpha_composite(self.img, Image.fromarray(rgba, "RGBA"))

    def finish(self, path):
        mask = Image.new("L", self.img.size, 0)
        ImageDraw.Draw(mask).polygon(squircle(SHAPE * self.k, self.off), fill=255)
        body = self.img.copy()
        body.putalpha(Image.composite(body.getchannel("A"), Image.new("L", body.size, 0), mask))
        shadow = Image.new("RGBA", body.size, (0, 0, 0, 0))
        sm = mask.filter(ImageFilter.GaussianBlur(10 * self.k)).point(lambda a: int(a * 0.3))
        shifted = Image.new("L", body.size, 0)
        shifted.paste(sm, (0, int(10 * self.k)))
        shadow.putalpha(shifted)
        final = Image.alpha_composite(shadow, body).resize((CANVAS, CANVAS), Image.LANCZOS)
        final.save(path, optimize=True)


def ellipse(d, p, cx, cy, rx, ry=None):
    ry = rx if ry is None else ry
    d.ellipse([p.X(cx - rx), p.X(cy - ry), p.X(cx + rx), p.X(cy + ry)], fill=255)


def fluff_shape(d, p, dy=0):
    for x, y, r in FLUFF:
        fx, fy = tf(x, y)
        ellipse(d, p, fx, fy + dy, r)


def poly(d, p, pts):
    d.polygon([(p.X(x), p.X(y)) for x, y in pts], fill=255)


def rot(points):
    return [tf(x, y) for x, y in points]


def face(p, eye="#2B2B33", shine=True, blush=False, glasses=False):
    if blush:
        for cx in (40.5, 59.5):
            x, y = tf(cx, 56.5)
            p.layer(lambda d, p, x=x, y=y: ellipse(d, p, x, y, 2.4), hexc("#F6A795", 190))
    if glasses:
        for ex in (45, 55):
            pts = rot([(ex - 4.3, 48.2), (ex + 4.3, 48.2), (ex + 3.6, 54.2), (ex - 3.6, 54.2)])
            p.layer(lambda d, p, pts=pts: poly(d, p, pts), hexc("#1F1F26"))
        bridge = rot([(48.6, 49.2), (51.4, 49.2), (51.4, 50.2), (48.6, 50.2)])
        p.layer(lambda d, p: poly(d, p, bridge), hexc("#1F1F26"))
        for ex in (45, 55):
            pts = rot([(ex - 2.8, 49.2), (ex - 1.2, 49.2), (ex - 2.2, 52.4), (ex - 3.2, 52.4)])
            p.layer(lambda d, p, pts=pts: poly(d, p, pts), hexc("#FFFFFF", 150))
        return
    for ex, ey in EYES:
        x, y = tf(ex, ey)
        p.layer(lambda d, p, x=x, y=y: ellipse(d, p, x, y, 2.6), hexc(eye))
        if shine:
            sx, sy = tf(ex - 0.8, ey - 0.9)
            p.layer(lambda d, p, x=sx, y=sy: ellipse(d, p, x, y, 0.8), hexc("#FFFFFF"))


def shadow(p, color="#7A2E20", a=46):
    p.layer(lambda d, p: ellipse(d, p, 48, 83, 13, 2.8), hexc(color, a))


def body(p, color="#FFFFFF", a=255):
    p.layer(lambda d, p: fluff_shape(d, p), hexc(color, a))


def hat(p, kind):
    if kind == "santa":
        cone = rot([(37, 36), (63, 35), (66, 22), (71, 13), (60, 20), (48, 24)])
        p.layer(lambda d, p: poly(d, p, cone), hexc("#E5484D"))
        band = rot([(35, 33.5), (65, 32.5), (65.5, 38.5), (35.5, 39.5)])
        p.layer(lambda d, p: poly(d, p, band), hexc("#FFFFFF"))
        x, y = tf(71, 13)
        p.layer(lambda d, p: ellipse(d, p, x, y, 3.6), hexc("#FFFFFF"))
    elif kind == "witch":
        x, y = tf(50, 34)
        p.layer(lambda d, p: ellipse(d, p, x, y, 19, 3.8), hexc("#3B2466"))
        cone = rot([(40, 34), (60, 34), (56, 22), (60, 8), (50, 18)])
        p.layer(lambda d, p: poly(d, p, cone), hexc("#4B2E83"))
        band = rot([(40.5, 30.5), (59.5, 30.5), (59, 33.5), (41, 33.5)])
        p.layer(lambda d, p: poly(d, p, band), hexc("#F5A524"))
    elif kind == "party":
        cone = rot([(42, 34), (58, 34), (50, 12)])
        p.layer(lambda d, p: poly(d, p, cone), hexc("#7CC4F2"))
        for t0 in (0.25, 0.55):
            a = rot([(42 + 8 * t0 * 2 * 0.5, 34 - 22 * t0), (58 - 8 * t0, 34 - 22 * t0),
                     (58 - 8 * (t0 + 0.12), 34 - 22 * (t0 + 0.12)), (42 + 8 * (t0 + 0.12), 34 - 22 * (t0 + 0.12))])
            p.layer(lambda d, p, a=a: poly(d, p, a), hexc("#F9E3A0"))
        x, y = tf(50, 11)
        p.layer(lambda d, p: ellipse(d, p, x, y, 3), hexc("#F2836B"))
    elif kind == "crown":
        crown = rot([(39, 35), (61, 35), (62, 22), (56.5, 28), (50, 19), (43.5, 28), (38, 22)])
        p.layer(lambda d, p: poly(d, p, crown), hexc("#F5C542"))
        for gx in (44, 50, 56):
            x, y = tf(gx, 31.5)
            p.layer(lambda d, p, x=x, y=y: ellipse(d, p, x, y, 1.4), hexc("#E5484D" if gx == 50 else "#7CC4F2"))


def standard(name, bg_stops, eye="#2B2B33", body_color="#FFFFFF", body_alpha=255, shadow_color="#7A2E20",
             shadow_alpha=46, costume=None, blush=False, extra=None):
    p = Painter()
    p.gradient(bg_stops)
    if extra:
        extra(p)
    shadow(p, shadow_color, shadow_alpha)
    body(p, body_color, body_alpha)
    face(p, eye=eye, blush=blush or costume in ("santa", "party"), glasses=(costume == "sunglasses"))
    if costume and costume != "sunglasses":
        hat(p, costume)
    p.finish(os.path.join(OUT, name + ".png"))
    print("rendered", name)


CORAL = [(0, "#F69A84"), (1, "#EC6E56")]

standard("pur", CORAL)


def plastisch_extra(p):
    pass


def render_plastisch():
    p = Painter()
    p.gradient([(0, "#F8A28C"), (1, "#E9654D")])
    sh = Image.new("L", p.img.size, 0)
    ellipse(ImageDraw.Draw(sh), p, 48, 83, 14, 3.2)
    sh = sh.filter(ImageFilter.GaussianBlur(14 * p.k))
    col = Image.new("RGBA", p.img.size, (110, 36, 22, 0))
    col.putalpha(sh.point(lambda a: int(a * 0.35)))
    p.img = Image.alpha_composite(p.img, col)
    # underside shade, then a softly lit body
    p.layer(lambda d, p: fluff_shape(d, p, dy=1.6), hexc("#D9C4BD"))
    body_mask = Image.new("L", p.img.size, 0)
    fluff_shape(ImageDraw.Draw(body_mask), p)
    W = p.W
    ys, xs = np.mgrid[0:W, 0:W].astype(np.float32)
    cx, cy = p.X(46), p.X(40)
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / (30 * p.s)
    t = np.clip(d, 0, 1)[..., None]
    c0 = np.array([255, 255, 255], np.float32)
    c1 = np.array([235, 221, 216], np.float32)
    rgb = (c0 * (1 - t) + c1 * t).astype(np.uint8)
    lit = Image.fromarray(np.dstack([rgb, np.array(body_mask)]), "RGBA")
    p.img = Image.alpha_composite(p.img, lit)
    face(p, blush=True)
    p.finish(os.path.join(OUT, "plastisch.png"))
    print("rendered plastisch")


render_plastisch()
standard("glas", [(0, "#FFA07C"), (1, "#FF5436")], body_alpha=210,
         extra=lambda p: p.glow(22, 14, 70, 0.4))
standard("abendhimmel", [(0, "#9483C9"), (0.55, "#F2836B"), (1, "#F8C9A2")], shadow_alpha=40)
standard("dark", [(0, "#33364F"), (1, "#1B1C2B")], eye="#23253A", body_color="#F4F1EC",
         shadow_color="#000000", shadow_alpha=100)
standard("tinted", [(0, "#5E6069"), (1, "#36373E")], eye="#36373E", body_alpha=235,
         shadow_color="#000000", shadow_alpha=76)
for costume in ("santa", "witch", "party", "sunglasses", "crown"):
    standard(costume, CORAL, costume=costume)
