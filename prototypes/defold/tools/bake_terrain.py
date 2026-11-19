"""Pack the original Godot terrain and fluid optical lookup into Defold atlases."""
from pathlib import Path
import argparse

import numpy as np
from PIL import Image

MAIN = Path(__file__).resolve().parents[1] / "main"
ART = MAIN / "art"


def texture_water(source):
    """Add softly scattered micro-debris to the blue channel of the flow map."""
    rgb = np.asarray(source.convert("RGB")).copy()
    height, width = rgb.shape[:2]
    rng = np.random.default_rng(414)
    sediment = np.zeros((height, width), dtype=np.float32)
    offsets = np.arange(-4, 5)
    x, y = np.meshgrid(offsets, offsets)
    for _ in range(460):
        cx, cy = rng.integers(0, (width, height))
        angle = rng.uniform(0, np.pi)
        u = x * np.cos(angle) + y * np.sin(angle)
        v = -x * np.sin(angle) + y * np.cos(angle)
        grain = rng.uniform(.20, .82) * np.exp(-(u / rng.uniform(1, 2.8))**2 - (v / .65)**2)
        patch = np.ix_((cy + offsets) % height, (cx + offsets) % width)
        sediment[patch] = np.maximum(sediment[patch], grain)
    rgb[..., 2] = np.rint(np.clip(rgb[..., 2] * .43 + sediment * 255 * .67, 0, 255)).astype(np.uint8)
    return Image.fromarray(rgb)


def pack(source):
    names = []
    for kind in ("bed", "bed_fibril", "fibril", "wall"):
        for biome in range(2):
            for variant in range(4):
                name = f"{kind}_{biome}_{variant}"
                rgba = np.asarray(Image.open(source / f"{name}.png").convert("RGBA")).copy()
                alpha = rgba[..., 3:]
                colors = np.zeros_like(rgba[..., :3], dtype=np.float32)
                np.divide(rgba[..., :3].astype(np.float32) * 255, alpha,
                          out=colors, where=alpha > 0)
                rgba[..., :3] = np.clip(colors, 0, 255).astype(np.uint8)
                Image.fromarray(rgba).save(ART / f"{name}.png", optimize=True)
                names.append(name)
    (MAIN / "terrain.atlas").write_text(
        "".join(f'images {{ image: "/main/art/{name}.png" }}\n' for name in names)
        + "margin: 2\nextrude_borders: 2\ninner_padding: 0\n"
    )
    # Exactly one 256x256 image with no padding so the GPU can repeat it.
    flow_path = ART / "liquid_flow.png"
    texture_water(Image.open(source / flow_path.name)).save(flow_path, optimize=True)
    (MAIN / "liquid.atlas").write_text('images { image: "/main/art/liquid_flow.png" }\n')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    pack(parser.parse_args().source)
