import math, json, sys, os, urllib.request, concurrent.futures as cf
import mapbox_vector_tile as mvt, gzip
T = open(sys.argv[1]).read().strip()
CITIES = {"sf": (37.7880, -122.4075), "beijing": (39.9150, 116.4040), "shanghai": (31.2304, 121.4737), "nyc": (40.7540, -73.9860)}
Z, N = 16, 12
def tile(lat, lng):
    n = 2 ** Z; x = (lng + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return int(x), int(y)
def fetch(z, x, y):
    url = f"https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/{z}/{x}/{y}.vector.pbf?access_token={T}"
    for _ in range(3):
        try:
            return urllib.request.urlopen(url, timeout=30).read()
        except Exception as e: err = e
    print("fail", z, x, y, err, file=sys.stderr); return b""
for city, (lat, lng) in CITIES.items():
    cx, cy = tile(lat, lng); jobs = [(Z, cx + dx, cy + dy) for dx in range(-N//2, N//2) for dy in range(-N//2, N//2)]
    os.makedirs("tools/map/poi_survey/data", exist_ok=True); out = open(f"tools/map/poi_survey/data/{city}.jsonl", "w"); seen = set(); n = 0
    with cf.ThreadPoolExecutor(8) as ex:
        for (z, x, y), data in zip(jobs, ex.map(lambda j: fetch(*j), jobs)):
            if not data: continue
            layers = mvt.decode(gzip.decompress(data) if data[:2]==b'\x1f\x8b' else data)
            for f in layers.get("poi_label", {}).get("features", []):
                p = f["properties"]; key = (f.get("id"), p.get("name"))
                if key in seen: continue
                seen.add(key); out.write(json.dumps(p, ensure_ascii=False) + "\n"); n += 1
    print(city, len(jobs), "tiles", n, "pois")
