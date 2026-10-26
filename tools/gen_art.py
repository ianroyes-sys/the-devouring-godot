#!/usr/bin/env python3
"""Procedural placeholder pixel art for The Devouring.

Generates parallax backdrop planes and rim-lit character silhouettes directly in the palettes
defined in docs/ART_DIRECTION.md, using real 4x4 Bayer ordered dithering rather than smooth
gradients. Output is intentionally in-style rather than generically "programmer art", so the game
reads as intentional during playtests — and carries zero third-party licensing exposure, which
matters because episodes 2+ are sold (brief 13.2).

Everything here is a placeholder in the sense that it is *swappable* (all paths flow through
src/stage/art_registry.gd), not in the sense that it looks unfinished.

    python3 tools/gen_art.py

Deterministic: a fixed seed means regenerating never silently changes the look of a scene.
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 480, 960
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG_DIR = os.path.join(ROOT, "assets", "bg")
CHAR_DIR = os.path.join(ROOT, "assets", "char")

SEED = 20260726

# --- palettes (mirror of docs/ART_DIRECTION.md 2) --------------------------------------------

PALETTES = {
    "ASHFALL":   dict(ramp=["#0d0810", "#1a1018", "#3a0d14", "#7a1520", "#b8322e", "#d9553a"],
                      accent="#ff9a3c", accent_hi="#ffd98a"),
    "DROWNED":   dict(ramp=["#070b1a", "#0e1730", "#1b2a52", "#2d4a86", "#4a7fc4", "#7fa9dd"],
                      accent="#5fe0e8", accent_hi="#b6f5f2"),
    "VIOLET":    dict(ramp=["#140a1f", "#26123a", "#3f1d5c", "#6b2f86", "#a34a9e", "#d97ab5"],
                      accent="#f2d7ff", accent_hi="#ffffff"),
    "BOGSHADE":  dict(ramp=["#101410", "#1b241c", "#2e3d2e", "#47593f", "#6b7d55", "#96a37c"],
                      accent="#c6cfa8", accent_hi="#e4e8cd"),
    "CRYPT":     dict(ramp=["#060608", "#121216", "#22222a", "#3a3a44", "#5c5c68", "#8a8a96"],
                      accent="#ffb45c", accent_hi="#ffd9a8"),
    "SNOWLIGHT": dict(ramp=["#0b0f18", "#182231", "#2c3a4d", "#4d5f75", "#8397ab", "#cdd8e2"],
                      accent="#e8f2ff", accent_hi="#ffffff"),
}

MAGIC_GLOW = "#5fe0e8"

BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def _bayer(n):
    """Recursively build an n x n ordered-dither matrix normalised to [0, 1).

    8x8 rather than 4x4 for skies: a 4x4 matrix only has 16 threshold levels, which over a
    500px-tall gradient produces visible 30px horizontal bands. The reference board's skies read
    as fine noise, not stripes, so we need the finer matrix.
    """
    m = [[0]]
    size = 1
    while size < n:
        m = [[4 * v for v in row] + [4 * v + 2 for v in row] for row in m] + \
            [[4 * v + 3 for v in row] + [4 * v + 1 for v in row] for row in m]
        size *= 2
    return [[v / float(n * n) for v in row] for row in m]


BAYER8 = _bayer(8)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def pal(name):
    p = PALETTES[name]
    return [rgb(c) for c in p["ramp"]], rgb(p["accent"]), rgb(p["accent_hi"])


# --- dithering --------------------------------------------------------------------------------

def dither_ramp(img, ramp, y0, y1, t0, t1, curve=1.0, jitter=0.14, seed=0):
    """Ordered-dither gradient across the *whole* palette ramp, not just two stops.

    This is the single most load-bearing function in the file. `t` walks a continuous position
    through the ramp; each pixel dithers between the two ramp entries it falls between. Because
    every 1/5th of the gradient only ever mixes two adjacent (and therefore similar) colours, the
    result reads as fine grain rather than the hard bands a two-colour dither produces.

    `jitter` adds a little per-pixel randomness to the threshold. Pure ordered dithering is
    visibly regular at these sizes; the board's skies have a slightly organic grain to them.
    """
    px = img.load()
    rnd = random.Random(SEED + seed)
    span = max(1, y1 - y0)
    top = len(ramp) - 1
    for y in range(max(0, y0), min(H, y1)):
        f = ((y - y0) / span) ** curve
        t = (t0 + (t1 - t0) * f) * top
        lo = int(math.floor(t))
        frac = t - lo
        lo = max(0, min(top, lo))
        hi = max(0, min(top, lo + 1))
        brow = BAYER8[y & 7]
        c_lo, c_hi = ramp[lo], ramp[hi]
        for x in range(W):
            thresh = brow[x & 7] + rnd.uniform(-jitter, jitter)
            px[x, y] = c_hi if frac > thresh else c_lo


def dither_vertical(img, top_color, bottom_color, y0, y1, curve=1.0):
    """Two-colour dithered gradient. Kept for small local transitions where a full ramp walk
    would be overkill."""
    px = img.load()
    span = max(1, y1 - y0)
    for y in range(max(0, y0), min(H, y1)):
        t = ((y - y0) / span) ** curve
        brow = BAYER8[y & 7]
        for x in range(W):
            px[x, y] = bottom_color if t > brow[x & 7] else top_color


def darken_toward(img, color, y0, y1, t0, t1, curve=1.0, seed=0):
    """Dithered fade of an existing region toward a colour.

    Used for the foreground crush: the board keeps roughly the bottom third of every frame close
    to black so the cast and UI read against it. Doing this as a dither rather than an alpha
    overlay keeps the palette count honest.
    """
    px = img.load()
    rnd = random.Random(SEED + seed + 991)
    span = max(1, y1 - y0)
    for y in range(max(0, y0), min(H, y1)):
        f = ((y - y0) / span) ** curve
        amt = t0 + (t1 - t0) * f
        brow = BAYER8[y & 7]
        for x in range(W):
            if amt > brow[x & 7] + rnd.uniform(-0.12, 0.12):
                src = px[x, y]
                if len(src) == 4 and src[3] == 0:
                    continue
                px[x, y] = color if len(src) == 3 else color + (src[3],)


def vignette(img, color, strength=0.75, seed=0):
    """Dithered corner falloff. Every pin on the board is darker at the edges than the centre —
    it's what focuses the eye on the one lit thing."""
    px = img.load()
    rnd = random.Random(SEED + seed + 555)
    cx, cy = W * 0.5, H * 0.46
    maxd = math.hypot(cx, cy)
    for y in range(H):
        brow = BAYER8[y & 7]
        for x in range(W):
            src = px[x, y]
            if len(src) == 4 and src[3] == 0:
                continue
            d = math.hypot(x - cx, y - cy) / maxd
            amt = max(0.0, (d - 0.42) / 0.58) ** 1.6 * strength
            if amt > brow[x & 7] + rnd.uniform(-0.10, 0.10):
                px[x, y] = color if len(src) == 3 else color + (src[3],)


