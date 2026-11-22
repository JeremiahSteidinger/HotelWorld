#!/usr/bin/env python3
"""Generate HotelWorld's placeholder pixel art (isometric tiles, buildings, props, characters).

Usage:  python3 tools/gen_art.py
Writes PNGs into art/. Any PNG can be replaced by hand-made art of the same size.

Isometric convention: one grid cell is a 64x32 diamond.
A box with footprint w (along grid x) by d (along grid y) and height h px is drawn on a
canvas of ((w+d)*32) x ((w+d)*16 + h); the footprint's top (back) corner sits at (d*32, h).
"""
import os
import random
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "art")
os.makedirs(OUT, exist_ok=True)
random.seed(7)


def save(img, name):
    img.save(os.path.join(OUT, name + ".png"))


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + ((c[3],) if len(c) == 4 else (255,))


def iso(gx, gy, ox, oy):
    """Grid point -> pixel on a canvas whose grid origin is at (ox, oy)."""
    return (ox + (gx - gy) * 32, oy + (gx + gy) * 16)


def diamond(draw, ox, oy, gx, gy, w, d, fill, lift=0, outline=None):
    pts = [iso(gx, gy, ox, oy - lift), iso(gx + w, gy, ox, oy - lift),
           iso(gx + w, gy + d, ox, oy - lift), iso(gx, gy + d, ox, oy - lift)]
    draw.polygon(pts, fill=fill, outline=outline)


def box(draw, ox, oy, gx, gy, w, d, h, top, left=None, right=None, lift=0):
    """Solid isometric box. Front-left face uses `left`, front-right face uses `right`."""
    left = left or shade(top, 0.75)
    right = right or shade(top, 0.6)
    a = iso(gx, gy + d, ox, oy - lift)
    b = iso(gx + w, gy + d, ox, oy - lift)
    c = iso(gx + w, gy, ox, oy - lift)
    draw.polygon([a, b, (b[0], b[1] - h), (a[0], a[1] - h)], fill=left)
    draw.polygon([b, c, (c[0], c[1] - h), (b[0], b[1] - h)], fill=right)
    diamond(draw, ox, oy, gx, gy, w, d, top, lift=lift + h)


def canvas(w, d, h):
    img = Image.new("RGBA", ((w + d) * 32, (w + d) * 16 + h), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img), d * 32, h


# ----------------------------------------------------------------------------- floor tiles

def tile(name, base, speckle=None, pattern=None):
    img, dr, ox, oy = canvas(1, 1, 0)
    diamond(dr, ox, oy, 0, 0, 1, 1, base)
    px = img.load()
    mask = [[px[x, y][3] > 0 for y in range(32)] for x in range(64)]
    if speckle:
        for _ in range(70):
            x, y = random.randrange(64), random.randrange(32)
            if mask[x][y]:
                px[x, y] = random.choice(speckle)
    if pattern:
        pattern(dr, px, mask)
    # crisp edge so the grid reads
    edge = shade(base, 0.88)
    for x in range(64):
        for y in range(32):
            if mask[x][y] and (y == 0 or not mask[x][y - 1] or x == 0 or not mask[x - 1][y]):
                px[x, y] = edge
    save(img, name)


def checker(dr, px, mask):
    for x in range(64):
        for y in range(32):
            if mask[x][y]:
                gx = (x / 32 + y / 16) / 2 * 4
                gy = (y / 16 - x / 32) / 2 * 4
                if (int(gx) + int(gy + 8)) % 2 == 0:
                    px[x, y] = (214, 196, 160, 255)


def road_line(dr, px, mask):
    for t in range(14, 50):
        y = 16 - (t - 32) // 2 * 0
        gx = t
        gy = int(32 - t / 2) // 2 + 8
    dr.line([iso(0, 0.5, 32, 0), iso(1, 0.5, 32, 0)], fill=(240, 210, 60, 255), width=2)


def parking_line(dr, px, mask):
    dr.line([iso(0, 0, 32, 0), iso(0, 1, 32, 0)], fill=(235, 235, 225, 255), width=2)


