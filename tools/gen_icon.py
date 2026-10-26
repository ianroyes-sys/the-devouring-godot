#!/usr/bin/env python3
"""App icon + boot splash for The Devouring.

Icon design brief, in order of priority:

1. **Legible at 60x60.** That's the real constraint. An App Store icon is judged at 1024 but *used*
   at 60. So the icon is one shape, one silhouette, and one light — not a scene. The Kharwyn keep
   that works beautifully as a backdrop turns to mush at 60px and is deliberately not used here.
2. **On-brand per docs/ART_DIRECTION.md.** ASHFALL crimson field, Bayer dithering, black silhouette,
   and exactly one light source.
3. **Says what the game is about.** The subject is an open hand in silhouette with cold light behind
   it — the game's inciting image, Cael turning his hands over with light coming out of them. A
   crimson ASHFALL world with DROWNED cyan (the palette's magic colour) bleeding through it: the
   premise in one mark. A hand also survives 29px, because the eye completes it from the fingertip
   rhythm alone.

The cyan-on-crimson pairing is also the most saturated complementary contrast available in the
project's palettes, which is what makes it survive being shrunk to a thumbnail.

    python3 tools/gen_icon.py
"""

import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "icon")
SEED = 20260726

ASHFALL = ["#0d0810", "#1a1018", "#3a0d14", "#7a1520", "#b8322e", "#d9553a"]
EMBER = "#ff9a3c"
GLOW = "#5fe0e8"
GLOW_HI = "#b6f5f2"

# Sizes required by Godot 4.7's iOS exporter. Note this schema changed from earlier 4.x: it now
# wants icon_1024x1024 (plus dark/tinted appearance variants for iOS 18+), ios_128/136/192, and
# spotlight_120 / notification_76 / notification_114. Cross-check against the binary if it ever
# fails validation again:
#   strings Godot | grep '^icons/'
IOS_SIZES = [
    (1024, "icon_1024.png"), (192, "icon_192.png"), (180, "icon_180.png"),
    (167, "icon_167.png"), (152, "icon_152.png"), (144, "icon_144.png"),
    (136, "icon_136.png"), (128, "icon_128.png"), (120, "icon_120.png"),
    (114, "icon_114.png"), (108, "icon_108.png"), (100, "icon_100.png"),
    (87, "icon_87.png"), (80, "icon_80.png"), (76, "icon_76.png"),
    (72, "icon_72.png"), (60, "icon_60.png"), (58, "icon_58.png"),
    (57, "icon_57.png"), (50, "icon_50.png"), (40, "icon_40.png"),
    (29, "icon_29.png"), (20, "icon_20.png"),
]


def _bayer(n):
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


def dither_ramp(img, ramp, y0, y1, t0, t1, curve=1.0, jitter=0.12, seed=0):
    W, H = img.size
    px = img.load()
    rnd = random.Random(SEED + seed)
    span = max(1, y1 - y0)
    top = len(ramp) - 1
    for y in range(max(0, y0), min(H, y1)):
        f = ((y - y0) / span) ** curve
        t = (t0 + (t1 - t0) * f) * top
        lo = max(0, min(top, int(math.floor(t))))
        frac = t - math.floor(t)
        hi = max(0, min(top, lo + 1))
        brow = BAYER8[y & 7]
        for x in range(W):
            px[x, y] = ramp[hi] if frac > brow[x & 7] + rnd.uniform(-jitter, jitter) else ramp[lo]


def dither_radial(img, cx, cy, radius, color, strength=1.0, squash=1.0, falloff=2.2):
    W, H = img.size
    px = img.load()
    rx = radius * squash
    for y in range(max(0, int(cy - radius)), min(H, int(cy + radius))):
        brow = BAYER8[y & 7]
        for x in range(max(0, int(cx - rx)), min(W, int(cx + rx))):
            d = math.hypot((x - cx) / squash, y - cy) / radius
            if d >= 1.0:
                continue
            f = (1.0 - d) ** falloff * strength
            if f > brow[x & 7]:
                s = px[x, y]
                px[x, y] = tuple(min(255, int(s[i] * (1 - f) + color[i] * f)) for i in range(3))


