"""Pack Godot's full-detail wall variants and a seamless water surface."""
from pathlib import Path
import argparse

import numpy as np
from PIL import Image

ART = Path(__file__).resolve().parents[1] / "main" / "art"
SIDE = 1024
BLEND = 256


def pack(source):
    for path in sorted(source.glob("wall_*.png")):
        rgba = np.asarray(Image.open(path).convert("RGBA")).copy()
        alpha = rgba[..., 3:]
        colors = np.zeros_like(rgba[..., :3], dtype=np.float32)
        np.divide(rgba[..., :3].astype(np.float32) * 255, alpha,
                  out=colors, where=alpha > 0)
        rgba[..., :3] = np.clip(colors, 0, 255).astype(np.uint8)
        Image.fromarray(rgba).save(ART / path.name, optimize=True)

    raw = np.asarray(Image.open(source / "fluid.png").convert("RGB"), dtype=np.float32)
    # Blend the overlapping 256 pixels into the repeated region in both axes.
    t = np.linspace(0, 1, BLEND, dtype=np.float32)
    weight = t*t*(3-2*t)
    horizontal = raw[:, :SIDE].copy()
    horizontal[:, :BLEND] = (raw[:, SIDE:]*(1-weight[None, :, None])
                            +raw[:, :BLEND]*weight[None, :, None])
    seamless = horizontal[:SIDE].copy()
    seamless[:BLEND] = (horizontal[SIDE:]*(1-weight[:, None, None])
                       +horizontal[:BLEND]*weight[:, None, None])
    Image.fromarray(np.uint8(np.clip(seamless, 0, 255))).save(ART/"fluid.png", optimize=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    pack(parser.parse_args().source)