def dither_band(img, color, y0, y1, density=0.35, seed_offset=0):
    """Horizontal haze band. Used between parallax planes for atmospheric separation."""
    px = img.load()
    rnd = random.Random(SEED + seed_offset)
    span = max(1, y1 - y0)
    for y in range(max(0, y0), min(H, y1)):
        # Fade the band out toward its edges so it doesn't read as a hard stripe.
        edge = 1.0 - abs(((y - y0) / span) * 2.0 - 1.0)
        local = density * edge
        brow = BAYER8[y & 7]
        for x in range(W):
            if brow[x & 7] < local and rnd.random() < 0.92:
                src = px[x, y]
                if len(src) == 4 and src[3] == 0:
                    continue
                px[x, y] = color if len(src) == 3 else color + (src[3],)


def dither_radial(img, cx, cy, radius, color, strength=1.0, squash=1.0, falloff=2.2):
    """Ordered-dither glow around a light source. One per frame, per art direction 3.

    `squash` stretches the glow horizontally (>1) so firelight behind a ridge spreads along the
    horizon instead of reading as a sun disc — the failure mode of the first pass at these
    backdrops. Call this *before* drawing the silhouettes that should occlude it.
    """
    px = img.load()
    rx = radius * squash
    x0, x1 = max(0, int(cx - rx)), min(W, int(cx + rx))
    y0, y1 = max(0, int(cy - radius)), min(H, int(cy + radius))
    for y in range(y0, y1):
        brow = BAYER8[y & 7]
        for x in range(x0, x1):
            d = math.hypot((x - cx) / squash, y - cy) / radius
            if d >= 1.0:
                continue
            f = (1.0 - d) ** falloff * strength
            if f > brow[x & 7]:
                src = px[x, y]
                if len(src) == 4 and src[3] == 0:
                    continue
                mixed = (
                    min(255, int(src[0] * (1 - f) + color[0] * f)),
                    min(255, int(src[1] * (1 - f) + color[1] * f)),
                    min(255, int(src[2] * (1 - f) + color[2] * f)),
                )
                px[x, y] = mixed if len(src) == 3 else mixed + (src[3],)


# --- silhouette primitives --------------------------------------------------------------------

def ridge_points(rnd, y_base, amplitude, roughness, jag=0.0):
    """Fractal ridge line across the full width. Mountains, treelines, rubble."""
    pts = [(0, y_base), (W, y_base)]
    step = W
    amp = amplitude
    while step > 3:
        new = [pts[0]]
        for i in range(len(pts) - 1):
            x0, y0 = pts[i]
            x1, y1 = pts[i + 1]
            mx = (x0 + x1) / 2.0
            my = (y0 + y1) / 2.0 + rnd.uniform(-amp, amp)
            new.append((mx, my))
            new.append((x1, y1))
        pts = new
        step /= 2.0
        amp *= roughness
    if jag > 0:
        pts = [(x, y + rnd.uniform(-jag, jag)) for x, y in pts]
    return pts


def fill_below(draw, pts, color):
    draw.polygon([(0, H)] + [(x, y) for x, y in pts] + [(W, H)], fill=color)


def spire(draw, x, base_y, width, height, color, cross=False):
    """A gothic tower/spire silhouette. The board's core architectural vocabulary."""
    half = width / 2.0
    draw.rectangle([x - half, base_y - height * 0.72, x + half, base_y], fill=color)
    draw.polygon([(x - half - 1, base_y - height * 0.72),
                  (x, base_y - height),
                  (x + half + 1, base_y - height * 0.72)], fill=color)
    if cross:
        top = base_y - height - 6
        draw.rectangle([x - 1, top, x + 1, base_y - height], fill=color)
        draw.rectangle([x - 4, top + 2, x + 4, top + 4], fill=color)


def grave_cross(draw, x, y, h, color, lean=0):
    draw.rectangle([x - 1 + lean, y - h, x + 1 + lean, y], fill=color)
    draw.rectangle([x - 5 + lean, y - int(h * 0.72), x + 5 + lean, y - int(h * 0.72) + 2], fill=color)


def planted_sword(draw, x, y, h, color, hi=None):
    """Recurring motif on the board: a sword driven into the ground."""
    draw.rectangle([x - 1, y - h, x + 1, y - int(h * 0.18)], fill=hi or color)
    draw.rectangle([x - 6, y - int(h * 0.22), x + 6, y - int(h * 0.19)], fill=color)
    draw.rectangle([x - 1, y - int(h * 0.19), x + 1, y], fill=color)


def dead_tree(draw, x, base_y, h, color, rnd):
    """Bare tree silhouette, grown recursively.

    The first pass at this drew a straight vertical line with straight spokes off it, which read
    unmistakably as a telephone pole. Trees need three things to read as trees: a trunk that leans
    and tapers, branches that *subdivide* rather than terminate, and upward bias at the tips.
    """
    # Trunk: a leaning, tapering polyline rather than a single stroke.
    lean = rnd.uniform(-0.16, 0.16)
    segs = 7
    trunk = []
    px_, py_ = float(x), float(base_y)
    for i in range(segs + 1):
        t = i / float(segs)
        trunk.append((px_, py_))
        px_ += lean * h / segs + rnd.uniform(-2.2, 2.2)
        py_ -= h / segs
    for i in range(segs):
        w = max(1, int(round(4.0 * (1.0 - i / float(segs)) + 1)))
        draw.line([trunk[i], trunk[i + 1]], fill=color, width=w)

    def branch(bx, by, ang, length, width, depth):
        if depth <= 0 or length < 3.0:
            return
        # Upward bias: dead branches still point at the sky.
        ang = ang * 0.82
        ex = bx + math.cos(ang) * length
        ey = by - abs(math.sin(ang)) * length * 0.55 - length * 0.45
        draw.line([(bx, by), (ex, ey)], fill=color, width=max(1, int(width)))
        forks = 2 if rnd.random() < 0.78 else 1
        for _ in range(forks):
            branch(ex, ey, ang + rnd.uniform(-0.85, 0.85), length * rnd.uniform(0.52, 0.72),
                   width - 1, depth - 1)

    # Branches start above the halfway point and alternate sides.
    for i in range(rnd.randint(4, 6)):
        t = rnd.uniform(0.42, 0.97)
        idx = min(segs, int(t * segs))
        bx, by = trunk[idx]
        side = 1.0 if i % 2 == 0 else -1.0
        branch(bx, by, side * rnd.uniform(0.35, 1.25), h * rnd.uniform(0.16, 0.27), 3, 3)


# --- backdrops --------------------------------------------------------------------------------

def _alpha_from_key(img, key=(0, 0, 0)):
    """Knock a key colour out to transparency. Lets us run the RGB-only dither helpers on a plane
    and then punch the untouched area back out."""
    px = img.load()
    for y in range(H):
        for x in range(W):
            if px[x, y][:3] == key:
                px[x, y] = (0, 0, 0, 0)
    return img


