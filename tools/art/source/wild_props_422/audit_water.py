"""Read-only water/shore preservation check, both repository and isolated b1 review."""
from pathlib import Path
import hashlib,json,subprocess
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/wild-422'
BASE='93befb18cd5af7e30a966d2c112279287b71b3e2';RUNTIME='a43500f36c1b5a13729187c686e0f68a2011fbad'
def protected(path):
 return (path.startswith(('assets/ponds/','assets/farm/art/water/','modules/fishing/')) or
  path in ['modules/ponds/pond_water.gdshader','modules/ponds/pond_ground.gdshader','modules/ponds/pond_lily.gdshader','scenes/p0/p0_pond.gd']) and not path.endswith(('.import','.uid'))
def audit(ref,folder):
 rows=[]
 paths=subprocess.check_output(['git','ls-tree','-r','--name-only',ref],cwd=ROOT,text=True).splitlines()
 for path in paths:
  if not protected(path):continue
  source=subprocess.check_output(['git','show',ref+':'+path],cwd=ROOT)
  actual=(folder/path).read_bytes();assert actual==source, 'water/shore source changed: '+str(folder/path)
  rows.append({'path':path,'sha256':hashlib.sha256(actual).hexdigest()})
 assert any(r['path']=='assets/farm/art/water/surface_flow.png' for r in rows)
 assert any(r['path']=='modules/ponds/pond_ground.gdshader' for r in rows)
 return {'reference':ref,'files_checked':len(rows),'files':rows,'all_byte_identical':True}
def main():
 report={'author':'赵云','passed':True,'repository':audit(BASE,ROOT),'isolated_b1':audit(RUNTIME,QA/'project'),
  'scope':'Source water/shore code, full pond_ground shader, water/shore textures and original P0Pond light/material setup. Godot-generated cache/import metadata is not substituted for source identity.'}
 (QA/'water-preservation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print('WATER_PRESERVED',report['repository']['files_checked'],report['isolated_b1']['files_checked'])
if __name__=='__main__':main()