def carpet(dr, px, mask):
    for x in range(64):
        for y in range(32):
            if mask[x][y] and (x + 2 * y) % 9 == 0:
                px[x, y] = (122, 70, 90, 255)


tile("tile_grass", (96, 160, 74, 255), [(84, 146, 64, 255), (112, 176, 86, 255), (128, 186, 92, 255)])
tile("tile_asphalt", (78, 80, 88, 255), [(70, 72, 80, 255), (90, 92, 100, 255)])
tile("tile_parking", (78, 80, 88, 255), [(70, 72, 80, 255), (90, 92, 100, 255)], parking_line)
tile("tile_concrete", (178, 176, 168, 255), [(166, 164, 156, 255), (190, 188, 180, 255)])
tile("tile_road", (58, 60, 66, 255), [(52, 54, 60, 255), (66, 68, 74, 255)])
tile("tile_road_line", (58, 60, 66, 255), [(52, 54, 60, 255), (66, 68, 74, 255)], road_line)
tile("tile_lobby", (196, 176, 140, 255), None, checker)
tile("tile_carpet", (140, 84, 104, 255), None, carpet)

# ----------------------------------------------------------------------------- building shells

WALL_H = 56
EXT = (236, 222, 190, 255)        # stucco
TRIM = (190, 74, 58, 255)          # red motel trim


def shell(name, w, d, wall_in, door_front_left=None, door_front_right=None, windows=True, sign=None, left_h=WALL_H):
    """Back walls (seen from inside) plus low front walls with door gaps."""
    img, dr, ox, oy = canvas(w, d, WALL_H)
    # back-left wall along grid x=0 (from y=0..d)
    a, b = iso(0, 0, ox, oy), iso(0, d, ox, oy)
    dr.polygon([a, b, (b[0], b[1] - left_h), (a[0], a[1] - left_h)], fill=shade(wall_in, 0.85))
    # back-right wall along grid y=0 (from x=0..w)
    c = iso(w, 0, ox, oy)
    dr.polygon([a, c, (c[0], c[1] - WALL_H), (a[0], a[1] - WALL_H)], fill=wall_in)
    # skirting + top trim
    dr.line([b, a, c], fill=shade(wall_in, 0.55), width=2)
    dr.line([(b[0], b[1] - left_h), (a[0], a[1] - left_h)], fill=TRIM, width=4)
    dr.line([(a[0], a[1] - WALL_H), (c[0], c[1] - WALL_H)], fill=TRIM, width=4)
    if left_h < WALL_H:
        dr.line([(a[0], a[1] - left_h), (a[0], a[1] - WALL_H)], fill=TRIM, width=2)
    if windows:
        # a window on the back-right wall
        for gx in ([w / 2] if w <= 2 else [w * 0.3, w * 0.7]):
            p = iso(gx, 0, ox, oy)
            x0, y0 = p[0], p[1]
            win = [(x0 - 12, y0 - 18), (x0 + 12, y0 - 6), (x0 + 12, y0 - 30), (x0 - 12, y0 - 42)]
            dr.polygon(win, fill=(150, 200, 230, 255), outline=(90, 70, 50, 255))
            dr.line([(x0, y0 - 12), (x0, y0 - 36)], fill=(90, 70, 50, 255))
    if sign:
        p = iso(0, d * 0.5, ox, oy)
        dr.polygon([(p[0] - 20, p[1] - 30), (p[0] + 2, p[1] - 41), (p[0] + 2, p[1] - 51), (p[0] - 20, p[1] - 40)],
                   fill=(60, 40, 30, 255))
    low = 9
    # low front-left wall along y=d, with an optional door gap [x0, x1)
    segs = [(0, w)] if door_front_left is None else [(0, door_front_left[0]), (door_front_left[1], w)]
    for s0, s1 in segs:
        if s1 > s0:
            p, q = iso(s0, d, ox, oy), iso(s1, d, ox, oy)
            dr.polygon([p, q, (q[0], q[1] - low), (p[0], p[1] - low)], fill=shade(EXT, 0.8), outline=shade(EXT, 0.55))
    segs = [(0, d)] if door_front_right is None else [(0, door_front_right[0]), (door_front_right[1], d)]
    for s0, s1 in segs:
        if s1 > s0:
            p, q = iso(w, s0, ox, oy), iso(w, s1, ox, oy)
            dr.polygon([p, q, (q[0], q[1] - low), (p[0], p[1] - low)], fill=shade(EXT, 0.65), outline=shade(EXT, 0.45))
    save(img, name)


