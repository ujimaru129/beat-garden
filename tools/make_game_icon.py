"""Makes the Beat Garden game icon (512x512 PNG): the night-time world in neon (a dark sky with neon rainbows, lasers
and stars, a glowing plot) and a 3D-looking glossy fruit character with headphones.
Usage: python3 tools/make_game_icon.py             ->  assets/branding/game_icon.png
       python3 tools/make_game_icon.py --no-title  ->  assets/branding/game_icon_notitle.png (+ a 1024 px copy)
Needs Pillow and numpy."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import numpy as np
import math, os, random, sys

NO_TITLE = "--no-title" in sys.argv  # the same scene without the title badge (for adding your own logo)

S = 1024
random.seed(7)

def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

# --- night sky ------------------------------------------------------------------------------------------------
sky = np.zeros((S, S, 3), dtype=np.float32)
TOP, MID, LOW = (12, 10, 44), (44, 24, 104), (150, 40, 150)
for y in range(S):
    t = y / S
    c = lerp(TOP, MID, t / 0.6) if t < 0.6 else lerp(MID, LOW, (t - 0.6) / 0.4)
    sky[y, :, :] = c
img = Image.fromarray(sky.astype(np.uint8), "RGB").convert("RGBA")

def glow(layer: Image.Image, radius: float, strength: float = 1.0) -> Image.Image:
    """Adds a blurred copy of `layer` (a glow) under it."""
    blurred = layer.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        a = blurred.split()[3].point(lambda v: min(255, int(v * strength)))
        blurred.putalpha(a)
    return Image.alpha_composite(blurred, layer)

def add(base: Image.Image, layer: Image.Image) -> Image.Image:
    return Image.alpha_composite(base, layer)

def new_layer() -> Image.Image:
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))

# stars
layer = new_layer()
d = ImageDraw.Draw(layer)
for _ in range(120):
    x, y = random.randint(0, S), random.randint(0, int(S * 0.6))
    r = random.choice([2, 2, 3, 4])
    d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, random.randint(120, 255)))
img = add(img, glow(layer, 3))

# --- neon rainbow ---------------------------------------------------------------------------------------------
NEON = [(255, 79, 163), (255, 154, 77), (255, 225, 77), (61, 255, 176), (63, 200, 255), (168, 107, 255)]
layer = new_layer()
d = ImageDraw.Draw(layer)
cx, cy = S / 2, S * 0.72
for i, col in enumerate(NEON):
    r = S * 0.50 - i * S * 0.05
    d.arc([cx - r, cy - r, cx + r, cy + r], 180, 360, fill=col + (255,), width=16)
big = glow(glow(layer, 18, 1.4), 6, 1.0)
img = add(img, big)

# lasers: a dazzling fan of beams from behind the hill, plus beams crossing from the lower corners
def beam(layer, x0, y0, ang_deg, length, col, width):
    d = ImageDraw.Draw(layer)
    a = math.radians(ang_deg)
    x1, y1 = x0 + math.cos(a) * length, y0 + math.sin(a) * length
    d.line([x0, y0, x1, y1], fill=col + (235,), width=width)
    d.line([x0, y0, x1, y1], fill=(255, 255, 255, 255), width=max(2, width // 3))  # hot white core

fan = new_layer()
FAN = [(255, 79, 163), (63, 200, 255), (61, 255, 176), (255, 225, 77), (168, 107, 255), (255, 154, 77)]
n = 17
for k in range(n):
    ang = 196 + k * (148 / (n - 1))
    beam(fan, S * 0.5, S * 0.8, ang, 1300, FAN[k % len(FAN)], 11 if k % 2 else 7)
cross = new_layer()
for k, col in enumerate(FAN[:4]):
    beam(cross, -40, S * (0.35 + k * 0.13), -20 + k * 6, 1500, col, 9)
    beam(cross, S + 40, S * (0.30 + k * 0.14), 200 - k * 6, 1500, FAN[(k + 2) % 6], 9)
img = add(img, glow(glow(fan, 22, 1.6), 7, 1.1))
img = add(img, glow(glow(cross, 20, 1.5), 6, 1.0))
# a haze where the beams meet
haze = new_layer()
ImageDraw.Draw(haze).ellipse([S * 0.1, S * 0.62, S * 0.9, S * 0.98], fill=(255, 79, 200, 90))
img = add(img, haze.filter(ImageFilter.GaussianBlur(60)))

# --- hill with a neon rim -------------------------------------------------------------------------------------
layer = new_layer()
d = ImageDraw.Draw(layer)
d.ellipse([-S * 0.35, S * 0.78, S * 1.35, S * 1.7], fill=(255, 79, 163, 255))
d.ellipse([-S * 0.35, S * 0.795, S * 1.35, S * 1.7], fill=(30, 20, 84, 255))
rim = new_layer()
ImageDraw.Draw(rim).arc([-S * 0.35, S * 0.78, S * 1.35, S * 1.7], 200, 340, fill=(255, 79, 163, 255), width=10)
img = add(img, layer)
img = add(img, glow(rim, 12, 1.5))

# a glowing plot under the plant
layer = new_layer()
d = ImageDraw.Draw(layer)
pcx, pcy, pw, ph = S / 2, (S * 0.88 if NO_TITLE else S * 0.74), S * 0.4, S * 0.06
d.polygon([(pcx - pw / 2, pcy), (pcx + pw / 2, pcy), (pcx + pw / 2 + 60, pcy + ph), (pcx - pw / 2 - 60, pcy + ph)],
          fill=(36, 24, 96, 255), outline=(63, 200, 255, 255), width=8)
img = add(img, glow(layer, 10, 1.4))

# --- 3D shading helpers ---------------------------------------------------------------------------------------
LIGHT = np.array([-0.45, -0.6, 0.66], dtype=np.float32)
LIGHT /= np.linalg.norm(LIGHT)

def sphere(width: int, height: int, base, rim_color=(120, 220, 255), spec=0.9, shine=40) -> Image.Image:
    """A glossy ellipsoid: soft diffuse from the top-left, a hot specular spot and a cool rim light."""
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    nx = (xs - width / 2) / (width / 2)
    ny = (ys - height / 2) / (height / 2)
    r2 = nx * nx + ny * ny
    inside = r2 <= 1.0
    nz = np.sqrt(np.clip(1 - r2, 0, 1))
    n = np.stack([nx, ny, nz], axis=-1)
    diffuse = np.clip(n @ LIGHT, 0, 1)
    ambient = 0.38
    color = np.array(base, dtype=np.float32)[None, None, :] * (ambient + 0.85 * diffuse)[..., None]
    # specular
    view = np.array([0, 0, 1], dtype=np.float32)
    half = LIGHT + view
    half /= np.linalg.norm(half)
    s = np.clip(n @ half, 0, 1) ** shine
    color += (255 * spec * s)[..., None]
    # rim light on the lower right edge
    rim = np.clip(1 - nz, 0, 1) ** 3 * np.clip((nx * 0.7 + ny * 0.7), 0, 1)
    color += np.array(rim_color, dtype=np.float32)[None, None, :] * rim[..., None] * 0.9
    out = np.zeros((height, width, 4), dtype=np.uint8)
    out[..., :3] = np.clip(color, 0, 255).astype(np.uint8)
    # soft anti-aliased edge
    edge = np.clip((1 - np.sqrt(np.clip(r2, 0, 1.2))) * (min(width, height) / 2), 0, 1)
    out[..., 3] = (edge * 255 * inside).astype(np.uint8)
    return Image.fromarray(out, "RGBA")

def paste_sphere(base_img: Image.Image, cx: float, cy: float, w: int, h: int, color, **kw) -> Image.Image:
    sph = sphere(w, h, color, **kw)
    layer = new_layer()
    layer.paste(sph, (int(cx - w / 2), int(cy - h / 2)), sph)
    return add(base_img, layer)

def shadow(base_img: Image.Image, cx: float, cy: float, w: float, h: float, alpha=120) -> Image.Image:
    layer = new_layer()
    ImageDraw.Draw(layer).ellipse([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], fill=(5, 0, 30, alpha))
    return add(base_img, layer.filter(ImageFilter.GaussianBlur(18)))

# --- the plant ------------------------------------------------------------------------------------------------
fx, fy, fr = (S * 0.5, S * 0.4, S * 0.21) if NO_TITLE else (S * 0.5, S * 0.265, S * 0.155)  # fruit centre and radius

# stem: lit from the left, dark on the right
stem = new_layer()
sd = ImageDraw.Draw(stem)
x0, x1, y0, y1 = S * 0.5 - 24, S * 0.5 + 24, fy + fr * 0.8, (S * 0.9 if NO_TITLE else S * 0.66)
for i in range(48):
    t = i / 47
    col = lerp((150, 255, 170), (20, 110, 80), t)
    sd.rectangle([x0 + i, y0, x0 + i + 1, y1], fill=tuple(int(v) for v in col) + (255,))
img = add(img, glow(stem, 10, 0.5))

def leaf(cx_, cy_, w, h, angle, flip):
    sph = sphere(int(w), int(h), (90, 220, 130), rim_color=(61, 255, 176), spec=0.5, shine=30)
    sph = sph.rotate(angle, resample=Image.BICUBIC, expand=True)
    layer = new_layer()
    layer.paste(sph, (int(cx_ - sph.width / 2), int(cy_ - sph.height / 2)), sph)
    return add(img, glow(layer, 8, 0.4))
LY = 0.15 if NO_TITLE else 0
img = leaf(S * 0.5 - 120, S * (0.5 + LY), 210, 78, 22, False)
img = leaf(S * 0.5 + 120, S * (0.46 + LY), 210, 78, -22, True)
if NO_TITLE:
    img = leaf(S * 0.5 - 100, S * 0.76, 190, 72, 14, False)

# fruit glow, shadow and body
halo = new_layer()
for k in range(7, 0, -1):
    rr = fr + k * 30
    ImageDraw.Draw(halo).ellipse([fx - rr, fy - rr, fx + rr, fy + rr], fill=(255, 225, 77, 22))
img = add(img, halo.filter(ImageFilter.GaussianBlur(14)))
img = shadow(img, fx + 20, fy + fr + 40, fr * 1.5, 50, 90)

# headphone band (behind the fruit's top edge): a lit tube
band = new_layer()
bd = ImageDraw.Draw(band)
bb = [fx - fr - 30, fy - fr - 34, fx + fr + 30, fy + fr + 34]
bd.arc(bb, 188, 352, fill=(40, 30, 90, 255), width=44)
bd.arc(bb, 188, 352, fill=(90, 70, 170, 255), width=30)
bd.arc([bb[0] + 6, bb[1] + 6, bb[2] - 6, bb[3] - 6], 215, 300, fill=(200, 190, 255, 255), width=8)
img = add(img, glow(band, 6, 0.5))

img = paste_sphere(img, fx, fy, int(fr * 2), int(fr * 2), (255, 205, 60), rim_color=(255, 120, 60), spec=0.95, shine=36)

# face: glossy eyes, cheeks, smile
for side in (-1, 1):
    ex, ey = fx + side * fr * 0.36, fy + fr * 0.0
    img = paste_sphere(img, ex, ey, 62, 82, (40, 30, 70), rim_color=(120, 120, 255), spec=0.95, shine=18)
    cheek = new_layer()
    ImageDraw.Draw(cheek).ellipse([fx + side * fr * 0.66 - 34, fy + fr * 0.3 - 20, fx + side * fr * 0.66 + 34, fy + fr * 0.3 + 20], fill=(255, 90, 140, 170))
    img = add(img, cheek.filter(ImageFilter.GaussianBlur(5)))
mouth = new_layer()
ImageDraw.Draw(mouth).arc([fx - 40, fy + fr * 0.1, fx + 40, fy + fr * 0.5], 15, 165, fill=(70, 30, 70, 255), width=12)
img = add(img, mouth)

# headphone cups: glossy neon pink spheres with a glowing ring
for side in (-1, 1):
    cxp = fx + side * (fr + 28)
    ring = new_layer()
    ImageDraw.Draw(ring).ellipse([cxp - 62, fy - 20 - 96, cxp + 62, fy - 20 + 96], outline=(255, 79, 163, 255), width=8)
    img = add(img, glow(ring, 10, 1.3))
    img = paste_sphere(img, cxp, fy - 20, 108, 168, (255, 70, 150), rim_color=(255, 200, 240), spec=0.9, shine=30)

# --- neon notes, sparkles and the title -----------------------------------------------------------------------
def note(layer, x, y, s, col):
    d = ImageDraw.Draw(layer)
    d.ellipse([x - s, y - s * 0.7, x + s, y + s * 0.7], fill=col)
    d.line([x + s * 0.85, y, x + s * 0.85, y - s * 3.2], fill=col, width=int(s * 0.34))
    d.polygon([(x + s * 0.85, y - s * 3.2), (x + s * 2.2, y - s * 2.4), (x + s * 0.85, y - s * 2.1)], fill=col)
layer = new_layer()
note(layer, S * 0.17, S * 0.42, S * 0.04, (255, 79, 163, 255))
note(layer, S * 0.83, S * 0.5, S * 0.035, (63, 200, 255, 255))
note(layer, S * 0.76, S * 0.2, S * 0.025, (61, 255, 176, 255))
img = add(img, glow(layer, 9, 1.4))

def star(d, cx, cy, r, color):
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rad = r if i % 2 == 0 else r * 0.26
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    d.polygon(pts, fill=color)
layer = new_layer()
d = ImageDraw.Draw(layer)
star(d, S * 0.28, S * 0.2, S * 0.05, (255, 255, 255, 255))
star(d, S * 0.7, S * 0.62, S * 0.035, (255, 244, 170, 255))
star(d, S * 0.15, S * 0.66, S * 0.03, (255, 255, 255, 255))
img = add(img, glow(layer, 7, 1.5))

if not NO_TITLE:
    # title badge, like a neon sign: a dark disc ringed with neon circles, bold slanted white "BEAT", pink "GARDEN"
    # and a small script line underneath (the look of a promo badge)
    def load_font(paths, size):
        for path in paths:
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
        return ImageFont.load_default()

    HEAVY = ["/Library/Fonts/Archivo-BlackItalic.ttf", "/Library/Fonts/Kanit-BlackItalic.ttf",
             "/System/Library/Fonts/Supplemental/Arial Black.ttf"]
    SCRIPT = ["/Library/Fonts/Satisfy-Regular.ttf", "/Library/Fonts/KaushanScript-Regular.ttf"]

    bx, by, br = S * 0.5, S * 0.75, S * 0.335
    disc = new_layer()
    ImageDraw.Draw(disc).ellipse([bx - br, by - br, bx + br, by + br], fill=(26, 8, 70, 235))
    img = add(img, disc)
    rings = new_layer()
    rd = ImageDraw.Draw(rings)
    for rr, col, w in [(br, (255, 79, 200), 12), (br - 30, (63, 220, 255), 9), (br - 56, (255, 79, 200), 5), (br - 74, (63, 220, 255), 4)]:
        rd.ellipse([bx - rr, by - rr, bx + rr, by + rr], outline=col + (255,), width=w)
    img = add(img, glow(glow(rings, 16, 1.7), 5, 1.2))

    def slanted(text, cx, cy, size, slant=0.16):
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).text((cx, cy), text, font=load_font(HEAVY, size), fill=255, anchor="mm")
        return mask.transform((S, S), Image.AFFINE, (1, slant, -slant * cy, 0, 1, 0), resample=Image.BICUBIC)

    def solid(base, mask, color, glow_color=None, outline=None):
        if glow_color:
            g = Image.new("RGBA", (S, S), glow_color + (255,))
            g.putalpha(mask.filter(ImageFilter.MaxFilter(9)))
            base = add(base, glow(g, 14, 1.2))
        if outline:
            o = Image.new("RGBA", (S, S), outline + (255,))
            o.putalpha(mask.filter(ImageFilter.MaxFilter(11)))
            base = add(base, o)
        f = Image.new("RGBA", (S, S), color + (255,))
        f.putalpha(mask)
        return add(base, f)

    beat = slanted("BEAT", S * 0.5, S * 0.69, int(S * 0.19))
    img = solid(img, beat, (255, 255, 255), glow_color=(120, 220, 255), outline=(40, 10, 90))

    garden = slanted("GARDEN", S * 0.5, S * 0.805, int(S * 0.135))
    grad = Image.new("RGB", (S, S))
    gp = grad.load()
    for y in range(S):
        t = min(1, max(0, (y - S * 0.74) / (S * 0.12)))
        c = lerp((255, 90, 200), (255, 60, 130), t)
        for x in range(0, S):
            gp[x, y] = tuple(int(v) for v in c)
    gl = Image.new("RGBA", (S, S), (255, 70, 190, 255))
    gl.putalpha(garden.filter(ImageFilter.MaxFilter(9)))
    img = add(img, glow(gl, 14, 1.2))
    ol = Image.new("RGBA", (S, S), (40, 10, 90, 255))
    ol.putalpha(garden.filter(ImageFilter.MaxFilter(11)))
    img = add(img, ol)
    gf = grad.convert("RGBA")
    gf.putalpha(garden)
    img = add(img, gf)

    script = new_layer()
    ImageDraw.Draw(script).text((S * 0.5, S * 0.895), "Grow to the Beat", font=load_font(SCRIPT, int(S * 0.075)), fill=(255, 255, 255, 255), anchor="mm")
    img = add(img, glow(script, 10, 1.5))


os.makedirs("assets/branding", exist_ok=True)
rgb = img.convert("RGB")
if NO_TITLE:
    rgb.save("assets/branding/game_icon_notitle_1024.png")
    rgb.resize((512, 512), Image.LANCZOS).save("assets/branding/game_icon_notitle.png")
    print("assets/branding/game_icon_notitle.png (+ _1024)")
else:
    rgb.resize((512, 512), Image.LANCZOS).save("assets/branding/game_icon.png")
    print("assets/branding/game_icon.png")
