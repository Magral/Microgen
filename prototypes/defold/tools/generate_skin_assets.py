"""Generate compact, nine-slice friendly Microgen UI surfaces."""

from pathlib import Path
from PIL import Image, ImageDraw


OUT = Path(__file__).resolve().parents[1] / "main" / "ui_skin"
SIZE = 96
SCALE = 3

PALETTES = {
    "panel": ((7, 22, 32), (12, 35, 46), (53, 104, 115), (90, 211, 189)),
    "card": ((10, 30, 41), (16, 48, 60), (61, 119, 126), (112, 223, 195)),
    "button": ((14, 43, 54), (23, 60, 70), (73, 133, 141), (137, 226, 204)),
    "primary": ((74, 195, 164), (107, 224, 192), (168, 255, 223), (224, 255, 242)),
    "disabled": ((17, 34, 43), (23, 43, 51), (51, 77, 84), (76, 106, 110)),
}


def generate(name, colors):
    size = SIZE * SCALE
    inner = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((1, 1, size - 2, size - 2), radius=17 * SCALE, fill=255)
    pixels = inner.load()
    top, bottom, border, glow = colors
    for y in range(size):
        t = y / (size - 1)
        for x in range(size):
            lift = max(0.0, 1.0 - x / size) * 2.0
            rgb = tuple(round(top[c] * (1 - t) + bottom[c] * t + lift) for c in range(3))
            pixels[x, y] = (*rgb, mask.getpixel((x, y)))

    draw = ImageDraw.Draw(inner)
    pad = 2 * SCALE
    draw.rounded_rectangle((pad, pad, size - pad - 1, size - pad - 1),
        radius=15 * SCALE, outline=(*border, 235), width=1 * SCALE)
    draw.rounded_rectangle((4 * SCALE, 4 * SCALE, size - 4 * SCALE - 1, size - 4 * SCALE - 1),
        radius=12 * SCALE, outline=(*glow, 54), width=1 * SCALE)
    # A fine upper rim catches light while the side and lower edges stay deep.
    draw.line((18 * SCALE, 2 * SCALE, size - 18 * SCALE, 2 * SCALE),
        fill=(*glow, 145 if name != "disabled" else 65), width=1 * SCALE)
    # Soft membrane glints at the upper corners, outside the nine-slice center.
    draw.arc((7 * SCALE, 5 * SCALE, 35 * SCALE, 33 * SCALE), 185, 265,
        fill=(*glow, 62), width=1 * SCALE)
    draw.arc((size - 35 * SCALE, 5 * SCALE, size - 7 * SCALE, 33 * SCALE), 275, 355,
        fill=(*glow, 54), width=1 * SCALE)
    image = inner.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    image.save(OUT / f"{name}.png", optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, colors in PALETTES.items():
        generate(name, colors)


if __name__ == "__main__":
    main()
