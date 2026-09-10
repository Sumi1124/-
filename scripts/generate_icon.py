#!/usr/bin/env python3
"""Generate SourceDesk app icon (1024x1024 PNG) without external deps."""
import struct, zlib, math, os

SIZE = 1024
C = 0.28  # corner radius fraction for rounded square

def lerp(a, b, t):
    return a + (b - a) * t

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

def rounded_rect(x0, y0, x1, y1, rad):
    # returns signed-distance-like coverage in 0..1
    cx = clamp(x0, x0, x1)
    return None

def rr_coverage(px, py, x0, y0, x1, y1, rad):
    cx = clamp(px, x0 + rad, x1 - rad)
    cy = clamp(py, y0 + rad, y1 - rad)
    dx = px - cx
    dy = py - cy
    d2 = dx * dx + dy * dy
    if d2 <= rad * rad:
        return 1.0
    # outside: distance to the rounded rect
    qx = clamp(px, x0, x1)
    qy = clamp(py, y0, y1)
    return 0.0

def inside_rr(px, py, x0, y0, x1, y1, rad):
    cx = clamp(px, x0 + rad, x1 - rad)
    cy = clamp(py, y0 + rad, y1 - rad)
    dx = px - cx
    dy = py - cy
    if abs(dx) <= rad and abs(dy) <= rad:
        return dx * dx + dy * dy <= rad * rad
    if abs(dx) <= rad and py >= y0 and py <= y1:
        return True
    if abs(dy) <= rad and px >= x0 and px <= x1:
        return True
    qx = clamp(px, x0, x1)
    qy = clamp(py, y0, y1)
    return (px - qx) ** 2 + (py - qy) ** 2 <= rad * rad

def shade_inside(px, py, x0, y0, x1, y1, rad):
    return inside_rr(px, py, x0, y0, x1, y1, rad)

def write_png(path, w, h, pixels):  # pixels: list of (r,g,b,a) 0..255
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            raw += bytes((r, g, b, a))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)

def draw(supersample=2):
    W = SIZE * supersample
    img = [None] * (W * W)
    R = C * W

    for y in range(W):
        for x in range(W):
            t = y / W
            # background gradient deep blue -> dark
            bg_r = lerp(0x1E, 0x10, t)
            bg_g = lerp(0x3A, 0x16, t)
            bg_b = lerp(0x8A, 0x3A, t)

            r, g, b = bg_r, bg_g, bg_b

            # mask to rounded square (macOS icons are full-bleed; system clips)
            if x == 0 or y == 0 or x == W - 1 or y == W - 1:
                pass

            # ---- document/paper card ----
            rx0, ry0, rx1, ry1 = W * 0.20, W * 0.16, W * 0.80, W * 0.84
            in_card = inside_rr(x, y, rx0, ry0, rx1, ry1, W * 0.05)
            if in_card:
                # subtle vertical gradient on the paper
                ct = (y - ry0) / (ry1 - ry0)
                pr = lerp(0xF8, 0xE2, ct)
                pg = lerp(0xFA, 0xE8, ct)
                pb = lerp(0xFF, 0xF5, ct)
                r, g, b = pr, pg, pb

                # header bar accent
                if y > ry0 + W * 0.06 and y < ry0 + W * 0.135:
                    if x > rx0 + W * 0.10 and x < rx0 + W * 0.42:
                        r, g, b = 0x1D, 0x4E, 0xD8

                # text lines
                lx0, lx1 = rx0 + W * 0.10, rx1 - W * 0.10
                for i, (ly, lw) in enumerate([
                    (0.215, 1.0), (0.30, 0.85), (0.36, 0.85),
                    (0.46, 1.0), (0.545, 1.0), (0.615, 0.7), (0.685, 0.85),
                    (0.775, 0.55),
                ]):
                    yy = ry0 + ly * (ry1 - ry0)
                    lxo = lx0
                    lx2 = lx0 + (lx1 - lx0) * lw
                    if abs(y - yy) < W * 0.021:
                        if x > lxo and x < lx2:
                            r, g, b = lerp(0xb, 0x2c, 0), 0x2c, 0x5e  # dark slate blue lines
            else:
                # subtle border glow outside card
                pass

            # book ribbon
            rx0r, ry0r = W * 0.765, W * 0.16
            rx1r, ry1r = W * 0.825, W * 0.16 + W * 0.30
            if inside_rr(x, y, rx0r, ry0r, rx1r, ry1r, W * 0.02):
                r, g, b = 0xE6, 0x4A, 0x3B

            # radial highlight top-left
            hx, hy = W * 0.30, W * 0.22
            hr = W * 0.55
            d = ((x - hx) ** 2 + (y - hy) ** 2) ** 0.5
            if d < hr:
                halo = (1 - d / hr) * 0.12
                r = int(r + (255 - r) * halo)
                g = int(g + (255 - g) * halo)
                b = int(b + (255 - b) * halo)

            img[y * W + x] = (int(clamp(r, 0, 255)), int(clamp(g, 0, 255)), int(clamp(b, 0, 255)), 255)

    # downsample (box average) to SIZE
    out = []
    ss = supersample
    for y in range(SIZE):
        for x in range(SIZE):
            rs = gs = bs = asum = 0
            for dy in range(ss):
                rowoff = (y * ss + dy) * W
                for dx in range(ss):
                    r0, g0, b0, a0 = img[rowoff + x * ss + dx]
                    rs += r0; gs += g0; bs += b0; asum += a0
            n = ss * ss
            out.append((rs // n, gs // n, bs // n, asum // n))
    return out

base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
icons_dir = os.path.join(base, "SourceDesk", "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(icons_dir, exist_ok=True)
src = os.path.join(icons_dir, "master.png")
pixels = draw(supersample=2)
write_png(src, SIZE, SIZE, pixels)
print("wrote", src)

sizes = {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}
for name, sz in sizes.items():
    dest = os.path.join(icons_dir, name)
    os.system(f'sips -z {sz} {sz} "{src}" --out "{dest}" >/dev/null 2>&1')
    print("made", name, sz)