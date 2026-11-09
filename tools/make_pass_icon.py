"""Makes the Plot Pass icon (512x512 PNG) in the game's candy-pastel look: sky, rainbow, clouds, a pastel ground
with three garden plots (the big one gold-framed, with a plus) and a "+2" badge.
Usage: python3 tools/make_pass_icon.py  ->  assets/branding/plot_pass.png"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

S = 1024  # drawn big, then shrunk for smooth edges

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# sky: light blue at the top to a pink haze at the horizon
img = Image.new("RGB", (S, S))
px = img.load()
TOP, MID, LOW = (143, 211, 255), (214, 200, 255), (255, 205, 230)
for y in range(S):
    t = y / S
    c = lerp(TOP, MID, t / 0.55) if t < 0.55 else lerp(MID, LOW, (t - 0.55) / 0.45)
    for x in range(S):
        px[x, y] = c
d = ImageDraw.Draw(img, "RGBA")

# rainbow (pastel), a big arch behind the plots
cx, cy = S / 2, S * 0.62
colors = [(255, 160, 190), (255, 200, 150), (255, 236, 150), (170, 235, 190), (150, 215, 255), (200, 175, 255)]
for i, col in enumerate(colors):
    r = S * 0.50 - i * S * 0.045
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (255,))
r_in = S * 0.50 - len(colors) * S * 0.045
d.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in], fill=(235, 220, 255, 255))

# clouds
def cloud(x, y, s):
    for dx, dy, rr in [(-0.9, 0.1, 0.6), (-0.3, -0.25, 0.75), (0.4, -0.1, 0.7), (1.0, 0.15, 0.55), (0.05, 0.2, 0.7)]:
        d.ellipse([x + dx * s - rr * s, y + dy * s - rr * s, x + dx * s + rr * s, y + dy * s + rr * s], fill=(255, 255, 255, 235))
cloud(S * 0.17, S * 0.2, S * 0.07)
cloud(S * 0.83, S * 0.32, S * 0.06)

# ground: a mint hill with a pink rim, like the island
d.ellipse([-S * 0.25, S * 0.62, S * 1.25, S * 1.5], fill=(255, 170, 215, 255))
d.ellipse([-S * 0.25, S * 0.65, S * 1.25, S * 1.5], fill=(170, 235, 215, 255))
d.ellipse([S * 0.05, S * 0.72, S * 0.95, S * 1.3], fill=(190, 242, 225, 255))

# balloons
def balloon(x, y, r, col):
    d.line([x, y + r, x - r * 0.15, y + r * 3.2], fill=(255, 255, 255, 200), width=5)
    d.ellipse([x - r, y - r * 1.15, x + r, y + r * 1.15], fill=col + (255,))
    d.ellipse([x - r * 0.55, y - r * 0.85, x - r * 0.1, y - r * 0.3], fill=(255, 255, 255, 140))
balloon(S * 0.1, S * 0.5, S * 0.05, (255, 175, 210))
balloon(S * 0.91, S * 0.58, S * 0.045, (255, 225, 140))
balloon(S * 0.2, S * 0.42, S * 0.035, (190, 170, 255))

def tile(cx, cy, size, frame, soil):
    h = size / 2
    d.rounded_rectangle([cx - h + 8, cy - h + 18, cx + h + 8, cy + h + 18], radius=size * 0.14, fill=(120, 100, 170, 70))  # shadow
    d.rounded_rectangle([cx - h, cy - h, cx + h, cy + h], radius=size * 0.14, fill=(255, 255, 255, 255))
    d.rounded_rectangle([cx - h + 12, cy - h + 12, cx + h - 12, cy + h - 12], radius=size * 0.11, fill=frame + (255,))
    d.rounded_rectangle([cx - h + 38, cy - h + 38, cx + h - 38, cy + h - 38], radius=size * 0.07, fill=soil + (255,))

tile(S * 0.24, S * 0.78, S * 0.25, (170, 215, 255), (200, 180, 240))
tile(S * 0.76, S * 0.78, S * 0.25, (255, 175, 210), (200, 180, 240))
tile(S * 0.50, S * 0.66, S * 0.42, (255, 216, 77), (255, 214, 232))

# plus on the big plot
px_, py_, arm, thick = S * 0.5, S * 0.66, S * 0.12, S * 0.042
d.rounded_rectangle([px_ - arm, py_ - thick, px_ + arm, py_ + thick], radius=thick, fill=(255, 130, 175, 255))
d.rounded_rectangle([px_ - thick, py_ - arm, px_ + thick, py_ + arm], radius=thick, fill=(255, 130, 175, 255))

def star(cx, cy, r, color=(255, 255, 255, 255)):
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rad = r if i % 2 == 0 else r * 0.28
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    d.polygon(pts, fill=color)
star(S * 0.34, S * 0.5, S * 0.05, (255, 255, 255, 255))
star(S * 0.67, S * 0.46, S * 0.04, (255, 244, 170, 255))
star(S * 0.5, S * 0.4, S * 0.035, (255, 255, 255, 255))

# "+2" badge
bx, by, br = S * 0.82, S * 0.17, S * 0.125
d.ellipse([bx - br + 8, by - br + 12, bx + br + 8, by + br + 12], fill=(120, 100, 170, 70))
d.ellipse([bx - br, by - br, bx + br, by + br], fill=(255, 130, 165, 255), outline=(255, 255, 255, 255), width=16)
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf", int(S * 0.15))
except OSError:
    font = ImageFont.load_default()
d.text((bx, by + 4), "+2", font=font, fill=(255, 255, 255, 255), anchor="mm")

out = img.resize((512, 512), Image.LANCZOS)
os.makedirs("assets/branding", exist_ok=True)
out.save("assets/branding/plot_pass.png")
print("assets/branding/plot_pass.png")
