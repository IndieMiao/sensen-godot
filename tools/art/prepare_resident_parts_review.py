#!/usr/bin/env python3
"""Prepare local-only review inputs; supplied portrait baker is never committed."""
import argparse,json,shutil,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/resident-parts-284'
p=argparse.ArgumentParser();p.add_argument('--bake-script',type=Path,default=Path.home()/'incoming/resident-parts/bake_resident_portraits.gd');p.add_argument('--tomo',action='store_true',help='Prepare only the Tomo increment in its own output directory');p.add_argument('--project-root',type=Path,default=ROOT,help='Runtime checkout containing the assets');p.add_argument('--out',type=Path,help='Output directory relative to project root');args=p.parse_args()
ROOT=args.project_root.resolve();OUT=ROOT/'output/resident-parts-284'
if args.tomo:OUT=ROOT/'output/resident-parts-284-tomo'
if args.out:OUT=ROOT/args.out
OUT.mkdir(parents=True,exist_ok=True);(ROOT/'output/.gdignore').touch()
# An offline, separate user-data directory for the existing game autoloads.
override='[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SensenResident284QA"\n[sensen]\nnetwork/base_url="http://127.0.0.1:9/v1"\nnetwork/mobile_base_url="http://127.0.0.1:9/v1"\n'
override_path=ROOT/'override.cfg'
if override_path.exists() and override_path.read_text()!=override:raise RuntimeError('Preserve existing override.cfg; use an isolated worktree for this review')
override_path.write_text(override)

looks={
 'res_granny_wu':{'slots':{'hairHat':'hairhat80_npc_granny_wu','cloth':'cloth11','shoes':'shoes5'}},
 'res_ivo':{'slots':{'hairHat':'hairhat_npc_ivo','mask':'mask16_npc_ivo','cloth':'cloth1_npc_ivo','shoes':'shoes3'}}}
if args.tomo:looks={'res_tomo':{'slots':{'hairHat':'hairhat0_npc_tomo','glass':'glass0','cloth':'cloth0','shoes':'shoes2','messengerBag':'messengerbag3'}}}
(OUT/'looks-new.json').write_text(json.dumps(looks,indent=2)+'\n')
npcs={k:{**v,'name':{'res_granny_wu':'Granny Wu','res_ivo':'Ivo','res_tomo':'Tomo'}[k],'scale':1.0} for k,v in looks.items()}
(OUT/'lineup-fixture.json').write_text(json.dumps({'npcs':npcs},indent=2)+'\n')
source=ROOT/'tools/dev/npc_lineup.gd';s=source.read_text()
s=s.replace('const NPCS_PATH := "res://assets/p0/outpost_npcs.json"',f'const NPCS_PATH := "res://{OUT.relative_to(ROOT)}/lineup-fixture.json"')
s='\n'.join(line for line in s.splitlines() if not line.startswith('\tcast.append({"id": "player"'))+'\n'
s=s.replace('\t\trig.play_motion("idle")','\t\trig.play_motion("idle")\n\t\tvar ap = rig.get_node("AnimationPlayer")\n\t\tap.seek(0.0, true)\n\t\tap.pause()')
s=s.replace('Vector3(0.0, 1.0, 3.2), Vector3(1.9, 1.0, 2.6)','Vector3(0.0, 1.0, 3.5), Vector3(2.078125, 1.0, 2.84375)').replace('Vector3(0.0, 0.95, 0.0)','Vector3(0.0, 0.90, 0.0)')
s='\n'.join('\t\tvar parts := "silver bun / green apron / cream shoes" if entry.id=="res_granny_wu" else "miner helmet / canvas shirt / black boots"' if l.startswith('\t\tvar parts := ') else l for l in s.splitlines())+'\n'
if args.tomo:
 s='\n'.join('\t\tvar parts := "warm brown hair / glasses / white T / camera bag"' if l.startswith('\t\tvar parts := ') else l for l in s.splitlines())+'\n'
 s=s.replace('var cols := 2','var cols := 1')
(OUT/'npc_lineup_284.gd').write_text(s)
dest=ROOT/'tools/art/bake_resident_portraits.gd'
if dest.exists() and dest.read_bytes()!=args.bake_script.read_bytes():raise RuntimeError('Preserve existing portrait baker: file differs from supplied script')
shutil.copy2(args.bake_script,dest)
(OUT/'review-script-provenance.json').write_text(json.dumps({'lineup_source':'tools/dev/npc_lineup.gd','lineup_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'lineup_fixture_sha256':hashlib.sha256(s.encode()).hexdigest(),'portrait_baker_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'portrait_baker_committed':False,'lineup_changes':[f'{len(looks)} resident looks from fixture, no player column','Freeze idle at zero for open eyes','Camera distance 3.5 m and target Y 0.90 for complete feet','Short readable captions']},indent=2)+'\n')
print('Prepared',len(looks),'resident fixture and uncommitted portrait baker')
