"""Build an owned handoff table from the approved pinned layout, never edit it."""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;KIT=ROOT/'assets/landmarks/alcatraz_island'
REF='34df9c0b6af42a85567dfb5318c6717f929a4ab8'
raw=subprocess.check_output(['git','show',REF+':assets/landmarks/alcatraz_island/layout.json'],cwd=ROOT);layout=json.loads(raw)
names={'alc_lighthouse','alc_watertower','alc_far_bridge','alc_far_city','alc_far_hills'}
cards={n for n in names if n.startswith('alc_far_')};rows=[]
for p in layout['placements']:
 if p['asset'] not in names:continue
 row={k:p[k] for k in ['asset','zone','position','rotation_degrees','scale','collision']}
 row['owner']='黄忠';row['single_lod']=p['asset'] in cards
 if not row['single_lod']:
  row['far_asset']=p['asset']+'_far';row['switch_distance_m']=55;row['margin_m']=0
 else:row['host_depth_fraction']=.94 if p['asset']=='alc_far_bridge' else .96 if p['asset']=='alc_far_city' else .98
 rows.append(row)
data={'task':'SGODOT-424','revision':'v1.1','author':'黄忠','source_commit':REF,'source_layout_sha256':hashlib.sha256(raw).hexdigest(),
 'coordinate_system':layout['axes'],'spawn':layout['spawn'],'camera':layout['camera'],'far_anchor':layout['far_anchor'],'far_zone':layout['far_zone'],
 'zone_transform':'identity in pinned scene; placements are already in world coordinates; do not add far_anchor twice',
 'depth_note':'layout declares render_depth_fraction 0.92; pinned host shader binding uses bridge .94 / city .96 / hills .98; review preserves host code exactly',
 'placements':rows,'single_card_lod_agreement':'SGODOT-424 comment 6b09d152-58e2-4deb-bc6f-b7e51d760471 (Marco Polo)',
 'host_layout_edit':'Remove lod_group from the three far-card placements and remove those three card lod_groups; keep both tower pairs at 55 m.'}
(KIT/'alc_far_placement.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
p=KIT/'alc_far_manifest.json';m=json.loads(p.read_text());m['revision']='v1.1';m['placement_status']='aligned with 34df9c0b; cards single LOD';m['placement_file']='alc_far_placement.json'
m['card_names']=['alc_far_city','alc_far_bridge','alc_far_hills'];m['card_lod_count']=1
for name,spec in m['assets'].items():
 spec['source']='tools/art/source/alcatraz_far_424/'+name+'.blend'
 prov=SRC/'modules'/name/'reuse_provenance.json'
 d=json.loads(prov.read_text());d['source']=spec['source'];d['module']=name
 if name in cards:d['changes']='v1.1: align final name and XY silhouette size to #792 34df9c0b; front-only colour geometry projected to Z=0; no baked world placement.'
 prov.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
p.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
print('Aligned',len(rows),'placements with',REF)