shell("room_shell", 2, 2, (210, 196, 220, 255), door_front_left=(0, 1), left_h=16)
shell("lobby_shell", 4, 5, (226, 206, 160, 255), door_front_left=(2, 3), door_front_right=(2, 3))

# ----------------------------------------------------------------------------- furniture / props

def desk():
    img, dr, ox, oy = canvas(2, 1, 22)
    box(dr, ox, oy, 0, 0.15, 2, 0.7, 20, (150, 96, 56, 255))
    diamond(dr, ox, oy, 0, 0.1, 2, 0.8, (196, 140, 90, 255), lift=20)
    # bell + computer
    p = iso(1.4, 0.5, ox, oy - 20)
    dr.rectangle([p[0] - 6, p[1] - 12, p[0] + 4, p[1] - 4], fill=(60, 64, 72, 255))
    dr.rectangle([p[0] - 5, p[1] - 11, p[0] + 3, p[1] - 6], fill=(120, 210, 230, 255))
    q = iso(0.5, 0.5, ox, oy - 20)
    dr.ellipse([q[0] - 3, q[1] - 4, q[0] + 3, q[1]], fill=(240, 200, 60, 255))
    save(img, "desk")


def bed(name, blanket, messy):
    img, dr, ox, oy = canvas(1, 1, 18)
    box(dr, ox, oy, 0.05, 0.05, 0.9, 0.9, 8, (120, 80, 50, 255))           # frame
    box(dr, ox, oy, 0.08, 0.08, 0.84, 0.84, 4, (245, 245, 240, 255), lift=8)  # mattress
    if messy:
        diamond(dr, ox, oy, 0.25, 0.1, 0.6, 0.8, shade(blanket, 0.9), lift=12)
        diamond(dr, ox, oy, 0.5, 0.15, 0.35, 0.5, shade(blanket, 0.7), lift=13)
        p = iso(0.2, 0.6, ox, oy - 12)
        dr.ellipse([p[0] - 6, p[1] - 3, p[0] + 4, p[1] + 2], fill=(240, 240, 235, 255))
        # clothes on the floor
        for (gx, gy, col) in [(0.9, 0.95, (70, 110, 200, 255)), (0.1, 1.0, (220, 90, 70, 255))]:
            p = iso(gx, gy, ox, oy)
            dr.rectangle([p[0] - 4, p[1] - 2, p[0] + 3, p[1] + 1], fill=col)
    else:
        diamond(dr, ox, oy, 0.35, 0.08, 0.57, 0.84, blanket, lift=12)
        diamond(dr, ox, oy, 0.08, 0.15, 0.25, 0.7, (250, 250, 250, 255), lift=13)
    save(img, name)


def car(name, color):
    img, dr, ox, oy = canvas(1, 1, 22)
    box(dr, ox, oy, 0.1, 0.18, 0.8, 0.64, 10, color, lift=3)
    box(dr, ox, oy, 0.3, 0.24, 0.45, 0.52, 7, (170, 210, 230, 255), shade((170, 210, 230, 255), 0.8),
        shade((170, 210, 230, 255), 0.65), lift=13)
    diamond(dr, ox, oy, 0.3, 0.24, 0.45, 0.52, shade(color, 1.1), lift=20)
    for gx, gy in [(0.2, 0.82), (0.75, 0.82)]:
        p = iso(gx, gy, ox, oy)
        dr.ellipse([p[0] - 4, p[1] - 6, p[0] + 3, p[1]], fill=(30, 30, 34, 255))
    save(img, name)


