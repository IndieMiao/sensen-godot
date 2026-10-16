#!/usr/bin/env python3
"""215 layout assembly. --preview writes an isolated layout; never edits anchors."""
import json,subprocess,argparse,copy,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];KIT=ROOT/'assets/rooms/post_office';BASE='4c287f6d27bf399ee1661c86a6fee5f9ef0fa056'
p=argparse.ArgumentParser();p.add_argument('--preview',action='store_true');args=p.parse_args()
layout=json.loads(subprocess.check_output(['git','show',BASE+':assets/rooms/post_office/layout.json'],cwd=ROOT));stats=json.loads(subprocess.check_output(['git','show',BASE+':assets/rooms/post_office/asset_stats.json'],cwd=ROOT));contract=json.loads((ROOT/'tools/art/source/post_215/contract.json').read_text())
removed={'counter_computer','magazine_rack','front_floor_runner','world_map'}
layout['assets']=[a for a in layout['assets'] if a['name'] not in removed];by={a['name']:a for a in layout['assets']}
def add(name,file,at,yaw=0,colliders=[],scale=None,material='plain'):
 row={'name':name,'file':file+'.glb','position':at,'yaw_degrees':yaw,'colliders':colliders,'material':material,'cast_shadow':True}
 if scale is not None:row['scale']=scale
 layout['assets'].append(row);by[name]=row;return row
def inst(name,asset,at,yaw=0):layout['instances'].append({'name':name,'asset':asset,'position':at,'yaw_degrees':yaw})
# Keep approved runtime placement of the fee board. Program must remove the
# duplicate anchors.props entry when adopting this self-contained layout.
add('fare_board','fare_board',[-3.208,1.65,-1.65],90)
by['packing_dressing']['file']='packing_dressing_215.glb'
add('stamp_desk_set','stamp_desk_set',[.10,1.122,1.60])
add('post_table_lamp','post_table_lamp',[-1.49,1.397,-.52])
# Two new fixtures + accepted door sconce = exactly three wall lights.
add('post_wall_lantern','post_wall_lantern',[-2.65,2.78,-2.875])
inst('post_wall_lantern_right','post_wall_lantern',[2.98,2.95,-2.875])
layout['review_lighting']['points'].extend([{'position':[-2.65,2.68,-2.48],'energy':.22,'color':'FFE1A2','range':1.35},{'position':[2.98,2.85,-2.48],'energy':.22,'color':'FFE1A2','range':1.35},{'position':[-1.49,1.71,-.52],'energy':.12,'color':'FFE1A2','range':.85}])
# Main daylight/ambient are unchanged.
add('brown_parcel_left','brown_parcel_reused',[-1.70,.084,2.85],0,[{'at':[0,.19,0],'size':[.51,.39,.44]}])
inst('blue_parcel_left','blue_parcel_door',[-1.70,.468,2.85],0)
add('blue_parcel_door','blue_parcel_reused',[-2.82,.084,.43],90,[{'at':[0,.156,0],'size':[.646,.313,.478]}])
inst('brown_parcel_door','brown_parcel_left',[-2.82,.084,-.10],90)
# Original under-shelf sacks stay; one derived bag completes the front pile.
for plant in layout['shared_plants']:
 if plant['name']=='door_floor_greenery':plant['position']=[2.08,.083,2.70]
# Authorized by 上官婉儿: original desk moved left; its GLB stays exact.
new=[-1.0,.082,2.20];delta=[new[0]-.31,0,new[2]-1.64]
by['packing_table']['position']=new
by['packing_dressing']['position']=delta
by['stamp_desk_set']['position']=[a+b for a,b in zip(by['stamp_desk_set']['position'],delta)]
by['packing_stool']['position']=[-1.0,.087,1.15]
by['brown_parcel_left']['position']=[-2.75,.084,2.34]
by['blue_parcel_door']['position']=[-2.75,.084,.25]
for row in layout['instances']:
 if row['name']=='blue_parcel_left':row['position']=[-2.75,.468,2.34];row['yaw_degrees']=90
 elif row['name']=='brown_parcel_door':row['position']=[-2.75,.084,-.42]
