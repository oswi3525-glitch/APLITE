#!/usr/bin/env python3
"""Draw APLite's bundled 'Đồng cỏ' (meadow) wallpaper locally — no network needed.

The image is a deterministic procedural illustration: a calm golden-hour sky, soft hills and a
textured grass field with small wildflowers. Output goes straight into the asset catalog.
"""
from pathlib import Path
import math
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 1920, 1080
random.seed(20261122)

out = Path(__file__).resolve().parent.parent / "APLite/Assets.xcassets/MeadowWallpaper.imageset"
out.mkdir(parents=True, exist_ok=True)

# Sky: top teal-blue fading into warm gold at the horizon.
sky = Image.new("RGB", (W, H))
px = sky.load()
horizon = int(H * 0.52)
for y in range(H):
    if y < horizon:
        t = y / horizon
        r = int(18 + 225 * t ** 2)
        g = int(62 + 150 * t)
        b = int(96 - 30 * t)
    else:
        t = (y - horizon) / (H - horizon)
        r, g, b = int(60 - 30 * t), int(120 - 45 * t), int(48 - 24 * t)
    for x in range(W):
        px[x, y] = (r, g, b)

# Soft sun glow.
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W * 0.70 - 170, horizon - 250, W * 0.70 + 170, horizon + 90], fill=(255, 226, 150, 120))
glow = glow.filter(ImageFilter.GaussianBlur(70))
sky = Image.alpha_composite(sky.convert("RGBA"), glow).convert("RGB")

draw = ImageDraw.Draw(sky)

# Distant hills, three layers for depth.
for layer, (base, amp, color) in enumerate([
    (horizon - 40, 46, (86, 128, 88)),
    (horizon + 10, 70, (58, 106, 62)),
    (horizon + 70, 90, (38, 86, 45)),
]):
    points = [(0, H)]
    for x in range(0, W + 40, 40):
        y = base - amp * (0.5 + 0.5 * math.sin(x / (220 + layer * 90) + layer))
        points.append((x, y))
    points.append((W, H))
    draw.polygon(points, fill=color)

# Grass field with a quiet perspective: shorter blades toward the horizon.
for i in range(26000):
    y = random.randint(horizon + 60, H - 1)
    depth = (y - horizon) / (H - horizon)
    x = random.randint(0, W - 1)
    length = int(6 + 34 * depth * random.uniform(0.5, 1.2))
    shade = random.randint(-18, 18)
    c = (
        max(0, min(255, int(48 + 46 * depth + shade))),
        max(0, min(255, int(104 + 44 * depth + shade))),
        max(0, min(255, int(46 + 10 * depth + shade // 2))),
    )
    lean = random.randint(-6, 6)
    draw.line([(x, y), (x + lean, y - length)], fill=c, width=1 if depth < 0.6 else 2)

# Wildflowers: tiny warm and pale dots, more numerous near the viewer.
for i in range(900):
    y = random.randint(horizon + 120, H - 1)
    x = random.randint(0, W - 1)
    r = random.randint(1, 3)
    color = random.choice([(255, 236, 170), (255, 196, 210), (226, 240, 255), (255, 222, 120)])
    draw.ellipse([x - r, y - r, x + r, y + r], fill=color)

# Gentle grain and a light vignette for a photographic finish.
grain = Image.new("L", (W, H), 0)
grain.putdata([random.randint(0, 26) for _ in range(W * H)])
sky = Image.blend(sky, Image.merge("RGB", (grain, grain, grain)), 0.06)
vignette = Image.new("L", (W, H), 0)
vd = ImageDraw.Draw(vignette)
vd.ellipse([-W * 0.25, -H * 0.35, W * 1.25, H * 1.35], fill=255)
vignette = vignette.filter(ImageFilter.GaussianBlur(180))
sky = Image.composite(sky, Image.new("RGB", (W, H), (6, 18, 14)), vignette)

target = out / "meadow.png"
sky.save(target, optimize=True)
(out / "Contents.json").write_text(
    '{\n  "images" : [\n    {\n      "filename" : "meadow.png",\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
)
(out.parent / "Contents.json").write_text('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
print(f"wrote {target} ({target.stat().st_size // 1024} KB)")
