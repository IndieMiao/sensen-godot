#!/usr/bin/env python3
"""Remove ten modeled letters and bypass their baked AO using clean plaque UVs.
Blender background. Reads the accepted baseline so repeat runs are idempotent.
"""
from pathlib import Path
import hashlib,json,struct,subprocess,sys
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb,accessor

ROOT=Path(__file__).resolve().parents[2]
BASE='4c287f6d27bf399ee1661c86a6fee5f9ef0fa056'
KIT=ROOT/'assets/rooms/post_office'
SRC=ROOT/'tools/art/source/post_215'
OUT=ROOT/'output/post-215'

def main():
 raw=subprocess.check_output(['git','show',BASE+':assets/rooms/post_office/post_office_sign.glb'],cwd=ROOT)
 original=OUT/'original_post_office_sign.glb';original.write_bytes(raw)
 doc,blob=load_glb(original);pr=doc['meshes'][0]['primitives'][0]
 vertices=accessor(doc,blob,pr['attributes']['POSITION'])
 indices=[v[0] for v in accessor(doc,blob,pr['indices'])]
 # Source object Bold sign POST OFFICE occupies this isolated front lower band.
 is_letter=[-.166<y<.070 and .086<z<.098 for x,y,z in vertices]
 keep=[];removed=[]
 for i in range(0,len(indices),3):
  tri=indices[i:i+3]
  assert all(is_letter[j] for j in tri) or not any(is_letter[j] for j in tri)
  (removed if is_letter[tri[0]] else keep).extend(tri)
 assert len(removed)//3==7460 and len(keep)//3==776
 used=sorted(set(keep));remap={old:new for new,old in enumerate(used)}
 packed=bytearray();views=[];accessors=[];attrs={}
 def append(data,kind,component,count,minmax=None):
  while len(packed)%4:packed.append(0)
  views.append({'buffer':0,'byteOffset':len(packed),'byteLength':len(data)})
  packed.extend(data);a={'bufferView':len(views)-1,'componentType':component,'count':count,'type':kind}
  if minmax:a.update(min=minmax[0],max=minmax[1])
  accessors.append(a);return len(accessors)-1
 for name,ai in pr['attributes'].items():
  a=doc['accessors'][ai];view=doc['bufferViews'][a['bufferView']]
  assert a['componentType']==5126
  width={'VEC2':2,'VEC3':3}[a['type']]*4
  start=view.get('byteOffset',0)+a.get('byteOffset',0);stride=view.get('byteStride',width)
  data=b''.join(struct.pack('<ff',690.5/2048,1259.5/2048) if name=='TEXCOORD_0' and vertices[i][2]<.075 else blob[start+i*stride:start+i*stride+width] for i in used)
  mm=[[min(vertices[j][i] for j in used) for i in range(3)],[max(vertices[j][i] for j in used) for i in range(3)]] if name=='POSITION' else None
  attrs[name]=append(data,a['type'],5126,len(used),mm)
 pr['attributes']=attrs
 pr['indices']=append(struct.pack('<'+'I'*len(keep),*(remap[i] for i in keep)),'SCALAR',5125,len(keep))
 while len(packed)%4:packed.append(0)
 doc['bufferViews']=views;doc['accessors']=accessors;doc['buffers']=[{'byteLength':len(packed)}]
 j=json.dumps(doc,separators=(',',':')).encode();j+=b' '*((-len(j))%4)
 target=KIT/'post_office_sign.glb'
 target.write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(packed))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(packed),0x004e4942)+packed)
 # Keep the original named editable plaque and emblem; no rebake or atlas writes.
 bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/art/source/post_office/post_office.blend'))
 collection=bpy.data.collections['KIT_post_office_sign']
 retained=set(collection.objects)
 for obj in list(bpy.data.objects):
  if obj not in retained or obj.name=='Bold sign POST OFFICE':bpy.data.objects.remove(obj,do_unlink=True)
 for c in list(bpy.data.collections):
  if c!=collection:bpy.data.collections.remove(c)
 # Red body samples its own clean upper-left atlas patch; no pixels are edited.
 plaque=bpy.data.objects['Arched deep red postal wall sign']
 uv=plaque.data.uv_layers.active or plaque.data.uv_layers.new(name='RoomAtlas')
 for loop in uv.data:loop.uv=(690.5/2048,1-1259.5/2048)
 mat=bpy.data.materials.new('RoomKit_SharedAtlas_CleanRed');mat.use_nodes=True
 bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.8
 im=mat.node_tree.nodes.new('ShaderNodeTexImage');im.image=bpy.data.images.load(str(KIT/'room_albedo_ao.png'));im.image.filepath='//../../../../assets/rooms/post_office/room_albedo_ao.png'
 mat.node_tree.links.new(im.outputs['Color'],bs.inputs['Base Color']);plaque.data.materials.clear();plaque.data.materials.append(mat)
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'post_office_sign.blend'))
 report={'baseline':BASE,'removed_object':'Bold sign POST OFFICE','removed_letter_components':10,'removed_triangles':len(removed)//3,'remaining_triangles':len(keep)//3,'retained_vertex_attributes':'Original POSITION / NORMAL bytes; envelope UV unchanged, red plaque UV redirected to its own clean upper-left color patch to bypass baked lettering AO','clean_red_pixel_top_left':[690,1259],'clean_red_gltf_uv':[690.5/2048,1259.5/2048],'atlas_changed_regions':[],'atlas_changed_pixels':0,'atlas_sha256':hashlib.sha256((KIT/'room_albedo_ao.png').read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
 (SRC/'sign-revision.json').write_text(json.dumps(report,indent=2)+'\n')
 print('POST_SIGN',json.dumps(report),flush=True)

if __name__=='__main__':
 main()
 if '--verify-repeat' in sys.argv:
  def hashes():return {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in KIT.glob('*.glb')}
  before=hashes();atlas=hashlib.sha256((KIT/'room_albedo_ao.png').read_bytes()).hexdigest()
  main();after=hashes()
  assert before==after and atlas==hashlib.sha256((KIT/'room_albedo_ao.png').read_bytes()).hexdigest()
  result={'command':'revise_post_sign_215.py -- --verify-repeat','checked_glbs':len(before),'all_glbs_byte_identical_after_repeat':True,'atlas_byte_identical':True,'sign_sha256':after['post_office_sign.glb'],'scope':'v1.2 sign revision repeated; previous eight-asset generation evidence retained in v1.1'}
  (OUT/'sign-reproducibility.json').write_text(json.dumps(result,indent=2)+'\n')
  print('POST_SIGN_REPEAT',json.dumps(result),flush=True)
