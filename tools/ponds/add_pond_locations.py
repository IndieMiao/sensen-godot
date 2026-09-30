#!/usr/bin/env python3
"""Append server-only pond locations to server/data/ponds/locations.json.

assets/ponds/catalog.json is frozen: every shipped client compares its sha256, so new cities
are added here instead and reach clients through GET /v1/ponds/cells. Placement follows
tools/art/build_system_ponds.py (seeded jitter, seed-shuffled shapes), and existing records are
never moved or rewritten. Region ids are the server city ids (GET /v1/cities/search).

    python3 tools/ponds/add_pond_locations.py            # write
    python3 tools/ponds/add_pond_locations.py --check    # fail if the file would change
"""
import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'assets/ponds/catalog.json'
DEST = ROOT / 'server/data/ponds/locations.json'
SEED = 'journey-system-ponds-20260924-v1'
NAMES = ['Willow', 'Clover', 'Fern', 'Pebble', 'Reed', 'Blossom']
SHAPES = ['crescent', 'gourd', 'meander']
# region slug (used in ids) -> server city id and curated anchors inside public parks.
CITIES = {
    'san_francisco': {'region_id': 'gn-5391959', 'anchors': [
        (37.7694, -122.4862),  # Golden Gate Park, west meadows
        (37.7989, -122.4590),  # Presidio, Main Post lawn
        (37.7596, -122.4269),  # Mission Dolores Park
        (37.7185, -122.4190),  # John McLaren Park
        (37.7360, -122.4770),  # Stern Grove / Pine Lake Park
        (37.7680, -122.4410),  # Buena Vista Park
    ]},
}

def build():
    catalog = json.loads(CATALOG.read_text())
    frozen = {p['id'] for p in catalog['locations']}
    prior = json.loads(DEST.read_text()) if DEST.exists() else {'version': 1, 'locations': []}
    existing = {p['id']: p for p in prior['locations']}
    out = []
    for slug, spec in CITIES.items():
        for i, (lat, lng) in enumerate(spec['anchors']):
            identity = f'pond_{slug}_{i+1:02d}'
            if identity in frozen: raise SystemExit(f'{identity} already ships in the bundled catalog')
            if identity in existing:
                out.append(existing.pop(identity)); continue
            digest = hashlib.sha256(f'{SEED}:{identity}'.encode()).digest()
            dy = (int.from_bytes(digest[:4], 'big') / 2**32 - .5) * 35
            dx = (int.from_bytes(digest[4:8], 'big') / 2**32 - .5) * 35
            variants = sorted(SHAPES, key=lambda t: hashlib.sha256(f'{SEED}:{slug}:{i//3}:{t}'.encode()).digest())
            template = variants[i % 3]
            out.append({'id': identity, 'region_id': spec['region_id'], 'name': NAMES[i % len(NAMES)] + ' Pond',
                        'kind': 'pond', 'category': 'Fishing pond',
                        'lat': round(lat + dy / 111320, 7), 'lng': round(lng + dx / (111320 * math.cos(math.radians(lat))), 7),
                        'template_id': template, 'decoration_seed': int.from_bytes(digest[9:13], 'big'),
                        'layout_revision': catalog['templates'][template]['revision'], 'generation_version': 1, 'enabled': True})
    # Records dropped from CITIES stay published; disable them by editing "enabled" instead.
    out += list(existing.values())
    return {'version': 1, 'locations': out}

def main():
    text = json.dumps(build(), ensure_ascii=False, indent=2) + '\n'
    if '--check' in sys.argv:
        if not DEST.exists() or DEST.read_text() != text: raise SystemExit('server/data/ponds/locations.json is stale')
        return
    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_text(text)
    data = json.loads(text)
    print(json.dumps({'locations': len(data['locations']),
                      'by_region': {r: [p['template_id'] for p in data['locations'] if p['region_id'] == r]
                                    for r in sorted({p['region_id'] for p in data['locations']})}}))

if __name__ == '__main__': main()
