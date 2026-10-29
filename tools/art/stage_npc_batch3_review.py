#!/usr/bin/env python3
"""Copy art-only review scripts into the isolated farm-dev checkout, never into its commit."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--runtime-root', type=Path, required=True)
args = parser.parse_args()
runtime = args.runtime_root.resolve()
out = runtime / 'output/npc-batch3'
out.mkdir(parents=True, exist_ok=True)
(runtime / 'output/.gdignore').touch()
(runtime / 'tools/art').mkdir(parents=True, exist_ok=True)
scripts = ['prepare_npc_batch3.gd', 'verify_npc_batch3.gd', 'review_npc_batch3.gd', 'bake_resident_portraits.gd']
hashes = {}
for name in scripts:
    source = ROOT / 'tools/art' / name
    if not source.exists():
        continue
    shutil.copy2(source, runtime / 'tools/art' / name)
    hashes[name] = hashlib.sha256(source.read_bytes()).hexdigest()
looks = json.loads((ROOT / 'docs/design/resident-clash-362-2026-10-29/looks-candidates.json').read_text())
ids = ['lena_now', 'lena_a', 'rafa_now', 'rafa_r1', 'nadia_now', 'sigrid', 'finn', 'mei', 'theo', 'sam_now', 'hana_a']
looks = {key: looks[key] for key in ids}
looks['lena_new'] = {'slots': {'hairHat': 'hairhat51_npc_lena', 'glass': 'glass1', 'cloth': 'cloth1_1', 'shoes': 'shoes1'}}
looks['rafa_new'] = {'slots': {'hairHat': 'hairhat36_npc_rafa', 'cloth': 'cloth1_1_npc_rafa', 'shoes': 'shoes4'}}
looks['rafa_hat_only'] = {'slots': {'hairHat': 'hairhat36_npc_rafa', 'cloth': 'cloth1_1', 'shoes': 'shoes4'}}
npcs = json.loads((runtime / 'assets/p0/outpost_npcs.json').read_text())['npcs']
looks['ama'] = {'slots': npcs['ama']['slots']}
looks['pip'] = {'slots': npcs['res_pip']['slots']}
(out / 'looks-phase1.json').write_text(json.dumps(looks, indent=2) + '\n')
(out / 'script-provenance.json').write_text(json.dumps(hashes, indent=2) + '\n')
print('BATCH3_REVIEW_STAGED', out)
