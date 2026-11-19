"""Pack the 1.4.1 DNA, resource and cyst forms for the world and reward UI."""
from pathlib import Path
from math import cos, pi, sin

from PIL import Image, ImageDraw

MAIN = Path(__file__).resolve().parents[1] / "main"
ART = MAIN / "art" / "collectibles"
SIDE = 128
ART.mkdir(exist_ok=True)
PALETTE = ((98, 242, 238), (194, 138, 255), (255, 219, 114))


def ellipse(draw, x, y, r, rgba):
    draw.ellipse((x-r, y-r, x+r, y+r), fill=rgba)


def rect_corners(x, y, r):
    return (x-r, y-r, x+r, y+r)


def cyst(tier):
    image = Image.new("RGBA", (SIDE, SIDE))
    draw = ImageDraw.Draw(image)
    center = SIDE / 2
    color = PALETTE[tier - 1]
    ellipse(draw, center, center, 55, (*color, 13))
    points = []
    for i in range(48):
        a = i * pi / 24
        modifier = (.22*cos(a*2)+.08*sin(a*3), .23*cos(a*3), .20*cos(a*6))[tier-1]
        r = 37*(1+modifier)
        points.append((cos(a)*r, sin(a)*r))
    for scale, alpha, weight in ((1,240,4), (.75,84,3)):
        coords = [(center+x*scale, center+y*scale) for x, y in points]
        if scale == 1:
            draw.polygon(coords, fill=(*color, 56))
        draw.line(coords+[coords[0]], fill=(*color,alpha), width=weight, joint="curve")
    ellipse(draw, center+4, center+2, 15, (*(int(x*.60) for x in color), 230))
    ellipse(draw, center+4, center+2, 10, (*color, 228))
    draw.arc(rect_corners(center+4,center+2,17),190,320,fill=(241,255,239,192),width=3)
    for i in range(tier+1):
        a=i*2*pi/(tier+1)
        ellipse(draw,center+cos(a)*24,center+sin(a)*24,3,(*color,216))
    return image


def pickup(kind):
    image = Image.new("RGBA", (SIDE, SIDE))
    draw = ImageDraw.Draw(image)
    half = SIDE//2
    if kind == "dna":
        draw.line((42,31,85,96), fill=(135,238,210,255), width=9)
        draw.line((85,31,42,96), fill=(135,238,210,170), width=9)
        for y in [42,85]:
            draw.line((42,y,85,y),fill=(135,238,210,255),width=5)
    elif kind == "core":
        ellipse(draw,half,half,54,(199,148,242,30))
        draw.polygon([(64,18),(105,63),(64,110),(23,63)],fill=(199,148,242,241))
        draw.polygon([(64,23),(93,63),(65,80),(40,63)],fill=(230,195,255,155))
    elif kind == "bio":
        ellipse(draw,half,half,48,(236,193,133,26))
        ellipse(draw,half,half,26,(236,193,133,243))
    else:
        color = {"heal":(107,255,184), "body_extension":(152,242,211),
                 "stock_extension":(197,177,255)}[kind]
        ellipse(draw,half,half,53,(*color,36))
        points=[]
        for i in range(36):
            angle=i*pi/18
            r=33*(1+.12*cos(angle*5))
            points.append((half+r*cos(angle),half+r*sin(angle)))
        draw.polygon(points,fill=(*color,205))
        light=(225,255,240,237)
        if kind=="heal":
            draw.line((52,64,76,64),fill=light,width=6)
            draw.line((64,52,64,76),fill=light,width=6)
        else:
            ellipse(draw,51,64,6,light)
            ellipse(draw,77,64,6,light)
    return image


def build():
    names = ["dna", "core", "bio", "heal", "body_extension", "stock_extension"]
    entries = [(name,pickup(name)) for name in names]
    for tier in range(1,4):
        image = cyst(tier)
        entries.append((f"cyst_{tier}", image))
        for side, bounds in (("left",(0,0,SIDE//2,SIDE)), ("right",(SIDE//2,0,SIDE,SIDE))):
            half = Image.new("RGBA", (SIDE//2, SIDE))
            half.paste(image.crop(bounds), (0,0))
            entries.append((f"cyst_{tier}_{side}", half))
    for name,image in entries:
        image.save(ART/f"{name}.png",optimize=True)
    (MAIN/"collectibles.atlas").write_text(
        "".join(f'images {{ image: "/main/art/collectibles/{name}.png" }}\n' for name,_ in entries)
        +"margin: 2\nextrude_borders: 2\ninner_padding: 0\n"
    )


if __name__=="__main__":
    build()
