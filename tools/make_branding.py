# Placeholder community emblem and cover from the master palette.
# Usage: python3 tools/make_branding.py assets/branding
from PIL import Image, ImageDraw, ImageFont
import math, sys
OUT = sys.argv[1]
H = lambda h: tuple(int(h[i:i+2],16) for i in (1,3,5))
SKY, GROUND, WASHI, SUMI = H("#14112B"), H("#231E45"), H("#FFF8F0"), H("#3B3346")
NIGHT = [H("#FF4FA3"), H("#3FC8FF"), H("#3DFFB0"), H("#FFE14D")]
DAY = [H("#F7C6D9"), H("#BFDDF5"), H("#BFE3C0"), H("#FBE7A1")]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

def shape(d, kind, cx, cy, r, fill):
    if kind == 0: d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=fill)
    elif kind == 1: d.polygon([(cx, cy-r*1.1), (cx+r*1.05, cy+r*0.8), (cx-r*1.05, cy+r*0.8)], fill=fill)
    elif kind == 2: d.rounded_rectangle([cx-r*0.85, cy-r*0.85, cx+r*0.85, cy+r*0.85], radius=r*0.15, fill=fill)
    else: d.polygon([(cx, cy-r*1.15), (cx+r*1.0, cy), (cx, cy+r*1.15), (cx-r*1.0, cy)], fill=fill)

def glow(img, cx, cy, r, color):
    g = Image.new("RGBA", img.size, (0,0,0,0)); gd = ImageDraw.Draw(g)
    for i in range(12, 0, -1):
        a = int(10 + (12 - i) * 2)
        rr = r * (1 + i * 0.12)
        gd.ellipse([cx-rr, cy-rr, cx+rr, cy+rr], fill=color + (a,))
    img.alpha_composite(g)

def text(d, xy, s, size, fill, anchor="mm", spacing=0):
    f = ImageFont.truetype(FONT, size)
    if spacing == 0:
        d.text(xy, s, font=f, fill=fill, anchor=anchor); return
    widths = [d.textlength(c, font=f) for c in s]
    total = sum(widths) + spacing * (len(s) - 1)
    x = xy[0] - total / 2
    for c, w in zip(s, widths):
        d.text((x, xy[1]), c, font=f, fill=fill, anchor="lm"); x += w + spacing

def emblem(S=512, SS=4):
    W = S * SS
    img = Image.new("RGBA", (W, W), SKY + (255,)); d = ImageDraw.Draw(img)
    # ground band
    d.rectangle([0, int(W*0.70), W, W], fill=GROUND)
    lane_w = W * 0.17; gap = W * 0.03
    x0 = (W - (4*lane_w + 3*gap)) / 2
    hit_y = W * 0.56
    heights = [0.30, 0.42, 0.24, 0.36]
    for i in range(4):
        cx = x0 + i*(lane_w+gap) + lane_w/2
        top = hit_y - W*heights[i]
        # lane trail
        trail = Image.new("RGBA", img.size, (0,0,0,0)); td = ImageDraw.Draw(trail)
        steps = 40
        for k in range(steps):
            y1 = top + (hit_y - top) * k / steps; y2 = top + (hit_y - top) * (k+1) / steps
            td.rectangle([cx-lane_w*0.22, y1, cx+lane_w*0.22, y2], fill=NIGHT[i] + (int(10 + 120*k/steps),))
        img.alpha_composite(trail)
        glow(img, cx, hit_y, lane_w*0.42, NIGHT[i])
        d = ImageDraw.Draw(img)
        shape(d, i, cx, hit_y, lane_w*0.40, NIGHT[i])
    # hit line
    d.rounded_rectangle([x0 - W*0.02, hit_y + W*0.105, W - x0 + W*0.02, hit_y + W*0.115], radius=W*0.005, fill=WASHI + (200,))
    text(d, (W/2, W*0.80), "BEAT", int(W*0.115), WASHI, spacing=W*0.012)
    text(d, (W/2, W*0.91), "WORKS", int(W*0.075), DAY[0], spacing=W*0.02)
    return img.resize((S, S), Image.LANCZOS).convert("RGB")

def cover(Wp=1440, Hp=456, SS=2):
    W, Hh = Wp*SS, Hp*SS
    img = Image.new("RGBA", (W, Hh), SKY + (255,))
    # day -> night horizontal gradient
    grad = Image.new("RGBA", (W, Hh)); gd = ImageDraw.Draw(grad)
    stops = [(0.0, WASHI), (0.30, WASHI), (0.45, H("#D8C8F0")), (0.58, GROUND), (0.72, SKY), (1.0, SKY)]
    for x in range(W):
        u = x / W
        for (a, ca), (b, cb) in zip(stops, stops[1:]):
            if a <= u <= b:
                t = (u - a) / (b - a) if b > a else 0; t = t*t*(3-2*t)
                c = tuple(int(ca[j]*(1-t) + cb[j]*t) for j in range(3)); break
        gd.line([(x, 0), (x, Hh)], fill=c + (255,))
    img.alpha_composite(grad)
    d = ImageDraw.Draw(img)
    # notes drifting across: pastel on the day side, neon on the night side
    import random; rnd = random.Random(4)
    for n in range(90):
        x = rnd.uniform(0.02, 0.98) * W; y = rnd.uniform(0.08, 0.92) * Hh
        if abs(x - W/2) < W*0.29 and abs(y - Hh/2) < Hh*0.33: continue
        lane = rnd.randrange(4); r = rnd.uniform(0.018, 0.042) * Hh
        t = min(1, max(0, (x / W - 0.40) / 0.25))
        col = tuple(int(DAY[lane][j]*(1-t) + NIGHT[lane][j]*t) for j in range(3))
        if t > 0.5: glow(img, x, y, r, NIGHT[lane]); d = ImageDraw.Draw(img)
        shape(d, lane, x, y, r, col)
    # title plate
    plate = Image.new("RGBA", img.size, (0,0,0,0)); pd = ImageDraw.Draw(plate)
    pd.rounded_rectangle([W*0.25, Hh*0.22, W*0.75, Hh*0.78], radius=Hh*0.06, fill=SKY + (220,))
    img.alpha_composite(plate); d = ImageDraw.Draw(img)
    text(d, (W/2, Hh*0.44), "BEAT WORKS", int(Hh*0.14), WASHI, spacing=Hh*0.012)
    text(d, (W/2, Hh*0.62), "RHYTHM GAMES ON ROBLOX", int(Hh*0.055), DAY[1], spacing=Hh*0.012)
    return img.resize((Wp, Hp), Image.LANCZOS).convert("RGB")

emblem().save(f"{OUT}/emblem_512.png")
cover().save(f"{OUT}/cover_1440x456.png")
print("ok")
