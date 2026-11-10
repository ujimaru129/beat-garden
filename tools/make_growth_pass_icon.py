"""Makes the Double Growth game pass icon (512x512 PNG) in the pop style of the logo and thumbnail: the mascot on diagonal
stripes with speed lines, upward arrows and a big "x2" badge.
Usage: python3 tools/make_growth_pass_icon.py  ->  assets/branding/double_growth_pass.png"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

S = 1024
INK = (44, 18, 82)
HEAVY = "/Library/Fonts/Archivo-BlackItalic.ttf"

def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))

# background: stripes in the mascot's colours
img = Image.new("RGBA", (S, S), (190, 120, 235, 255))
d = ImageDraw.Draw(img)
for col, start in (((90, 225, 185), 0.0), ((245, 70, 110), 0.30), ((190, 120, 235), 0.62), ((90, 225, 185), 0.84)):
    y0 = start * S
    d.polygon([(0, y0 + 140), (S, y0 - 300 + 140), (S, S + 500), (0, S + 500)], fill=col + (255,))

# speed lines rising from the bottom
lines = layer()
ld = ImageDraw.Draw(lines)
for k in range(14):
    x = 40 + k * 70
    h = 160 + (k * 37) % 220
    ld.line([(x, S - 20), (x, S - 20 - h)], fill=(255, 255, 255, 120), width=10)
img = Image.alpha_composite(img, lines)

def add(base, lay):
    return Image.alpha_composite(base, lay)

def sticker(src, outline=12):
    alpha = src.split()[3]
    grown = alpha
    for _ in range(outline):
        grown = grown.filter(ImageFilter.MaxFilter(3))
    base = Image.new("RGBA", src.size, (255, 255, 255, 255))
    base.putalpha(grown)
    return Image.alpha_composite(base, src)

# the mascot, centred a little low
mascot = Image.open("assets/branding/mascot_cutout.png").convert("RGBA")
mh = 800
mascot = mascot.resize((int(mascot.width * mh / mascot.height), mh), Image.LANCZOS)
m = sticker(mascot)
shadow = Image.new("RGBA", m.size, (30, 0, 60, 0))
shadow.putalpha(m.split()[3].point(lambda v: int(v * 0.5)))
sh = layer()
sh.paste(shadow, ((S - m.width) // 2 + 12, S - m.height + 10 + 16), shadow)
img = add(img, sh.filter(ImageFilter.GaussianBlur(12)))
lay = layer()
lay.paste(m, ((S - m.width) // 2 - 20, S - m.height + 10), m)
img = add(img, lay)

# upward arrows
def arrow(canvas, cx, cy, w, h, color):
    lay = layer()
    ad = ImageDraw.Draw(lay)
    pts = [(cx, cy - h), (cx + w, cy), (cx + w * 0.4, cy), (cx + w * 0.4, cy + h * 0.8), (cx - w * 0.4, cy + h * 0.8), (cx - w * 0.4, cy), (cx - w, cy)]
    ad.polygon([(x + 8, y + 12) for x, y in pts], fill=(30, 0, 60, 110))
    ad.polygon(pts, fill=color + (255,), outline=INK + (255,), width=10)
    return add(canvas, lay)
img = arrow(img, 130, 560, 70, 110, (255, 225, 77))
img = arrow(img, 100, 780, 52, 82, (255, 255, 255))
img = arrow(img, 905, 700, 62, 96, (61, 255, 176))

# the "x2" badge
bx, by, br = 780, 235, 215
badge = layer()
bd = ImageDraw.Draw(badge)
pts = []
for k in range(24):
    ang = math.pi * 2 * k / 24
    rad = br if k % 2 == 0 else br * 0.82
    pts.append((bx + math.cos(ang) * rad, by + math.sin(ang) * rad))
bd.polygon([(x + 10, y + 14) for x, y in pts], fill=(30, 0, 60, 120))
bd.polygon(pts, fill=(255, 79, 163, 255), outline=INK + (255,), width=14)
bd.ellipse([bx - br * 0.66, by - br * 0.66, bx + br * 0.66, by + br * 0.66], fill=(255, 225, 77, 255), outline=INK + (255,), width=10)
img = add(img, badge)

font = ImageFont.truetype(HEAVY, 250)
text = layer()
td = ImageDraw.Draw(text)
td.text((bx + 8, by + 14), "x2", font=font, fill=(30, 0, 60, 140), anchor="mm", stroke_width=14, stroke_fill=(30, 0, 60, 140))
td.text((bx, by + 6), "x2", font=font, fill=(255, 255, 255, 255), anchor="mm", stroke_width=16, stroke_fill=INK + (255,))
img = add(img, text)

# sparkles
def star(canvas, cx, cy, r, color):
    lay = layer()
    sd = ImageDraw.Draw(lay)
    for rr, col in ((r + 8, INK + (255,)), (r, color)):
        pts = []
        for i in range(8):
            ang = math.pi / 4 * i - math.pi / 2
            rad = rr if i % 2 == 0 else rr * 0.3
            pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
        sd.polygon(pts, fill=col)
    return add(canvas, lay)
img = star(img, 120, 130, 56, (255, 244, 130, 255))
img = star(img, 300, 330, 34, (255, 255, 255, 255))
img = star(img, 940, 860, 40, (255, 244, 130, 255))

os.makedirs("assets/branding", exist_ok=True)
img.convert("RGB").resize((512, 512), Image.LANCZOS).save("assets/branding/double_growth_pass.png")
print("assets/branding/double_growth_pass.png")
