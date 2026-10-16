#!/usr/bin/env python3
"""Collect only final rendered media + validation, not draft layouts or secrets."""
from pathlib import Path
import json,shutil,hashlib
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/post-215';DOC=ROOT/'docs/design/post-215-2026-10-16';DOC.mkdir(exist_ok=True)
for name in ['post_gameplay_43deg_360','post_full_room_360','post_full_room_panorama','post_stamp_desk_detail','post_npc_positions_360','post_npc_positions_panorama']:
 src=OUT/'captures'/(name+'.png');shutil.copy2(src,DOC/('SGODOT-215_POST_v1_'+name+'.png'))
report={'glb':json.loads((OUT/'glb-validation-left.json').read_text()),'godot':json.loads((OUT/'captures/godot-validation.json').read_text()),'reproducibility':json.loads((OUT/'reproducibility.json').read_text())}
assert not report['glb']['failures'] and not report['godot']['failures']
report['total_checks']=len(report['glb']['checks'])+len(report['godot']['checks']);report['atlas_changed_regions']=[]
report['media']={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.glob('SGODOT-215_POST_v1_*.png'))}
(DOC/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print('POST_215_PACKAGE',report['total_checks'],'checks',len(report['media']),'PNGs')
