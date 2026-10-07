#!/usr/bin/env python3
"""Compare UI kit gallery PNG shots with goldens (SGODOT-211). Exit 1 when a section is missing, resized,
or its mean per-channel difference exceeds the tolerance. Uses Godot-free decoding via `sips` fallback-free PNG reader."""
import sys, os, zlib, struct

def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    pos, w, h, ctype, idat = 8, 0, 0, 0, b''
    while pos < len(data):
        n, kind = struct.unpack('>I4s', data[pos:pos + 8]); body = data[pos + 8:pos + 8 + n]; pos += 12 + n
        if kind == b'IHDR': w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
        elif kind == b'IDAT': idat += body
    ch = {2: 3, 6: 4}[ctype]
    raw = zlib.decompress(idat); stride = w * ch; rows = []; prev = bytearray(stride); i = 0
    for _ in range(h):
        f = raw[i]; line = bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
        for x in range(stride):
            a = line[x - ch] if x >= ch else 0; b = prev[x]; c = prev[x - ch] if x >= ch else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    return w, h, ch, rows

def main(golden, shot, tol=2.0):
    bad = []
    for name in sorted(os.listdir(golden)):
        if not name.endswith('.png'): continue
        p = os.path.join(shot, name)
        if not os.path.exists(p): bad.append(f'{name}: missing'); continue
        gw, gh, gc, g = read_png(os.path.join(golden, name)); sw, sh, sc, s = read_png(p)
        if (gw, gh) != (sw, sh): bad.append(f'{name}: size {sw}x{sh} != {gw}x{gh}'); continue
        diff = sum(abs(g[y][x * gc + k] - s[y][x * sc + k]) for y in range(gh) for x in range(gw) for k in range(3))
        mean = diff / (gw * gh * 3)
        if mean > tol: bad.append(f'{name}: mean diff {mean:.2f} > {tol}')
    print('\n'.join(bad) if bad else 'all gallery shots match')
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 2.0))