def bg_kharwyn_field():
    """ASHFALL. The Rupture aftermath: Kharwyn still burning on the ridge, a field of grave-crosses,
    one planted sword. Register A tableau from art direction 4.

    Values here are deliberately crushed — on the reference board the crimson-sky pins are maybe
    15% lit and 85% near-black silhouette. An evenly-lit red frame reads as a sunset postcard, not
    as the morning after a massacre.
    """
    ramp, accent, accent_hi = pal("ASHFALL")
    name = "kharwyn_field"

    # --- far: sky + the fire behind the ridge
    far = Image.new("RGB", (W, H), ramp[0])
    # Sky walks ramp 1 -> 4 and stops well short of the brightest entry: the only thing allowed to
    # hit the accent is the fire itself.
    dither_ramp(far, ramp, 0, int(H * 0.63), 0.16, 0.70, curve=1.9, seed=1)
    # Firelight behind the ridge: wide and squashed along the horizon, never a disc.
    dither_radial(far, W * 0.60, H * 0.615, 210, accent, 0.55, squash=2.3, falloff=2.6)
    dither_radial(far, W * 0.60, H * 0.615, 96, accent_hi, 0.42, squash=1.8, falloff=2.0)

    d = ImageDraw.Draw(far)
    rnd = random.Random(SEED)
    # Two ridge lines, the far one lighter, for atmospheric depth.
    far_ridge = ridge_points(rnd, H * 0.585, 34, 0.55)
    fill_below(d, far_ridge, ramp[2])
    ridge = ridge_points(rnd, H * 0.625, 26, 0.52)
    fill_below(d, ridge, ramp[1])

    # The Hold: a broken keep on the high point, silhouetted against its own fire.
    keep_base = H * 0.628
    d.rectangle([206, keep_base - 40, 350, keep_base], fill=ramp[0])
    for x, w_, h_ in ((242, 22, 104), (286, 15, 74), (216, 13, 58), (330, 11, 48)):
        spire(d, x, keep_base - 2, w_, h_, ramp[0], cross=(w_ == 22))
    # A breach in the wall, lit from inside.
    d.polygon([(300, keep_base), (318, keep_base - 26), (336, keep_base)], fill=ramp[3])

    dither_band(far, ramp[3], int(H * 0.58), int(H * 0.66), 0.22, 11)
    vignette(far, ramp[0], 0.85, seed=1)
    far.save(os.path.join(BG_DIR, f"{name}_far.png"))

    # --- mid: nearer rubble ridge + skeletal trees
    mid = Image.new("RGB", (W, H), (0, 0, 0))
    dm = ImageDraw.Draw(mid)
    r2 = ridge_points(random.Random(SEED + 7), H * 0.715, 22, 0.5, jag=1.2)
    dm.polygon([(0, H)] + [(x, y) for x, y in r2] + [(W, H)], fill=ramp[1])
    for x, h_ in ((52, 118), (404, 96), (156, 68)):
        dead_tree(dm, x, H * 0.725, h_, ramp[0], random.Random(SEED + x))
    dither_band(mid, ramp[2], int(H * 0.69), int(H * 0.745), 0.20, 23)
    mid = _alpha_from_key(mid.convert("RGBA"))
    mid.save(os.path.join(BG_DIR, f"{name}_mid.png"))

    # --- near: the ground he's lying on, the field of crosses, the sword
    near = Image.new("RGB", (W, H), (0, 0, 0))
    dn = ImageDraw.Draw(near)
    rn = random.Random(SEED + 31)
    ground = ridge_points(rn, H * 0.795, 9, 0.45)
    dn.polygon([(0, H)] + [(x, y) for x, y in ground] + [(W, H)], fill=ramp[1])
    # Crosses lean, because nobody had time to plant them straight. Nearer ones are darker.
    for x in (22, 74, 132, 196, 300, 356, 412, 466):
        h_ = rn.randint(22, 40)
        grave_cross(dn, x, H * 0.815 + rn.randint(-3, 8), h_, ramp[0], lean=rn.randint(-3, 3))
    planted_sword(dn, 250, H * 0.875, 86, ramp[0], accent)
    for _ in range(140):
        x = rn.randint(0, W - 1)
        y = rn.randint(int(H * 0.82), H - 1)
        dn.rectangle([x, y, x + rn.randint(1, 5), y + rn.randint(1, 2)], fill=ramp[0])
    # Foreground crush: the bottom of frame goes to the darkest entry so cast and UI read.
    darken_toward(near, ramp[0], int(H * 0.86), H, 0.15, 1.0, curve=1.4, seed=31)
    near = _alpha_from_key(near.convert("RGBA"))
    near.save(os.path.join(BG_DIR, f"{name}_near.png"))
    print(f"  {name}: far/mid/near")


def bg_kharwyn_undercroft():
    """DROWNED. Below the Hold: flooded stone, colonnade, cold cyan light from the breach."""
    ramp, accent, accent_hi = pal("DROWNED")
    name = "kharwyn_undercroft"

    # --- far: the breach, glowing cold at the end of the hall
    far = Image.new("RGB", (W, H), ramp[0])
    dither_ramp(far, ramp, 0, int(H * 0.30), 0.0, 0.20, curve=1.0, seed=2)
    d = ImageDraw.Draw(far)
    # A tall pointed arch with the light behind it. The light is *cold* — this is the one place in
    # Episode 1 where magic is the light source, so it gets the DROWNED accent at full strength.
    ax, ay = W * 0.5, H * 0.50
    aw, ah = 118, 300
    d.rectangle([ax - aw / 2, ay - ah * 0.42, ax + aw / 2, H * 0.82], fill=ramp[2])
    d.polygon([(ax - aw / 2, ay - ah * 0.42), (ax, ay - ah * 0.78), (ax + aw / 2, ay - ah * 0.42)], fill=ramp[2])
    dither_radial(far, ax, ay - 20, 175, accent, 0.60, squash=0.9, falloff=1.9)
    dither_radial(far, ax, ay - 20, 74, accent_hi, 0.55, squash=0.85, falloff=1.7)
    vignette(far, ramp[0], 0.95, seed=2)
    far.save(os.path.join(BG_DIR, f"{name}_far.png"))

    # --- mid: colonnade receding toward the breach — the board's arcade/ruin motif
    mid = Image.new("RGB", (W, H), (0, 0, 0))
    dm = ImageDraw.Draw(mid)
    for x, w_, top in ((18, 40, 0.16), (88, 30, 0.21), (392, 30, 0.21), (462, 40, 0.16)):
        dm.rectangle([x - w_ / 2, H * top, x + w_ / 2, H * 0.86], fill=ramp[1])
        dm.polygon([(x - w_ / 2 - 7, H * top), (x, H * (top - 0.05)), (x + w_ / 2 + 7, H * top)], fill=ramp[1])
        # Capital block, one value up, so the columns aren't flat rectangles.
        dm.rectangle([x - w_ / 2 - 4, H * top, x + w_ / 2 + 4, H * top + 10], fill=ramp[2])
    # Vaulted ribs across the ceiling.
    for i in range(4):
        yy = H * (0.06 + i * 0.035)
        dm.arc([W * 0.10, yy, W * 0.90, yy + 120], 180, 360, fill=ramp[1], width=4)
    mid = _alpha_from_key(mid.convert("RGBA"))
    mid.save(os.path.join(BG_DIR, f"{name}_mid.png"))

    # --- near: standing water reflecting the breach
    near = Image.new("RGB", (W, H), (0, 0, 0))
    dn = ImageDraw.Draw(near)
    dn.rectangle([0, H * 0.82, W, H], fill=ramp[1])
    # Reflection: horizontal broken streaks, brightest directly under the arch.
    rn = random.Random(SEED + 9)
    for _ in range(220):
        y = rn.randint(int(H * 0.83), H - 2)
        depth = (y - H * 0.83) / (H * 0.17)
        spread = 18 + depth * 90
        x = int(W * 0.5 + rn.uniform(-spread, spread))
        ln = rn.randint(3, 14)
        col = ramp[3] if rn.random() < 0.72 else accent
        dn.rectangle([x, y, x + ln, y], fill=col)
    dither_band(near, ramp[2], int(H * 0.82), int(H * 0.88), 0.30, 9)
    darken_toward(near, ramp[0], int(H * 0.93), H, 0.1, 0.85, curve=1.5, seed=9)
    near = _alpha_from_key(near.convert("RGBA"))
    near.save(os.path.join(BG_DIR, f"{name}_near.png"))
    print(f"  {name}: far/mid/near")


