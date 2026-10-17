"""Draws the slime used in the README images, 24x24, into the input folder of
screenshots.gd: frames/ (hop and idle rows), keys/ and run_keys/ (two keys of a bounce)
and slime_sheet.png (the frames on magenta).

Usage: python _dev/readme/make_slime.py <input folder>
"""
import math
import sys
from pathlib import Path

from PIL import Image

S = 24
BASE = 21  # bottom row of the slime when on the ground
OUTLINE = (34, 84, 58, 255)
DARK = (52, 150, 92, 255)
BODY = (92, 206, 120, 255)
LIGHT = (170, 238, 176, 255)
EYE = (24, 40, 36, 255)
SHADOW = (0, 0, 0, 70)


def slime(w, h, lift=0.0, blink=False, look=0, shadow=True):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    cx = S / 2
    bottom = BASE + 1 - lift
    a = w / 2
    top_r = h * 0.68
    bot_r = h * 0.32
    cy = bottom - bot_r
    inside = set()
    for y in range(S):
        for x in range(S):
            dx = (x + 0.5 - cx) / a
            yy = y + 0.5
            dy = (yy - cy) / (top_r if yy < cy else bot_r)
            if dx * dx + dy * dy <= 1.0:
                inside.add((x, y))
    # no lone pixels sticking out of the top
    for y in range(S):
        row = [p for p in inside if p[1] == y]
        if row and len(row) < 3:
            inside.difference_update(row)
    # shadow, smaller the higher it is
    sw = max(4, int(round(w * (1 - lift / 14) * 0.8)))
    for x in range(int(cx - sw / 2), int(cx + sw / 2)) if shadow else []:
        px[x, BASE + 1] = SHADOW
    top = min(y for _, y in inside)
    for x, y in inside:
        rel = (y - top) / max(1, (bottom - top))
        color = BODY if rel < 0.62 else DARK
        px[x, y] = color
    # highlight on the upper left
    for x, y in inside:
        if (x + 0.5 - (cx - a * 0.45)) ** 2 / (a * 0.32) ** 2 + (y + 0.5 - (top + h * 0.22)) ** 2 / (h * 0.16) ** 2 <= 1:
            px[x, y] = LIGHT
    for x, y in inside:
        if any((x + ox, y + oy) not in inside for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            px[x, y] = OUTLINE
    ey = int(top + h * 0.38)
    for ex in (int(cx - 3) + look, int(cx + 2) + look):
        if blink:
            px[ex, ey + 1] = EYE
        else:
            px[ex, ey] = EYE
            px[ex, ey + 1] = EYE
    return img


IDLE = [(18, 13, 0), (18.6, 12.6, 0), (19.4, 12, 0), (18.6, 12.6, 0), (18, 13, 0), (17.4, 13.6, 0)]
# Two keys of a bounce, to generate the frames between
BOUNCE = [(18, 13, 0), (16.5, 14.5, 6)]
HOP = [(21, 10, 0), (15, 16, 2), (16, 15, 6), (17, 14, 7.5), (15.5, 15.5, 4), (22, 9.5, 0)]


def on_magenta(frames, columns):
    """[frames] in a sheet on magenta, half-transparent pixels made solid like a sheet
    drawn that way would have them"""
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * S, rows * S), (255, 0, 255, 255))
    for i, frame in enumerate(frames):
        frame = frame.copy()
        px = frame.load()
        for y in range(S):
            for x in range(S):
                if 0 < px[x, y][3] < 255:
                    px[x, y] = (70, 62, 78, 255)
        sheet.paste(frame, (i % columns * S, i // columns * S), frame)
    return sheet.convert("RGB")


def main():
    out = Path(sys.argv[1])
    for folder in ("frames", "keys", "run_keys"):
        (out / folder).mkdir(parents=True, exist_ok=True)
    hop = [
        slime(w, h, lift, look=1 if 1 <= i <= 4 else 0) for i, (w, h, lift) in enumerate(HOP)
    ]
    idle = [slime(w, h, lift, blink=(i == 4)) for i, (w, h, lift) in enumerate(IDLE)]
    for i, frame in enumerate(hop):
        frame.save(out / "frames" / f"hop_{i}.png")
    for i, frame in enumerate(idle):
        frame.save(out / "frames" / f"idle_{i}.png")
    on_magenta(hop + idle, 6).save(out / "slime_sheet.png")
    for i, (w, h, lift) in enumerate(BOUNCE):
        # No shadow: it stays on the ground while the slime moves, which in-betweens can't tell
        frame = slime(w, h, lift, shadow=False)
        frame.save(out / "keys" / f"bounce_{i}.png")
        frame.save(out / "run_keys" / f"bounce_{i}.png")


if __name__ == "__main__":
    main()
