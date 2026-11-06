"""Replace the 114 owner placeholders from #792 v6; never append a second scatter."""
from pathlib import Path
import json,copy,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'assets/landmarks/alcatraz_island'
BASE='b16c31982f34a64cdd4f9c6683064edbf20837a0'
def main():
 layout_path=SRC/'reference/blockout_layout.json'
 layout=json.loads(layout_path.read_text());manifest=json.loads((OUT/'alc_nature_manifest.json').read_text())
 points=[];adjustments=[]
 for original in layout['placements']:
  if original.get('owner')!='刘备':continue
  p=copy.deepcopy(original);p['source_name']=original['name'];p['source_asset']=original['asset']
  p['placeholder']=False;p['collision']=False;p['multimesh']=True;p['cast_shadow']=False
  if p['asset']=='alc_shrub':
   # Keep the agreed primary name; the warm variant is explicitly mapped here.
   if int(p['name'].rsplit('_',1)[1])%3==0:p['asset']='alc_shrub_b'
   p['position'][1]-=.035
   p['max_view_width_m']=8.0
  elif p['asset']=='alc_grass_tuft':
   p['position'][1]-=.01
   p['max_view_width_m']=8.0
  if p['name']=='alc_rock_c_003':
   p['asset']='alc_rock_a'
   p['position'][0]=-27.0
  elif p['name']=='alc_rock_a_004':
   p['position'][0]=-29.2
   p['position'][2]=8.5
  if p['position']!=original['position'] or p['asset']!=original['asset']:
   adjustments.append({'source_name':p['source_name'],'before_asset':original['asset'],'after_asset':p['asset'],
    'before_position':original['position'],'after_position':p['position'],
    'reason':'dock opening: replace foreground large rock with small, move west' if p['name']=='alc_rock_c_003' else 'dock opening: move west/south clear of bridge and city strip' if p['name']=='alc_rock_a_004' else 'variant assignment and root seating'})
  points.append(p)
 assert len(points)==114 and len({p['source_name'] for p in points})==114
 result={'task':'SGODOT-424','owner':'刘备','source_layout_commit':BASE,
  'source_layout_sha256':hashlib.sha256(layout_path.read_bytes()).hexdigest(),
  'status':'replacement suggestions; match source_name to existing owner points, never append',
  'supersedes':'179-point proposal in PR801 at 37bbf81de; do not combine both sets',
  'axes':layout['axes'],'sea_y':-.15,'points':points,'navigation_unchanged':True,
  'notes':['Replace each existing owner=刘备 placement by source_name; leave all other placements intact.',
   'Primary shrub is alc_shrub; optional warm variant alc_shrub_b has explicit assignments.',
   'Two dock rocks adjusted: c_003 uses small a at (-27,-.35,11.5); a_004 moves to (-29.2,-.35,8.5). Plant roots embed .035/.01m.',
   'Rocks keep v6 base Y=-.35. No collisions or interactions; disable cast shadows.',
   'Keep v6 foliage visibility rule: hide above 8m view width; whole-island art review shows all.',
   'Re-seat after owner remeshes terrain; retain original navigation.'],
  'adjustments':adjustments}
 result['counts']={n:sum(p['asset']==n for p in points) for n in manifest['assets']}
 result['placed_triangles']=sum(manifest['assets'][p['asset']]['triangles'] for p in points)
 (OUT/'alc_nature_placements.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
 print(result['counts'],result['placed_triangles'])
if __name__=='__main__':main()
