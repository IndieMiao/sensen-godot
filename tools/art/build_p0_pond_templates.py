#!/usr/bin/env python3
"""P0's pond outlines (SGODOT-374): the open-water shapes laid over assets/ponds/catalog.json for P0 only.

The catalog stays frozen (its sha256 is Journey's catalog_revision, and the server names template ids at layout
revision 1), so P0's own outlines live in assets/p0/p0_pond_templates.json and SystemPonds.template lays them over
the catalog's. Each template's polygon is the authority (不知火舞 on 374: the old outline's hull united with a
same-box ellipse, smoothed); this tool rebuilds the rest from it with build_system_ponds.py's rules: the walkable
rows and the shore distance texture into assets/ponds/p0/. The bed and the per-pond foam are baked by
bake_pond_bed.py / bake_pond_foam.py from the same file.

  python3 tools/art/build_p0_pond_templates.py [--polygons <json {template: [[x, y], ...]}>]
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_system_ponds import inside, distance, png

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/p0/p0_pond_templates.json'
ART = ROOT / 'assets/ponds/p0'
ART_RES = 'res://assets/ponds/p0/'
CELL = .25
SPAWN = [6.125, -1.625]
NOTE = ("P0's pond outlines (SGODOT-374, 不知火舞's open-water shapes): laid over assets/ponds/catalog.json's templates "
        "by SystemPonds.template, so every P0 pond of a template takes them; the catalog, the template ids and their "
        "revision stay as they are (Journey's catalog_revision; the server names template + layout_revision 1). "
        "polygon is the authority; navigation and art's <template>_shore.png come from it "
        "(tools/art/build_p0_pond_templates.py), the bed and the foam from bake_pond_bed.py / bake_pond_foam.py.")

def rows_for(poly):
    rows = []
    for y in range(64):
        row = ''
        for x in range(48):
            p = ((x + .5) * CELL, -(y + .5) * CELL)
            row += '1' if 3 <= x < 45 and 3 <= y < 61 and not inside(poly, p) and distance(poly, p) > CELL * math.sqrt(2) / 2 + .10 else '0'
        rows.append(row)
    return rows

def shore(path, poly):
    pixels = bytearray()
    for y in range(256):
        for x in range(192):
            p = ((x + .5) / 192 * 12, -(y + .5) / 256 * 16)
            wet = inside(poly, p)
            d = distance(poly, p)
            pixels.extend([round(min(1, d / 2) * 255) if wet else 0, 255 if wet else 0, 0, 255])
    png(path, 192, 256, bytes(pixels))

def main(argv):
    if '--polygons' in argv:
        polygons = json.loads(Path(argv[argv.index('--polygons') + 1]).read_text())
    else:
        polygons = {k: v['polygon'] for k, v in json.loads(OUT.read_text())['templates'].items()}
    ART.mkdir(parents=True, exist_ok=True)
    templates = {}
    for key in sorted(polygons):
        poly = [[round(float(p[0]), 4), round(float(p[1]), 4)] for p in polygons[key]]
        templates[key] = {'polygon': poly, 'extent': [12, 16],
                          'navigation': {'cell': CELL, 'rows': rows_for(poly), 'spawn': SPAWN}, 'art': ART_RES}
        shore(ART / f'{key}_shore.png', poly)
    OUT.write_text(json.dumps({'_note': NOTE, 'templates': templates}, ensure_ascii=False, indent=1) + '\n')
    print(json.dumps({k: {'points': len(v['polygon']), 'walkable': sum(r.count('1') for r in v['navigation']['rows'])} for k, v in templates.items()}))

if __name__ == '__main__': main(sys.argv[1:])
