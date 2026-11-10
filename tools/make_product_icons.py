"""Makes the icons (512x512 PNG) of the three developer products in the pop style of the logo: Instant Grow, Restock and
Growth Sprinkler. Roblox does not require an image for a developer product, but one makes the purchase window friendlier.
Usage: python3 tools/make_product_icons.py  ->  assets/branding/product_instant_grow.png, product_restock.png,
product_growth_sprinkler.png"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

S = 1024
INK = (44, 18, 82)
HEAVY = "/Library/Fonts/Archivo-BlackItalic.ttf"

def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))

def add(base, lay):
    return Image.alpha_composite(base, lay)

def background(colors):
    img = Image.new("RGBA", (S, S), colors[0] + (255,))
    d = ImageDraw.Draw(img)
    for col, start in zip(colors, (0.0, 0.30, 0.62, 0.84)):
        y0 = start * S
        d.polygon([(0, y0 + 140), (S, y0 - 300 + 140), (S, S + 500), (0, S + 500)], fill=col + (255,))
    return img

def sticker(src, outline=12):
    grown = src.split()[3]
    for _ in range(outline):
        grown = grown.filter(ImageFilter.MaxFilter(3))
    base = Image.new("RGBA", src.size, (255, 255, 255, 255))
    base.putalpha(grown)
    return Image.alpha_composite(base, src)

def shadowed(canvas, pic, x, y):
    sh = Image.new("RGBA", pic.size, (30, 0, 60, 0))
    sh.putalpha(pic.split()[3].point(lambda v: int(v * 0.5)))
    lay = layer(); lay.paste(sh, (int(x + 12), int(y + 16)), sh)
    canvas = add(canvas, lay.filter(ImageFilter.GaussianBlur(12)))
    lay = layer(); lay.paste(pic, (int(x), int(y)), pic)
    return add(canvas, lay)

def lerp(a, b, t):
    return tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3))

def gradient_in(mask, box, top, bottom):
    grad = Image.new("RGB", (S, S))
    gd = ImageDraw.Draw(grad)
    y0, y1 = int(box[1]), int(box[3])
    for y in range(y0, y1 + 1):
        gd.line([(0, y), (S, y)], fill=lerp(top, bottom, (y - y0) / max(1, y1 - y0)))
    out = grad.convert("RGBA")
    out.putalpha(mask)
    return out

def mascot(canvas, height, cx, bottom):
    """A drawn (vector) version of the mascot: a headphone fruit on a stem with two leaves. Clean edges at any size."""
    k = height / 800.0
    R = 190 * k
    fx, fy = cx, bottom - height + R + 40 * k
    lay = layer(); d = ImageDraw.Draw(lay)
    # stem
    d.rounded_rectangle([cx - 30 * k, fy + R * 0.6, cx + 30 * k, bottom - 20 * k], radius=22 * k, fill=INK + (255,))
    d.rounded_rectangle([cx - 20 * k, fy + R * 0.6, cx + 20 * k, bottom - 20 * k], radius=16 * k, fill=(96, 206, 110, 255))
    d.rounded_rectangle([cx - 20 * k, fy + R * 0.6, cx - 6 * k, bottom - 20 * k], radius=8 * k, fill=(150, 240, 150, 255))
    # leaves
    def leaf(lx, ly, w, h, angle):
        l = Image.new("RGBA", (int(w * 2), int(w * 2)), (0, 0, 0, 0))
        ld = ImageDraw.Draw(l)
        c = w
        ld.ellipse([c - w / 2 - 14 * k, c - h / 2 - 14 * k, c + w / 2 + 14 * k, c + h / 2 + 14 * k], fill=INK + (255,))
        ld.ellipse([c - w / 2, c - h / 2, c + w / 2, c + h / 2], fill=(130, 230, 80, 255))
        ld.ellipse([c - w / 2 + 10 * k, c - h / 2 + 8 * k, c + w / 2 - 30 * k, c], fill=(190, 255, 110, 255))
        l = l.rotate(angle, resample=Image.BICUBIC)
        lay.paste(l, (int(lx - w), int(ly - w)), l)
    leaf(cx - 130 * k, bottom - 190 * k, 230 * k, 84 * k, 24)
    leaf(cx + 130 * k, bottom - 240 * k, 230 * k, 84 * k, -24)
    canvas = shadowed(canvas, lay, 0, 0)
    # headphone band behind the head, then the fruit
    lay = layer(); d = ImageDraw.Draw(lay)
    d.arc([fx - R - 40 * k, fy - R - 44 * k, fx + R + 40 * k, fy + R + 44 * k], 188, 352, fill=INK + (255,), width=int(58 * k))
    d.arc([fx - R - 40 * k, fy - R - 44 * k, fx + R + 40 * k, fy + R + 44 * k], 188, 352, fill=(126, 96, 230, 255), width=int(36 * k))
    d.ellipse([fx - R - 16 * k, fy - R - 16 * k, fx + R + 16 * k, fy + R + 16 * k], fill=INK + (255,))
    canvas = add(canvas, lay)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([fx - R, fy - R, fx + R, fy + R], fill=255)
    canvas = add(canvas, gradient_in(mask, (fx - R, fy - R, fx + R, fy + R), (255, 240, 100), (255, 150, 50)))
    lay = layer(); d = ImageDraw.Draw(lay)
    d.ellipse([fx - R * 0.72, fy - R * 0.8, fx - R * 0.2, fy - R * 0.42], fill=(255, 255, 255, 200))
    for side in (-1, 1):
        ex, ey = fx + side * R * 0.38, fy + R * 0.04
        d.ellipse([ex - 28 * k, ey - 38 * k, ex + 28 * k, ey + 38 * k], fill=INK + (255,))
        d.ellipse([ex - 11 * k, ey - 26 * k, ex + 4 * k, ey - 10 * k], fill=(255, 255, 255, 255))
        d.ellipse([fx + side * R * 0.7 - 34 * k, fy + R * 0.34 - 18 * k, fx + side * R * 0.7 + 34 * k, fy + R * 0.34 + 18 * k], fill=(255, 96, 150, 200))
    d.arc([fx - 40 * k, fy + R * 0.1, fx + 40 * k, fy + R * 0.5], 12, 168, fill=INK + (255,), width=int(12 * k))
    canvas = add(canvas, lay)
    for side in (-1, 1):
        cxp = fx + side * (R + 34 * k)
        box = (cxp - 50 * k, fy - 86 * k, cxp + 50 * k, fy + 72 * k)
        lay = layer(); d = ImageDraw.Draw(lay)
        d.rounded_rectangle([box[0] - 13 * k, box[1] - 13 * k, box[2] + 13 * k, box[3] + 13 * k], radius=int(54 * k), fill=INK + (255,))
        canvas = add(canvas, lay)
        m2 = Image.new("L", (S, S), 0)
        ImageDraw.Draw(m2).rounded_rectangle(box, radius=int(44 * k), fill=255)
        canvas = add(canvas, gradient_in(m2, box, (255, 130, 190), (230, 50, 140)))
        lay = layer(); d = ImageDraw.Draw(lay)
        d.rounded_rectangle([box[0] + 13 * k, box[1] + 13 * k, box[0] + 31 * k, box[1] + 66 * k], radius=int(9 * k), fill=(255, 255, 255, 190))
        canvas = add(canvas, lay)
    return canvas

def star(canvas, cx, cy, r, color):
    lay = layer(); sd = ImageDraw.Draw(lay)
    for rr, col in ((r + 8, INK + (255,)), (r, color)):
        pts = []
        for i in range(8):
            ang = math.pi / 4 * i - math.pi / 2
            rad = rr if i % 2 == 0 else rr * 0.3
            pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
        sd.polygon(pts, fill=col)
    return add(canvas, lay)

def outlined_polygon(canvas, pts, fill, width=12, shadow=True):
    lay = layer(); d = ImageDraw.Draw(lay)
    if shadow:
        d.polygon([(x + 10, y + 14) for x, y in pts], fill=(30, 0, 60, 110))
    d.polygon(pts, fill=fill + (255,), outline=INK + (255,), width=width)
    return add(canvas, lay)

def label(canvas, text, cx, cy, size, fill=(255, 255, 255, 255)):
    f = ImageFont.truetype(HEAVY, size)
    lay = layer(); d = ImageDraw.Draw(lay)
    d.text((cx + 8, cy + 12), text, font=f, fill=(30, 0, 60, 140), anchor="mm", stroke_width=14, stroke_fill=(30, 0, 60, 140))
    d.text((cx, cy), text, font=f, fill=fill, anchor="mm", stroke_width=14, stroke_fill=INK + (255,))
    return add(canvas, lay)

def save(img, name):
    os.makedirs("assets/branding", exist_ok=True)
    img.convert("RGB").resize((512, 512), Image.LANCZOS).save(f"assets/branding/{name}.png")
    print(name)

# --- Instant Grow: a big lightning bolt, the mascot and "NOW!" ------------------------------------------------
img = background([(255, 215, 70), (255, 130, 60), (255, 215, 70), (255, 170, 80)])
bolt = [(820, 150), (560, 560), (740, 560), (650, 990), (1010, 470), (810, 470), (940, 150)]
img = outlined_polygon(img, bolt, (255, 79, 163), 16)
inner = [(x * 0.92 + 40, y * 0.92 + 30) for x, y in bolt]
img = mascot(img, 700, 390, 960)
img = star(img, 130, 150, 60, (255, 255, 255, 255))
img = star(img, 900, 260, 46, (255, 244, 130, 255))
img = star(img, 880, 800, 38, (255, 255, 255, 255))
img = label(img, "NOW!", 560, 120, 200, (255, 255, 255, 255))
save(img, "product_instant_grow")

# --- Restock: seed packets and circular arrows -----------------------------------------------------------------
img = background([(90, 225, 185), (60, 170, 200), (90, 225, 185), (130, 235, 200)])
def packet(canvas, cx, cy, color, angle):
    lay = layer()
    pd = ImageDraw.Draw(lay)
    w, h = 250, 340
    pd.rounded_rectangle([cx - w / 2 - 14, cy - h / 2 - 14, cx + w / 2 + 14, cy + h / 2 + 14], radius=40, fill=INK + (255,))
    pd.rounded_rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], radius=30, fill=(255, 250, 235, 255))
    pd.rounded_rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy - h / 2 + 90], radius=30, fill=color + (255,))
    pd.ellipse([cx - 70, cy - 20, cx + 70, cy + 120], fill=(255, 225, 77, 255), outline=INK + (255,), width=10)
    pd.polygon([(cx, cy - 10), (cx - 40, cy - 70), (cx + 5, cy - 50)], fill=(126, 217, 87, 255), outline=INK + (255,))
    pd.polygon([(cx, cy - 10), (cx + 50, cy - 80), (cx + 10, cy - 45)], fill=(95, 191, 106, 255), outline=INK + (255,))
    lay = lay.rotate(angle, resample=Image.BICUBIC, center=(cx, cy))
    sh = Image.new("RGBA", lay.size, (30, 0, 60, 0)); sh.putalpha(lay.split()[3].point(lambda v: int(v * 0.45)))
    s2 = layer(); s2.paste(sh, (12, 16), sh)
    canvas = add(canvas, s2.filter(ImageFilter.GaussianBlur(10)))
    return add(canvas, lay)
img = packet(img, 330, 600, (255, 79, 163), -14)
img = packet(img, 690, 600, (63, 200, 255), 12)
img = packet(img, 510, 540, (255, 154, 77), 0)
def arc_arrow(canvas, a0, a1):
    lay = layer(); ad = ImageDraw.Draw(lay)
    box = [90, 90, S - 90, S - 90]
    ad.arc(box, a0, a1, fill=INK + (255,), width=84)
    ad.arc(box, a0, a1, fill=(255, 255, 255, 255), width=56)
    cx = cy = S / 2; r = S / 2 - 90
    t = math.radians(a1)
    tip = (cx + math.cos(t + 0.28) * r, cy + math.sin(t + 0.28) * r)
    b1 = (cx + math.cos(t) * (r + 80), cy + math.sin(t) * (r + 80))
    b2 = (cx + math.cos(t) * (r - 80), cy + math.sin(t) * (r - 80))
    ad.polygon([tip, b1, b2], fill=INK + (255,))
    ad.polygon([(cx + math.cos(t + 0.2) * r, cy + math.sin(t + 0.2) * r),
                (cx + math.cos(t + 0.0) * (r + 58), cy + math.sin(t + 0.0) * (r + 58)),
                (cx + math.cos(t + 0.0) * (r - 58), cy + math.sin(t + 0.0) * (r - 58))], fill=(255, 255, 255, 255))
    return add(canvas, lay)
img = arc_arrow(img, 200, 330)
img = arc_arrow(img, 20, 150)
img = star(img, 120, 880, 48, (255, 244, 130, 255))
img = star(img, 910, 150, 44, (255, 255, 255, 255))
img = label(img, "NEW", 512, 130, 170, (255, 244, 130, 255))
save(img, "product_restock")

# --- Growth Sprinkler: a watering can pouring sparkles on a sprout ---------------------------------------------
img = background([(255, 160, 215), (190, 120, 235), (255, 160, 215), (230, 140, 230)])
can = layer(); cd = ImageDraw.Draw(can)
def rr(box, fill, radius=40, outline=INK, width=14):
    cd.rounded_rectangle(box, radius=radius, fill=fill + (255,), outline=outline + (255,), width=width)
cd.polygon([(520, 250), (780, 150), (820, 220), (560, 320)], fill=(120, 190, 255, 255), outline=INK + (255,), width=14)  # spout
cd.ellipse([740, 110, 860, 250], fill=(255, 255, 255, 255), outline=INK + (255,), width=14)  # rose
rr([150, 230, 570, 560], (63, 200, 255))  # body
rr([180, 190, 540, 260], (255, 225, 77), 30)  # lid
cd.arc([60, 250, 260, 500], 90, 270, fill=INK + (255,), width=40)  # handle
cd.arc([70, 258, 252, 492], 90, 270, fill=(255, 79, 163, 255), width=18)
cd.ellipse([220, 300, 320, 360], fill=(255, 255, 255, 180))
can = can.rotate(-12, resample=Image.BICUBIC, center=(400, 400))
img = shadowed(img, can, 0, 0)
RAIN = [(255, 79, 163), (255, 225, 77), (61, 255, 176), (63, 200, 255), (168, 107, 255)]
lay = layer(); dd = ImageDraw.Draw(lay)
for k in range(15):
    x = 640 + (k % 5) * 70 + (k // 5) * 30
    y = 330 + (k % 3) * 80 + (k // 5) * 90
    col = RAIN[k % 5]
    dd.ellipse([x - 20, y - 28, x + 20, y + 28], fill=col + (255,), outline=INK + (255,), width=7)
img = add(img, lay)
img = mascot(img, 560, 640, 990)
img = star(img, 120, 150, 58, (255, 255, 255, 255))
img = star(img, 900, 700, 48, (255, 244, 130, 255))
img = star(img, 520, 90, 38, (255, 255, 255, 255))
img = label(img, "x3", 770, 880, 200, (255, 255, 255, 255))
save(img, "product_growth_sprinkler")
