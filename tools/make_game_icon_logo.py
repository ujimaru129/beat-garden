"""Makes the Beat Garden game icon (512x512 + a 1024 copy) around the hand-made logo (assets/branding/
logo_beat_garden.png): a pop, sticker-like look to match it - thick dark outlines, bright gradients, a sunburst and
neon laser beams on a deep violet night, a headphone-wearing fruit mascot above the logo.
Usage: python3 tools/make_game_icon_logo.py  ->  assets/branding/game_icon.png (+ game_icon_1024.png)"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import math, os, random

S = 1024
random.seed(11)
INK = (44, 18, 82)  # the dark outline colour (same family as the logo's)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def new_layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))

def add(base, layer):
    return Image.alpha_composite(base, layer)

def glow(layer, radius, strength=1.0):
    blurred = layer.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        blurred.putalpha(blurred.split()[3].point(lambda v: min(255, int(v * strength))))
    return Image.alpha_composite(blurred, layer)

# --- background: violet night with a pink glow, a sunburst and laser beams -----------------------------------
arr = np.zeros((S, S, 3), dtype=np.uint8)
ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
dist = np.sqrt((xs - S * 0.5) ** 2 + (ys - S * 0.62) ** 2) / (S * 0.75)
dist = np.clip(dist, 0, 1)
inner, outer = np.array((200, 60, 190), np.float32), np.array((22, 12, 66), np.float32)
arr[:] = (inner[None, None, :] * (1 - dist[..., None]) + outer[None, None, :] * dist[..., None]).astype(np.uint8)
img = Image.fromarray(arr, "RGB").convert("RGBA")

rays = new_layer()
rd = ImageDraw.Draw(rays)
cx, cy = S * 0.5, S * 0.62
for k in range(28):
    a0 = math.radians(k * (360 / 28))
    a1 = a0 + math.radians(360 / 56)
    rd.polygon([(cx, cy), (cx + math.cos(a0) * 1500, cy + math.sin(a0) * 1500), (cx + math.cos(a1) * 1500, cy + math.sin(a1) * 1500)],
               fill=(255, 255, 255, 22))
img = add(img, rays)

stars = new_layer()
sd = ImageDraw.Draw(stars)
for _ in range(90):
    x, y = random.randint(0, S), random.randint(0, int(S * 0.55))
    r = random.choice([2, 2, 3, 4])
    sd.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, random.randint(120, 255)))
img = add(img, glow(stars, 3))

beams = new_layer()
bd = ImageDraw.Draw(beams)
BEAM = [(255, 79, 163), (63, 220, 255), (61, 255, 176), (255, 225, 77), (168, 107, 255), (255, 154, 77)]
n = 13
for k in range(n):
    ang = math.radians(198 + k * (144 / (n - 1)))
    col = BEAM[k % len(BEAM)]
    x1, y1 = cx + math.cos(ang) * 1400, cy + math.sin(ang) * 1400
    bd.line([cx, cy, x1, y1], fill=col + (235,), width=10)
    bd.line([cx, cy, x1, y1], fill=(255, 255, 255, 255), width=3)
img = add(img, glow(glow(beams, 16, 1.5), 5, 1.0))

# --- outlined cartoon helpers ---------------------------------------------------------------------------------
def outlined_ellipse(layer, box, fill, width=16):
    d = ImageDraw.Draw(layer)
    d.ellipse([box[0] - width, box[1] - width, box[2] + width, box[3] + width], fill=INK + (255,))
    d.ellipse(box, fill=fill)

def gradient_fill(box, top, bottom, mask_fn):
    """A vertical gradient inside the shape drawn by mask_fn(draw)."""
    mask = Image.new("L", (S, S), 0)
    mask_fn(ImageDraw.Draw(mask))
    grad = Image.new("RGB", (S, S))
    gp = ImageDraw.Draw(grad)
    y0, y1 = int(box[1]), int(box[3])
    for y in range(y0, y1 + 1):
        gp.line([(0, y), (S, y)], fill=lerp(top, bottom, (y - y0) / max(1, y1 - y0)))
    out = grad.convert("RGBA")
    out.putalpha(mask)
    return out

layer = new_layer()
FX, FY, FR = S * 0.5, S * 0.33, S * 0.215  # the fruit

# stem and leaves (outlined)
def leaf(cx_, cy_, w, h, angle):
    lay = Image.new("RGBA", (int(w * 2), int(w * 2)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    c = w
    ld.ellipse([c - w / 2 - 14, c - h / 2 - 14, c + w / 2 + 14, c + h / 2 + 14], fill=INK + (255,))
    ld.ellipse([c - w / 2, c - h / 2, c + w / 2, c + h / 2], fill=(130, 230, 80, 255))
    ld.ellipse([c - w / 2 + 10, c - h / 2 + 8, c + w / 2 - 30, c], fill=(190, 255, 110, 255))
    ld.line([c - w / 2 + 18, c, c + w / 2 - 18, c], fill=(60, 160, 70, 255), width=6)
    lay = lay.rotate(angle, resample=Image.BICUBIC)
    layer.paste(lay, (int(cx_ - w), int(cy_ - w)), lay)

d = ImageDraw.Draw(layer)
d.rounded_rectangle([S * 0.5 - 38, FY + FR * 0.6, S * 0.5 + 38, S * 0.62], radius=20, fill=INK + (255,))
d.rounded_rectangle([S * 0.5 - 26, FY + FR * 0.6, S * 0.5 + 26, S * 0.62], radius=14, fill=(96, 206, 110, 255))
d.rounded_rectangle([S * 0.5 - 26, FY + FR * 0.6, S * 0.5 - 8, S * 0.62], radius=9, fill=(150, 240, 150, 255))
leaf(S * 0.5 - 150, S * 0.55, 250, 92, 24)
leaf(S * 0.5 + 150, S * 0.5, 250, 92, -24)

# a soft glow behind the fruit
halo = new_layer()
for k in range(6, 0, -1):
    rr = FR + k * 26
    ImageDraw.Draw(halo).ellipse([FX - rr, FY - rr, FX + rr, FY + rr], fill=(255, 235, 120, 24))
img = add(img, halo.filter(ImageFilter.GaussianBlur(12)))
img = add(img, layer)

layer = new_layer()
d = ImageDraw.Draw(layer)
# headphone band behind the head
d.arc([FX - FR - 40, FY - FR - 44, FX + FR + 40, FY + FR + 44], 188, 352, fill=INK + (255,), width=58)
d.arc([FX - FR - 40, FY - FR - 44, FX + FR + 40, FY + FR + 44], 188, 352, fill=(126, 96, 230, 255), width=36)
d.arc([FX - FR - 34, FY - FR - 38, FX + FR + 34, FY + FR + 38], 205, 300, fill=(190, 170, 255, 255), width=10)
# the fruit: outline, a warm gradient, a highlight
d.ellipse([FX - FR - 16, FY - FR - 16, FX + FR + 16, FY + FR + 16], fill=INK + (255,))
img = add(img, layer)
fruit = gradient_fill((FX - FR, FY - FR, FX + FR, FY + FR), (255, 240, 100), (255, 150, 50),
                      lambda m: m.ellipse([FX - FR, FY - FR, FX + FR, FY + FR], fill=255))
img = add(img, fruit)
layer = new_layer()
d = ImageDraw.Draw(layer)
d.ellipse([FX - FR * 0.72, FY - FR * 0.8, FX - FR * 0.2, FY - FR * 0.42], fill=(255, 255, 255, 200))
d.ellipse([FX - FR * 0.86, FY - FR * 0.42, FX - FR * 0.72, FY - FR * 0.26], fill=(255, 255, 255, 200))
# face
for side in (-1, 1):
    ex, ey = FX + side * FR * 0.38, FY + FR * 0.04
    d.ellipse([ex - 30, ey - 42, ex + 30, ey + 42], fill=INK + (255,))
    d.ellipse([ex - 12, ey - 28, ex + 4, ey - 10], fill=(255, 255, 255, 255))
    d.ellipse([ex - 6, ey + 6, ex + 8, ey + 18], fill=(255, 255, 255, 200))
    d.ellipse([FX + side * FR * 0.7 - 36, FY + FR * 0.34 - 20, FX + side * FR * 0.7 + 36, FY + FR * 0.34 + 20], fill=(255, 96, 150, 200))
d.arc([FX - 44, FY + FR * 0.1, FX + 44, FY + FR * 0.52], 12, 168, fill=INK + (255,), width=13)
d.chord([FX - 28, FY + FR * 0.3, FX + 28, FY + FR * 0.5], 0, 180, fill=(255, 110, 130, 255))
img = add(img, layer)

# headphone cups (in front)
for side in (-1, 1):
    cxp = FX + side * (FR + 36)
    box = (cxp - 54, FY - 92, cxp + 54, FY + 76)
    lay = new_layer()
    ld = ImageDraw.Draw(lay)
    ld.rounded_rectangle([box[0] - 14, box[1] - 14, box[2] + 14, box[3] + 14], radius=58, fill=INK + (255,))
    img = add(img, lay)
    cup = gradient_fill(box, (255, 130, 190), (230, 50, 140), lambda m, b=box: m.rounded_rectangle(b, radius=48, fill=255))
    img = add(img, cup)
    lay = new_layer()
    ld = ImageDraw.Draw(lay)
    ld.rounded_rectangle([box[0] + 14, box[1] + 14, box[0] + 34, box[1] + 70], radius=10, fill=(255, 255, 255, 190))
    ld.ellipse([cxp - 16, FY - 22, cxp + 16, FY + 10], fill=(255, 255, 255, 120))
    img = add(img, lay)

# notes and sparkles (outlined)
def note(x, y, s, col):
    lay = new_layer()
    ld = ImageDraw.Draw(lay)
    def shape(dx, w, fill):
        ld.ellipse([x - s - w, y - s * 0.7 - w, x + s + w, y + s * 0.7 + w], fill=fill)
        ld.line([x + s * 0.85, y, x + s * 0.85, y - s * 3.2], fill=fill, width=int(s * 0.34 + 2 * w))
        ld.polygon([(x + s * 0.85 - w, y - s * 3.2 - w), (x + s * 2.2 + w, y - s * 2.4), (x + s * 0.85 + w, y - s * 2.0 + w)], fill=fill)
    shape(0, 9, INK + (255,))
    shape(0, 0, col + (255,))
    return lay
img = add(img, note(S * 0.15, S * 0.4, S * 0.04, (255, 100, 170)))
img = add(img, note(S * 0.85, S * 0.46, S * 0.035, (63, 220, 255)))
def star(cx_, cy_, r, color):
    lay = new_layer()
    ld = ImageDraw.Draw(lay)
    for rr, col in ((r + 9, INK + (255,)), (r, color)):
        pts = []
        for i in range(8):
            ang = math.pi / 4 * i - math.pi / 2
            rad = rr if i % 2 == 0 else rr * 0.3
            pts.append((cx_ + math.cos(ang) * rad, cy_ + math.sin(ang) * rad))
        ld.polygon(pts, fill=col)
    return lay
img = add(img, star(S * 0.27, S * 0.17, S * 0.045, (255, 255, 255, 255)))
img = add(img, star(S * 0.76, S * 0.2, S * 0.04, (255, 244, 130, 255)))

# --- the logo, big, along the bottom -------------------------------------------------------------------------
logo = Image.open("assets/branding/logo_beat_garden.png").convert("RGBA")
target_w = int(S * 0.98)
logo = logo.resize((target_w, int(logo.height * target_w / logo.width)), Image.LANCZOS)
shadow = Image.new("RGBA", logo.size, (10, 0, 40, 0))
shadow.putalpha(logo.split()[3].point(lambda v: int(v * 0.55)))
lx, ly = (S - logo.width) // 2, int(S * 0.97) - logo.height
sh_layer = new_layer()
sh_layer.paste(shadow, (lx + 8, ly + 14), shadow)
img = add(img, sh_layer.filter(ImageFilter.GaussianBlur(10)))
lg_layer = new_layer()
lg_layer.paste(logo, (lx, ly), logo)
img = add(img, lg_layer)

rgb = img.convert("RGB")
os.makedirs("assets/branding", exist_ok=True)
rgb.save("assets/branding/game_icon_1024.png")
rgb.resize((512, 512), Image.LANCZOS).save("assets/branding/game_icon.png")
print("assets/branding/game_icon.png (+ _1024)")
