#!/usr/bin/env python3
"""Ad image assets (Google Ads style): three looks x three shapes x two languages -> promo/ads/*.png
  A  night   dark neon background, a close-up of the lanes, the mascot peeking in
  B  pop     the thumbnail's stripes and halftone, the mascot big, one phone screen
  C  steps   pastel background, three phone screens: plant / play / grow
Shapes: L 1200x628 (1.91:1), S 1200x1200 (1:1), P 960x1200 (4:5). Languages: ja, en (a descriptive catch line).
Usage: python3 tools/make_ad_assets.py
Inputs: assets/branding/{logo_beat_garden,mascot_cutout}.png, assets/screenshots/*."""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "promo/ads"
SHOTS = ROOT / "assets/screenshots"
BRAND = ROOT / "assets/branding"
FONT_JA = "/System/Library/Fonts/ヒラギノ丸ゴ ProN W4.ttc"
FONT_EN = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
INK = (44, 18, 82)
SIZES = {"L": (1200, 628), "S": (1200, 1200), "P": (960, 1200)}

COPY = {
    "ja": {
        "night": ["リズムゲームで", "庭を育てよう"],
        "pop": ["タップして、育てて、", "遊ぼう！"],
        "steps_head": ["植えて、リズムで世話して、育てよう"],
        "steps": ["植える", "リズムで世話", "育つ！"],
        "free": "無料で遊べる",
    },
    "en": {
        "night": ["Tap to the beat.", "Grow your garden."],
        "pop": ["A free rhythm game", "where plants grow"],
        "steps_head": ["Plant it. Play the rhythm. Watch it grow."],
        "steps": ["Plant a seed", "Play the rhythm", "Watch it grow!"],
        "free": "Free on Roblox",
    },
}


def font(lang, size):
    return ImageFont.truetype(FONT_EN if lang == "en" else FONT_JA, size)


def load(path):
    return Image.open(path).convert("RGBA")


def fit_w(img, w):
    return img.resize((round(w), round(img.height * w / img.width)), Image.LANCZOS)


def fit_h(img, h):
    return img.resize((round(img.width * h / img.height), round(h)), Image.LANCZOS)


def shadowed(canvas, pic, x, y, angle=0.0, blur=14, alpha=0.5, dy=18):
    if angle:
        pic = pic.rotate(angle, resample=Image.BICUBIC, expand=True)
    lay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sh = Image.new("RGBA", pic.size, (30, 0, 60, 0))
    sh.putalpha(pic.getchannel("A").point(lambda v: int(v * alpha)))
    lay.paste(sh, (round(x + dy * 0.6), round(y + dy)), sh)
    canvas.alpha_composite(lay.filter(ImageFilter.GaussianBlur(blur)))
    lay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    lay.paste(pic, (round(x), round(y)), pic)
    canvas.alpha_composite(lay)


def sticker(src, outline=10, color=(255, 255, 255, 255)):
    grown = src.getchannel("A")
    for _ in range(outline):
        grown = grown.filter(ImageFilter.MaxFilter(3))
    base = Image.new("RGBA", src.size, color)
    base.putalpha(grown)
    return Image.alpha_composite(base, src)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out


def framed(img, w, border=8, radius=26, color=(18, 14, 40, 255), glow=None):
    """The picture with rounded corners inside a dark bezel, and an optional coloured glow around it."""
    pic = fit_w(img, w - border * 2)
    pic = rounded(pic, radius - border)
    box = Image.new("RGBA", (pic.width + border * 2, pic.height + border * 2), color)
    box = rounded(box, radius)
    box.alpha_composite(pic, (border, border))
    if glow:
        pad = 60
        g = Image.new("RGBA", (box.width + pad * 2, box.height + pad * 2), (0, 0, 0, 0))
        gl = Image.new("RGBA", box.size, glow + (255,))
        gl.putalpha(box.getchannel("A"))
        g.alpha_composite(gl, (pad, pad))
        g = g.filter(ImageFilter.GaussianBlur(22))
        g.alpha_composite(box, (pad, pad))
        return g, pad
    return box, 0


