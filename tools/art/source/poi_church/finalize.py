"""Bind every module to one external atlas, audit GLBs, count placed geometry."""
from pathlib import Path
import json,hashlib,sys
import numpy as np
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/rooms/poi_church';SRC=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/art'));sys.path.insert(0,str(ROOT/'tools/art/source/tea_house'))
from verify_chef_sign import load_glb,accessor
from finalize_atlas import write_glb
def main():
 layout=json.loads((KIT/'layout.json').read_text());stats=[]
 for spec in layout['assets']:
  path=KIT/spec['file'];doc,blob=load_glb(path)
  doc['images']=[{'uri':'room_albedo_ao.png'}];doc['textures']=[{'source':0,'sampler':0}]
  doc['samplers']=[{'magFilter':9729,'minFilter':9987,'wrapS':33071,'wrapT':33071}]
  mat={'name':'Church_'+spec['material'],'pbrMetallicRoughness':{'baseColorFactor':[1,1,1,.28 if spec['material']=='light_patch' else 1], 'baseColorTexture':{'index':0},'metallicFactor':0,'roughnessFactor':.88}}
  if spec['material']=='light_patch':mat.update(alphaMode='BLEND',doubleSided=True)
  if spec['material']=='cloth':mat['doubleSided']=True
  if spec['material']=='glass':mat.update(emissiveFactor=[.16,.16,.16],emissiveTexture={'index':0})
  doc['materials']=[mat];pts=[];tris=0
  for m in doc['meshes']:
   m['name']=spec['name']+'_mobile'
   for prim in m['primitives']:
    prim['material']=0;pts.extend(accessor(doc,blob,prim['attributes']['POSITION']));tris+=len(accessor(doc,blob,prim['indices']))//3
  write_glb(path,doc,blob);pts=np.array(pts)
  stats.append({'name':spec['name'],'file':spec['file'],'triangles':tris,'surfaces':sum(len(m['primitives']) for m in doc['meshes']),'bounds':[pts.min(0).tolist(),pts.max(0).tolist()],'dimensions_m':np.ptp(pts,axis=0).tolist(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
 by={a['name']:a for a in stats};placed=[a['name'] for a in layout['assets'] if not a['review_only']]+[a['asset'] for a in layout['instances']];plants={a['name'] for a in layout['assets'] if a['vegetation']}
 result={'assets':stats,'scene_triangles':sum(by[n]['triangles'] for n in placed),'static_draw_surfaces':sum(by[n]['surfaces'] for n in placed),'plant_triangles':sum(by[n]['triangles'] for n in placed if n in plants),'placed_modules':len(placed),'unique_triangles':sum(a['triangles'] for a in stats),'atlas':{'size':[2048,2048],'file':'room_albedo_ao.png','purpose':'shared baked albedo and subtle contact AO'},'limits':{'triangles':200000,'surfaces':60,'plant_triangles':100000}}
 assert result['scene_triangles']<=200000 and result['static_draw_surfaces']<=60 and result['plant_triangles']<=100000
 (KIT/'asset_stats.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({k:v for k,v in result.items() if k!='assets'},indent=2))
if __name__=='__main__':main()
