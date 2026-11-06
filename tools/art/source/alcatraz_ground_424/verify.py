"""Audit palette eligibility, untouched host bytes, sampler budget and imports."""
from pathlib import Path
import hashlib, json, sys, subprocess
import numpy as np
from PIL import Image
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
sys.path.insert(0,str(SRC.parent/'alcatraz_foam_424'))
from geometry import read_glb
ASSET=ROOT/'assets/landmarks/alcatraz_island/ground'
OUT=ROOT/'output/alcatraz-ground-424'
HOST='bf0c31b1c871011008b455434d167224d14de59c'
checks=[]
def check(ok,name):
 checks.append({'passed':bool(ok),'check':name})
 if not ok:raise AssertionError(name)
def linear(h):
 s=np.array([int(h[i:i+2],16)/255 for i in (0,2,4)])
 return np.where(s<=.04045,s/12.92,((s+.055)/1.055)**2.4)
def main():
 p=json.loads((SRC/'reference/palette.json').read_text())['colors']
 records={};preserved={}
 for name in ['alc_ground_dock','alc_ground_terraces','alc_ground_summit','dock']:
  path=OUT/'project/assets/landmarks/alcatraz_island'/(name+'.glb')
  g,prims=read_glb(path);check(len(prims)==1,name+': one original surface')
  q=prims[0];colors=q['COLOR_0'][:,:3]
  candidates=['wood','wood_light','wood_dark'] if name=='dock' else ['garden','garden_dark','garden_light','road']
  masks=np.array([np.linalg.norm(colors-linear(p[k]),axis=1)<.012 for k in candidates])
  check((masks.sum(0)<=1).all(),name+': palette classes do not overlap')
  srgb=np.where(colors<=.0031308,colors*12.92,1.055*colors**(1/2.4)-.055)
  decoded=[''.join('%02X'%v for v in row) for row in np.rint(srgb*255).astype(int)]
  eligible=np.array([h in [p[k] for k in candidates] for h in decoded])
  check(np.array_equal(eligible,masks.any(0)),name+': no cliff/wall/soil/cap colours selected')
  normals=q['NORMAL'];top=normals[:,1]>.98
  if name=='dock':top&=abs(q['POSITION'][:,1])<.015
  record={'triangles':len(q['indices'])//3,'eligible_top_vertices':{},'unchanged_other_vertices':int((~(eligible&top)).sum())}
  for k,mask in zip(candidates,masks):
   record['eligible_top_vertices'][k]=int((mask&top).sum())
  check((eligible&top).any(),name+': detail applies to actual top geometry')
  records[name]=record
 # Every staged owner asset plus scene is byte identical, including GLB UVs,
 # water shader, navigation JSON, lighting and camera code.
 names=subprocess.check_output(['git','ls-tree','-r','--name-only',HOST,
  'assets/landmarks/alcatraz_island','scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.tscn'],cwd=ROOT).decode().splitlines()
 for rel in names:
  if rel.endswith('.import'):continue # engine may refresh imports, not source assets
  original=subprocess.check_output(['git','show',HOST+':'+rel],cwd=ROOT)
  check(original==(OUT/'project'/rel).read_bytes(),rel+': owner bytes preserved')
  preserved[rel]=hashlib.sha256(original).hexdigest()
 textures={}
 for path in ASSET.glob('*.png'):
  im=Image.open(path);check(im.size==(1024,1024) and im.mode=='RGB',path.name+': 1024 RGB data')
  imp=path.with_suffix('.png.import').read_text()
  check('uid="uid://' in imp and 'mipmaps/generate=true' in imp and 'compress/mode=2' in imp,path.name+': engine UID, mips, VRAM compression')
  textures[path.name]={'size':list(im.size),'channels':'RGB data / linear','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'png_bytes':path.stat().st_size}
 check(len(textures)==2,'exactly two textures')
 shader=(ASSET/'alc_ground_detail.gdshader').read_text()
 check(shader.count('uniform sampler2D')==2,'two sampler bindings')
 check(all(s not in shader for s in ['TIME','NORMAL_MAP','DEPTH','ALPHA =','SCREEN_TEXTURE','UV.']),'static opaque, no depth/normal/UV/screen pass')
 report={'passed':True,'host_commit':HOST,'checks':checks,'palette_regions':records,'textures':textures,'preserved_host_sha256':preserved,
 'scope':'optional materials only; host source archived solely into ignored QA project'}
 (OUT/'source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
 print(len(checks),'asset/source checks passed')
if __name__=='__main__':main()
