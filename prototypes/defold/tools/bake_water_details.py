"""Bake fixed-resolution blurred particles and swimming wake sprites."""
from pathlib import Path

import numpy as np
from PIL import Image

MAIN = Path(__file__).resolve().parents[1] / "main"


def build():
    axes = np.linspace(-1, 1, 128, dtype=np.float32)
    x, y = np.meshgrid(axes, axes)
    radius = np.hypot(x, y)
    angle = np.arctan2(y, x)
    envelope = np.clip((.28 - x) * 4, 0, 1)
    irregular = np.clip(.76 + .24 * np.cos(3 * angle + .1), 0, 1)
    alpha = {
        "haze": np.interp(radius, [0, .20, .50, .80, 1.0], [.80, .68, .30, .045, 0]),
        "wake": envelope * np.exp(-np.square((radius - .72) / .025)),
        "far_body": np.clip((.77 + .08 * np.cos(3 * angle) + .045 * np.sin(5 * angle) - radius) * 10, 0, 1)
                    * irregular,
    }
    for key, opacity in alpha.items():
        rgba = np.full((128, 128, 4), 255, dtype=np.uint8)
        rgba[:, :, 3] = (np.clip(opacity, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(rgba).save(MAIN / "art" / f"water_{key}.png", optimize=True)
    (MAIN / "water_details.atlas").write_text(
        "".join(f'images {{ image: "/main/art/water_{name}.png" }}\n' for name in alpha)
        + "margin: 2\nextrude_borders: 2\ninner_padding: 0\n"
    )


if __name__ == "__main__":
    build()