def bg_treeline_dusk():
    """VIOLET. The road away from the Hold at dusk — the board's 'gorgeous and about to hurt you'
    register."""
    ramp, accent, accent_hi = pal("VIOLET")
    name = "treeline_dusk"

    # --- far: dusk sky, moon, distant mountains
    far = Image.new("RGB", (W, H), ramp[0])
    # Deep at the zenith, hot at the horizon — the board's magenta pins all run this direction.
    dither_ramp(far, ramp, 0, int(H * 0.60), 0.06, 0.88, curve=2.1, seed=3)
    d = ImageDraw.Draw(far)
    mx, my = W * 0.28, H * 0.17
    dither_radial(far, mx, my, 150, accent, 0.34, falloff=2.4)
    d.ellipse([mx - 23, my - 23, mx + 23, my + 23], fill=accent_hi)
    # A bite of shadow across the moon so it isn't a flat white circle.
    d.ellipse([mx - 8, my - 19, mx + 26, my + 15], fill=rgb("#e8c4f5"))

    rnd = random.Random(SEED + 3)
    # Three mountain planes, each darker as it comes forward.
    for depth, shade in ((0.505, ramp[3]), (0.545, ramp[2]), (0.60, ramp[1])):
        pts = ridge_points(rnd, H * depth, 58 * (1.0 - depth), 0.56)
        fill_below(d, pts, shade)
        dither_band(far, ramp[4], int(H * depth) - 12, int(H * depth) + 10, 0.26, int(depth * 200))
    vignette(far, ramp[0], 0.8, seed=3)
    far.save(os.path.join(BG_DIR, f"{name}_far.png"))

    # --- mid: nearer ridge with a small castle on it
    mid = Image.new("RGB", (W, H), (0, 0, 0))
    dm = ImageDraw.Draw(mid)
    r2 = ridge_points(random.Random(SEED + 17), H * 0.675, 30, 0.5)
    dm.polygon([(0, H)] + [(x, y) for x, y in r2] + [(W, H)], fill=ramp[1])
    for x, w_, h_ in ((374, 15, 70), (398, 10, 48), (352, 9, 40)):
        spire(dm, x, H * 0.673, w_, h_, ramp[0], cross=(w_ == 15))
    dm.rectangle([344, H * 0.673 - 20, 408, H * 0.675], fill=ramp[0])
    mid = _alpha_from_key(mid.convert("RGBA"))
    mid.save(os.path.join(BG_DIR, f"{name}_mid.png"))

    # --- near: conifer treeline framing both edges, centre left open for the cast
    near = Image.new("RGB", (W, H), (0, 0, 0))
    dn = ImageDraw.Draw(near)
    rn = random.Random(SEED + 41)
    ground = ridge_points(rn, H * 0.785, 8, 0.4)
    dn.polygon([(0, H)] + [(x, y) for x, y in ground] + [(W, H)], fill=ramp[1])
    for x in list(range(-14, 116, 22)) + list(range(374, W + 26, 21)):
        h_ = rn.randint(210, 400)
        base = H * 0.80 + rn.randint(-8, 10)
        w_ = h_ * 0.20
        # Layered conifer: stacked triangles read better at this scale than one big cone.
        for k in range(4):
            t = k / 4.0
            yy = base - h_ * t
            ww = w_ * (1.0 - t * 0.55)
            dn.polygon([(x - ww / 2, yy), (x, yy - h_ * 0.42), (x + ww / 2, yy)], fill=ramp[0])
        dn.rectangle([x - 2, base - h_ * 0.1, x + 2, base], fill=ramp[0])
    darken_toward(near, ramp[0], int(H * 0.84), H, 0.1, 0.9, curve=1.4, seed=41)
    near = _alpha_from_key(near.convert("RGBA"))
    near.save(os.path.join(BG_DIR, f"{name}_near.png"))
    print(f"  {name}: far/mid/near")


