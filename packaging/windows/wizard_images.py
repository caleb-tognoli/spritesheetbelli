"""Draws the installer's wizard images from the app's splash, at every size Inno Setup
picks from for the screen's scaling: the side image of the last page and the corner
image of the others.

Usage: wizard_images.py <output folder>
"""

import os
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
# The splash screen's background, see boot_splash/bg_color in project.godot
BACKGROUND = (27, 28, 31)
# Sizes for 100% to 250% scaling, as the Inno Setup documentation lists them
SIDE_SIZES = [(164, 314), (192, 386), (246, 459), (273, 556), (328, 604), (383, 722), (410, 797)]
CORNER_SIZES = [(55, 55), (64, 68), (69, 69), (83, 80), (92, 97), (110, 106), (119, 123), (138, 140)]


def main(out: str) -> None:
    os.makedirs(out, exist_ok=True)
    icon = Image.open(os.path.join(ROOT, "assets", "branding", "splash.png")).convert("RGBA")
    for width, height in SIDE_SIZES:
        side = Image.new("RGBA", (width, height), BACKGROUND + (255,))
        size = round(width * 0.6)
        shown = icon.resize((size, size), Image.LANCZOS)
        side.alpha_composite(shown, ((width - size) // 2, round(height * 0.3 - size / 2)))
        side.convert("RGB").save(os.path.join(out, "side-%d.bmp" % width))
    for width, height in CORNER_SIZES:
        corner = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        size = min(width, height)
        shown = icon.resize((size, size), Image.LANCZOS)
        corner.alpha_composite(shown, ((width - size) // 2, (height - size) // 2))
        corner.save(os.path.join(out, "corner-%d.bmp" % width))


if __name__ == "__main__":
    main(sys.argv[1])
