"""Puts together the README images screenshots.gd can't take on its own: the in-betweens
GIF from the animation it saved, and the reload dialog over the main window.

Usage: python _dev/readme/compose.py <input folder>
"""
import glob
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

DOCS = Path(__file__).resolve().parents[2] / "docs"
FONTS = Path("C:/Windows/Fonts")
BG = (38, 40, 45, 255)


def gif(run_dir, scale=8, tick=80):
    """The keys played as drawn, next to the keys with the frames generated after each,
    every frame shown for a [tick]"""
    files = sorted(glob.glob(str(run_dir / "*.png")))

    def big(f):
        img = Image.open(f).convert("RGBA")
        return img.resize((img.width * scale, img.height * scale), Image.NEAREST)

    drawn, filled, keys = [], [], []
    for f in files:
        if f.endswith("_key.png"):
            keys.append(big(f))
        drawn.append(keys[-1])
        filled.append(big(f))
    generated = len(filled) - len(keys)
    w, h = keys[0].size
    pad = 24
    title = ImageFont.truetype(str(FONTS / "seguisb.ttf"), 17)
    small = ImageFont.truetype(str(FONTS / "segoeui.ttf"), 14)
    out = []
    for t in range(len(drawn)):
        c = Image.new("RGBA", (w * 2 + pad * 3, h + 72), BG)
        d = ImageDraw.Draw(c)
        c.alpha_composite(drawn[t], (pad, 40))
        c.alpha_composite(filled[t], (pad * 2 + w, 40))
        for x, text, sub in (
            (pad, "Drawn", f"{len(keys)} frames"),
            (pad * 2 + w, "With in-betweens", f"{len(keys)} drawn + {generated} generated"),
        ):
            d.text((x + w / 2, 12), text, font=title, fill=(230, 230, 235), anchor="mt")
            d.text((x + w / 2, h + 48), sub, font=small, fill=(150, 152, 160), anchor="mt")
        out.append(c.convert("RGB").quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE))
    out[0].save(DOCS / "inbetweens.gif", save_all=True, append_images=out[1:], duration=tick, loop=0)


def over_main(dialog_file, main_file, out_file):
    main = Image.open(DOCS / main_file).convert("RGBA")
    dialog = Image.open(dialog_file).convert("RGBA")
    dim = Image.new("RGBA", main.size, (0, 0, 0, 90))
    main.alpha_composite(dim)
    x = (main.width - dialog.width) // 2
    y = (main.height - dialog.height) // 2
    shadow = Image.new("RGBA", main.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle(
        (x - 4, y + 2, x + dialog.width + 4, y + dialog.height + 10), fill=(0, 0, 0, 150)
    )
    main.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(12)))
    ImageDraw.Draw(main).rectangle(
        (x - 1, y - 1, x + dialog.width, y + dialog.height), outline=(80, 84, 92, 255)
    )
    main.alpha_composite(dialog, (x, y))
    main.convert("RGB").save(DOCS / out_file)


def with_before(window_file, sheet_file, out_file):
    """The Add Spritesheet window with the sheet as drawn, on magenta, in a corner"""
    window = Image.open(window_file).convert("RGBA")
    sheet = Image.open(sheet_file).convert("RGBA")
    sheet = sheet.resize((sheet.width * 3 // 2, sheet.height * 3 // 2), Image.NEAREST)
    small = ImageFont.truetype(str(FONTS / "segoeui.ttf"), 13)
    x, y = 24, 98
    d = ImageDraw.Draw(window)
    d.rectangle((x - 9, y - 30, x + sheet.width + 8, y + sheet.height + 8), fill=BG, outline=(80, 84, 92))
    d.text((x, y - 24), "The file, as drawn", font=small, fill=(170, 172, 180))
    window.alpha_composite(sheet, (x, y))
    window.convert("RGB").save(DOCS / out_file)


def main():
    input_dir = Path(sys.argv[1])
    gif(input_dir / "run_out")
    over_main(input_dir / "reload-dialog.png", "screenshot.png", "reload.png")
    with_before(input_dir / "cut-window.png", input_dir / "slime_sheet.png", "cut.png")


if __name__ == "__main__":
    main()
