import math, struct, zlib
from pathlib import Path


def png_rgba(path, w, h):
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            # premium teal/navy radial background
            nx = (x - w*0.5)/(w*0.5)
            ny = (y - h*0.45)/(h*0.5)
            r = min(1.0, math.sqrt(nx*nx + ny*ny))
            t = max(0.0, 1.0-r)
            R = int(8 + 8*t)
            G = int(22 + 64*t)
            B = int(35 + 72*t)

            # luminous oval / face-liveness motif
            cx, cy = w*0.5, h*0.49
            rx, ry = w*0.245, h*0.325
            q = ((x-cx)/rx)**2 + ((y-cy)/ry)**2
            ring = abs(q-1.0)
            if ring < 0.045:
                a = 1.0-ring/0.045
                R = int(R*(1-a) + 110*a)
                G = int(G*(1-a) + 244*a)
                B = int(B*(1-a) + 225*a)

            # tiny centered sparkle to avoid looking like a plain camera icon
            dx, dy = abs(x-cx), abs(y-(cy-ry*0.62))
            if dx < w*0.015 or dy < h*0.015:
                if dx < w*0.06 and dy < h*0.06:
                    a = max(0.0, 1.0-max(dx/(w*0.06), dy/(h*0.06)))
                    R = int(R*(1-a) + 235*a)
                    G = int(G*(1-a) + 255*a)
                    B = int(B*(1-a) + 250*a)

            row.extend((R,G,B,255))
        rows.append(bytes(row))

    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag+data) & 0xffffffff)

    raw = b''.join(rows)
    out = b'\x89PNG\r\n\x1a\n'
    out += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    out += chunk(b'IDAT', zlib.compress(raw, 9))
    out += chunk(b'IEND', b'')
    Path(path).write_bytes(out)

Path('Resources').mkdir(exist_ok=True)
png_rgba('Resources/Icon60@2x.png', 120, 120)
png_rgba('Resources/Icon60@3x.png', 180, 180)
png_rgba('Resources/AppIcon.png', 1024, 1024)
print('Generated app icons')
