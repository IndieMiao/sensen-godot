#!/usr/bin/env python3
"""Bake original foam noise and waterline distance masks for the 12 seeded ponds.

First run export_pond_foam_contacts.gd in the offline pond preview project.
Only foam assets are written; bank geometry, pond polygons and bed art stay intact.
--merge (SGODOT-272): contacts exported from another pond list (--ponds=res://assets/p0/p0_ponds.json) add their
masks to the bundled ones: the pattern and the catalog's entries stay as they are; the manifest gains the entries and
that list's path and sha256 (ponds_sha256), the catalog's own still checked by catalog_sha256.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ponds/art/foam'


def smooth(a, b, v):
    v = np.clip((v - a) / (b - a), 0, 1)
    return v * v * (3 - 2 * v)


def bake_pattern():
    n = 512
    yy, xx = np.mgrid[:n, :n] / n
    u = xx * 6 + .18 * np.sin(yy * np.pi * 4) + .07 * np.sin(yy * np.pi * 8)
    v = yy * 6 + .16 * np.sin(xx * np.pi * 4 + .7)
    rng = np.random.default_rng(30092027)
    nearest = np.full((n, n), 100.)
    second = nearest.copy()
    for y in range(6):
        for x in range(6):
            point = np.array([x, y]) + rng.uniform(.15, .85, 2)
            d = np.hypot((u - point[0] + 3) % 6 - 3, (v - point[1] + 3) % 6 - 3)
            second = np.minimum(second, np.maximum(nearest, d))
            nearest = np.minimum(nearest, d)
    froth = 1 - smooth(.025, .42, second - nearest)
    k = np.fft.fftfreq(n) * n
    radius = np.hypot(k[:, None], k[None, :])
    noise = np.fft.fft2(rng.normal(size=(n, n)))
    channels = []
    for scale in [10.0, 2.0]:
        field = np.fft.ifft2(noise * np.exp(-(radius / scale) ** 2)).real
        channels.append(np.clip(.5 + .18 * (field - field.mean()) / field.std(), 0, 1))
    # R: rounded shoreline breakup; G: surface filaments; B: sparse coverage.
    Image.fromarray(np.uint8(np.round(np.dstack([channels[0], froth, channels[1]]) * 255))).save(OUT / 'foam_pattern.png')


def bake_contacts(data, merge=False, out=OUT, shores=ROOT / 'assets/ponds'):
    width, height = 384, 512
    xx, zz = np.meshgrid((np.arange(width) + .5) * 12 / width, -(np.arange(height) + .5) * 16 / height)
    manifest = {'water_y': data['water_y'], 'catalog_sha256': data['catalog_sha256'], 'size': [width, height], 'distance_metres_per_unit': 1.0, 'entries': []}
    if merge:
        manifest = json.loads((out / 'manifest.json').read_text())
        assert manifest['water_y'] == data['water_y'] and manifest['catalog_sha256'] == data['catalog_sha256']
        assert manifest['size'] == [width, height]
        ids = {e['id'] for e in data['entries']}
        manifest['entries'] = [e for e in manifest['entries'] if e['id'] not in ids]
        manifest['ponds'] = {**manifest.get('ponds', {}), data['ponds_path']: data['ponds_sha256']}
    for entry in data['entries']:
        shore = Image.open(shores / (entry['template_id'] + '_shore.png')).getchannel('R')
        distance = np.minimum(np.asarray(shore.resize((width, height), Image.Resampling.BILINEAR), dtype=float) / 255 * 2, 1)
        for ax, az, bx, bz in entry['segments']:
            x0 = max(0, int(np.floor((min(ax, bx) - 1) / 12 * width)))
            x1 = min(width, int(np.ceil((max(ax, bx) + 1) / 12 * width)))
            y0 = max(0, int(np.floor((-max(az, bz) - 1) / 16 * height)))
            y1 = min(height, int(np.ceil((-min(az, bz) + 1) / 16 * height)))
            if x0 >= x1 or y0 >= y1:
                continue
            dx, dz = bx - ax, bz - az
            u, v = xx[y0:y1, x0:x1] - ax, zz[y0:y1, x0:x1] - az
            t = np.clip((u * dx + v * dz) / max(dx * dx + dz * dz, 1e-12), 0, 1)
            local = distance[y0:y1, x0:x1]
            np.minimum(local, np.hypot(u - t * dx, v - t * dz), out=local)
        assert entry['segments']
        Image.fromarray(np.uint8(np.round(np.clip(distance, 0, 1) * 255))).save(out / (entry['id'] + '.png'))
        manifest['entries'].append({k: v for k, v in entry.items() if k != 'segments'})
        print(entry['id'], len(entry['segments']), 'waterline segments', flush=True)
    for key in ('ponds_path', 'ponds_sha256', 'templates_path', 'templates_sha256'):
        if not merge and key in data: manifest[key] = data[key]
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('contacts', type=Path)
    parser.add_argument('--merge', action='store_true', help='add these ponds to the bundled masks (another pond list)')
    parser.add_argument('--art', help='a template art folder (P0 override, SGODOT-374: res://assets/ponds/p0/): its own '
                        'shore bands are read and its foam/ written with a manifest of its own; the shared pattern stays')
    args = parser.parse_args()
    data = json.loads(args.contacts.read_text())
    if args.art:
        art = ROOT / args.art.removeprefix('res://')
        out = art / 'foam'
        out.mkdir(parents=True, exist_ok=True)
        bake_contacts(data, False, out, art)
    else:
        OUT.mkdir(parents=True, exist_ok=True)
        if not args.merge:
            bake_pattern()
        bake_contacts(data, args.merge)
