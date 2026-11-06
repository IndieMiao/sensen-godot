"""v1.1: patch COLOR_0 RGB only from the accepted v1 blobs; geometry stays exact."""
from pathlib import Path
import json,struct,hashlib,subprocess

ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/landmarks/_shared/street_kit'
BASE='76a13070d750fe3ded43372e6edb897fadc38506'
MAPPING={'BB8B52':'A3815D','D0A56C':'B89972','9A7046':'795F47'}
def linear(h):
 return tuple(x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in [v/255 for v in bytes.fromhex(h)])
def original(path):return subprocess.check_output(['git','show',BASE+':'+str(path.relative_to(ROOT))],cwd=ROOT)
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','base':BASE,'mapping_srgb':MAPPING,'assets':{}}
m=json.loads((KIT/'kit_manifest.json').read_text());m['revision']='v1.1'
for name in ['bench_wood','umbrella_table']:
 path=KIT/(name+'.glb');old=original(path);raw=bytearray(old);json_length=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+json_length]);start=28+json_length
 prim=d['meshes'][0]['primitives'][0];a=d['accessors'][prim['attributes']['COLOR_0']];view=d['bufferViews'][a['bufferView']]
 kind=a['componentType'];size={5121:1,5123:2,5126:4}[kind];code={5121:'B',5123:'H',5126:'f'}[kind];norm={5121:255,5123:65535,5126:1}[kind]
 stride=view.get('byteStride',size*int(a['type'][-1]));offset=start+view.get('byteOffset',0)+a.get('byteOffset',0)
 allowed=set();counts={h:0 for h in MAPPING};unchanged=0
 for i in range(a['count']):
  pos=offset+i*stride;rgb=tuple(x/norm for x in struct.unpack_from('<'+code*3,old,pos))
  source=next((h for h in MAPPING if max(abs(x-y) for x,y in zip(rgb,linear(h)))<.0001),None)
  if source is None:unchanged+=1;continue
  target=linear(MAPPING[source]);values=target if kind==5126 else tuple(round(x*norm) for x in target)
  struct.pack_into('<'+code*3,raw,pos,*values);allowed.update(range(pos,pos+size*3));counts[source]+=1
 assert sum(counts.values())>0
 assert len(old)==len(raw) and all(x==y or i in allowed for i,(x,y) in enumerate(zip(old,raw)))
 path.write_bytes(raw);digest=hashlib.sha256(raw).hexdigest();m['assets'][name]['sha256']=digest
 report['assets'][name]={'before_sha256':hashlib.sha256(old).hexdigest(),'after_sha256':digest,'matched_vertices_by_old_srgb':counts,'unchanged_other_colour_vertices':unchanged,'only_COLOR_0_RGB_bytes_changed':True,'JSON_geometry_normals_indices_alpha_unchanged':True,'triangles':m['assets'][name]['triangles']}
for role,h in zip(['furniture_wood','furniture_wood_light','furniture_wood_dark'],MAPPING.values()):m['palette_srgb'][role]=h
(KIT/'kit_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
pal=json.loads((KIT/'palette.json').read_text());pal['colors_srgb']=m['palette_srgb'];pal['furniture_wood_override']={'modules':['bench_wood','umbrella_table'],'source':'Shangguan Waner dispatch / Liubei #830 v1.1','wood':'A3815D','light':'B89972','dark':'795F47','other_materials':'unchanged'}
(KIT/'palette.json').write_text(json.dumps(pal,ensure_ascii=False,indent=2)+'\n')
for path in KIT.glob('*.glb.import'):assert path.read_bytes()==original(path),path
for path in KIT.glob('*.glb'):
 if path.stem not in report['assets']:assert path.read_bytes()==original(path),path
report['all_16_imports_byte_identical']=True;report['other_14_glbs_byte_identical']=True;report['passed']=True
out=ROOT/'output/street-kit-429';(out/'wood-colour-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
