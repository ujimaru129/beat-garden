"""Makes the song sleeves (512x512 PNG) for the song select screen, in the logo's pop style: a genre-coloured
background with a motif that suits the song, a big outlined title, the genre and the BPM.
Usage: python3 tools/make_song_art.py  ->  assets/songart/<songId>.png (+ contact_sheet.png)
Upload each PNG to Creator Hub as an Image and put its id in src/shared/Songs/Art.luau."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os, random

S = 1024
INK = (44, 18, 82)
HEAVY = "/Library/Fonts/Archivo-BlackItalic.ttf"

SONGS = [
    # id, title, genre, bpm, (top, bottom) colours, motif
    ("kabuki_dance", "Kabuki Dance", "JAPAN", 150, ((255, 90, 90), (150, 20, 60)), "sun"),
    ("dard_aur_dhamaka", "Dard aur Dhamaka", "DANCE", 148, ((70, 220, 255), (90, 40, 190)), "rings"),
    ("pastel_trip", "Pastel Trip", "POP", 100, ((255, 190, 225), (170, 210, 255)), "clouds"),
    ("kamikaze", "Kamikaze", "ROCK", 148, ((190, 90, 255), (40, 10, 90)), "bolt"),
    ("gorilla_glue", "Gorilla Glue", "ROCK", 164, ((120, 230, 90), (30, 20, 90)), "hex"),
    ("fly_me_to_the_saitama", "Fly Me to the Saitama", "DANCE", 150, ((110, 200, 255), (255, 170, 220)), "stars"),
    ("metropolitan_expressway", "Metropolitan Expressway", "DANCE", 152, ((255, 150, 60), (30, 20, 100)), "road"),
    ("naniwa_march", "Naniwa March", "JAPAN", 144, ((255, 215, 70), (240, 90, 40)), "stripes"),
    ("blue_samurai", "Blue Samurai", "JAPAN", 177, ((90, 160, 255), (20, 20, 90)), "slash"),
    ("shinjuku_deep_romance", "Shinjuku Deep Romance", "POP", 133, ((255, 80, 190), (60, 20, 130)), "rain"),
]

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(top, bottom):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S))
    return img.convert("RGBA")

def glow(layer, r):
    b = layer.filter(ImageFilter.GaussianBlur(r))
    return Image.alpha_composite(b, layer)

def lay():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))

# --- motifs (drawn on the upper two thirds; the title sits at the bottom) -----------------------------------------
def motif(name, img):
    random.seed(name)
    L = lay(); d = ImageDraw.Draw(L)
    cx, cy = S * 0.5, S * 0.4
    if name == "sun":
        for k in range(24):
            a0 = math.radians(k * 15); a1 = a0 + math.radians(7.5)
            d.polygon([(cx, cy), (cx + math.cos(a0) * 900, cy + math.sin(a0) * 900), (cx + math.cos(a1) * 900, cy + math.sin(a1) * 900)], fill=(255, 220, 120, 70))
        d.ellipse([cx - 190, cy - 190, cx + 190, cy + 190], fill=(255, 236, 150, 255), outline=INK + (255,), width=14)
        for k in range(5):
            r = 260 + k * 38
            d.arc([cx - r, cy - r, cx + r, cy + r], 200, 340, fill=(255, 255, 255, 200), width=10)
    elif name == "rings":
        for k in range(7):
            r = 90 + k * 70
            d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 230 - k * 25), width=14)
        d.ellipse([cx - 60, cy - 60, cx + 60, cy + 60], fill=(255, 79, 200, 255), outline=INK + (255,), width=10)
    elif name == "clouds":
        for (x, y, s) in [(0.25, 0.3, 120), (0.7, 0.22, 150), (0.5, 0.48, 170), (0.82, 0.5, 100), (0.15, 0.55, 90)]:
            for dx, dy, rr in [(-0.9, 0.1, 0.6), (-0.3, -0.3, 0.8), (0.4, -0.1, 0.7), (1.0, 0.15, 0.55), (0.05, 0.2, 0.7)]:
                d.ellipse([S * x + dx * s - rr * s, S * y + dy * s - rr * s, S * x + dx * s + rr * s, S * y + dy * s + rr * s], fill=(255, 255, 255, 235))
    elif name == "bolt":
        pts = [(cx + 40, cy - 330), (cx - 150, cy + 20), (cx - 10, cy + 20), (cx - 90, cy + 330), (cx + 170, cy - 60), (cx + 20, cy - 60)]
        d.polygon([(x + 10, y + 16) for x, y in pts], fill=(20, 0, 60, 120))
        d.polygon(pts, fill=(255, 235, 90, 255), outline=INK + (255,), width=12)
    elif name == "hex":
        for gy in range(-1, 7):
            for gx in range(-1, 8):
                x = gx * 150 + (75 if gy % 2 else 0); y = gy * 130 - 30
                pts = [(x + 70 * math.cos(math.radians(60 * k + 30)), y + 70 * math.sin(math.radians(60 * k + 30))) for k in range(6)]
                d.polygon(pts, outline=(255, 255, 255, 70), width=6)
        pts = [(cx + 200 * math.cos(math.radians(60 * k + 30)), cy + 200 * math.sin(math.radians(60 * k + 30))) for k in range(6)]
        d.polygon(pts, fill=(160, 255, 110, 255), outline=INK + (255,), width=14)
        d.ellipse([cx - 70, cy - 70, cx + 70, cy + 70], fill=(40, 20, 100, 255))
    elif name == "stars":
        for _ in range(26):
            x, y, r = random.randint(40, S - 40), random.randint(40, 700), random.randint(10, 30)
            d.polygon([(x + math.cos(math.pi / 4 * i - math.pi / 2) * (r if i % 2 == 0 else r * 0.3), y + math.sin(math.pi / 4 * i - math.pi / 2) * (r if i % 2 == 0 else r * 0.3)) for i in range(8)], fill=(255, 255, 255, 220))
        d.polygon([(cx - 230, cy + 40), (cx + 250, cy - 120), (cx - 10, cy + 20), (cx + 60, cy + 150)], fill=(255, 255, 255, 255), outline=INK + (255,), width=12)
    elif name == "road":
        horizon = S * 0.42
        d.rectangle([0, horizon, S, S], fill=(40, 24, 90, 255))
        for k in range(-6, 7):
            d.line([(cx + k * 30, horizon), (cx + k * 220, S)], fill=(255, 190, 90, 230), width=8)
        for k in range(6):
            y = horizon + (k + 1) ** 2 * 14
            d.line([(0, y), (S, y)], fill=(255, 120, 200, 140), width=6)
        for k in range(14):
            x = k * 80; h = random.randint(80, 230)
            d.rectangle([x, horizon - h, x + 64, horizon], fill=(24, 14, 70, 255))
            for wy in range(int(horizon - h) + 12, int(horizon) - 10, 26):
                d.rectangle([x + 12, wy, x + 22, wy + 10], fill=(255, 220, 120, 255))
    elif name == "stripes":
        for k in range(-3, 9):
            d.polygon([(k * 150, S * 0.0), (k * 150 + 70, 0), (k * 150 + 70 - 300, S), (k * 150 - 300, S)], fill=(255, 255, 255, 60))
        d.ellipse([cx - 210, cy - 210, cx + 210, cy + 210], fill=(255, 240, 200, 255), outline=INK + (255,), width=14)
        d.ellipse([cx - 120, cy - 120, cx + 120, cy + 120], outline=(240, 90, 40, 255), width=18)
    elif name == "slash":
        d.ellipse([S * 0.62, S * 0.08, S * 0.92, S * 0.38], fill=(235, 245, 255, 255), outline=INK + (255,), width=10)
        d.polygon([(40, 640), (980, 120), (990, 190), (60, 700)], fill=(255, 255, 255, 255))
        d.polygon([(40, 640), (980, 120), (940, 100), (10, 620)], fill=(120, 190, 255, 255))
        d.line([(40, 640), (980, 120)], fill=INK + (255,), width=10)
    elif name == "rain":
        for _ in range(60):
            x, y = random.randint(0, S), random.randint(0, 760)
            d.line([(x, y), (x - 24, y + 90)], fill=(255, 190, 240, 200), width=6)
        # a neon heart
        pts = []
        for k in range(0, 360, 4):
            t = math.radians(k)
            pts.append((cx + 16 * math.sin(t) ** 3 * 12, cy - (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) * 12 + 10))
        d.polygon(pts, fill=(255, 90, 170, 255), outline=(255, 255, 255, 255), width=12)
    return Image.alpha_composite(img, glow(L, 6) if name in ("rings", "rain", "bolt") else L)

# --- text ---------------------------------------------------------------------------------------------------------
def fit_lines(title):
    words = title.split()
    options = []
    for split in range(1, len(words)):
        options.append([" ".join(words[:split]), " ".join(words[split:])])
    options.append([title])
    best = None
    for lines in options:
        size = 200
        while size > 50:
            f = ImageFont.truetype(HEAVY, size)
            if max(f.getlength(l) for l in lines) <= S * 0.86 and size * len(lines) * 1.0 <= 360:
                break
            size -= 4
        if best is None or size > best[0]:
            best = (size, lines)
    return best

def draw_text(img, title, genre, bpm):
    size, lines = fit_lines(title)
    f = ImageFont.truetype(HEAVY, size)
    d = ImageDraw.Draw(img)
    total = len(lines) * size * 0.98
    y = S * 0.93 - total + size * 0.5
    for line in lines:
        d.text((S / 2 + 6, y + 8), line, font=f, fill=(20, 0, 50, 140), anchor="mm", stroke_width=16, stroke_fill=(20, 0, 50, 140))
        d.text((S / 2, y), line, font=f, fill=(255, 255, 255, 255), anchor="mm", stroke_width=14, stroke_fill=INK + (255,))
        y += size * 0.98
    chip = ImageFont.truetype(HEAVY, 56)
    for text, x in ((genre, 70), (f"{bpm} BPM", S - 70)):
        w = chip.getlength(text)
        x0 = x if x < S / 2 else x - w - 50
        d.rounded_rectangle([x0, 50, x0 + w + 50, 130], radius=40, fill=(255, 255, 255, 240), outline=INK + (255,), width=8)
        d.text((x0 + 25 + w / 2, 91), text, font=chip, fill=INK + (255,), anchor="mm")

os.makedirs("assets/songart", exist_ok=True)
sheet = Image.new("RGB", (5 * 256, 2 * 256))
for k, (sid, title, genre, bpm, (top, bottom), mot) in enumerate(SONGS):
    img = gradient(top, bottom)
    img = motif(mot, img)
    draw_text(img, title, genre, bpm)
    out = img.convert("RGB").resize((512, 512), Image.LANCZOS)
    out.save(f"assets/songart/{sid}.png")
    sheet.paste(out.resize((256, 256), Image.LANCZOS), ((k % 5) * 256, (k // 5) * 256))
sheet.save("assets/songart/contact_sheet.png")
print("done", len(SONGS))
