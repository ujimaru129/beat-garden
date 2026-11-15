#!/usr/bin/env python3
"""Cuts the raw screen recording into 9:16 TikTok clips: the gameplay in the middle over a blurred copy of itself,
the game icon + title on top, and a short info line below. Usage: python3 tools/make_promo_clips.py [clip name ...]"""
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAWS = sorted((ROOT / "promo/raw").glob("*.mp4"))
RAW_OLD = RAWS[0]  # 11/12: a 1080x2400 phone recording with the game in a strip
RAW_LANDSCAPE = RAWS[1] if len(RAWS) > 1 else None  # 11/13: 2400x1080 landscape recording
OUT = ROOT / "promo/final"
ICON = ROOT / "assets/branding/game_icon_final_512.png"
FONT = "/System/Library/Fonts/ヒラギノ丸ゴ ProN W4.ttc"
W, H = 1080, 1920
GAME_Y = 480  # top of the gameplay strip in the 9:16 frame
CROP = "crop=1080:484:0:958"  # the game is a 1080x484 strip inside the 1080x2400 recording

# name, start, length, line under the title
CLIPS = [
    ("01_combo", 33, 22, "リズムに合わせてタップ！"),
    ("02_combo_100", 97, 23, "100コンボ目指せ！"),
    ("03_plant_harvest", 123.5, 20, "リズムゲームで植物が育つ"),
    ("04_park", 180, 20, "自分の庭が遊園地になる"),
    ("05_select_and_play", 198, 25, "好きな曲を選んで遊ぼう"),
    ("06_combo_50", 242, 22, "50コンボ！ノリノリ"),
]

# The landscape recording (song select -> difficulty -> Expert). The temporary Day / Night button (top centre) is
# removed from the picture; the whole width is scaled to the strip.
CROP_LANDSCAPE = "delogo=x=1045:y=165:w=310:h=125,scale=1080:484"
CLIPS_LANDSCAPE = [("07_song_select_expert", 15, 30, "")]
# 11/14: song select scroll (new songs) -> Good Morning Harajuku play. Uses the landscape recording from Dropbox.
RAW_NEWSONGS = Path("/Users/tadashi/TOKYOLOGIC Dropbox/Ujigawa Tadashi/screen-20261114-124808-1794628016845.mp4~2.mp4")
CLIPS_NEWSONGS = [("08_new_songs", 0, 43, "NEW SONGS ADDED")]
# 11/14 evening: a real 2400x1080 landscape recording (daytime, Pastel Trip), scaled whole into the strip.
RAW_DAY = Path("/Users/tadashi/TOKYOLOGIC Dropbox/Ujigawa Tadashi/screen-20261114-200756-1794654424737.mp4~2.mp4")
CLIPS_DAY = [("09_day_pastel_trip", 5, 20.5, "")]
# 11/15: Spirits select -> level up -> jump (Mac screen recording 2578x1326, a little top/bottom trimmed to fit the strip).
RAW_SPIRITS = Path("/Users/tadashi/Desktop/画面収録 2026-11-15 12.11.36.mov")
CLIPS_SPIRITS = [("10_spirits_levelup", 2, 26, "")]


# the white banner text needs a dark backdrop: the daytime recording is bright, so its blurred background is darkened
BG_EQ = {"09_day_pastel_trip": "brightness=-0.38:saturation=1.1"}


def font(size):
    return ImageFont.truetype(FONT, size)


def text_c(d, y, text, size, fill, stroke=None, sw=0):
    f = font(size)
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y), text, font=f, fill=fill, stroke_width=sw, stroke_fill=stroke)


def paste_shadowed(img, art, width, y):
    art = art.resize((width, round(art.height * width / art.width)), Image.LANCZOS)
    x = (W - width) // 2
    shadow = Image.new("RGBA", art.size, (40, 20, 90, 0))
    shadow.putalpha(art.getchannel("A").point(lambda a: int(a * 0.55)))
    from PIL import ImageFilter
    shadow = shadow.filter(ImageFilter.GaussianBlur(8))
    img.alpha_composite(shadow, (x + 4, y + 8))
    img.alpha_composite(art, (x, y))


def overlay(line, path):
    # the logo, the tagline and the info banner are artwork from assets/branding/promo (the line argument is unused)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    art = ROOT / "assets/branding/promo"
    # Everything sits in the upper 3/4: YouTube Shorts and TikTok cover the bottom with the title and buttons.
    paste_shadowed(img, Image.open(art / "logo.png"), 700, 100)
    paste_shadowed(img, Image.open(art / "info_banner.png"), 840, GAME_Y + 484 + 30)
    if line == "NEW SONGS ADDED":  # a pill under the info banner
        d = ImageDraw.Draw(img)
        f = font(64)
        w = d.textlength(line, font=f)
        x0, y0 = (W - w) / 2 - 50, 1365
        d.rounded_rectangle((x0, y0, x0 + w + 100, y0 + 100), 50, fill=(255, 62, 150, 255), outline=(255, 255, 255, 255), width=6)
        d.text((x0 + 50, y0 + 12), line, font=f, fill=(255, 255, 255, 255))
    img.save(path)


def main():
    OUT.mkdir(exist_ok=True)
    tmp = OUT / "_overlay.png"
    jobs = [(RAW_OLD, CROP, c) for c in CLIPS]
    if RAW_LANDSCAPE:
        jobs += [(RAW_LANDSCAPE, CROP_LANDSCAPE, c) for c in CLIPS_LANDSCAPE]
    jobs += [(RAW_NEWSONGS, CROP, c) for c in CLIPS_NEWSONGS]  # a portrait 1080x2400 phone recording (rotation metadata), like the first one
    jobs += [(RAW_DAY, "scale=1080:486,crop=1080:484", c) for c in CLIPS_DAY]
    jobs += [(RAW_SPIRITS, "crop=2578:1156:0:85,scale=1080:484", c) for c in CLIPS_SPIRITS]
    only = sys.argv[1:]  # clip names to make (default: all)
    for raw, crop, (name, start, length, line) in jobs:
        if only and name not in only:
            continue
        overlay(line, tmp)
        fade_out = length - 0.4
        bg_eq = BG_EQ.get(name, "brightness=0.05:saturation=1.2")
        fc = (
            f"[0:v]{crop},split[a][b];"
            f"[a]scale=-2:{H},crop={W}:{H},boxblur=40:4,eq={bg_eq}[bg];"
            f"[bg][b]overlay=0:{GAME_Y}[v1];"
            f"[v1][1:v]overlay=0:0,fps=30,fade=t=in:st=0:d=0.3,fade=t=out:st={fade_out}:d=0.4[v]"
        )
        has_audio = bool(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=index",
                                         "-of", "csv=p=0", str(raw)], capture_output=True, text=True).stdout.strip())
        audio = ["-map", "0:a", "-af", f"afade=t=in:d=0.3,afade=t=out:st={length - 0.6}:d=0.6",
                 "-c:a", "aac", "-b:a", "160k"] if has_audio else ["-an"]  # some screen recordings are silent
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-t", str(length), "-i", str(raw), "-i", str(tmp),
             "-filter_complex", fc, "-map", "[v]", *audio,
             "-c:v", "libx264", "-crf", "23", "-preset", "medium", "-pix_fmt", "yuv420p",
             "-movflags", "+faststart", str(OUT / f"{name}.mp4")],
            check=True)
        print("made", name)
    tmp.unlink()


if __name__ == "__main__":
    main()
