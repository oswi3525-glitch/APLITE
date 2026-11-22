#!/usr/bin/env python3
"""Regenerate APLite's bundled raster assets (no network, deterministic).

Usage: python3 scripts/generate_assets.py
Requires: Pillow (pip install pillow). Outputs are committed so a normal
build needs neither Python nor Pillow.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import json, math

ROOT = Path(__file__).resolve().parent.parent / "iDesk" / "Assets.xcassets"
S = 3  # supersample


def canvas(size):
    return Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0))


def finish(img, size):
    return img.resize((size, size), Image.Resampling.LANCZOS)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient(size, top, bottom):
    img = canvas(size)
    px = img.load()
    for y in range(size * S):
        c = lerp(top, bottom, y / max(1, size * S - 1))
        for x in range(size * S):
            px[x, y] = c + (255,)
    return img


def glow(img, color, box, blur):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse(tuple(int(v * S) for v in box), fill=color + (150,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur * S))
    img.alpha_composite(layer)


def rounded_tile(size, top, bottom, radius=0.22):
    img = gradient(size, top, bottom)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * S - 1, size * S - 1),
                                           radius=int(size * radius * S), fill=255)
    img.putalpha(mask)
    return img


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf"):
        if Path(path).exists():
            from PIL import ImageFont
            return ImageFont.truetype(path, int(size * S))
    from PIL import ImageFont
    return ImageFont.load_default()


def centered_text(d, box, text, fnt, fill):
    x0, y0, x1, y1 = [int(v * S) for v in box]
    bb = d.textbbox((0, 0), text, font=fnt)
    d.text((x0 + (x1 - x0 - (bb[2] - bb[0])) / 2 - bb[0],
            y0 + (y1 - y0 - (bb[3] - bb[1])) / 2 - bb[1]), text, font=fnt, fill=fill)


# App icon: deep glass, teal light, an AirPlay-style arc and a crisp A.
icon = gradient(1024, (7, 19, 40), (9, 62, 78))
glow(icon, (56, 189, 248), (120, -160, 900, 560), 90)
glow(icon, (32, 211, 170), (-180, 520, 620, 1180), 110)
d = ImageDraw.Draw(icon)
for i, (inset, width, alpha) in enumerate([(196, 9, 110), (244, 6, 80), (288, 4, 55)]):
    d.arc((inset * S, (inset + 90) * S, (1024 - inset) * S, (1024 - inset + 90) * S),
          start=196, end=344, fill=(220, 250, 255, alpha), width=width * S)
centered_text(d, (200, 250, 824, 790), "A", font(360), (255, 255, 255, 245))
d.polygon([(512 * S, 700 * S), (632 * S, 850 * S), (392 * S, 850 * S)], fill=(255, 255, 255, 235))
icon = finish(icon, 1024)
icon.convert("RGB").save(ROOT / "AppIcon.appiconset" / "AppIcon.png", optimize=True)

# Launch mark: transparent, used by UILaunchScreen (no app name drawn here).
(ROOT / "LaunchMark.imageset").mkdir(parents=True, exist_ok=True)
mark = canvas(512)
d = ImageDraw.Draw(mark)
d.arc((90 * S, 130 * S, 422 * S, 430 * S), start=200, end=340, fill=(56, 189, 248, 220), width=18 * S)
centered_text(d, (80, 100, 432, 410), "A", font(250), (255, 255, 255, 255))
finish(mark, 512).save(ROOT / "LaunchMark.imageset" / "LaunchMark.png", optimize=True)

# Built-in app icons (small, crisp, no text).
def browser():
    img = rounded_tile(192, (28, 122, 224), (12, 64, 140))
    d = ImageDraw.Draw(img)
    c = 96 * S
    for r, w in ((58, 5), (58, 2), (30, 4)):
        d.ellipse((c - r * S, c - r * S, c + r * S, c + r * S), outline=(255, 255, 255, 210), width=w * S)
    d.line((c - 58 * S, c, c + 58 * S, c), fill=(255, 255, 255, 210), width=4 * S)
    d.arc((c - 58 * S, c - 58 * S, c + 58 * S, c + 58 * S), 0, 360, fill=(255, 255, 255, 210), width=4 * S)
    return finish(img, 192)


def files():
    img = rounded_tile(192, (86, 196, 138), (24, 108, 92))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((26 * S, 56 * S, 166 * S, 150 * S), radius=12 * S, fill=(245, 252, 247, 235))
    d.polygon([(26 * S, 70 * S), (76 * S, 70 * S), (90 * S, 52 * S), (128 * S, 52 * S),
               (142 * S, 70 * S), (166 * S, 70 * S), (166 * S, 86 * S), (26 * S, 86 * S)],
              fill=(225, 244, 232, 240))
    return finish(img, 192)


def settings():
    img = rounded_tile(192, (150, 158, 174), (76, 84, 104))
    d = ImageDraw.Draw(img)
    c = 96 * S
    for i in range(8):
        a = i * math.pi / 4
        x, y = c + 54 * S * math.cos(a), c + 54 * S * math.sin(a)
        d.rounded_rectangle((x - 9 * S, y - 22 * S, x + 9 * S, y + 22 * S), radius=8 * S,
                            fill=(255, 255, 255, 220))
    d.ellipse((c - 48 * S, c - 48 * S, c + 48 * S, c + 48 * S), fill=(70, 78, 96, 255))
    d.ellipse((c - 24 * S, c - 24 * S, c + 24 * S, c + 24 * S), fill=(255, 255, 255, 235))
    return finish(img, 192)


def trash():
    img = rounded_tile(192, (206, 110, 110), (128, 48, 58))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((48 * S, 64 * S, 144 * S, 152 * S), radius=10 * S, fill=(255, 246, 246, 235))
    d.rounded_rectangle((40 * S, 52 * S, 152 * S, 66 * S), radius=6 * S, fill=(255, 255, 255, 245))
    d.rounded_rectangle((84 * S, 40 * S, 108 * S, 54 * S), radius=6 * S, fill=(255, 255, 255, 245))
    for x in (74, 96, 118):
        d.rounded_rectangle((x * S, 80 * S, (x + 8) * S, 138 * S), radius=4 * S,
                            fill=(180, 70, 70, 180))
    return finish(img, 192)


def camera():
    img = rounded_tile(192, (88, 170, 210), (26, 96, 132))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((28 * S, 60 * S, 164 * S, 146 * S), radius=16 * S,
                        fill=(248, 252, 255, 240))
    d.rounded_rectangle((66 * S, 48 * S, 126 * S, 66 * S), radius=7 * S,
                        fill=(232, 244, 250, 245))
    d.ellipse((68 * S, 76 * S, 124 * S, 132 * S), fill=(52, 132, 168, 255))
    d.ellipse((80 * S, 88 * S, 112 * S, 120 * S), fill=(22, 62, 88, 255))
    return finish(img, 192)


def imageset(name, image192, image64):
    folder = ROOT / name
    folder.mkdir(parents=True, exist_ok=True)
    image64.save(folder / f"{name}.png", optimize=True)
    image192.save(folder / f"{name}@3x.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [
            {"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
            {"filename": f"{name}@3x.png", "idiom": "universal", "scale": "3x"},
        ], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


# Source at 192, 1x at 64 for the small dock/desktop glyphs.
for name, fn in (("BrowserIcon", browser), ("FilesIcon", files),
                 ("SettingsIcon", settings), ("TrashIcon", trash),
                 ("CameraIcon", camera)):
    big = fn()
    imageset(name, big, big.resize((64, 64), Image.Resampling.LANCZOS))

# LaunchMark needs a 1x/3x imageset too.
mark512 = finish(mark, 512)
markdir = ROOT / "LaunchMark.imageset"
(markdir / "LaunchMark.png").write_bytes((markdir / "LaunchMark.png").read_bytes())
(markdir / "LaunchMark@3x.png").write_bytes((markdir / "LaunchMark.png").read_bytes())
(markdir / "Contents.json").write_text(json.dumps({
    "images": [
        {"filename": "LaunchMark.png", "idiom": "universal", "scale": "1x"},
        {"filename": "LaunchMark@3x.png", "idiom": "universal", "scale": "3x"},
    ], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def colorset(name, hex_color):
    folder = ROOT / name
    folder.mkdir(parents=True, exist_ok=True)
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    (folder / "Contents.json").write_text(json.dumps({
        "colors": [{"color": {"color-space": "srgb", "components": {
            "alpha": "1.000", "blue": f"{b:.3f}", "green": f"{g:.3f}", "red": f"{r:.3f}"}},
            "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


colorset("LaunchBackground", "071426")
colorset("AccentColor", "38BDF8")
print("assets written to", ROOT)
