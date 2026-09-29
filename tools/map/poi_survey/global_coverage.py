import math, json, sys, urllib.request, gzip, concurrent.futures as cf, re, collections
import mapbox_vector_tile as mvt
T = open('mapbox_token.txt').read().strip()
src = open('modules/map/city_map_data.gd').read()
def gd_dict(name):
    m = re.search(name + r' := \{(.*?)\}\n', src, re.S); return dict(re.findall(r'"([^"]+)":\s*(?:"([^"]*)"|\d+)', m.group(1)))
variants = set(gd_dict('ICON_VARIANTS')); alias = set(gd_dict('ICON_ALIAS'))
mapped = variants | alias
CITIES = {"san_francisco": (37.7880, -122.4075), "new_york": (40.7540, -73.9860), "tokyo": (35.6812, 139.7671), "london": (51.5072, -0.1276),
          "paris": (48.8566, 2.3522), "seattle": (47.6062, -122.3321), "chicago": (41.8781, -87.6298), "sydney": (-33.8688, 151.2093)}
Z, N = 16, 8
def tile(lat, lng):
    n = 2 ** Z; return int((lng + 180) / 360 * n), int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)
def fetch(j):
    z, x, y = j
    url = f"https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/{z}/{x}/{y}.vector.pbf?access_token={T}"
    for _ in range(3):
        try: return urllib.request.urlopen(url, timeout=30).read()
        except Exception: pass
    return b""
out = {}
for city, (lat, lng) in CITIES.items():
    cx, cy = tile(lat, lng); jobs = [(Z, cx + dx, cy + dy) for dx in range(-N//2, N//2) for dy in range(-N//2, N//2)]
    seen = set(); pois = []
    with cf.ThreadPoolExecutor(8) as ex:
        for data in ex.map(fetch, jobs):
            if not data: continue
            layers = mvt.decode(gzip.decompress(data) if data[:2] == b'\x1f\x8b' else data)
            for f in layers.get("poi_label", {}).get("features", []):
                p = f["properties"]; key = (f.get("id"), p.get("name"))
                if not p.get("name") or key in seen: continue
                seen.add(key); pois.append(p)
    top = [p for p in pois if float(p.get("filterrank", 5)) <= 3]
    share = lambda xs: round(100 * sum(1 for p in xs if p.get("maki") in mapped) / max(1, len(xs)))
    miss = collections.Counter(p.get("maki") or "(none)" for p in top if p.get("maki") not in mapped)
    out[city] = {"pois": len(pois), "all_pct": share(pois), "rank3": len(top), "rank3_pct": share(top), "top_missing": miss.most_common(8)}
    print(city, out[city]["pois"], "all", out[city]["all_pct"], "% | rank<=3", out[city]["rank3"], out[city]["rank3_pct"], "% | missing:", ", ".join(f"{k} {v}" for k, v in miss.most_common(8)))
json.dump(out, open('/tmp/poi_global/result.json', 'w'), ensure_ascii=False, indent=1)