def sign(full):
    """Roadside sign. full=False: green VACANCY with an unlit NO. full=True: red neon NO VACANCY."""
    img = Image.new("RGBA", (80, 120), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.rectangle([37, 40, 42, 118], fill=(90, 90, 100, 255))
    dr.rounded_rectangle([2, 2, 77, 44], 6, fill=(40, 40, 60, 255), outline=(255, 90, 120, 255), width=3)
    # "MOTEL" in blocky pixels
    font = {
        "M": ["10001", "11011", "10101", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "01110"],
        "T": ["11111", "00100", "00100", "00100", "00100"],
        "E": ["11111", "10000", "11110", "10000", "11111"],
        "L": ["10000", "10000", "10000", "10000", "11111"],
    }
    x = 18
    for ch in "MOTEL":
        for r, row in enumerate(font[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    dr.rectangle([x + c * 2, 10 + r * 2, x + c * 2 + 1, 10 + r * 2 + 1], fill=(255, 220, 90, 255))
        x += 9
    # "NO" box: dark when unlit, red neon when full
    dr.rectangle([6, 26, 21, 37], fill=(150, 25, 35, 255) if full else (55, 45, 55, 255))
    dr.text((8, 26), "NO", fill=(255, 225, 220, 255) if full else (90, 80, 90, 255))
    # "VACANCY" box: green normally, red when full
    dr.rectangle([24, 26, 73, 37], fill=(150, 25, 35, 255) if full else (30, 120, 60, 255))
    dr.text((27, 26), "VACANCY", fill=(255, 225, 220, 255) if full else (150, 255, 170, 255))
    save(img, "sign_full" if full else "sign")


def tree():
    img = Image.new("RGBA", (40, 64), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.ellipse([8, 54, 32, 62], fill=(0, 0, 0, 60))
    dr.rectangle([17, 36, 22, 58], fill=(110, 76, 46, 255))
    for (x, y, r, c) in [(20, 22, 15, (56, 120, 60)), (13, 28, 10, (64, 134, 66)), (27, 28, 10, (50, 112, 56)), (20, 14, 10, (78, 150, 74))]:
        dr.ellipse([x - r, y - r, x + r, y + r], fill=c + (255,))
    save(img, "tree")


def plant():
    img = Image.new("RGBA", (20, 30), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.polygon([(5, 20), (15, 20), (13, 29), (7, 29)], fill=(180, 90, 60, 255))
    for (x, y) in [(10, 8), (5, 12), (15, 12), (8, 16), (12, 16)]:
        dr.ellipse([x - 4, y - 5, x + 4, y + 5], fill=(60, 140, 70, 255))
    save(img, "plant")


def ice_machine():
    img, dr, ox, oy = canvas(1, 1, 34)
    box(dr, ox, oy, 0.25, 0.25, 0.5, 0.5, 32, (200, 210, 220, 255))
    p = iso(0.5, 0.75, ox, oy)
    dr.rectangle([p[0] - 14, p[1] - 26, p[0] - 4, p[1] - 18], fill=(80, 160, 220, 255))
    dr.text((p[0] - 15, p[1] - 17), "ICE", fill=(40, 60, 90, 255))
    save(img, "ice_machine")


desk()
bed("bed_clean", (70, 120, 190, 255), False)
bed("bed_messy", (70, 120, 190, 255), True)
car("car_red", (200, 60, 60, 255))
car("car_blue", (60, 100, 200, 255))
car("car_green", (70, 160, 90, 255))
car("car_yellow", (220, 180, 60, 255))
sign(False)
sign(True)
tree()
plant()
ice_machine()

# ----------------------------------------------------------------------------- characters

SKINS = [(240, 200, 160), (200, 150, 110), (150, 100, 70), (110, 72, 50), (250, 215, 185)]
HAIRS = [(60, 40, 30), (30, 25, 25), (180, 130, 60), (200, 80, 40), (150, 150, 150)]


def outline(img):
    px = img.load()
    w, h = img.size
    solid = [[px[x, y][3] > 200 for y in range(h)] for x in range(w)]
    for x in range(w):
        for y in range(h):
            if not solid[x][y] and px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and solid[nx][ny]:
                        px[x, y] = (34, 28, 36, 255)
                        break


def person(dr, x, top, shirt, pants, skin, hair, frame, scale=1.0, extra=None):
    """Draw a small person whose feet are near row top+28*scale. x is the centre column."""
    s = scale
    def R(x0, y0, x1, y1, c):
        dr.rectangle([x + int(x0 * s), top + int(y0 * s), x + int(x1 * s), top + int(y1 * s)], fill=c + (255,))
    # legs (frame 1 = stepping)
    if frame == 0:
        R(-3, 19, -1, 26, pants); R(1, 19, 3, 26, pants)
        R(-3, 27, -1, 27, (40, 36, 40)); R(1, 27, 3, 27, (40, 36, 40))
    else:
        R(-4, 19, -2, 25, pants); R(2, 19, 4, 26, pants)
        R(-4, 26, -2, 26, (40, 36, 40)); R(2, 27, 4, 27, (40, 36, 40))
    # torso + arms
    R(-4, 10, 4, 19, shirt)
    arm = shade(shirt + (255,), 0.8)[:3]
    if frame == 0:
        R(-6, 11, -5, 18, arm); R(5, 11, 6, 18, arm)
    else:
        R(-6, 10, -5, 17, arm); R(5, 12, 6, 19, arm)
    R(-6, 19 if frame == 0 else 18, -5, 19 if frame == 0 else 18, skin); R(5, 19 if frame == 0 else 20, 6, 19 if frame == 0 else 20, skin)
    # head
    R(-3, 2, 3, 9, skin)
    R(-4, 1, 4, 3, hair); R(-4, 3, -4, 6, hair); R(4, 3, 4, 5, hair)
    R(-2, 5, -2, 5, (30, 30, 40)); R(1, 5, 1, 5, (30, 30, 40))
    if extra:
        extra(R, frame)


def char(name, shirt, pants, extra=None, skin=None, hair=None, kid=None):
    for frame in (0, 1):
        img = Image.new("RGBA", (28 if kid else 18, 34), (0, 0, 0, 0))
        dr = ImageDraw.Draw(img)
        dr.ellipse([2, 29, (25 if kid else 15), 33], fill=(0, 0, 0, 70))
        sk = skin or random.choice(SKINS)
        hr = hair or random.choice(HAIRS)
        person(dr, 9, 3, shirt, pants, sk, hr, frame, extra=extra)
        if kid:
            person(dr, 21, 12, kid, (60, 80, 140), sk, hr, 1 - frame, scale=0.7)
        outline(img)
        save(img, f"{name}_{frame}")


def cap(R, f):
    R(-4, 0, 4, 2, (200, 40, 40)); R(3, 2, 6, 2, (200, 40, 40))


def apron(R, f):
    R(-3, 13, 3, 20, (245, 245, 245)); R(-4, 0, 4, 1, (240, 240, 240))


def vest(R, f):
    R(-4, 10, -1, 19, (110, 60, 150)); R(1, 10, 4, 19, (110, 60, 150)); R(0, 11, 0, 14, (200, 40, 40))


def briefcase(R, f):
    R(6, 17, 9, 21, (110, 70, 40)); R(7, 16, 8, 16, (60, 40, 20))


def backpack(R, f):
    R(-7, 11, -5, 18, (200, 140, 40)); R(-4, 10, -4, 12, (150, 100, 30))


char("owner", (220, 70, 60), (60, 70, 110), cap, skin=SKINS[0], hair=HAIRS[0])
char("clerk", (240, 240, 245), (40, 40, 50), vest)
char("housekeeper", (70, 170, 170), (70, 170, 170), apron)
char("guest_budget", (90, 170, 80), (90, 110, 160), backpack)
char("guest_business", (50, 60, 90), (50, 60, 90), briefcase)
char("guest_family", (240, 150, 60), (110, 90, 70), kid=(240, 200, 60))

# ----------------------------------------------------------------------------- icon

def icon():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.rounded_rectangle([2, 2, 61, 61], 12, fill=(40, 40, 64, 255))
    dr.rectangle([12, 26, 52, 50], fill=EXT)
    dr.polygon([(8, 28), (32, 10), (56, 28)], fill=TRIM)
    for x in (16, 28, 40):
        dr.rectangle([x, 34, x + 7, 49], fill=(140, 84, 60, 255))
    dr.rectangle([20, 52, 44, 56], fill=(255, 90, 120, 255))
    save(img, "icon")


def window_lit():
    """Same canvas as room_shell: the back window with the lights on and curtains half drawn."""
    img, dr, ox, oy = canvas(2, 2, WALL_H)
    x0, y0 = iso(1, 0, ox, oy)
    frame = (90, 70, 50, 255)
    dr.polygon([(x0 - 12, y0 - 18), (x0 + 12, y0 - 6), (x0 + 12, y0 - 30), (x0 - 12, y0 - 42)],
               fill=(255, 214, 120, 255), outline=frame)
    curtain = (196, 92, 84, 255)
    for (a, b) in [(-11, -5), (5, 11)]:
        # vertical strips that follow the wall's slope (y rises 1px per 2px of x)
        dr.polygon([(x0 + a, y0 - 41 + (a + 12) // 2), (x0 + b, y0 - 41 + (b + 12) // 2),
                    (x0 + b, y0 - 19 + (b + 12) // 2), (x0 + a, y0 - 19 + (a + 12) // 2)], fill=curtain)
    dr.line([(x0, y0 - 12), (x0, y0 - 36)], fill=frame)
    save(img, "window_lit")


def luggage(kind):
    """Small upright props left in an occupied room."""
    img = Image.new("RGBA", (26, 24), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.ellipse([2, 19, 23, 23], fill=(0, 0, 0, 60))

    def case(x, y, w, h, col):
        dr.rectangle([x, y, x + w, y + h], fill=col, outline=shade(col, 0.55))
        dr.rectangle([x + w // 2 - 2, y - 3, x + w // 2 + 2, y - 1], outline=(50, 50, 56, 255))
        dr.line([(x + 2, y + h // 2), (x + w - 2, y + h // 2)], fill=shade(col, 0.75))

    if kind == "budget":       # a stuffed backpack slumped on the floor
        dr.rounded_rectangle([7, 7, 19, 21], 4, fill=(200, 140, 40, 255), outline=(130, 88, 24, 255))
        dr.rounded_rectangle([9, 13, 17, 19], 2, fill=(170, 116, 32, 255))
        dr.line([(9, 7), (11, 3), (15, 3), (17, 7)], fill=(130, 88, 24, 255), width=2)
    elif kind == "business":   # rolling carry-on with the handle up
        dr.line([(10, 1), (10, 9)], fill=(70, 70, 78, 255), width=1)
        dr.line([(16, 1), (16, 9)], fill=(70, 70, 78, 255), width=1)
        dr.line([(10, 1), (16, 1)], fill=(70, 70, 78, 255), width=2)
        dr.rectangle([7, 9, 19, 20], fill=(52, 58, 80, 255), outline=(30, 32, 44, 255))
        dr.line([(9, 12), (17, 12)], fill=(80, 88, 116, 255))
        dr.point([(9, 21), (17, 21)], fill=(20, 20, 24, 255))
    else:                      # family: a big suitcase and a small one
        case(1, 8, 13, 12, (60, 130, 110, 255))
        case(14, 12, 9, 8, (230, 120, 60, 255))
    outline(img)
    save(img, "luggage_" + kind)


icon()
window_lit()
for k in ("budget", "business", "family"):
    luggage(k)
print("art written to", os.path.abspath(OUT))
