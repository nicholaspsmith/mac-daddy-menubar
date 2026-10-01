#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

"""Build Mac Daddy's menu-bar art from the mascot and its two Gemini edits.

Inputs (this folder):
  source.png        the approved mascot (widgets.nicksmith.software art/raw/mac-daddy.png)
  asleep-raw.png    Gemini edit of source: eyes closed (only its eyes are used)
  hattip-raw3.png   Gemini edit of source: hat lifted and tipped
Outputs (../Resources/bundle/), each at 1x and @2x for a 24x22pt canvas:
  macdaddy-base, macdaddy-asleep, macdaddy-hattip      the art
  macdaddy-hat-mask, macdaddy-hattip-hat-mask          the purple hat (band + feather excluded)
plus debug/ previews. Needs Pillow + numpy.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "Resources" / "bundle"
DEBUG = HERE / "debug"
CANVAS = (24, 22)          # points
ART_H = 22.0               # the art's height inside the canvas, points


def load(name):
    return Image.open(HERE / name).convert("RGB")


def features(img):
    """Iris centres (left, right) and the medallion centre, for aligning the edits."""
    a = np.asarray(img).astype(float) / 255
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    H, W = r.shape
    yy, xx = np.mgrid[0:H, 0:W]
    blue = (b > r + 0.15) & (b > g + 0.02) & (b > 0.4) & (yy > 400) & (yy < 650)
    gold = (r > 0.85) & (g > 0.65) & (b < 0.35) & (yy > 800)
    pts = []
    for half in (xx < W / 2, xx >= W / 2):
        m = blue & half
        pts.append((xx[m].mean(), yy[m].mean()))
    pts.append((xx[gold].mean(), yy[gold].mean()))
    return np.array(pts)


def align(img, ref_pts):
    """Uniform scale + translation that maps img's features onto ref_pts."""
    p = features(img)
    pc, rc = p.mean(0), ref_pts.mean(0)
    s = np.sum((p - pc) * (ref_pts - rc)) / np.sum((p - pc) ** 2)
    t = rc - s * pc
    # PIL's affine maps output -> input: x_in = (x_out - t) / s
    return img.transform(img.size, Image.AFFINE, (1 / s, 0, -t[0] / s, 0, 1 / s, -t[1] / s),
                         resample=Image.BICUBIC, fillcolor=(255, 255, 255)), s, t


def cutout(img, tolerance=60):
    """White background -> transparent by flood fill from the corners."""
    im = img.convert("RGBA")
    w, h = im.size
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        if im.getpixel(seed)[3] != 0:
            ImageDraw.floodfill(im, seed, (255, 255, 255, 0), thresh=tolerance)
    # Soften the cut a touch so the outline's anti-aliasing survives.
    a = im.getchannel("A").filter(ImageFilter.GaussianBlur(1.2))
    im.putalpha(a)
    return im


def hat_mask(img):
    """The purple of the crown and brim: hue in the violet band, some saturation.
    Excludes the gold band, the pink feather and the black outline."""
    hsv = np.asarray(img.convert("HSV")).astype(float)
    h, s, v = hsv[..., 0] * 360 / 255, hsv[..., 1] / 255, hsv[..., 2] / 255
    m = (h > 235) & (h < 300) & (s > 0.18) & (v > 0.18)
    mask = Image.fromarray((m * 255).astype(np.uint8))
    # Close pinholes (shading speckle), drop specks.
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    # Reach a few pixels into the outline so the recolour has no purple fringe.
    mask = mask.filter(ImageFilter.MaxFilter(5))
    return mask


def fit(img, box, px_scale, resample=Image.LANCZOS, sharpen=True):
    """Crop `box` and place it centred in the canvas at px_scale pixels per point."""
    W, H = CANVAS[0] * px_scale, CANVAS[1] * px_scale
    crop = img.crop(box)
    h = round(ART_H * px_scale)
    w = round(crop.width * h / crop.height)
    small = crop.resize((w, h), resample)
    if sharpen and img.mode != "L":
        small = small.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=1))
    mode = img.mode
    canvas = Image.new(mode, (W, H), 0 if mode == "L" else (0, 0, 0, 0))
    canvas.paste(small, ((W - w) // 2, (H - h) // 2))
    return canvas, ((W - w) // 2, (H - h) // 2, w / crop.width)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    DEBUG.mkdir(exist_ok=True)
    base = load("source.png")
    ref = features(base)

    # Asleep: the original with only the eye band taken from the edit, feathered.
    asleep_edit = load("asleep-raw.png")
    band = Image.new("L", base.size, 0)
    ImageDraw.Draw(band).rounded_rectangle((300, 395, 724, 585), radius=60, fill=255)
    band = band.filter(ImageFilter.GaussianBlur(12))
    asleep = Image.composite(asleep_edit, base, band)

    hattip, s, t = align(load("hattip-raw3.png"), ref)
    print(f"hat-tip aligned: scale {s:.4f}, shift ({t[0]:.1f}, {t[1]:.1f})")

    cut = {"base": cutout(base), "asleep": cutout(asleep), "hattip": cutout(hattip)}
    masks = {"hat-mask": hat_mask(base), "hattip-hat-mask": hat_mask(hattip)}
    for k in masks:  # never outside the figure
        masks[k] = Image.fromarray(np.minimum(np.asarray(masks[k]),
                                              np.asarray(cut["hattip" if "hattip" in k else "base"].getchannel("A"))))

    # One crop for every state so the face never moves; pad to the canvas aspect.
    boxes = [im.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox() for im in cut.values()]
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    box = (x0, y0, x1, y1)
    print("crop box", box, "size", (x1 - x0, y1 - y0))

    for scale, suffix in ((1, ""), (2, "@2x")):
        for name, im in cut.items():
            out, (ox, oy, k) = fit(im, box, scale)
            out.save(OUT / f"macdaddy-{name}{suffix}.png", optimize=True)
        for name, m in masks.items():
            out, _ = fit(m, box, scale, resample=Image.BOX, sharpen=False)
            out.save(OUT / f"macdaddy-{name}{suffix}.png", optimize=True)

    # Feature positions in canvas points (y up, AppKit), for the code overlays.
    _, (ox, oy, k) = fit(cut["base"], box, 8)
    def pt(x, y):
        return round((ox + (x - x0) * k) / 8, 2), round(CANVAS[1] - (oy + (y - y0) * k) / 8, 2)
    print("eyes", pt(*ref[0]), pt(*ref[1]), "medallion", pt(*ref[2]))
    print("left temple", pt(300, 560), "right temple", pt(724, 560), "hat crown top-left", pt(330, 150))

    # Debug: mask over the art.
    for name, src in (("hat-mask", base), ("hattip-hat-mask", hattip)):
        red = Image.new("RGB", src.size, (255, 0, 0))
        Image.composite(red, src, masks[name].point(lambda a: a * 6 // 10)).resize((512, 512)).save(DEBUG / f"{name}-overlay.png")


if __name__ == "__main__":
    main()
