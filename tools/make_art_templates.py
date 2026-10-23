#!/usr/bin/env python3
"""Draws guide templates for Fenlight art (see docs/ART_SPEC.md).

Each PNG is a guide layer: import it into Procreate (or Figma) as the bottom layer, lock it, draw on
layers above, and hide it before exporting. Run from the repo root:

    python3 tools/make_art_templates.py

Writes art/templates/2x/ (the sizes in ART_SPEC.md) and art/templates/3x/ (1.5 times larger).
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

GRID = (90, 200, 255, 70)        # faint 2:1 grid
FOOT = (90, 200, 255, 60)        # footprint fill
EDGE = (0, 150, 255, 255)        # footprint outline
SUB = (0, 150, 255, 140)         # tile lines inside a footprint
WALL = (255, 80, 160, 200)       # vertical guides up from the corners
ANCHOR = (255, 60, 60, 255)
FIGURE = (40, 40, 40, 110)       # scale figure
TEXT = (30, 30, 30, 255)


def font(size):
    return ImageFont.load_default(size=size)


def diamond(cx, top, w, h):
    """Points of a 2:1 diamond whose top corner is at (cx, top)."""
    return [(cx, top), (cx + w / 2, top + h / 2), (cx, top + h), (cx - w / 2, top + h / 2)]


def dashed_line(d, a, b, fill, width, dash):
    (x0, y0), (x1, y1) = a, b
    length = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
    steps = max(1, int(length // dash))
    for i in range(0, steps, 2):
        t0, t1 = i / steps, min(1, (i + 1) / steps)
        d.line([(x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0), (x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)],
               fill=fill, width=width)


def iso_grid(d, width, height, tw, th, ox, oy):
    """2:1 grid lines through the point (ox, oy), across the whole canvas."""
    span = width + height * 2
    k = -span
    while k <= span:
        # Lines going down-right and up-right, spaced one tile edge apart.
        for slope in (0.5, -0.5):
            x0, x1 = -width, width * 2
            # Pass through (ox + k, oy): y = oy + slope * (x - ox - k)
            d.line([(x0, oy + slope * (x0 - ox - k)), (x1, oy + slope * (x1 - ox - k))], fill=GRID, width=1)
        k += tw
    _ = th


def figure(d, foot_x, foot_y, s):
    """A resident-sized silhouette (48 x 72 pt) with its feet at (foot_x, foot_y)."""
    w, h = 96 * s, 144 * s
    top = foot_y - h * 0.92          # the game anchors walkers 8% up from the bottom
    d.ellipse([foot_x - w * 0.32, foot_y - 7 * s, foot_x + w * 0.32, foot_y + 7 * s], fill=(40, 40, 40, 60))
    head = w * 0.42
    d.ellipse([foot_x - head / 2, top, foot_x + head / 2, top + head], fill=FIGURE)
    d.rounded_rectangle([foot_x - w * 0.3, top + head * 0.95, foot_x + w * 0.3, foot_y],
                        radius=int(w * 0.2), fill=FIGURE)


def anchor_mark(d, x, y, s):
    r = 9 * s
    d.line([(x - r * 2, y - 1), (x + r * 2, y - 1)], fill=ANCHOR, width=max(2, int(2 * s)))
    d.line([(x, y - r * 2), (x, y)], fill=ANCHOR, width=max(2, int(2 * s)))
    d.ellipse([x - r / 2, y - r / 2 - 1, x + r / 2, y + r / 2 - 1], outline=ANCHOR, width=max(2, int(2 * s)))


def label(d, lines, s, x=None, y=None):
    f = font(int(15 * s))
    x = 10 * s if x is None else x
    y = 8 * s if y is None else y
    for line in lines:
        d.text((x, y), line, font=f, fill=TEXT)
        y += 20 * s


def building(n, s, out):
    tw, th = 256 * s, 128 * s
    w = n * tw
    foot_h = n * th
    headroom = 256 * s * n
    h = int(foot_h + headroom)
    img = Image.new("RGBA", (int(w), h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, top = w / 2, h - foot_h
    iso_grid(d, w, h, tw, th, cx, top)

    # Footprint, its tiles, and its outline.
    d.polygon(diamond(cx, top, w, foot_h), fill=FOOT)
    for i in range(1, n):
        # Lines parallel to each edge, one tile apart.
        a = (cx - i * tw / 2, top + i * th / 2)
        d.line([a, (a[0] + w / 2, a[1] + foot_h / 2)], fill=SUB, width=max(1, int(s)))
        b = (cx + i * tw / 2, top + i * th / 2)
        d.line([b, (b[0] - w / 2, b[1] + foot_h / 2)], fill=SUB, width=max(1, int(s)))
    d.polygon(diamond(cx, top, w, foot_h), outline=EDGE, width=max(2, int(2 * s)))

    # Wall guides straight up from the left, bottom and right corners.
    for x, y in [(cx - w / 2, top + foot_h / 2), (cx, h), (cx + w / 2 - 1, top + foot_h / 2)]:
        dashed_line(d, (x, y), (x, 0), WALL, max(1, int(s)), 10 * s)

    figure(d, cx - w * 0.3, top + foot_h * 0.5 + 6 * s, s)   # standing on the left corner
    anchor_mark(d, cx, h, s)
    label(d, [f"Building {n}x{n}  ·  {int(w)} px wide ({'@2x' if s == 1 else '@3x'})",
              "Anchor: bottom centre (red)",
              "Stay inside the front edges;",
              "go as tall as you like",
              "Grey figure = a resident, for scale"], s)
    img.save(out / f"building_{n}x{n}.png")


def tile(s, out):
    tw, th = int(256 * s), int(128 * s)
    img = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = diamond(tw / 2, 0, tw - 1, th - 1)
    d.polygon(pts, fill=FOOT, outline=EDGE, width=max(2, int(2 * s)))
    # Quarter lines and edge midpoints: things that cross an edge must line up with the next tile.
    d.line([((pts[0][0] + pts[3][0]) / 2, (pts[0][1] + pts[3][1]) / 2),
            ((pts[1][0] + pts[2][0]) / 2, (pts[1][1] + pts[2][1]) / 2)], fill=SUB, width=1)
    d.line([((pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2),
            ((pts[3][0] + pts[2][0]) / 2, (pts[3][1] + pts[2][1]) / 2)], fill=SUB, width=1)
    label(d, ["Ground tile", f"{tw} x {th}"], s * 0.8, x=tw / 2 - 45 * s, y=th / 2 - 18 * s)
    img.save(out / "tile.png")


def walker(s, out):
    w, h = int(96 * s), int(144 * s)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=EDGE, width=max(1, int(s)))
    feet = h * 0.92
    figure(d, w / 2, feet, s)
    dashed_line(d, (w / 2, 0), (w / 2, h), WALL, 1, 6 * s)
    d.line([(0, feet), (w, feet)], fill=ANCHOR, width=max(1, int(s)))
    f = font(int(11 * s))
    d.text((4 * s, 4 * s), "Walker", font=f, fill=TEXT)
    d.text((4 * s, 18 * s), "faces right", font=f, fill=TEXT)
    d.text((4 * s, feet - 16 * s), "feet", font=f, fill=ANCHOR)
    img.save(out / "walker.png")


def portrait(s, out):
    w = int(512 * s)
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, w - 1], outline=EDGE, width=max(1, int(s)))
    d.ellipse([0, 0, w - 1, w - 1], outline=WALL, width=max(2, int(2 * s)))
    face = w * 0.32
    d.ellipse([w / 2 - face / 2, w * 0.24, w / 2 + face / 2, w * 0.24 + face * 1.2], outline=SUB, width=max(1, int(s)))
    label(d, ["Portrait", "Pink circle = crop in the", "townsfolk list; keep the", "face in the blue oval"],
          s * 1.5, x=12 * s, y=w * 0.68)
    img.save(out / "portrait.png")


def grid_sheet(s, out):
    """A plain 2:1 grid, 8 tiles across, for laying out the whole-town style mockup."""
    tw, th = 256 * s, 128 * s
    w, h = int(tw * 8), int(th * 8)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for slope in (0.5, -0.5):
        k = -w * 2
        while k <= w * 2:
            d.line([(0, slope * (0 - k)), (w, slope * (w - k))], fill=(0, 150, 255, 110), width=max(1, int(s)))
            k += tw
    figure(d, w / 2, h / 2 + th / 2, s)
    label(d, ["Town mockup grid  ·  one diamond = one tile", "Grey figure = a resident, for scale"], s * 1.4)
    img.save(out / "town_mockup_grid.png")


def main():
    for name, s in (("2x", 1.0), ("3x", 1.5)):
        out = Path("art/templates") / name
        out.mkdir(parents=True, exist_ok=True)
        for n in (1, 2, 3):
            building(n, s, out)
        tile(s, out)
        walker(s, out)
        portrait(s, out)
        grid_sheet(s, out)
        print("wrote", out)


if __name__ == "__main__":
    main()
