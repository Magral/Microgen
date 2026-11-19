"""Bake neutral combat sprites. Their color, placement and timing are driven by effects_view.lua."""

from math import cos, pi, sin, tau
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "main"
OUT = ROOT / "art" / "combat"
SIZE = 192
SUPERSAMPLE = 3
SIDE = SIZE * SUPERSAMPLE
sprites = []


def pixel(point):
    return tuple(round((v + 0.5) * SIDE) for v in point)


def curve(image, points, width=0.012, opacity=210):
    vertices = list(map(pixel, points))
    for spread, alpha in ((3.3, opacity // 8), (1.8, opacity // 4), (1, opacity)):
        layer = Image.new("RGBA", (SIDE, SIDE))
        ImageDraw.Draw(layer).line(vertices, fill=(255, 255, 255, alpha),
                                   width=max(1, round(width * SIDE * spread)), joint="curve")
        image.alpha_composite(layer)


def fill(image, points, opacity):
    ImageDraw.Draw(image).polygon(list(map(pixel, points)), fill=(255, 255, 255, opacity))


def spot(image, center, radius, opacity):
    x, y = center
    layer = Image.new("RGBA", (SIDE, SIDE))
    ImageDraw.Draw(layer).ellipse((pixel((x - radius, y - radius)), pixel((x + radius, y + radius))),
                                  fill=(255, 255, 255, opacity))
    image.alpha_composite(layer)


def path(radius, start=0.0, sweep=tau, lobes=3, phase=0.0, texture=0.065, center=(0, 0)):
    points = []
    for i in range(121):
        a = start + sweep * i / 120
        r = radius * (1 + texture * sin(a * lobes + phase) + texture * 0.35 * sin(a * 5 - phase))
        points.append((center[0] + cos(a) * r, center[1] + sin(a) * r))
    return points


def ring(image, lobes=3, texture=0.065, phase=0.0):
    curve(image, path(0.44, lobes=lobes, texture=texture, phase=phase))


def field(image):
    points = path(0.44, texture=0.1)
    fill(image, points, 71)
    curve(image, points, 0.01, 100)


def arc(image):
    curve(image, path(0.44, -0.875, 1.75, phase=0.5), 0.014, 233)


def jaw(image):
    curve(image, path(0.44, -0.86, 1.72, phase=1.1), 0.026, 220)
    for i in range(3):
        a = -0.57 + i * 0.53
        curve(image, [(cos(a) * 0.44, sin(a) * 0.44),
                      (cos(a + 0.13) * 0.31, sin(a + 0.13) * 0.31)], 0.012, 201)


def thorn(image):
    ring(image, lobes=8, texture=0.09, phase=-pi / 2)
    for i in range(8):
        a = tau * i / 8
        curve(image, [(cos(a - 0.13) * 0.38, sin(a - 0.13) * 0.38),
                      (cos(a) * 0.48, sin(a) * 0.48),
                      (cos(a + 0.10) * 0.40, sin(a + 0.10) * 0.40)], 0.010, 196)


def corona(image):
    for i in range(4):
        curve(image, path(0.45, tau * i / 4 - 0.4, 0.8, lobes=4, phase=0.2), 0.019, 225)


def plume(image):
    curve(image, path(0.41, -1.5, pi * 1.54, texture=0.12), 0.027, 196)
    curve(image, path(0.22, -0.1, pi * 1.52, phase=0.4, center=(0.12, 0.07)), 0.018, 169)
    curve(image, path(0.11, 0.6, pi * 1.3, center=(0.10, 0.07)), 0.008, 137)


def petal(image):
    points = [(0.85 * (u - 0.5), sin(pi * u) * (0.64 + 0.13 * sin(tau * u))) for u in
              (i / 60 for i in range(61))]
    curve(image, [(x, y * 0.62) for x, y in points], 0.062, 213)


def thread(image, phase, electrical=False, hooked=False):
    if electrical:
        points = [(-0.425, 0)] + [
            (0.85 * (i / 16 - 0.5), sin(pi * i / 16) *
             (0.24 * sin(i * 2.21 + phase) + 0.06 * sin(i * 0.98))) for i in range(1, 16)
        ] + [(0.425, 0)]
    else:
        points = [(0.85 * (u - 0.5), sin(pi * u) * sin(u * 7 + phase) * 0.34) for u in
                  (i / 60 for i in range(61))]
    curve(image, points, 0.085 if electrical else 0.13, 240)
    if hooked:
        curve(image, [(0.425, 0), (0.27, -0.23), (0.19, -0.19)], 0.12, 230)


def vessel(image):
    for i in range(3):
        a = i * tau / 3 + 0.14
        local = [(0, 0), (0.19, -0.025), (0.28, 0.045), (0.42, 0.01)]
        branch = [(0.19, -0.025), (0.27, -0.13), (0.35, -0.155)]
        def rotate(points):
            return [(x * cos(a) - y * sin(a), x * sin(a) + y * cos(a)) for x, y in points]
        curve(image, rotate(local), 0.015)
        curve(image, rotate(branch), 0.008, 165)
        spot(image, rotate(local)[-1], 0.038, 204)
        spot(image, rotate(branch)[-1], 0.023, 157)


def shard(image, variant):
    rim = []
    for i in range(31):
        a = -0.43 + 0.86 * i / 30
        r = 0.695 + 0.038 * sin(i * 0.8 + variant * 1.9) + 0.017 * cos(i * 1.87)
        rim.append((cos(a) * r - 0.38, sin(a) * r))
    points = [(-0.32, 0), *rim, (-0.32, 0)]
    fill(image, points, 100)
    curve(image, points, 0.012, 250)
    for i in (4, 11, 20, 27):
        x, y = rim[i]
        curve(image, [(-0.14, 0), (x * 0.19, y * 0.55), (x - 0.037, y * 0.94)], 0.005, 95)


def reward(image):
    for i in range(5):
        a = i * tau / 5
        x, y = cos(a) * 0.245, sin(a) * 0.245
        petals = path(0.154, a, lobes=3, phase=i, center=(x, y))
        fill(image, petals, 102)
        curve(image, petals, 0.013, 219)
        spot(image, (x, y), 0.055, 207)
    spot(image, (0, 0), 0.12, 190)
    spot(image, (0.025, -0.025), 0.064, 252)
    curve(image, path(0.454, texture=0.04), 0.006, 148)


def beam(image):
    curve(image, [(-0.45, 0), (0.45, 0)], 0.17, 235)


def projectile(image):
    curve(image, [(-0.42, 0), (-0.22, 0.019), (0.27, 0)], 0.13, 168)
    spot(image, (0.307, 0.0), 0.151, 120)
    spot(image, (0.307, 0.0), 0.087, 251)


def bake(name, draw, *args, aspect=1):
    image = Image.new("RGBA", (SIDE, SIDE))
    draw(image, *args)
    image = image.resize((SIZE, round(SIZE * aspect)), Image.Resampling.LANCZOS)
    image.save(OUT / f"{name}.png", optimize=True)
    sprites.append(name)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    bake("ring", ring)
    bake("membrane", ring, 5, 0.075, 1.8)
    bake("skin", field)
    bake("arc", arc)
    bake("jaw", jaw)
    bake("thorn", thorn)
    bake("corona", corona)
    bake("plume", plume)
    bake("petal", petal, aspect=0.33)
    bake("vessel", vessel)
    for i in range(3):
        bake(f"thread_{i}", thread, i * tau / 3, aspect=0.25)
        bake(f"bolt_{i}", thread, i * tau / 3, True, aspect=0.25)
        bake(f"shard_{i}", shard, i)
    bake("barb", thread, 1.2, False, True, aspect=0.25)
    bake("reward", reward)
    bake("beam", beam, aspect=0.125)
    bake("projectile", projectile, aspect=0.33)
    atlas = ['images { image: "/main/art/combat/%s.png" }' % name for name in sprites]
    (ROOT / "combat.atlas").write_text("\n".join([*atlas, "margin: 2", "extrude_borders: 2", "inner_padding: 2", ""]))


if __name__ == "__main__":
    main()
