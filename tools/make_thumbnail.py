"""Makes the game page thumbnail (1920x1080) from the hand-made pieces: the logo, the mascot illustration (cut out)
and phone-shaped game screenshots, on a pop background (diagonal stripes, halftone dots).
Usage: python3 tools/make_thumbnail.py            ->  assets/branding/thumbnail_1.png
       python3 tools/make_thumbnail.py --blank    ->  assets/branding/thumbnail_blank.png (no logo, no mascot)
Inputs: assets/branding/logo_beat_garden.png, mascot_cutout.png, assets/screenshots/*_phone.png"""
from PIL import Image, ImageDraw, ImageFilter
import math, random, sys

BLANK = "--blank" in sys.argv  # no logo and no mascot (to add your own on the left)

W, H = 1920, 1080
random.seed(5)
INK = (44, 18, 82)

def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))

# --- background: diagonal pop stripes in the mascot's colours, with halftone dots in two corners ----------------
img = Image.new("RGBA", (W, H), (190, 120, 235, 255))
d = ImageDraw.Draw(img)
BANDS = [((90, 225, 185), 0.00), ((245, 70, 110), 0.28), ((190, 120, 235), 0.58), ((90, 225, 185), 0.8)]
shear = 0.55
for k, (col, start) in enumerate(BANDS):
    y0 = start * H
    d.polygon([(0, y0 + 160), (W, y0 - 340 + 160), (W, H + 600), (0, H + 600)], fill=col + (255,))
# a soft pink glow behind where the mascot stands
glow = layer()
ImageDraw.Draw(glow).ellipse([60, 200, 900, 1100], fill=(255, 235, 140, 110))
img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(80)))
dots = layer()
dd = ImageDraw.Draw(dots)
for corner in ((0, 0), (W, H)):
    for gx in range(0, 520, 26):
        for gy in range(0, 380, 26):
            x = corner[0] + (gx if corner[0] == 0 else -gx)
            y = corner[1] + (gy if corner[1] == 0 else -gy)
            r = max(1, int(10 * (1 - math.hypot(gx / 520, gy / 380))))
            dd.ellipse([x - r, y - r, x + r, y + r], fill=(60, 20, 90, 120))
img = Image.alpha_composite(img, dots)

def sticker(src, outline=14, color=(255, 255, 255, 255)):
    """The picture with a thick white outline and a soft drop shadow, like a sticker."""
    alpha = src.split()[3]
    grown = alpha
    for _ in range(outline):
        grown = grown.filter(ImageFilter.MaxFilter(3))
    base = Image.new("RGBA", src.size, color)
    base.putalpha(grown)
    out = Image.alpha_composite(base, src)
    return out

def put(canvas, pic, x, y, angle=0.0, shadow=True):
    pic = pic.rotate(angle, resample=Image.BICUBIC, expand=True) if angle else pic
    if shadow:
        sh = Image.new("RGBA", pic.size, (30, 0, 60, 0))
        sh.putalpha(pic.split()[3].point(lambda v: int(v * 0.5)))
        lay = layer()
        lay.paste(sh, (int(x + 14), int(y + 20)), sh)
        canvas = Image.alpha_composite(canvas, lay.filter(ImageFilter.GaussianBlur(14)))
    lay = layer()
    lay.paste(pic, (int(x), int(y)), pic)
    return Image.alpha_composite(canvas, lay)

# --- game screens on the right, fanned a little ----------------------------------------------------------------
shots = [("garden_day", -3, 1070, 30), ("rhythm_lane_day", 2, 1100, 372), ("night_lasers", -2, 1060, 716)]
pw = 740
for name, angle, x, y in shots:
    ph = Image.open(f"assets/screenshots/{name}_phone.png").convert("RGBA")
    ph = ph.resize((pw, int(ph.height * pw / ph.width)), Image.LANCZOS)
    img = put(img, ph, x, y, angle)

if not BLANK:
    # --- the logo, on top ------------------------------------------------------------------------------------------
    logo = Image.open("assets/branding/logo_beat_garden.png").convert("RGBA")
    lw = 940
    logo = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
    # a cream sticker backing under the logo (fills the gaps inside it and hides stray edge pixels)
    la = logo.split()[3]
    back = la
    for _ in range(14):
        back = back.filter(ImageFilter.MaxFilter(3))
    for _ in range(10):
        back = back.filter(ImageFilter.MinFilter(3))
    back = back.filter(ImageFilter.GaussianBlur(7)).point(lambda v: 255 if v > 120 else 0).filter(ImageFilter.GaussianBlur(1.2))
    backing = Image.new("RGBA", logo.size, (255, 250, 232, 255))
    backing.putalpha(back)
    logo = Image.alpha_composite(backing, logo)
    img = put(img, logo, 30, 16, 0)

    # --- the mascot, large, on the left ----------------------------------------------------------------------------
    mascot = Image.open("assets/branding/mascot_cutout.png").convert("RGBA")
    mh = 730
    mascot = mascot.resize((int(mascot.width * mh / mascot.height), mh), Image.LANCZOS)
    img = put(img, sticker(mascot, 12), 330, H - mh - 6, -3)


# a few sparkles
def star(canvas, cx, cy, r, color=(255, 244, 130, 255)):
    lay = layer()
    ld = ImageDraw.Draw(lay)
    for rr, col in ((r + 8, INK + (255,)), (r, color)):
        pts = []
        for i in range(8):
            ang = math.pi / 4 * i - math.pi / 2
            rad = rr if i % 2 == 0 else rr * 0.3
            pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
        ld.polygon(pts, fill=col)
    return Image.alpha_composite(canvas, lay)
img = star(img, 960, 70, 40)
img = star(img, 900, 560, 34)
img = star(img, 1860, 1020, 36, (255, 255, 255, 255))

out = "assets/branding/thumbnail_blank.png" if BLANK else "assets/branding/thumbnail_1.png"
img.convert("RGB").save(out)
print(out)
