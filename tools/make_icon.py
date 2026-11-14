"""Punch Tower app icon: in-game sprites and palettes composed on a 32x32 pixel grid.
Usage: python3 make_icon.py OUTDIR"""
import sys, math, random
from PIL import Image

G = 32
random.seed(7)

def hexc(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

def FIRE(k):  # FIREPAL from the game
    return '#ffffff' if k > .82 else '#fff1a0' if k > .64 else '#ffd04a' if k > .44 else '#ff7a1a' if k > .24 else '#c8341a'

# --- sprites straight from index.html ---
RISE = ["........ss.", ".......SssS", ".......ssss", "..kkkk..ss.", ".kkkkkk.ss.", ".rrrrrr.ss.", ".ssssss.gg.",
        ".sesses.gg.", ".ssssss.gg.", "..ssss.gg..", ".gggggggg..", "sgGGggggg..", "s.bbbbbb...", "..gggggg...",
        "..gg.gggg..", "..dd...dd.."]
PAL = {'k': '#2a1a14', 'r': '#e8344a', 's': '#f2b68a', 'S': '#c88a60', 'e': '#1a1020', 'g': '#f4efe8', 'G': '#c4bccd',
       'b': '#1e1a24', 'd': '#3a2a24'}
BRICK = ['#b5523b', '#6e2a20', '#d97456']


def compose(safe=False):
    """safe=True: art pulled into the centre (maskable / round launchers crop the edges)."""
    px = [[None] * G for _ in range(G)]

    def put(x, y, c):
        if 0 <= x < G and 0 <= y < G and c: px[y][x] = c

    # background: tower shaft, darker at the top, warm at the bottom (lava light)
    for y in range(G):
        for x in range(G):
            t = y / (G - 1)
            r, g, b = (11 + 40 * t ** 2, 8 + 6 * t ** 2, 17 + 4 * t)
            px[y][x] = '#%02x%02x%02x' % (int(r), int(g), int(b))
    # side walls (dark stone bricks)
    for y in range(G):
        for x in list(range(0, 3)) + list(range(G - 3, G)):
            mortar = (y % 4 == 3) or ((x + (2 if (y // 4) % 2 else 0)) % 6 == 5)
            put(x, y, '#1c1626' if mortar else ('#2c2438' if (x + y) % 5 else '#342a42'))

    # ceiling slab being smashed: brick floor across the top, cracked open in the middle
    top0, top1 = 2, 7
    cx = 19  # the hole sits right above the fist
    for y in range(top0, top1):
        for x in range(3, G - 3):
            if abs(x + .5 - cx) < 3.2 - (y - top0) * .2:  # the hole the fist punched
                continue
            mortar = (y - top0) % 3 == 2 or ((x + (3 if ((y - top0) // 3) % 2 else 0)) % 6 == 0)
            c = BRICK[1] if mortar else (BRICK[2] if y == top0 else BRICK[0])
            put(x, y, c)
    # the hole: blast of fire through it, dark broken rims
    for y in range(0, top1):
        w = 3.2 - (y - top0) * .2 if y >= top0 else 3.4 + (top0 - y) * .6
        for x in range(3, G - 3):
            d = abs(x + .5 - cx)
            if d < w and (y >= top0 or d < w - .2):
                k = 1 - d / (w + .5) * .9 + random.uniform(-.08, .08) - (0 if y >= top0 else (top0 - y) * .15)
                put(x, y, FIRE(k))
    for y in range(top0, top1):
        w = 3.2 - (y - top0) * .2
        for sd in (-1, 1):
            put(int(math.floor(cx + sd * w + (0 if sd > 0 else -.0))) + (0 if sd > 0 else -1) + (1 if sd < 0 else 0), y, '#2a120c')
    # flying chunks
    for (x, y, sz) in [(12, 0, 2), (25, 0, 2), (9, 1, 1), (28, 1, 1), (14, 8, 1), (26, 9, 2), (6, 10, 1), (15, 1, 1), (23, 1, 1)]:
        for dy in range(sz):
            for dx in range(sz):
                put(x + dx, y + dy, BRICK[2] if dy == 0 else BRICK[0])
    # lava along the bottom
    for x in range(G):
        w = round(math.sin(x * .7) * .8 + math.sin(x * .23 + 1) * .7)
        y = 28 + w
        put(x, y, '#ffe27a')
        for yy in range(y + 1, y + 3): put(x, yy, '#ff8a1a')
        for yy in range(y + 3, G): put(x, yy, '#c8341a')
    for (x, y) in [(5, 30), (14, 31), (25, 30), (20, 29)]:
        put(x, y, '#8a1c10'); put(x + 1, y, '#8a1c10')
    for (x, y) in [(8, 24), (23, 23), (12, 25), (27, 25), (4, 22)]:
        put(x, y, '#ffd04a')

    # hero: rising uppercut, fist up into the hole. Sprite is 11 wide, lead arm at columns 7-10
    hx, hy = cx - 9, 11
    # fire aura hugging the outline (KING body fire), 2 px thick with flicker
    body = {(hx + c, hy + r) for r, row in enumerate(RISE) for c, ch in enumerate(row) if ch != '.'}
    for (x, y) in list(body):
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-2, 0), (2, 0), (0, 1), (-1, -1), (1, -1), (0, -2)]:
            p = (x + dx, y + dy)
            if p in body: continue
            d = abs(dx) + abs(dy)
            k = (.75 if d == 1 else .4) + random.uniform(-.15, .12) - max(0, y - 20) * .04
            put(p[0], p[1], FIRE(k))
    # flames licking up from the shoulders
    for i in range(14):
        x = hx + random.randint(0, 9); y = hy + 3 - random.randint(0, 4)
        if (x, y) not in body: put(x, y, FIRE(random.uniform(.3, .9)))
    for r, row in enumerate(RISE):
        for c, ch in enumerate(row):
            if ch != '.': put(hx + c, hy + r, PAL[ch])
    # blazing fist on the lead arm (drawSuperPlayer)
    fx, fy = hx + 8, hy - 7
    for y in range(8):
        for x in range(-2, 6):
            d = math.hypot(x - 1.5, y - 4)
            if d < 4.4 + math.sin(y * 1.7) * .5:
                put(fx + x, fy + y, FIRE(1 - d / 5 + random.uniform(0, .12)))
    for r, row in enumerate(["sss", "sSs", "sss"]):
        for c, ch in enumerate(row):
            put(fx + c, fy + 3 + r, {'s': '#fff6d0', 'S': '#ffd04a'}[ch])

    img = Image.new('RGBA', (G, G))
    for y in range(G):
        for x in range(G):
            img.putpixel((x, y), hexc(px[y][x]))
    if safe:  # shrink art into the 80% safe circle, background extended
        inner = img.resize((26, 26), Image.NEAREST)
        out = Image.new('RGBA', (G, G), hexc('#120c18'))
        # extend: stretch the edges of the original as the backdrop
        out.paste(img.resize((G, G), Image.NEAREST), (0, 0))
        out.paste(inner, (3, 3))
        img = out
    return img


def save(img, size, path):
    img.resize((size, size), Image.NEAREST if size % G == 0 else Image.BOX).save(path)


def maskable(a):
    """art at 75% in the middle, the tower (walls, ceiling, lava) carried on to the edges"""
    b = Image.new('RGBA', (40, 40))
    b.paste(a, (4, 4))
    for y in range(40):
        sy = min(max(y - 4, 0), G - 1)
        for x in range(40):
            if 4 <= x < 36 and 4 <= y < 36: continue
            if x < 4 or x >= 36:  # side walls: same brick pattern, carried outward
                b.putpixel((x, y), a.getpixel(((x % 3) if x < 4 else G - 3 + (x % 3), sy)))
            elif y < 4:   # above: the dark shaft
                b.putpixel((x, y), hexc('#0b0811'))
            else:         # below: deep lava with a few dark crusts
                b.putpixel((x, y), hexc('#8a1c10' if (x * 7 + y * 3) % 11 == 0 else '#c8341a'))
    big = b.resize((480, 480), Image.NEAREST)
    out = Image.new('RGBA', (512, 512))
    out.paste(big.resize((512, 512), Image.NEAREST))  # edge fill
    out.paste(big, (16, 16))
    return out


def build(out):
    a = compose()
    a.resize((512, 512), Image.NEAREST).save(f'{out}/icon-512.png')
    a.resize((192, 192), Image.NEAREST).save(f'{out}/icon-192.png')
    a.resize((576, 576), Image.NEAREST).resize((180, 180), Image.LANCZOS).save(f'{out}/apple-touch-icon.png')
    a.resize((64, 64), Image.NEAREST).save(f'{out}/favicon-64.png')
    maskable(a).save(f'{out}/maskable-512.png')


if __name__ == '__main__':
    build(sys.argv[1])