def text(canvas, lines, x, y, size, lang, fill=(255, 255, 255), stroke=INK, sw=None, align="left", gap=1.12, max_w=None):
    d = ImageDraw.Draw(canvas)
    while max_w and size > 12 and max(d.textlength(t, font=font(lang, size)) for t in lines) > max_w:
        size -= 1  # shrink until the longest line fits
    f = font(lang, size)
    sw = max(2, size // 9) if sw is None else sw
    for i, line in enumerate(lines):
        w = d.textlength(line, font=f)
        px = x - w / 2 if align == "center" else x
        d.text((px, y + i * size * gap), line, font=f, fill=fill, stroke_width=sw, stroke_fill=stroke)


def star(canvas, cx, cy, r, color=(255, 244, 130, 255)):
    lay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    for rr, col in ((r + r * 0.22, INK + (255,)), (r, color)):
        pts = []
        for i in range(8):
            ang = math.pi / 4 * i - math.pi / 2
            rad = rr if i % 2 == 0 else rr * 0.3
            pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
        ld.polygon(pts, fill=col)
    canvas.alpha_composite(lay)


def pill(canvas, label, cx, cy, lang, size, fill=(255, 244, 130), ink=INK):
    f = font(lang, size)
    d = ImageDraw.Draw(canvas)
    w = d.textlength(label, font=f)
    pad = size * 0.55
    box = [cx - w / 2 - pad, cy - size * 0.75, cx + w / 2 + pad, cy + size * 0.75]
    d.rounded_rectangle(box, size, fill=fill + (255,), outline=ink + (255,), width=max(2, size // 8))
    d.text((cx - w / 2, cy - size * 0.58), label, font=f, fill=ink)


# --- backgrounds -----------------------------------------------------------------------------------------------
def bg_night(W, H):
    img = Image.new("RGBA", (W, H))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        c = (int(18 + 60 * t), int(14 + 14 * t), int(56 + 60 * t), 255)
        for x in range(W):
            px[x, y] = c
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k, col in enumerate(((255, 60, 170), (40, 220, 255), (255, 230, 90))):
        x0 = W * (0.15 + 0.3 * k)
        d.polygon([(x0, 0), (x0 + 60, 0), (x0 - W * 0.35 + 60, H), (x0 - W * 0.35, H)], fill=col + (70,))
    img.alpha_composite(lay.filter(ImageFilter.GaussianBlur(10)))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W * 0.3, H * 0.25, W * 1.1, H * 1.1], fill=(150, 60, 255, 110))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(90)))
    return img


