#!/usr/bin/env python3
"""C-193: fetch parcel farm files for building_fit_stats.gd, each checked against the dataset manifest.

Read-only HTTPS from the pinned dataset; nothing is uploaded. The full manifest's SHA-256 must be given (for r8 it is
the `manifest_sha256` named by the pinned client-manifest, see tests/dynamic_farm/README.md); a file whose bytes do not
match the manifest is retried and then reported, never used. Writes <out>/farms/<id>.json (`*` → `-star`) and
<out>/list.txt, one path per line, the input of building_fit_stats.gd.

Which parcels (one of):
  --starter-zone FILE   the claimable parcels of a starter zone file: `parcels` minus `too_small`
                        (assets/farm/data/dynamic_farm_starter_zone.json is r8's)
  --ids FILE            a JSON list of block IDs (e.g. the r8 starter IDs, to read an older release's version)
  --sample N            N parcels drawn with --seed from the dataset's index.geojson, outside the starter zone
                        (--starter-zone given too) and with core_cell_count >= --min-core (default 400)

  python3 -I tools/dev/dynamic_farm/fetch_parcels.py --base URL --manifest-sha SHA --out DIR (--starter-zone F | --ids F | --sample N ...)
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import random
import sys
import urllib.parse
import urllib.request


def get(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", required=True, help="dataset base URL ending in /")
    ap.add_argument("--manifest-sha", required=True, help="SHA-256 of the dataset's full manifest.json")
    ap.add_argument("--out", required=True)
    ap.add_argument("--starter-zone")
    ap.add_argument("--ids")
    ap.add_argument("--sample", type=int)
    ap.add_argument("--seed", type=int, default=193)
    ap.add_argument("--min-core", type=int, default=400)
    ap.add_argument("--jobs", type=int, default=8)
    a = ap.parse_args()
    if not a.base.endswith("/"):
        a.base += "/"
    raw = get(a.base + "manifest.json")
    if hashlib.sha256(raw).hexdigest() != a.manifest_sha:
        print("manifest.json does not match --manifest-sha", file=sys.stderr)
        return 1
    files = json.loads(raw)["files"]
    zone = set()
    if a.starter_zone:
        z = json.load(open(a.starter_zone))["zones"][0]
        zone = set(z["parcels"])
        claimable = sorted(zone - set(z.get("too_small", [])))
    if a.sample is not None:
        index = get(a.base + "index.geojson")
        if hashlib.sha256(index).hexdigest() != files["index.geojson"]:
            print("index.geojson does not match the manifest", file=sys.stderr)
            return 1
        pool = sorted(f["properties"]["block_id"] for f in json.loads(index)["features"]
                      if f["properties"]["block_id"] not in zone and f["properties"].get("core_cell_count", 0) >= a.min_core)
        ids = random.Random(a.seed).sample(pool, min(a.sample, len(pool)))
        print(f"sample {len(ids)} of {len(pool)} (seed {a.seed}, core >= {a.min_core}, outside the zone)")
    elif a.ids:
        ids = json.load(open(a.ids))
    elif a.starter_zone:
        ids = claimable
    else:
        ap.error("give --starter-zone, --ids or --sample")
    os.makedirs(os.path.join(a.out, "farms"), exist_ok=True)

    def one(block: str) -> str | None:
        want = files.get(f"farms/{block}.json")
        if want is None:
            return None  # not in this release
        path = os.path.join(a.out, "farms", block.replace("*", "-star") + ".json")
        if os.path.exists(path) and hashlib.sha256(open(path, "rb").read()).hexdigest() == want:
            return path
        for _ in range(4):
            try:
                body = get(a.base + "farms/" + urllib.parse.quote(block) + ".json")
            except OSError:
                continue
            if hashlib.sha256(body).hexdigest() == want:
                with open(path, "wb") as f:
                    f.write(body)
                return path
        raise RuntimeError(f"{block}: could not fetch a copy matching the manifest")

    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        paths = list(ex.map(one, ids))
    missing = [b for b, p in zip(ids, paths) if p is None]
    got = [os.path.abspath(p) for p in paths if p]
    with open(os.path.join(a.out, "list.txt"), "w") as f:
        f.write("".join(p + "\n" for p in got))
    print(f"{len(got)} parcels in {a.out}/list.txt; {len(missing)} not in this release")
    return 0


if __name__ == "__main__":
    sys.exit(main())