def bg_bog_road():
    """BOGSHADE. Fog, sickly green, low contrast — the palette for scenes where the player is
    being lied to."""
    ramp, accent, accent_hi = pal("BOGSHADE")
    name = "bog_road"

    # --- far: flat sickly light, no visible sun. Low contrast is the whole point of this palette.
    far = Image.new("RGB", (W, H), ramp[0])
    dither_ramp(far, ramp, 0, int(H * 0.70), 0.34, 0.62, curve=1.0, jitter=0.20, seed=5)
    d = ImageDraw.Draw(far)
    rnd = random.Random(SEED + 5)
    # Receding fog planes. Each is *lighter* than the one behind it — inverted from the other
    # backdrops, which is what makes fog read as fog rather than as haze.
    for depth, shade in ((0.58, ramp[3]), (0.635, ramp[2]), (0.69, ramp[1])):
        pts = ridge_points(rnd, H * depth, 18, 0.5)
        fill_below(d, pts, shade)
        dither_band(far, ramp[4], int(H * depth) - 16, int(H * depth) + 12, 0.34, int(depth * 300))
    vignette(far, ramp[0], 0.7, seed=5)
    far.save(os.path.join(BG_DIR, f"{name}_far.png"))

    # --- mid: skeletal trees in the fog
    mid = Image.new("RGB", (W, H), (0, 0, 0))
    dm = ImageDraw.Draw(mid)
    for x in (40, 122, 214, 306, 398, 458):
        dead_tree(dm, x, H * 0.735, random.Random(SEED + x).randint(180, 300),
                  ramp[1], random.Random(SEED + x * 3))
    dither_band(mid, ramp[2], int(H * 0.58), int(H * 0.74), 0.24, 77)
    mid = _alpha_from_key(mid.convert("RGBA"))
    mid.save(os.path.join(BG_DIR, f"{name}_mid.png"))

    # --- near: standing water, reeds, and heavy foreground crush
    near = Image.new("RGB", (W, H), (0, 0, 0))
    dn = ImageDraw.Draw(near)
    rn = random.Random(SEED + 53)
    ground = ridge_points(rn, H * 0.79, 7, 0.4)
    dn.polygon([(0, H)] + [(x, y) for x, y in ground] + [(W, H)], fill=ramp[1])
    for _ in range(46):
        x, y = rn.randint(0, W), rn.randint(int(H * 0.81), H - 6)
        dn.ellipse([x, y, x + rn.randint(10, 40), y + rn.randint(2, 5)], fill=ramp[2])
    # Reeds along the bottom edge — near-black, breaking the frame edge.
    for _ in range(150):
        x = rn.randint(-4, W + 4)
        base = rn.randint(int(H * 0.90), H + 8)
        h_ = rn.randint(20, 78)
        lean = rn.uniform(-9, 9)
        dn.line([(x, base), (x + lean, base - h_)], fill=ramp[0], width=rn.choice((1, 1, 2)))
    darken_toward(near, ramp[0], int(H * 0.86), H, 0.2, 1.0, curve=1.3, seed=53)
    near = _alpha_from_key(near.convert("RGBA"))
    near.save(os.path.join(BG_DIR, f"{name}_near.png"))
    print(f"  {name}: far/mid/near")