def bg_pop(W, H):
    img = Image.new("RGBA", (W, H), (190, 120, 235, 255))
    d = ImageDraw.Draw(img)
    for col, start in (((90, 225, 185), 0.0), ((245, 70, 110), 0.3), ((190, 120, 235), 0.6), ((90, 225, 185), 0.82)):
        y0 = start * H
        d.polygon([(0, y0 + H * 0.15), (W, y0 - H * 0.3 + H * 0.15), (W, H * 2), (0, H * 2)], fill=col + (255,))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-W * 0.05, H * 0.15, W * 0.55, H * 1.1], fill=(255, 235, 140, 120))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(70)))
    dots = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    step = max(18, W // 46)
    for corner in ((0, 0), (W, H)):
        for gx in range(0, int(W * 0.28), step):
            for gy in range(0, int(H * 0.34), step):
                x = corner[0] + (gx if corner[0] == 0 else -gx)
                y = corner[1] + (gy if corner[1] == 0 else -gy)
                r = max(1, int(step * 0.38 * (1 - math.hypot(gx / (W * 0.28), gy / (H * 0.34)))))
                dd.ellipse([x - r, y - r, x + r, y + r], fill=(60, 20, 90, 120))
    img.alpha_composite(dots)
    return img


def bg_steps(W, H):
    img = Image.new("RGBA", (W, H), (255, 244, 214, 255))
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.ellipse([-W * 0.2, -H * 0.3, W * 0.45, H * 0.35], fill=(255, 175, 210, 170))
    d.ellipse([W * 0.65, H * 0.55, W * 1.25, H * 1.3], fill=(150, 230, 200, 170))
    d.ellipse([W * 0.5, -H * 0.4, W * 1.1, H * 0.2], fill=(190, 160, 245, 130))
    img.alpha_composite(lay.filter(ImageFilter.GaussianBlur(30)))
    return img


# --- the three looks -------------------------------------------------------------------------------------------
def logo_img(lang):
    return load(BRAND / "logo_beat_garden.png")


def make_night(shape, lang):
    W, H = SIZES[shape]
    img = bg_night(W, H)
    copy = COPY[lang]
    lane = load(SHOTS / "expert_lane_night_a.png").crop((0, 40, 1500, 820))
    logo, mascot = logo_img(lang), load(BRAND / "mascot_cutout.png")
    if shape == "L":
        shadowed(img, fit_w(logo, W * 0.38), W * 0.03, H * 0.04)
        text(img, copy["night"], W * 0.045, H * 0.41, round(H * 0.082), lang, fill=(255, 244, 130), max_w=W * 0.4)
        f, pad = framed(lane, W * 0.5, glow=(255, 60, 170))
        shadowed(img, f, W * 0.47 - pad, H * 0.24 - pad, blur=1, alpha=0)
        shadowed(img, sticker(fit_h(mascot, H * 0.36), 8), W * 0.04, H * 0.64, -4)
        pill(img, copy["free"], W * 0.72, H * 0.9, lang, round(H * 0.04))
    elif shape == "S":
        shadowed(img, fit_w(logo, W * 0.56), (W - W * 0.56) / 2, H * 0.02)
        text(img, copy["night"], W / 2, H * 0.3, round(H * 0.055), lang, fill=(255, 244, 130), align="center")
        f, pad = framed(lane, W * 0.84, glow=(255, 60, 170))
        shadowed(img, f, W * 0.08 - pad, H * 0.45 - pad, blur=1, alpha=0)
        shadowed(img, sticker(fit_h(mascot, H * 0.25), 8), W * 0.0, H * 0.75, -4)
    else:
        shadowed(img, fit_w(logo, W * 0.6), (W - W * 0.6) / 2, H * 0.02)
        text(img, copy["night"], W / 2, H * 0.28, round(H * 0.048), lang, fill=(255, 244, 130), align="center")
        f, pad = framed(lane, W * 0.86, glow=(255, 60, 170))
        shadowed(img, f, W * 0.07 - pad, H * 0.43 - pad, blur=1, alpha=0)
        shadowed(img, sticker(fit_h(mascot, H * 0.26), 8), W * 0.0, H * 0.74, -4)
    return img


def make_pop(shape, lang):
    W, H = SIZES[shape]
    img = bg_pop(W, H)
    copy = COPY[lang]
    logo, mascot = logo_img(lang), load(BRAND / "mascot_cutout.png")
    phone = load(SHOTS / "rhythm_lane_day_phone.png")
    back = sticker(logo, 12, (255, 250, 232, 255))
    if shape == "L":
        shadowed(img, sticker(fit_h(mascot, H * 0.98), 12), W * 0.02, H * 0.03, -3)
        shadowed(img, fit_w(back, W * 0.5), W * 0.33, H * 0.03)
        text(img, copy["pop"], W * 0.37, H * 0.5, round(H * 0.075), lang, align="left", max_w=W * 0.46)
        shadowed(img, fit_w(phone, W * 0.3), W * 0.66, H * 0.7, 2)
        pill(img, copy["free"], W * 0.5, H * 0.88, lang, round(H * 0.045))
    elif shape == "S":
        shadowed(img, fit_w(back, W * 0.78), (W - W * 0.78) / 2, H * 0.02)
        shadowed(img, sticker(fit_h(mascot, H * 0.62), 12), W * 0.01, H * 0.36, -3)
        text(img, copy["pop"], W * 0.72, H * 0.355, round(H * 0.05), lang, align="center", max_w=W * 0.52)
        shadowed(img, fit_w(phone, W * 0.5), W * 0.47, H * 0.5, 3)
        pill(img, copy["free"], W * 0.5, H * 0.94, lang, round(H * 0.04))
    else:
        shadowed(img, fit_w(back, W * 0.8), (W - W * 0.8) / 2, H * 0.02)
        shadowed(img, sticker(fit_h(mascot, H * 0.6), 12), W * 0.0, H * 0.4, -3)
        text(img, copy["pop"], W * 0.7, H * 0.33, round(H * 0.043), lang, align="center", max_w=W * 0.5)
        shadowed(img, fit_w(phone, W * 0.5), W * 0.47, H * 0.54, 3)
        pill(img, copy["free"], W * 0.5, H * 0.94, lang, round(H * 0.037))
    star(img, W * 0.95, H * 0.07, H * 0.045)
    star(img, W * 0.3, H * 0.62, H * 0.03, (255, 255, 255, 255))
    return img


def make_steps(shape, lang):
    W, H = SIZES[shape]
    img = bg_steps(W, H)
    copy = COPY[lang]
    logo = logo_img(lang)
    names = ["garden_day", "rhythm_lane_day", "night_lasers"]
    shots = [load(SHOTS / f"{n}_phone.png") for n in names]
    caps = copy["steps"]
    cols = [(90, 200, 160), (245, 70, 120), (150, 100, 235)]
    if shape == "L":
        shadowed(img, fit_w(logo, W * 0.26), W * 0.02, H * 0.0)
        text(img, copy["steps_head"], W * 0.3, H * 0.07, round(H * 0.07), lang, fill=(70, 30, 120), stroke=(255, 255, 255), sw=4, max_w=W * 0.67)
        pw = W * 0.3
        xs = [W * 0.03, W * 0.35, W * 0.67]
        ys = [H * 0.33, H * 0.37, H * 0.33]
    elif shape == "S":
        shadowed(img, fit_w(logo, W * 0.5), (W - W * 0.5) / 2, H * 0.01)
        text(img, copy["steps_head"], W / 2, H * 0.24, round(H * 0.04), lang, fill=(70, 30, 120), stroke=(255, 255, 255), sw=4, align="center", max_w=W * 0.94)
        pw = W * 0.8
        xs = [W * 0.02, W * 0.2, W * 0.1]
        ys = [H * 0.3, H * 0.5, H * 0.7]
    else:
        shadowed(img, fit_w(logo, W * 0.5), (W - W * 0.5) / 2, H * 0.01)
        text(img, copy["steps_head"], W / 2, H * 0.235, round(H * 0.035), lang, fill=(70, 30, 120), stroke=(255, 255, 255), sw=4, align="center", max_w=W * 0.94)
        pw = W * 0.72
        xs = [W * 0.02, W * 0.26, W * 0.1]
        ys = [H * 0.29, H * 0.49, H * 0.69]
    if shape != "L":
        pw = H * 0.4
        ys = [H * (0.3 + 0.215 * i) for i in range(3)]
        # single column of three rows: screen on one side, caption on the other
        for i in range(3):
            side_left = i % 2 == 0
            sx = W * 0.05 if side_left else W - pw - W * 0.05
            f, pad = framed(shots[i], pw, glow=None)
            shadowed(img, f, sx, ys[i], -2 if side_left else 2)
            cx = sx + pw + (W - pw - W * 0.05 - sx - pw) / 2 if side_left else sx / 2 + W * 0.0
            if side_left:
                cx = sx + pw + (W - (sx + pw)) / 2
            else:
                cx = sx / 2
            cy = ys[i] + f.height / 2
            pill(img, str(i + 1), cx, cy - H * 0.06, lang, round(H * 0.045), fill=cols[i], ink=(255, 255, 255))
            text(img, [caps[i]], cx, cy, round(H * 0.045), lang, fill=(70, 30, 120), stroke=(255, 255, 255), sw=3, align="center", max_w=W * 0.4)
        return img
    for i in range(3):
        f, pad = framed(shots[i], pw, glow=None)
        shadowed(img, f, xs[i], ys[i], -2 + i * 2)
        pill(img, str(i + 1), xs[i] + pw / 2, ys[i] - H * 0.02, lang, round(H * 0.04), fill=cols[i], ink=(255, 255, 255))
        text(img, [caps[i]], xs[i] + pw / 2, ys[i] + f.height + H * 0.02, round(H * 0.05), lang, fill=(70, 30, 120), stroke=(255, 255, 255), sw=3, align="center", max_w=pw)
    pill(img, copy["free"], W * 0.5, H * 0.93, lang, round(H * 0.04))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("a_night", make_night), ("b_pop", make_pop), ("c_steps", make_steps)):
        for lang in ("ja", "en"):
            for shape, (W, H) in SIZES.items():
                path = OUT / f"{name}_{lang}_{shape}_{W}x{H}.png"
                fn(shape, lang).convert("RGB").save(path)
                print(path.name)


if __name__ == "__main__":
    main()
