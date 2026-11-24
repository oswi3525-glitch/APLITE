#!/usr/bin/env python3
"""Regenerate every bundled APLite raster asset (deterministic, no network).

Usage: python3 scripts/generate_assets.py
Requires Pillow. Outputs are committed so normal builds need neither Python nor Pillow.
The style: deep navy/teal glass, soft light blooms, crisp white glyphs, 4x supersampled.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import json, math

ROOT = Path(__file__).resolve().parent.parent / "APLite" / "Assets.xcassets"
S = 4


def canvas(size):
    return Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0))


def finish(img, size):
    return img.resize((size, size), Image.Resampling.LANCZOS)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient(size, stops):
    """stops: [(position 0..1, (r,g,b)), ...] top -> bottom."""
    img = canvas(size)
    px = img.load()
    w = h = size * S
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                local = (t - p0) / max(0.0001, p1 - p0)
                c = lerp(c0, c1, local)
                break
        else:
            c = stops[-1][1]
        for x in range(w):
            px[x, y] = c + (255,)
    return img


def glow(img, color, box, blur, alpha=150):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(tuple(int(v * S) for v in box), fill=color + (alpha,))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur * S)))


def mask_rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, img.width - 1, img.height - 1), radius=int(img.width * radius * S), fill=255)
    img.putalpha(mask)
    return img


def sheen(img, size, alpha=34):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([(0, 0), (int(size * S * 0.95), 0), (0, int(size * S * 0.78))], fill=(255, 255, 255, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(12 * S))
    img.alpha_composite(layer)
    return img


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, int(size * S))
    return ImageFont.load_default()


def centered_text(d, box, text, fnt, fill):
    x0, y0, x1, y1 = [int(v * S) for v in box]
    bb = d.textbbox((0, 0), text, font=fnt)
    d.text((x0 + (x1 - x0 - (bb[2] - bb[0])) / 2 - bb[0],
            y0 + (y1 - y0 - (bb[3] - bb[1])) / 2 - bb[1]), text, font=fnt, fill=fill)


def tile(size, stops, radius=0.23):
    img = gradient(size, stops)
    glow(img, stops[-1][1], (size * 0.1, -size * 0.25, size * 0.95, size * 0.5), 0.16, 110)
    mask_rounded(img, radius)
    sheen(img, size, 30)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((2 * S, 2 * S, size * S - 2 * S, size * S - 2 * S),
                        radius=int(size * radius * S), outline=(255, 255, 255, 45), width=2 * S)
    return img


def imageset(name, big, small):
    # Xcode derives the asset type from the folder extension. A plain folder is ignored by the
    # asset catalog, which made every branded icon invisible at runtime.
    folder = ROOT / (name if name.endswith(".imageset") else name + ".imageset")
    folder.mkdir(parents=True, exist_ok=True)
    big.save(folder / f"{name}@3x.png", optimize=True)
    small.save(folder / f"{name}.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [
            {"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
            {"filename": f"{name}@3x.png", "idiom": "universal", "scale": "3x"},
        ], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


# ---------------------------------------------------------------- App icon
icon = gradient(1024, [(0, (7, 18, 38)), (0.48, (9, 48, 74)), (1, (10, 96, 96))])
glow(icon, (56, 189, 248), (110, -190, 920, 560), 110, 165)
glow(icon, (45, 212, 168), (-190, 520, 640, 1220), 130, 150)
glow(icon, (120, 90, 240), (620, 600, 1200, 1120), 140, 70)
d = ImageDraw.Draw(icon)
for inset, width, alpha in ((168, 11, 120), (222, 7, 88), (272, 4, 58)):
    d.arc((inset * S, (inset + 96) * S, (1024 - inset) * S, (1024 - inset + 96) * S),
          start=198, end=342, fill=(224, 250, 255, alpha), width=width * S)
centered_text(d, (190, 236, 834, 786), "A", font(372), (255, 255, 255, 248))
d.polygon([(512 * S, 706 * S), (636 * S, 858 * S), (388 * S, 858 * S)], fill=(255, 255, 255, 238))
sheen(icon, 1024, 22)
appicon = finish(icon, 1024)
appicon.convert("RGB").save(ROOT / "AppIcon.appiconset" / "AppIcon.png", optimize=True)

# ---------------------------------------------------------------- Launch mark
mark = canvas(512)
d = ImageDraw.Draw(mark)
d.arc((84 * S, 126 * S, 428 * S, 432 * S), start=202, end=338,
      fill=(56, 189, 248, 230), width=19 * S)
d.arc((104 * S, 146 * S, 408 * S, 412 * S), start=204, end=336,
      fill=(160, 240, 230, 120), width=5 * S)
centered_text(d, (76, 96, 436, 412), "A", font(252), (255, 255, 255, 255))
big_mark = finish(mark, 512)
(ROOT / "LaunchMark.imageset").mkdir(parents=True, exist_ok=True)
big_mark.save(ROOT / "LaunchMark.imageset" / "LaunchMark@3x.png", optimize=True)
big_mark.resize((256, 256), Image.Resampling.LANCZOS).save(
    ROOT / "LaunchMark.imageset" / "LaunchMark.png", optimize=True)
(ROOT / "LaunchMark.imageset" / "Contents.json").write_text(json.dumps({
    "images": [
        {"filename": "LaunchMark.png", "idiom": "universal", "scale": "1x"},
        {"filename": "LaunchMark@3x.png", "idiom": "universal", "scale": "3x"},
    ], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

# ---------------------------------------------------------------- Lock mark
lock = canvas(256)
d = ImageDraw.Draw(lock)
d.ellipse((18 * S, 18 * S, 238 * S, 238 * S), fill=(255, 255, 255, 26))
d.ellipse((18 * S, 18 * S, 238 * S, 238 * S), outline=(255, 255, 255, 110), width=3 * S)
# shackle
d.arc((74 * S, 48 * S, 182 * S, 156 * S), start=180, end=360, fill=(255, 255, 255, 250), width=15 * S)
# body
d.rounded_rectangle((62 * S, 118 * S, 194 * S, 204 * S), radius=18 * S, fill=(255, 255, 255, 248))
d.ellipse((114 * S, 146 * S, 142 * S, 174 * S), fill=(20, 74, 96, 255))
d.rounded_rectangle((121 * S, 160 * S, 135 * S, 186 * S), radius=5 * S, fill=(20, 74, 96, 255))
big_lock = finish(lock, 256)
imageset("LockMark", big_lock, big_lock.resize((96, 96), Image.Resampling.LANCZOS))

# ---------------------------------------------------------------- Built-in app icons
def browser():
    img = tile(192, [(0, (36, 150, 226)), (1, (12, 70, 144))])
    d = ImageDraw.Draw(img)
    c = 96 * S
    d.ellipse((c - 58 * S, c - 58 * S, c + 58 * S, c + 58 * S), outline=(255, 255, 255, 230), width=6 * S)
    d.arc((c - 30 * S, c - 58 * S, c + 30 * S, c + 58 * S), 90, 270, fill=(255, 255, 255, 200), width=5 * S)
    d.arc((c - 30 * S, c - 58 * S, c + 30 * S, c + 58 * S), 270, 450, fill=(255, 255, 255, 200), width=5 * S)
    d.line((c - 57 * S, c, c + 57 * S, c), fill=(255, 255, 255, 220), width=5 * S)
    d.arc((c - 56 * S, c - 58 * S, c + 56 * S, c + 58 * S), 0, 360, fill=(255, 255, 255, 160), width=4 * S)
    return finish(img, 192)


def files():
    img = tile(192, [(0, (92, 208, 142)), (1, (18, 104, 92))])
    d = ImageDraw.Draw(img)
    d.polygon([(24 * S, 66 * S), (74 * S, 66 * S), (90 * S, 48 * S), (132 * S, 48 * S),
               (148 * S, 66 * S), (168 * S, 66 * S), (168 * S, 84 * S), (24 * S, 84 * S)],
              fill=(242, 252, 246, 245))
    d.rounded_rectangle((24 * S, 76 * S, 168 * S, 152 * S), radius=14 * S, fill=(248, 253, 249, 240))
    d.rounded_rectangle((24 * S, 76 * S, 168 * S, 92 * S), radius=8 * S, fill=(220, 242, 230, 250))
    return finish(img, 192)


def settings():
    img = tile(192, [(0, (166, 176, 192)), (1, (74, 84, 104))])
    d = ImageDraw.Draw(img)
    c = 96 * S
    points = []
    for i in range(24):
        a = i * math.pi / 12
        r = 62 * S if i % 3 in (0, 1) else 48 * S
        points.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(points, fill=(255, 255, 255, 226))
    d.ellipse((c - 38 * S, c - 38 * S, c + 38 * S, c + 38 * S), fill=(78, 88, 108, 255))
    d.ellipse((c - 22 * S, c - 22 * S, c + 22 * S, c + 22 * S), fill=(255, 255, 255, 240))
    return finish(img, 192)


def trash():
    img = tile(192, [(0, (222, 116, 116)), (1, (124, 44, 56))])
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((38 * S, 50 * S, 154 * S, 64 * S), radius=7 * S, fill=(255, 252, 252, 248))
    d.rounded_rectangle((84 * S, 38 * S, 108 * S, 52 * S), radius=6 * S, fill=(255, 252, 252, 248))
    d.rounded_rectangle((50 * S, 68 * S, 142 * S, 154 * S), radius=12 * S, fill=(255, 246, 246, 240))
    for x in (72, 96, 120):
        d.rounded_rectangle((x * S, 82 * S, (x + 7) * S, 140 * S), radius=4 * S, fill=(190, 70, 72, 170))
    return finish(img, 192)


# --------------------------------------------------- built-in web app icons
def zalo():
    img = tile(192, [(0, (44, 156, 240)), (1, (12, 78, 168))])
    d = ImageDraw.Draw(img)
    centered_text(d, (44, 30, 148, 138), "Z", font(126), (255, 255, 255, 250))
    # small chat bubble tail
    d.polygon([(60 * S, 126 * S), (92 * S, 126 * S), (60 * S, 152 * S)],
              fill=(255, 255, 255, 240))
    return finish(img, 192)


def facebook():
    img = tile(192, [(0, (72, 150, 255)), (1, (24, 92, 222))])
    d = ImageDraw.Draw(img)
    centered_text(d, (54, 18, 138, 150), "f", font(152), (255, 255, 255, 252))
    return finish(img, 192)


def telegram():
    img = tile(192, [(0, (56, 202, 244)), (1, (16, 126, 196))])
    d = ImageDraw.Draw(img)
    # paper plane: nose, two swept wings and the folded centre
    d.polygon([(38 * S, 96 * S), (158 * S, 46 * S), (128 * S, 150 * S),
               (96 * S, 118 * S), (78 * S, 138 * S), (80 * S, 106 * S)],
              fill=(255, 255, 255, 248))
    d.polygon([(80 * S, 106 * S), (158 * S, 46 * S), (96 * S, 118 * S)],
              fill=(214, 238, 252, 220))
    return finish(img, 192)


for name, fn in (("BrowserIcon", browser), ("FilesIcon", files),
                 ("SettingsIcon", settings), ("TrashIcon", trash),
                 ("ZaloIcon", zalo), ("FacebookIcon", facebook),
                 ("TelegramIcon", telegram)):
    big = fn()
    imageset(name, big, big.resize((64, 64), Image.Resampling.LANCZOS))


def colorset(name, hex_color):
    folder = ROOT / (name if name.endswith(".colorset") else name + ".colorset")
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