add('mail_sack_left','mail_sack_reused',[-2.75,.082,2.81],0,[{'at':[0,.49,0],'size':[.46,.984,.46]}],scale=[.60,.60,.60])
add('compass_rug','compass_rug',[1.40,.083,1.15])
anchors=json.loads(subprocess.check_output(['git','show','f8c3391c:assets/p0/outposts/post.anchors.json'],cwd=ROOT))['anchors'];suggestions={a['name']:copy.deepcopy(a) for a in anchors}
suggestions['npc_pip'].update(position=[-1.03,.08,2.80],yaw_degrees=180)
suggestions['stand_pip'].update(position=[-.45,.08,2.70],yaw_degrees=90)
suggestions['npc_sam'].update(position=[2.45,.08,.85],yaw_degrees=180)
suggestions['stand_sam'].update(position=[1.75,.08,.85],yaw_degrees=-90)
suggestions['npc_pip']['position']=[-2.10,.08,1.20];suggestions['stand_pip']['position']=[-1.65,.08,.70]
suggestions['use_stamp_desk']['position']=[-1.0,1.10,2.20]
layout['suggested_anchors']=suggestions;layout['spawn']=suggestions['spawn']['position']
layout['revision_215']={'base_commit':BASE,'runtime_reference':'f8c3391c8c0606ae664fb8e06ad85068aa199f69','atlas_changed_regions':[],'desk_option':'left','desk_relocation_authorized':True,'removed_from_layout':sorted(removed),'map_choice':'Omitted: left wall already contains fare board/postal sign, door and notices; existing packing table is not on that wall. Fare board preserved at exact approved runtime position.','lights':'Existing door sconce plus two new wall lanterns, plus counter table lamp; daylight remains dominant.','dressing':'Keep under-desk boxes and airmail; replace the mat with identical-size clean swatch geometry to remove baked ghosts from the removed parcel/scale/tools, without touching atlas pixels.','anchor_handoff':'Suggestions only. Remove duplicate fare_board from post.anchors.json props when adopting layout; preserve use_fee_board and exact board placement.'}
# Stats are measured from the actual files rather than copied stale totals.
import sys
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
rows={}
for r in layout['assets']:
 name=Path(r['file']).stem
 if name in rows:continue
 d,b=load_glb(KIT/r['file']);pr=[p for m in d['meshes'] for p in m['primitives']]
 rows[name]={'name':name,'vertices':sum(d['accessors'][p['attributes']['POSITION']]['count'] for p in pr),'triangles':sum(d['accessors'][p['indices']]['count']//3 for p in pr),'surfaces':len(pr),'bytes':(KIT/r['file']).stat().st_size}
local=sum(rows[Path(r['file']).stem]['triangles'] for r in layout['assets']);surfaces=sum(rows[Path(r['file']).stem]['surfaces'] for r in layout['assets'])
for r in layout['instances']:local+=rows[Path(by[r['asset']]['file']).stem]['triangles'];surfaces+=rows[Path(by[r['asset']]['file']).stem]['surfaces']
shared=sum(next(a['triangles'] for a in stats['shared_assets'] if a['name']==Path(r['file']).stem) for r in layout['shared_plants'])
stats.update(assets=list(rows.values()),unique_triangles=sum(r['triangles'] for r in rows.values()),local_scene_triangles=local,shared_scene_triangles=shared,scene_triangles=local+shared,static_draw_surfaces=surfaces+len(layout['shared_plants']),placed_instances=len(layout['assets'])+len(layout['instances'])+len(layout['shared_plants']),glb_bytes=sum(r['bytes'] for r in rows.values()),revision='SGODOT-215',materials=len({r['material'] for r in layout['assets']})+1,budget_passed=local+shared<=200000 and surfaces+len(layout['shared_plants'])<=60)
out=ROOT/'output/post-215/preview' if args.preview else KIT;out.mkdir(exist_ok=True)
(out/'layout.json').write_text(json.dumps(layout,indent=2)+'\n');(out/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n');print('approved left desk',stats['scene_triangles'],stats['static_draw_surfaces'])