def vignette(img, color, strength=0.8):
    W, H = img.size
    px = img.load()
    cx, cy = W * 0.5, H * 0.5
    maxd = math.hypot(cx, cy)
    for y in range(H):
        brow = BAYER8[y & 7]
        for x in range(W):
            d = math.hypot(x - cx, y - cy) / maxd
            amt = max(0.0, (d - 0.50) / 0.50) ** 1.7 * strength
            if amt > brow[x & 7]:
                px[x, y] = color


def ridge(rnd, W, y_base, amplitude, roughness):
    pts = [(0.0, y_base), (float(W), y_base)]
    amp = amplitude
    step = W
    while step > 3:
        new = [pts[0]]
        for i in range(len(pts) - 1):
            x0, y0 = pts[i]
            x1, y1 = pts[i + 1]
            new.append(((x0 + x1) / 2.0, (y0 + y1) / 2.0 + rnd.uniform(-amp, amp)))
            new.append((x1, y1))
        pts = new
        step /= 2.0
        amp *= roughness
    return pts


def _rrect(d, x0, y0, x1, y1, r, fill):
    """Rounded rectangle built from primitives, so it stays crisp at 29px."""
    r = max(1.0, min(r, (x1 - x0) / 2.0, (y1 - y0) / 2.0))
    d.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
    d.rectangle([x0, y0 + r, x1, y1 - r], fill=fill)
    for cx, cy in ((x0 + r, y0 + r), (x1 - r, y0 + r), (x0 + r, y1 - r), (x1 - r, y1 - r)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def hand(d, S, fill):
    """Open hand, palm to camera, fingers up and slightly spread.

    This is the game's inciting image — Cael turning his hands over with light coming out of them —
    and a hand is one of the few shapes that survives being shrunk to 29px, because the brain
    completes it from the fingertip rhythm alone. An earlier version of this icon used the Rupture
    fissure instead; as a widening-downward wedge it read as a glowing tree, which is why the
    subject changed rather than the palette.

    Proportions are deliberately chunky. Anatomically slim fingers merge into a paddle below ~40px.
    """
    cx = S * 0.5
    palm_top, palm_bot = S * 0.455, S * 0.775
    palm_hw = S * 0.175
    _rrect(d, cx - palm_hw, palm_top, cx + palm_hw, palm_bot, S * 0.075, fill)
    # Heel of the hand: slightly narrower, so the silhouette tapers toward the wrist.
    _rrect(d, cx - palm_hw * 0.78, palm_bot - S * 0.02, cx + palm_hw * 0.78, S * 0.86, S * 0.05, fill)

    # (x offset from centre, tip height above palm top, half-width, lean)
    fingers = [
        (-0.118, 0.205, 0.043, -0.016),   # index
        (-0.020, 0.250, 0.045, -0.004),   # middle
        (+0.078, 0.222, 0.043, +0.010),   # ring
        (+0.158, 0.150, 0.037, +0.024),   # little
    ]
    for dx, up, hw, lean in fingers:
        bx = cx + S * dx
        tx = bx + S * lean
        tip_y = palm_top - S * up
        hwp = S * hw
        # Tapered shaft plus a domed tip.
        d.polygon([
            (bx - hwp, palm_top + S * 0.03), (tx - hwp * 0.86, tip_y + hwp),
            (tx + hwp * 0.86, tip_y + hwp), (bx + hwp, palm_top + S * 0.03),
        ], fill=fill)
        d.ellipse([tx - hwp * 0.86, tip_y, tx + hwp * 0.86, tip_y + hwp * 1.72], fill=fill)

    # Thumb: out to the left and down, which is what stops the shape reading as a mitten.
    tb = (cx - palm_hw * 0.85, S * 0.585)
    tt = (cx - palm_hw * 2.02, S * 0.470)
    hwp = S * 0.046
    d.polygon([
        (tb[0] - hwp * 0.5, tb[1] + hwp * 1.5), (tt[0] - hwp * 0.8, tt[1] + hwp),
        (tt[0] + hwp * 0.6, tt[1] - hwp * 0.4), (tb[0] + hwp, tb[1] - hwp),
    ], fill=fill)
    d.ellipse([tt[0] - hwp, tt[1] - hwp * 0.6, tt[0] + hwp, tt[1] + hwp * 1.4], fill=fill)


def rim_light(img, color, light_from="right", depth=2):
    """Paint the first `depth` solid pixels from the lit side, matching the in-game silhouettes."""
    W, H = img.size
    px = img.load()
    mask = img.copy().load()
    dx = 1 if light_from == "right" else -1
    for y in range(H):
        xs = range(W - 1, -1, -1) if dx > 0 else range(W)
        prev_dark = False
        hits = 0
        for x in xs:
            dark = _is_silhouette(mask[x, y])
            if dark and not prev_dark:
                px[x, y] = color
                if 0 <= x - dx < W and _is_silhouette(mask[x - dx, y]):
                    px[x - dx, y] = tuple(v // 2 for v in color)
                hits += 1
                if hits >= depth:
                    break
            prev_dark = dark
    return img


def _is_silhouette(c):
    return c[0] < 30 and c[1] < 26 and c[2] < 36


def build(size):
    """Render the icon at `size`. Drawn at native resolution rather than scaled from 1024, so the
    dithering stays a crisp 1px pattern instead of turning into mush at small sizes."""
    S = size
    ramp = [rgb(c) for c in ASHFALL]
    img = Image.new("RGB", (S, S), ramp[0])
    rnd = random.Random(SEED)

    # Crimson sky, dark at the top, hot toward the horizon.
    dither_ramp(img, ramp, 0, int(S * 0.80), 0.16, 0.80, curve=1.7, seed=1)

    d = ImageDraw.Draw(img)

    # A low ridge so the hand has a world behind it rather than floating on a gradient.
    far = ridge(rnd, S, S * 0.71, S * 0.05, 0.55)
    d.polygon([(0, S)] + [(x, y) for x, y in far] + [(S, S)], fill=ramp[2])
    near = ridge(rnd, S, S * 0.83, S * 0.03, 0.5)
    d.polygon([(0, S)] + [(x, y) for x, y in near] + [(S, S)], fill=ramp[1])

    # The cold wrong light, behind the hand. Drawn *before* the silhouette so the hand occludes it —
    # the shape is defined by contrast against the glow, which is what makes it survive at 29px.
    #
    # The falloff is deliberately shallow and the radius large. A tight bright core would be
    # entirely hidden behind the palm; what has to be visible is the halo *around* the hand and the
    # light coming through the gaps between the fingers.
    # Balance point found by inspection at 29/60/1024 together: strong enough to halo the hand and
    # bleed through the finger gaps, weak enough that the frame still reads crimson. Pushing the
    # radius past ~0.6 or the strength past ~0.7 turns the whole icon teal and loses the world.
    dither_radial(img, S * 0.5, S * 0.58, S * 0.56, rgb(GLOW), 0.66, squash=1.0, falloff=1.30)
    dither_radial(img, S * 0.5, S * 0.58, S * 0.30, rgb(GLOW_HI), 0.55, squash=1.0, falloff=1.30)

    # One ember note so the crimson reads as fire-lit rather than as a flat red sky.
    dither_radial(img, S * 0.88, S * 0.76, S * 0.18, rgb(EMBER), 0.40, squash=1.7, falloff=2.0)

    hand(d, S, ramp[0])

    # Rim the hand in the magic colour it's standing in front of.
    if S >= 40:
        rim_light(img, rgb(GLOW_HI), "right", depth=3 if S >= 180 else (2 if S >= 80 else 1))

    # Light vignette only — a heavy one eats the halo, which is the whole point of the composition.
    vignette(img, ramp[0], 0.45)
    return img


def build_splash(W=480, H=960):
    """Boot splash. Same language as the icon, composed for a tall screen with room for the title."""
    ramp = [rgb(c) for c in ASHFALL]
    img = Image.new("RGB", (W, H), ramp[0])
    rnd = random.Random(SEED + 5)
    dither_ramp(img, ramp, 0, int(H * 0.76), 0.10, 0.72, curve=2.0, seed=3)

    d = ImageDraw.Draw(img)
    far = ridge(rnd, W, H * 0.62, 30, 0.55)
    d.polygon([(0, H)] + [(x, y) for x, y in far] + [(W, H)], fill=ramp[2])
    near = ridge(rnd, W, H * 0.72, 18, 0.5)
    d.polygon([(0, H)] + [(x, y) for x, y in near] + [(W, H)], fill=ramp[1])

    # Same subject as the icon, positioned lower so the splash has headroom for the title text the
    # boot scene draws over it.
    dither_radial(img, W * 0.5, H * 0.615, W * 0.85, rgb(GLOW), 0.60, falloff=1.5)
    dither_radial(img, W * 0.5, H * 0.615, W * 0.42, rgb(GLOW_HI), 0.52, falloff=1.4)

    # The hand helper is written against a square canvas; run it on one and paste it in.
    hs = int(W * 1.02)
    layer = Image.new("RGB", (hs, hs), (0, 0, 0))
    hand(ImageDraw.Draw(layer), hs, ramp[0])
    lp = layer.load()
    px = img.load()
    oy = int(H * 0.615 - hs * 0.61)
    for y in range(hs):
        ty = y + oy
        if ty < 0 or ty >= H:
            continue
        for x in range(hs):
            tx = x + int((W - hs) * 0.5)
            if 0 <= tx < W and lp[x, y] == ramp[0]:
                px[tx, ty] = ramp[0]

    rim_light(img, rgb(GLOW_HI), "right", depth=2)
    vignette(img, ramp[0], 0.42)
    return img


def build_dark(S=1024):
    """Dark-appearance variant. iOS 18+ shows this when the home screen is in dark mode. The icon is
    already a night scene, so this is the same composition pushed deeper rather than a redesign."""
    img = build(S)
    px = img.load()
    for y in range(S):
        for x in range(S):
            r, g, b = px[x, y]
            px[x, y] = (int(r * 0.62), int(g * 0.62), int(b * 0.70))
    return img


def build_tinted(S=1024):
    """Tinted-appearance variant. iOS applies the user's chosen hue itself, so this must be
    greyscale — supplying a coloured image here produces a muddy double-tint on device."""
    img = build(S)
    px = img.load()
    for y in range(S):
        for x in range(S):
            r, g, b = px[x, y]
            # Rec. 709 luma, then expanded so the hand still separates from the halo once the
            # crimson/cyan colour contrast the design relies on is gone.
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            v = int(max(0.0, min(255.0, (lum - 26.0) * 1.55)))
            px[x, y] = (v, v, v)
    return img


def main():
    os.makedirs(ICON_DIR, exist_ok=True)
    for size, name in IOS_SIZES:
        # Opaque, no alpha channel — App Store rejects icons with transparency.
        build(size).convert("RGB").save(os.path.join(ICON_DIR, name))
    build_dark().convert("RGB").save(os.path.join(ICON_DIR, "icon_1024_dark.png"))
    build_tinted().convert("RGB").save(os.path.join(ICON_DIR, "icon_1024_tinted.png"))
    print("icons: %d sizes + dark + tinted -> assets/icon/" % len(IOS_SIZES))

    build_splash().save(os.path.join(ROOT, "assets", "splash.png"))
    print("splash: assets/splash.png")

    # Godot's own editor/window icon.
    build(256).save(os.path.join(ROOT, "assets", "icon.png"))
    print("editor icon: assets/icon.png")


if __name__ == "__main__":
    main()
