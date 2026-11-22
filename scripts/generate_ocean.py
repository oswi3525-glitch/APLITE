#!/usr/bin/env python3
"""Draw APLite's bundled 'Biển' (ocean) wallpaper locally — no network needed.

Deterministic procedural illustration: a calm golden-hour sky, a low sun and a textured sea with
gentle swells and a shimmering reflection. Output goes straight into the asset catalog, exactly
like scripts/generate_meadow.py.
"""
from pathlib import Path
import math
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 1920, 1080
random.seed(20261123)

out = Path(__file__).resolve().parent.parent / "APLite/Assets.xcassets/OceanWallpaper/ocean.imageset"
out.mkdir(parents=True, exist_ok=True)

horizon = int(H * 0.46)
sun_x = int(W * 0.68)
sun_y = horizon - 96

# ---------------------------------------------------------------- sky
sky = Image.new("RGB", (W, H))
px = sky.load()
for y in range(H):
    if y < horizon:
        t = y / horizon
        # deep blue at the top → teal → warm gold near the water
        r = int(12 + 235 * (t ** 2.2))
        g = int(48 + 120 * (t ** 1.9))
        b = int(112 - 22 * t)
    else:
        t = (y - horizon) / (H - horizon)
        r, g, b = int(14 + 6 * t), int(74 - 26 * t), int(104 - 40 * t)
    for x in range(W):
        px[x, y] = (r, g, b)

# Warm sun glow and disc.
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([sun_x - 260, sun_y - 260, sun_x + 260, sun_y + 260], fill=(255, 216, 150, 150))
glow = glow.filter(ImageFilter.GaussianBlur(110))
sky = Image.alpha_composite(sky.convert("RGBA"), glow).convert("RGB")
disc = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(disc).ellipse([sun_x - 38, sun_y - 38, sun_x + 38, sun_y + 38], fill=(255, 244, 214, 245))
disc = disc.filter(ImageFilter.GaussianBlur(6))
sky = Image.alpha_composite(sky.convert("RGBA"), disc).convert("RGB")

# Soft horizontal clouds, fanned out toward the horizon.
clouds = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(clouds)
for i in range(26):
    cx = random.randint(0, W)
    cy = random.randint(40, horizon - 40)
    cw = random.randint(140, 520) * (0.5 + 0.5 * cy / horizon)
    ch = random.randint(8, 24)
    tone = random.randint(190, 255)
    cd.ellipse([cx - cw / 2, cy - ch, cx + cw / 2, cy + ch],
               fill=(tone, tone - 8, tone - 18, random.randint(24, 64)))
clouds = clouds.filter(ImageFilter.GaussianBlur(22))
sky = Image.alpha_composite(sky.convert("RGBA"), clouds).convert("RGB")

draw = ImageDraw.Draw(sky)

# ---------------------------------------------------------------- sea
# Horizontal swell bands: brighter where the sun reflects, darker farther out.
for y in range(horizon, H):
    depth = (y - horizon) / (H - horizon)
    for x in range(0, W, 4):
        wave = (math.sin(x / (70 + 130 * depth) + depth * 22)
                + 0.5 * math.sin(x / 37 + depth * 41)) * (2 + 9 * depth)
        # Reflection column under the sun, tapering toward the viewer.
        spread = 70 + 460 * depth
        dx = abs(x - sun_x) / spread
        shimmer = max(0.0, 1.0 - dx) ** 2 * (0.55 + 0.45 * math.sin(x / 9 + y / 7))
        r = int(14 + 26 * depth + 150 * shimmer * (0.6 + 0.4 * depth) + wave)
        g = int(66 - 18 * depth + 130 * shimmer + wave)
        b = int(94 - 34 * depth + 100 * shimmer + wave)
        c = (max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
        draw.rectangle([x, y, x + 4, y], fill=c)

# Whitecaps / foam: short bright strokes, denser near the viewer.
for i in range(5200):
    depth = random.random() ** 1.6
    y = int(horizon + 12 + depth * (H - horizon - 12))
    x = random.randint(0, W - 1)
    length = int(8 + 46 * depth * random.uniform(0.4, 1.0))
    dx = abs(x - sun_x) / (110 + 420 * depth)
    shine = max(0.0, 1.0 - dx)
    alpha = 90 + int(120 * shine)
    tone = int(206 + 44 * shine)
    draw.line([(x, y), (x + length, y + random.randint(-2, 2))],
              fill=(tone, tone + 6, min(255, tone + 12), alpha), width=1 if depth < 0.5 else 2)

# A thin bright horizon line.
draw.line([(0, horizon), (W, horizon)], fill=(255, 226, 178, 150), width=2)

# ---------------------------------------------------------------- finish
grain = Image.new("L", (W, H), 0)
grain.putdata([random.randint(0, 22) for _ in range(W * H)])
sky = Image.blend(sky, Image.merge("RGB", (grain, grain, grain)), 0.05)
vignette = Image.new("L", (W, H), 0)
vd = ImageDraw.Draw(vignette)
vd.ellipse([-W * 0.22, -H * 0.32, W * 1.22, H * 1.30], fill=255)
vignette = vignette.filter(ImageFilter.GaussianBlur(170))
sky = Image.composite(sky, Image.new("RGB", (W, H), (4, 16, 28)), vignette)

target = out / "ocean.png"
sky.save(target, optimize=True)
(out / "Contents.json").write_text(
    '{\n  "images" : [\n    {\n      "filename" : "ocean.png",\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
)
(out.parent / "Contents.json").write_text('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
print(f"wrote {target} ({target.stat().st_size // 1024} KB)")
