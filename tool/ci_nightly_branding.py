"""Recolour the existing launcher and tray artwork in a Nightly build checkout."""

import os
import sys
from pathlib import Path


ORANGE = (255, 122, 26)
PURPLE = (168, 120, 247)
TRAY = ("assets/tray/tray.ico", "assets/tray/tray.png")
ASSETS = {
    "windows": ("windows/runner/resources/app_icon.ico", *TRAY),
    "linux": ("linux/runner/riflay.png", "linux/runner/riflay.svg", *TRAY),
    "android": ("android/app/src/main/res/mipmap-*/ic_launcher*.png",),
    "macos": ("macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png", *TRAY),
    "ios": ("ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png",),
}


def recolour(image):
    rgba = image.convert("RGBA")

    def pixel(colour):
        red, green, blue, alpha = colour
        if not alpha or not red > green > blue or red - blue <= 8:
            return colour
        # Scale the change at antialiased edges by the orange's contribution.
        coverage = min(1.0, (red - blue) / (ORANGE[0] - ORANGE[2]))
        return (
            *(max(0, min(255, round(c + (new - old) * coverage)))
              for c, new, old in zip(colour, PURPLE, ORANGE)),
            alpha,
        )

    rgba.putdata([pixel(colour) for colour in rgba.get_flattened_data()])
    return rgba.convert("RGB") if image.mode == "RGB" else rgba


def write_icon(path, image_module):
    if path.suffix == ".svg":
        svg = path.read_bytes()
        path.write_bytes(svg.replace(b"#FF7A1A", b"#A878F7"))
        return
    with image_module.open(path) as source:
        if path.suffix == ".ico":
            sizes = sorted(source.ico.sizes(), reverse=True)
            primary, *others = [recolour(source.ico.getimage(size)) for size in sizes]
            options = {"format": "ICO", "sizes": sizes, "append_images": others}
        else:
            primary = recolour(source)
            options = {}
    primary.save(path, **options)


def main():
    if os.environ.get("RIFLAY_NIGHTLY") != "true":
        return
    platform = sys.argv[1]
    from PIL import Image

    root = Path(__file__).resolve().parent.parent
    for pattern in ASSETS[platform]:
        paths = list(root.glob(pattern))
        if not paths:
            raise FileNotFoundError(pattern)
        for path in paths:
            if "monochrome" not in path.name:
                write_icon(path, Image)


if __name__ == "__main__":
    main()