def bg_tunnel_mouth():
    """CRYPT. Near-monochrome. Where the colour drains out of the game and a monster is about to
    be in frame."""
    ramp, accent, accent_hi = pal("CRYPT")
    name = "tunnel_mouth"

    # --- far: what's *inside* the tunnel. Almost nothing, which is the point.
    far = Image.new("RGB", (W, H), ramp[0])
    dither_ramp(far, ramp, int(H * 0.20), int(H * 0.86), 0.30, 0.02, curve=0.8, seed=6)
    d = ImageDraw.Draw(far)
    rn = random.Random(SEED + 61)
    # Suggestion of a receding passage: progressively smaller, darker arches.
    for i in range(5):
        t = i / 5.0
        half = 150 * (1.0 - t * 0.62)
        top = H * (0.30 + t * 0.10)
        base = H * (0.86 - t * 0.06)
        shade = ramp[max(0, 2 - i // 2)]
        d.rectangle([W * 0.5 - half, top + 60, W * 0.5 + half, base], fill=shade)
        d.polygon([(W * 0.5 - half, top + 60), (W * 0.5, top), (W * 0.5 + half, top + 60)], fill=shade)
    far.save(os.path.join(BG_DIR, f"{name}_far.png"))

    # --- mid: the arch mouth itself, as a near-black frame biting into the edges
    mid = Image.new("RGB", (W, H), (0, 0, 0))
    dm = ImageDraw.Draw(mid)
    cx, top, half = W * 0.5, H * 0.12, 176
    # Draw the surrounding stone as a full-frame fill, then punch the arch opening out of it.
    dm.rectangle([0, 0, W, H], fill=ramp[1])
    dm.rectangle([cx - half, H * 0.34, cx + half, H], fill=(0, 0, 0))
    dm.polygon([(cx - half, H * 0.34), (cx, top), (cx + half, H * 0.34)], fill=(0, 0, 0))
    # Voussoir blocks around the arch so the opening has masonry, not a vector edge.
    for a in range(0, 181, 7):
        ang = math.radians(a)
        bx = cx - math.cos(ang) * (half + 13)
        by = H * 0.34 - math.sin(ang) * (H * 0.34 - top + 13)
        dm.rectangle([bx - 8, by - 7, bx + 8, by + 7], fill=ramp[2])
        dm.rectangle([bx - 6, by - 5, bx + 6, by + 5], fill=ramp[1])
    # Coursed blocks down the jambs.
    for y in range(int(H * 0.34), H, 26):
        for x in (cx - half - 14, cx + half + 14):
            dm.rectangle([x - 16, y, x + 16, y + 23], fill=ramp[2])
            dm.rectangle([x - 14, y + 2, x + 14, y + 21], fill=ramp[1])
    darken_toward(mid, ramp[0], 0, int(H * 0.30), 0.9, 0.25, seed=61)
    mid = _alpha_from_key(mid.convert("RGBA"))
    mid.save(os.path.join(BG_DIR, f"{name}_mid.png"))

    # --- near: floor + a single torch on the right jamb, the frame's only warm note
    near = Image.new("RGB", (W, H), (0, 0, 0))
    dn = ImageDraw.Draw(near)
    ground = ridge_points(random.Random(SEED + 67), H * 0.855, 6, 0.4)
    dn.polygon([(0, H)] + [(x, y) for x, y in ground] + [(W, H)], fill=ramp[1])
    for _ in range(120):
        x = rn.randint(0, W)
        y = rn.randint(int(H * 0.87), H - 1)
        dn.rectangle([x, y, x + rn.randint(2, 9), y + rn.randint(1, 3)], fill=ramp[2])
    tx, ty = W * 0.885, H * 0.545
    dither_radial(near, tx, ty, 165, accent, 0.52, squash=0.85, falloff=2.1)
    dn.rectangle([tx - 2, ty, tx + 2, ty + 44], fill=ramp[0])
    dn.ellipse([tx - 6, ty - 13, tx + 6, ty + 3], fill=accent)
    dn.ellipse([tx - 3, ty - 9, tx + 3, ty - 1], fill=accent_hi)
    darken_toward(near, ramp[0], int(H * 0.90), H, 0.15, 0.8, curve=1.3, seed=67)
    near = _alpha_from_key(near.convert("RGBA"))
    near.save(os.path.join(BG_DIR, f"{name}_near.png"))
    print(f"  {name}: far/mid/near")


# --- characters -------------------------------------------------------------------------------

def silhouette(size, body, light_from="right", glow=None, seed=0):
    """Rim-lit silhouette: near-black body, 1-2px accent edge on the lit side.

    This is exactly how every figure on the reference board is handled, and it means a character's
    identity has to live in their *shape*, per art direction 5.
    """
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    body(d, w, h)

    base = img.copy()
    px = base.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    po = out.load()

    lit = rgb(glow) if glow else None
    dx = 1 if light_from == "right" else -1

    for y in range(h):
        for x in range(w):
            a = px[x, y][3]
            if a == 0:
                continue
            po[x, y] = px[x, y]

    # Walk each row inward from the lit side and paint the first 2 solid pixels as rim light.
    if lit:
        for y in range(h):
            xs = range(w - 1, -1, -1) if dx > 0 else range(w)
            hits = 0
            prev_solid = False
            for x in xs:
                solid = px[x, y][3] > 0
                if solid and not prev_solid:
                    po[x, y] = lit + (255,)
                    if 0 <= x - dx < w and px[x - dx, y][3] > 0:
                        r, g, b = lit
                        po[x - dx, y] = (r // 2, g // 2, b // 2, 255)
                    hits += 1
                    if hits >= 2:
                        break
                prev_solid = solid
    return out


def _cloaked(d, w, h, hood=True, shoulders=1.0, hem_tear=True, rnd=None):
    rnd = rnd or random.Random(SEED)
    body = (14, 12, 20, 255)
    head_r = w * 0.17
    cx = w * 0.5
    # head
    d.ellipse([cx - head_r, h * 0.04, cx + head_r, h * 0.04 + head_r * 2], fill=body)
    if hood:
        d.polygon([(cx - head_r * 1.5, h * 0.13), (cx, h * 0.01), (cx + head_r * 1.5, h * 0.13)], fill=body)
    # torso, tapering into a cloak
    sw = w * 0.40 * shoulders
    d.polygon([(cx - sw, h * 0.19), (cx + sw, h * 0.19),
               (cx + w * 0.30, h * 0.72), (cx - w * 0.30, h * 0.72)], fill=body)
    # legs
    d.rectangle([cx - w * 0.20, h * 0.70, cx - w * 0.04, h * 0.98], fill=body)
    d.rectangle([cx + w * 0.04, h * 0.70, cx + w * 0.20, h * 0.98], fill=body)
    if hem_tear:
        for _ in range(7):
            x = rnd.uniform(cx - w * 0.30, cx + w * 0.30)
            d.polygon([(x, h * 0.72), (x + 4, h * 0.72), (x + 2, h * 0.79)], fill=(0, 0, 0, 0))


def char_protagonist(d, w, h):
    rnd = random.Random(SEED + 101)
    _cloaked(d, w, h, hood=False, shoulders=1.05, rnd=rnd)
    body = (14, 12, 20, 255)
    cx = w * 0.5
    # kettle helm: rounded dome plus a brim, which is the whole silhouette read
    d.ellipse([cx - w * 0.19, h * 0.03, cx + w * 0.19, h * 0.16], fill=body)
    d.rectangle([cx - w * 0.24, h * 0.115, cx + w * 0.24, h * 0.14], fill=body)
    # sword held low, angled back
    d.line([(cx + w * 0.28, h * 0.55), (cx + w * 0.44, h * 0.95)], fill=body, width=3)


def char_brother(d, w, h):
    rnd = random.Random(SEED + 102)
    _cloaked(d, w, h, hood=False, shoulders=0.86, rnd=rnd)
    body = (14, 12, 20, 255)
    cx = w * 0.5
    # bare head, hunched forward: reads as younger and hurt
    d.ellipse([cx - w * 0.155, h * 0.05, cx + w * 0.155, h * 0.185], fill=body)
    # one arm out, hand open — where the glow will come from
    d.line([(cx + w * 0.18, h * 0.34), (cx + w * 0.42, h * 0.46)], fill=body, width=4)
    d.ellipse([cx + w * 0.36, h * 0.43, cx + w * 0.48, h * 0.53], fill=body)


def char_medic(d, w, h):
    rnd = random.Random(SEED + 103)
    _cloaked(d, w, h, hood=False, shoulders=1.0, rnd=rnd)
    body = (14, 12, 20, 255)
    cx = w * 0.5
    d.ellipse([cx - w * 0.16, h * 0.045, cx + w * 0.16, h * 0.175], fill=body)
    # the satchel: breaks his outline asymmetrically, per art direction 5
    d.rectangle([cx + w * 0.24, h * 0.42, cx + w * 0.52, h * 0.62], fill=body)
    d.line([(cx - w * 0.10, h * 0.22), (cx + w * 0.34, h * 0.44)], fill=body, width=3)


def char_enemy_soldier(d, w, h):
    rnd = random.Random(SEED + 104)
    _cloaked(d, w, h, hood=False, shoulders=1.18, hem_tear=False, rnd=rnd)
    body = (14, 12, 20, 255)
    cx = w * 0.5
    # faceted, angular helm — Vaethari industry vs Aldrethi roundness
    d.polygon([(cx - w * 0.20, h * 0.16), (cx - w * 0.16, h * 0.04),
               (cx + w * 0.16, h * 0.04), (cx + w * 0.20, h * 0.16)], fill=body)
    d.rectangle([cx - w * 0.44, h * 0.19, cx + w * 0.44, h * 0.24], fill=body)


def char_prophet(d, w, h):
    rnd = random.Random(SEED + 105)
    body = (14, 12, 20, 255)
    cx = w * 0.5
    # a column: robed to the ground, no visible arms, tallest of the cast
    d.polygon([(cx - w * 0.34, h), (cx - w * 0.20, h * 0.20),
               (cx + w * 0.20, h * 0.20), (cx + w * 0.34, h)], fill=body)
    d.ellipse([cx - w * 0.15, h * 0.06, cx + w * 0.15, h * 0.21], fill=body)
    d.polygon([(cx - w * 0.24, h * 0.20), (cx, h * 0.015), (cx + w * 0.24, h * 0.20)], fill=body)


def char_scavenger(d, w, h):
    rnd = random.Random(SEED + 106)
    _cloaked(d, w, h, hood=True, shoulders=0.80, rnd=rnd)
    body = (14, 12, 20, 255)
    cx = w * 0.5
    # hanging junk: the outline should look noisy even at 48px
    for _ in range(9):
        x = rnd.uniform(cx - w * 0.30, cx + w * 0.32)
        y = rnd.uniform(h * 0.40, h * 0.66)
        ln = rnd.uniform(5, 15)
        d.line([(x, y), (x, y + ln)], fill=body, width=2)
        d.rectangle([x - 2, y + ln, x + 2, y + ln + 3], fill=body)


CHARACTERS = {
    "protagonist": char_protagonist,
    "brother": char_brother,
    "medic": char_medic,
    "enemy_soldier": char_enemy_soldier,
    "prophet": char_prophet,
    "scavenger": char_scavenger,
}

# Per-character rim colour. The Brother's is the magic override from art direction 2 — his glow
# does not belong to any scene palette, and that clash is the visual thesis of the game.
RIM = {
    "protagonist": "#ff9a3c",
    "brother": MAGIC_GLOW,
    "medic": "#ffb45c",
    "enemy_soldier": "#7fa9dd",
    "prophet": "#c6cfa8",
    "scavenger": "#d97ab5",
}

# Prophet reads as the tallest of the cast (art direction 5).
FULL_SIZES = {
    "prophet": (48, 104),
    "scavenger": (48, 84),
}


BUST_W, BUST_H = 220, 280

# Per-character bust construction: headgear shape, shoulder spread, and any silhouette-breaking
# extra. Drawn purpose-built at bust proportions rather than cropped out of the full-body sprite —
# cropping a full figure at this scale yields a canvas-filling torso slab with no readable head.
BUST_SPEC = {
    "protagonist":   dict(head="kettle",  shoulders=1.00, extra=None),
    "brother":       dict(head="bare",    shoulders=0.84, extra="hand"),
    "medic":         dict(head="bare",    shoulders=0.96, extra="strap"),
    "enemy_soldier": dict(head="faceted", shoulders=1.16, extra="gorget"),
    "prophet":       dict(head="hood",    shoulders=0.90, extra=None),
    "scavenger":     dict(head="hood",    shoulders=0.78, extra="junk"),
}


def _bust(who):
    """Chest-up portrait plate for `close` framing (art direction 4, Register B).

    Proportions matter more than detail here: a readable head with clear negative space around it,
    shoulders running off the bottom of the canvas, and the whole thing still a near-black
    silhouette carrying only a rim light and a handful of facial pixels. A character's entire
    expressive range is those few pixels, which is a production gift, not a limitation.
    """
    spec = BUST_SPEC[who]
    rnd = random.Random(SEED + 700 + len(who))
    body = (14, 12, 20, 255)

    img = Image.new("RGBA", (BUST_W, BUST_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx = BUST_W * 0.5
    head_cy = BUST_H * 0.28
    head_rx, head_ry = 51, 57

    # Shoulders as a rounded mass, not a polygon. The first version used a trapezoid whose outer
    # points fell outside the canvas, so it clipped to hard vertical lines and the whole plate read
    # as "a head sitting on a black box". An ellipse tapers inside the canvas on both sides, which
    # is what makes it read as a body.
    sw = 101.0 * spec["shoulders"]
    shoulder_y = BUST_H * 0.56
    # The ellipse's widest point must fall *inside* the canvas. Pushed far below it (an earlier
    # attempt used BUST_H + 210) only the near-vertical flanks are visible and the torso reads as a
    # rectangle again — the curve has to be on screen to do its job.
    d.ellipse([cx - sw, shoulder_y - 18, cx + sw, BUST_H + 26], fill=body)
    # Trapezius: fills the notch between neck and shoulder line so the head doesn't look detached.
    d.polygon([
        (cx - sw * 0.80, shoulder_y + 30),
        (cx - head_rx * 0.60, shoulder_y - 34),
        (cx + head_rx * 0.60, shoulder_y - 34),
        (cx + sw * 0.80, shoulder_y + 30),
    ], fill=body)
    # Neck.
    d.rectangle([cx - 21, head_cy + head_ry - 18, cx + 21, shoulder_y], fill=body)
    # Skull.
    d.ellipse([cx - head_rx, head_cy - head_ry, cx + head_rx, head_cy + head_ry], fill=body)

    head = spec["head"]
    if head == "kettle":
        # Rounded dome plus a wide brim — the Aldrethi infantry read.
        d.ellipse([cx - head_rx - 4, head_cy - head_ry - 14, cx + head_rx + 4, head_cy + 8], fill=body)
        d.rectangle([cx - head_rx - 20, head_cy - 12, cx + head_rx + 20, head_cy - 2], fill=body)
    elif head == "faceted":
        # Angular, industrial — Vaethari, deliberately the opposite of Aldrethi roundness.
        d.polygon([
            (cx - head_rx - 3, head_cy + 12), (cx - head_rx + 6, head_cy - head_ry - 10),
            (cx + head_rx - 6, head_cy - head_ry - 10), (cx + head_rx + 3, head_cy + 12),
        ], fill=body)
        d.polygon([(cx - head_rx - 3, head_cy + 12), (cx, head_cy + 30), (cx + head_rx + 3, head_cy + 12)], fill=body)
    elif head == "hood":
        d.polygon([
            (cx - head_rx - 22, head_cy + head_ry - 4),
            (cx - head_rx - 10, head_cy - head_ry - 6),
            (cx, head_cy - head_ry - 30),
            (cx + head_rx + 10, head_cy - head_ry - 6),
            (cx + head_rx + 22, head_cy + head_ry - 4),
        ], fill=body)
        # Punch the face cavity back out so the hood reads as a hood, not a helmet.
        d.ellipse([cx - 27, head_cy - 20, cx + 27, head_cy + 30], fill=(0, 0, 0, 0))

    extra = spec["extra"]
    if extra == "strap":
        d.polygon([(cx - sw * 0.8, BUST_H), (cx - 4, shoulder_y - 6),
                   (cx + 16, shoulder_y - 2), (cx - sw * 0.55, BUST_H)], fill=(24, 21, 30, 255))
    elif extra == "gorget":
        d.rectangle([cx - sw * 0.9, shoulder_y + 6, cx + sw * 0.9, shoulder_y + 20], fill=(24, 21, 30, 255))
    elif extra == "hand":
        # Cael's hand coming up into frame — the source of the glow, and the reason his close-up
        # never looks like anyone else's.
        d.ellipse([cx + 44, BUST_H * 0.74, cx + 96, BUST_H * 0.99], fill=body)
        for i in range(4):
            d.rectangle([cx + 50 + i * 12, BUST_H * 0.70, cx + 57 + i * 12, BUST_H * 0.80], fill=body)
    elif extra == "junk":
        for _ in range(7):
            x = rnd.uniform(cx - sw * 0.7, cx + sw * 0.7)
            y = rnd.uniform(shoulder_y + 16, BUST_H - 8)
            ln = rnd.uniform(10, 26)
            d.line([(x, y), (x, y + ln)], fill=(24, 21, 30, 255), width=3)

    # Dissolve the bottom of the torso into nothing with a dithered alpha fade. Without this the
    # plate ends in a hard rectangular edge where the canvas cuts the shoulders off, which reads as
    # a black box sitting on the scene. The board handles figures the same way — they lose
    # themselves in shadow rather than terminating on a line.
    _fade_bottom(img, 0.60, seed=len(who))

    # Rim light down the lit edge, using the same routine as the tableau sprites so the two
    # registers agree about where the light is.
    lit = _rim_only(img, RIM[who], "right")

    # Facial pixels: eyes as two high-contrast marks, plus a jaw edge. Four pixels of performance.
    fd = ImageDraw.Draw(lit)
    ec = rgb(RIM[who])
    eye_y = int(head_cy + 2)
    if head == "hood":
        # Under a hood you get eyes and nothing else.
        fd.rectangle([cx - 17, eye_y, cx - 9, eye_y + 4], fill=ec + (255,))
        fd.rectangle([cx + 9, eye_y, cx + 17, eye_y + 4], fill=ec + (255,))
    else:
        fd.rectangle([cx - 20, eye_y, cx - 11, eye_y + 4], fill=ec + (255,))
        fd.rectangle([cx + 11, eye_y, cx + 20, eye_y + 4], fill=ec + (255,))
        # Jaw catch-light, dimmer than the eyes.
        dim = tuple(v // 2 for v in ec)
        fd.line([(cx + 26, head_cy + 18), (cx + 14, head_cy + 40)], fill=dim + (255,), width=2)
    return lit


def _fade_bottom(img, start_frac, seed=0):
    """Bayer-dithered alpha fade from `start_frac` of the height down to fully transparent."""
    w, h = img.size
    px = img.load()
    rnd = random.Random(SEED + 4000 + seed)
    y0 = int(h * start_frac)
    span = max(1, h - y0)
    for y in range(y0, h):
        amt = ((y - y0) / span) ** 0.85
        brow = BAYER8[y & 7]
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            if amt > brow[x & 7] + rnd.uniform(-0.10, 0.10):
                px[x, y] = (0, 0, 0, 0)
    return img


def _rim_only(src, glow_hex, light_from="right"):
    """Copy `src` and paint a 2px rim light along the first solid pixels from the lit side."""
    w, h = src.size
    px = src.load()
    out = src.copy()
    po = out.load()
    lit = rgb(glow_hex)
    dx = 1 if light_from == "right" else -1
    for y in range(h):
        xs = range(w - 1, -1, -1) if dx > 0 else range(w)
        hits = 0
        prev_solid = False
        for x in xs:
            solid = px[x, y][3] > 0
            if solid and not prev_solid:
                po[x, y] = lit + (255,)
                if 0 <= x - dx < w and px[x - dx, y][3] > 0:
                    po[x - dx, y] = tuple(v // 2 for v in lit) + (255,)
                hits += 1
                if hits >= 2:
                    break
            prev_solid = solid
    return out


def gen_characters():
    for who, body in CHARACTERS.items():
        size = FULL_SIZES.get(who, (48, 96))
        img = silhouette(size, body, "right", RIM[who])
        img.save(os.path.join(CHAR_DIR, f"{who}_full.png"))

        bust = _bust(who)
        bust.save(os.path.join(CHAR_DIR, f"{who}_bust.png"))
    print(f"  characters: {len(CHARACTERS)} x (full + bust)")


# --- audio ------------------------------------------------------------------------------------

def gen_audio():
    """Ambient beds, tension pulses, and stings as 16-bit mono WAVs.

    Synthesised with the stdlib only. These are not final sound design, but the brief puts weight
    on audio precisely because there's no voice acting, and silent playtests mislead badly about
    pacing — a scene that feels tense with a bed underneath it often feels inert without one.
    """
    import struct
    import wave

    out_dir = os.path.join(ROOT, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)
    rate = 22050

    def write(name, samples):
        path = os.path.join(out_dir, name)
        with wave.open(path, "w") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(rate)
            f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples))

    def noise_bed(dur, cutoff, base_hz, amp, rnd_seed, rumble=0.0):
        rnd = random.Random(rnd_seed)
        n = int(rate * dur)
        out = []
        lp = 0.0
        for i in range(n):
            white = rnd.uniform(-1, 1)
            lp += (white - lp) * cutoff
            v = lp * amp
            if base_hz:
                v += math.sin(2 * math.pi * base_hz * i / rate) * amp * 0.35
            if rumble:
                v += math.sin(2 * math.pi * 31.0 * i / rate) * rumble
            # Fade the loop seam so it doesn't click.
            fade = min(1.0, i / (rate * 0.4), (n - i) / (rate * 0.4))
            out.append(v * fade)
        return out

    write("bed_battlefield.wav", noise_bed(6.0, 0.02, 48.0, 0.30, 1, rumble=0.06))
    write("bed_wind.wav", noise_bed(6.0, 0.05, 0.0, 0.26, 2))
    write("bed_cave.wav", noise_bed(6.0, 0.012, 38.0, 0.24, 3, rumble=0.09))
    write("bed_forest.wav", noise_bed(6.0, 0.09, 0.0, 0.18, 4))

    # Dread: two detuned low sines beating against each other.
    n = int(rate * 5.0)
    write("pulse_dread.wav", [
        (math.sin(2 * math.pi * 55.0 * i / rate) + math.sin(2 * math.pi * 58.3 * i / rate)) * 0.22
        * min(1.0, i / (rate * 0.5), (n - i) / (rate * 0.5))
        for i in range(n)
    ])

    n = int(rate * 2.0)
    def heartbeat(i):
        t = (i / rate) % 1.0
        env = 0.0
        for onset in (0.0, 0.22):
            dt = t - onset
            if 0 <= dt < 0.16:
                env += math.exp(-dt * 26) * (1.0 if onset == 0 else 0.7)
        return math.sin(2 * math.pi * 48 * i / rate) * env * 0.5
    write("pulse_heartbeat.wav", [heartbeat(i) for i in range(n)])

    def sting(dur, f0, f1, decay, noise=0.0, seed=0):
        rnd = random.Random(seed)
        n = int(rate * dur)
        out = []
        for i in range(n):
            t = i / rate
            f = f0 + (f1 - f0) * (t / dur)
            env = math.exp(-t * decay)
            v = math.sin(2 * math.pi * f * t) * env
            if noise:
                v += rnd.uniform(-1, 1) * env * noise
            out.append(v * 0.55)
        return out

    write("sting_magic.wav", sting(1.1, 320, 1280, 4.0, 0.10, 11))
    write("sting_reveal.wav", sting(1.4, 180, 90, 2.6, 0.05, 12))
    write("sting_impact.wav", sting(0.5, 150, 44, 12.0, 0.55, 13))
    write("sting_remember.wav", sting(0.5, 880, 1180, 9.0, 0.0, 14))
    write("ui_tick.wav", sting(0.06, 1500, 1100, 55.0, 0.12, 15))
    write("ui_select.wav", sting(0.13, 620, 880, 22.0, 0.05, 16))
    print("  audio: 4 beds, 2 pulses, 6 stings")


# --- main -------------------------------------------------------------------------------------

def main():
    os.makedirs(BG_DIR, exist_ok=True)
    os.makedirs(CHAR_DIR, exist_ok=True)
    random.seed(SEED)

    print("Backdrops:")
    bg_kharwyn_field()
    bg_kharwyn_undercroft()
    bg_treeline_dusk()
    bg_bog_road()
    bg_tunnel_mouth()

    print("Characters:")
    gen_characters()

    print("Audio:")
    gen_audio()

    print("\nDone. All output is placeholder-by-swappability, not placeholder-by-ugliness:")
    print("paths flow through src/stage/art_registry.gd, so commissioned art drops in with a")
    print("registry edit and no scene changes.")


if __name__ == "__main__":
    main()
