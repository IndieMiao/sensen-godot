#!/usr/bin/env python3
"""Review maps for the water table (SGODOT-280, q(126)): one Mapbox static map per city, red = generated point,
green = moved point, the same letter for the same place. Reads output/world-water/shard-*.jsonl.
   python3 tools/world_water_review_maps.py <out dir> <cluster id> [...]
The Mapbox token is read from mapbox_token.txt (never printed)."""
import glob, json, os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
token = open(os.path.join(ROOT, 'mapbox_token.txt')).read().strip()
lines = {}
for f in sorted(glob.glob(os.path.join(ROOT, 'output/world-water/shard-*.jsonl'))):
    for l in open(f):
        d = json.loads(l)
        if 'error' not in d:
            lines[d['cluster']] = d
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
letters = 'abcdefghijklmnopqrstuvwxyz'
for cid in sys.argv[2:]:
    d = lines.get(cid)
    if not d or not d.get('moved'):
        print(cid, 'nothing moved'); continue
    pins = []
    for i, m in enumerate(d['moved'][:26]):
        pins.append(f"pin-s-{letters[i]}+e53935({m['from'][1]},{m['from'][0]})")
        pins.append(f"pin-s-{letters[i]}+2e7d32({m['to'][1]:.6f},{m['to'][0]:.6f})")
    name = ''.join(ch for ch in d.get('name', cid) if ch.isalnum()) or cid
    path = os.path.join(out, f"SGODOT-280-water-{name}.jpg")
    url = f"https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/static/{','.join(pins)}/auto/900x900@2x?padding=120&access_token={token}"
    raw = path + '.raw'
    ok = False
    for _ in range(4):   # Mapbox drops a connection now and then; the URL carries the token, so never print it
        if subprocess.run(['curl', '-sS', '-f', '-m', '60', '-o', raw, url], capture_output=True).returncode == 0:
            ok = True; break
    if not ok:
        print(cid, 'map request failed'); continue
    subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '80', raw, '--out', path], capture_output=True, check=True)
    os.remove(raw)
    legend = '; '.join(f"{letters[i]} {m['name']} {m['moved_m']} m" for i, m in enumerate(d['moved'][:26]))
    print(path, '|', d.get('name'), d.get('tier'), '|', legend)
