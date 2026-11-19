"""Bake original cellular artwork in source space. Run from any directory."""
import json
import math
from pathlib import Path
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

MAIN = Path(__file__).resolve().parents[1] / "main"
ART = MAIN / "art"
ART.mkdir(exist_ok=True)
FIXTURE = json.loads((MAIN / "arena.json").read_text())
SEED = FIXTURE["seed"]


def save(image, name, colors=256):
    method = Image.Quantize.FASTOCTREE if image.mode == "RGBA" else Image.Quantize.MEDIANCUT
    image.quantize(colors=colors, method=method).save(ART / f"{name}.png", optimize=True)


def membrane(name, size, seed, tint, lobes, shell=False):
    rng = random.Random(seed)
    out = Image.new("RGBA", (size,size))
    alpha = Image.new("L",(size,size))
    points = []
    for i in range(160):
        a = i * math.tau / 160
        r = size*.378 * (1 + .10 * math.cos(lobes*a + seed) + .045*math.sin(7*a))
        points.append((size/2+math.cos(a)*r, size/2+math.sin(a)*r*.94))
    ImageDraw.Draw(alpha).polygon(points, fill=255)
    x,y = np.meshgrid(np.linspace(-1,1,size),np.linspace(-1,1,size))
    dist = np.sqrt(x*x + y*y)
    gleam = np.exp(-((x+.27)**2 + (y+.35)**2)*7.5)
    bands = .025 * np.sin(x*35+y*14 + np.sin(y*15))
    light = np.clip(.53 + .46*gleam + .28*(1-dist) + bands, .38, 1.2)
    rgb = np.zeros((size,size,4),dtype=np.uint8)
    for ix,color in enumerate(tint):
        rgb[:,:,ix] = np.clip(color*light + 51*gleam,0,255)
    rgb[:,:,3] = np.asarray(alpha)*(1 if shell else .94)
    out = Image.fromarray(rgb)
    overlay = Image.new("RGBA",out.size)
    draw = ImageDraw.Draw(overlay)
    draw.line(points+[points[0]], fill=(*tint,130 if shell else 220),width=max(2,size//80),joint="curve")
    draw.line(points[82:129],fill=(205,255,240,145),width=max(2,size//52),joint="curve")
    if not shell:
        for i in range(4):
            offset=(i-1.5)*size*.085
            coords=[(size*.29+j*size*.017,size*.55 + offset + math.sin(j*.26+i)*size*.036) for j in range(25)]
            draw.line(coords,fill=(165,255,217,55),width=max(1,size//145))
        for i in range(28):
            a=rng.random()*math.tau
            r=(rng.random()**.55)*size*.30
            px=size*.5+math.cos(a)*r;py=size*.50+math.sin(a)*r
            rr=rng.uniform(.008,.018)*size
            draw.ellipse((px-rr,py-rr,px+rr,py+rr), fill=(215,255,236,rng.randrange(18,94)))
        for i in range(4):
            rr=size*(.115-i*.016)
            cx,cy=size*.46,size*.48
            draw.ellipse((cx-rr,cy-rr,cx+rr,cy+rr),fill=(26+i*11,54+i*14,75+i*15,170))
        draw.ellipse((size*.425,size*.43,size*.47,size*.47),fill=(178,251,225,178))
    else:
        for i in range(18):
            a=rng.random()*math.tau;r=rng.random()**.5*size*.31
            px=size*.5+math.cos(a)*r;py=size*.5+math.sin(a)*r
            draw.ellipse((px-2,py-2,px+2,py+2),fill=(4,23,29,95))
    out.alpha_composite(overlay)
    if name:
        save(out,name)
    return out


def waves(name, lobes, partial=False):
    size=256
    layer=Image.new('RGBA',(size,size))
    for width,alpha in [(14,24),(8,54),(3,222)]:
        pattern=Image.new("RGBA",layer.size)
        coords=[]
        for i in range(161):
            a=math.tau*i/160*(.78 if partial else 1)
            r=104*(1+.090*math.cos(lobes*a))
            coords.append((128+r*math.cos(a),128+r*math.sin(a)))
        ImageDraw.Draw(pattern).line(coords,fill=(227,255,244,alpha),width=width,joint="curve")
        layer.alpha_composite(pattern)
    save(layer,name)


def terrain():
    w,h=1845,810
    x,y = np.meshgrid(np.linspace(0,1,w),np.linspace(0,1,h))
    r = (np.sin(x*18 + y*7 + .50*np.sin(y*18)) + np.cos(y*21 - x*15 + .55*np.sin(x*20)))
    fibers = np.exp(-np.abs(r-.82)*13)*.13
    light = .28 + .27*(1-y) + .16*np.exp(-((x-.40)**2+(y-.3)**2)*3)+fibers
    warm=np.clip((x+.1*np.sin(y*4)-.35)*2.6,0,1)
    rgb=np.stack([7+15*light+14*warm,21+37*light+8*warm,33+47*light-17*warm],axis=2)
    out=Image.fromarray(rgb.astype(np.uint8)).convert("RGBA")
    draw=ImageDraw.Draw(out)
    rng=random.Random(SEED)
    for i in range(460):
        px,py=rng.randrange(w),rng.randrange(h)
        size=rng.choice((1,1,2,3))
        draw.ellipse((px,py,px+size*2,py+size),fill=(27,70+rng.randrange(19),78,255))
    cold=membrane(None,176,8,(75,141,153),5,True)
    warm=membrane(None,176,6,(109,146,104),6,True)
    for wall in sorted(FIXTURE["walls"],key=lambda value:value["pos"][1]):
        px,py=(round(q*.75) for q in wall["pos"])
        sprite=(warm if wall["warm"] else cold).rotate(math.degrees(wall["phase"]),Image.Resampling.BICUBIC)
        shadow=Image.new("RGBA",sprite.size,(1,8,12,0))
        shadow.putalpha(sprite.getchannel("A").filter(ImageFilter.GaussianBlur(5)).point(lambda value:value//2))
        out.alpha_composite(shadow,(px-86,py-76))
        out.alpha_composite(sprite,(px-88,py-88))
    save(out.convert("RGB"),"terrain")


terrain()
membrane("player",320,11,(72,209,175),3)
membrane("hunter",192,12,(237,105,124),5)
membrane("prey",144,18,(188,218,108),4)
membrane("spitter",180,6,(135,116,223),5)
membrane("boss",420,2,(235,154,93),6)
waves("field",5)
waves("shield",4)
waves("surge",7,True)
speck=Image.new("RGBA",(48,48))
d=ImageDraw.Draw(speck)
d.ellipse((4,4,44,44),fill=(92,209,188,65))
d.ellipse((12,12,36,36),fill=(98,228,189,122))
d.ellipse((19,19,29,29),fill=(206,255,223,238))
save(speck,"speck")

(ROOT := MAIN / "world.atlas").write_text('images { image: "/main/art/terrain.png" }\nextrude_borders: 2\n')
names = ("player","hunter","prey","spitter","boss","field","shield","surge","speck")
(MAIN / "cells.atlas").write_text(
    "".join(f'images {{ image: "/main/art/{name}.png" }}\n' for name in names)
    + "margin: 2\nextrude_borders: 2\ninner_padding: 2\n"
)
