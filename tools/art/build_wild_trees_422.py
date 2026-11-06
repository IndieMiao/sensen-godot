"""Two single decorative trees for 422; original twelve wild props stay byte-identical.

Run through flock ~/gs66-render.lock. Metres / Godot Y-up, bottom-centre pivots.
"""
from pathlib import Path
import hashlib,json,math,struct,sys
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
SRC=ROOT/'tools/art/source/wild_props_422';OUT=ROOT/'assets/farm/art'
PALETTE={'pine_bark':'AD9879','pine_bark_light':'C3AE8D','pine_lower':'496940','pine_mid':'57784A','pine_top':'6A8855',
 'round_bark':'C3AB84','round_bark_light':'D4BF99','round_lower':'89973F','round_mid':'A0AD4A','round_top':'B4BC62'}
def pine_skirt(name,base,radius,height,color,spin):
 n=12
 # Flared lower lip, rounded shoulder and one true apex, avoiding zero-area pole quads.
 profiles=[(.055,0),(radius,.075),(radius*.80,height*.28)]
 points=[(r*math.cos(i*math.tau/n+spin),base+y,r*math.sin(i*math.tau/n+spin)) for r,y in profiles for i in range(n)]
 points.append((0,base+height,0))
 faces=[tuple(reversed(range(n)))]
 for row in range(2):faces.extend((row*n+i,row*n+(i+1)%n,(row+1)*n+(i+1)%n,(row+1)*n+i) for i in range(n))
 faces.extend((2*n+i,2*n+(i+1)%n,3*n) for i in range(n))
 return K.mesh(name,points,faces,color,True)
def pine():
 K.cylinder('Pine / one pale timber trunk',(0,.59,0),.085,1.18,'pine_bark',top=.045,segments=8)
 pine_skirt('Pine / lower flared crown',.57,.58,1.02,'pine_lower',0)
 pine_skirt('Pine / middle flared crown',1.13,.46,.91,'pine_mid',math.pi/12)
 pine_skirt('Pine / pointed upper crown',1.72,.32,.90,'pine_top',0)
def round_tree():
 K.cylinder('Round tree / one pale trunk',(0,.64,0),.075,1.28,'round_bark',top=.050,segments=8)
 for i,tip in enumerate([(-.28,1.40,.04),(.27,1.43,-.06)]):
  K.rod(f'Round tree / crown branch {i+1}',(0,.93,0),tip,.040,'round_bark_light',segments=5,top=.016)
 obj=K.ellipsoid('Round tree / single broad rounded crown',(0,1.66,0),(1.34,1.25,1.22),'round_mid',segments=12,rings=8)
 obj.data.materials.append(K.MATS['round_lower']);obj.data.materials.append(K.MATS['round_top'])
 for face in obj.data.polygons:
  z=sum(obj.data.vertices[i].co.z for i in face.vertices)/len(face.vertices)
  face.material_index=1 if z<-.25 else 2 if z>.40 else 0
def main():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 for role,value in PALETTE.items():
  m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);m.use_nodes=True
  p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18;K.MATS[role]=m
 material=bpy.data.materials.new('Farm matte vertex paint');material.use_nodes=True
 p=material.node_tree.nodes['Principled BSDF'];p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18
 vc=material.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';material.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
 entries={}
 for i,(name,build) in enumerate([('wild_tree_pine',pine),('wild_tree_round',round_tree)]):
  K.begin(name,[1,1],300,generator='tools/art/build_wild_trees_422.py',author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',pivot='footprint bottom centre',purpose='single non-interactive decorative tree',collision='none')
  build();bpy.context.view_layer.update()
  points=[o.matrix_world@v.co for o in K.CURRENT.objects for v in o.data.vertices]
  lo=Vector([min(p[k] for p in points) for k in range(3)]);hi=Vector([max(p[k] for p in points) for k in range(3)])
  offset=Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z))
  for o in K.CURRENT.objects:o.location+=offset
  entry=K.export_asset(name,K.CURRENT,material)
  path=OUT/(name+'.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:]
  doc['meshes'][0]['name']=name+'_mobile';data=json.dumps(doc,separators=(',',':')).encode();data+=b' '*(-len(data)%4)
  path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(data)+len(tail))+struct.pack('<II',len(data),0x4e4f534a)+data+tail)
  entry.update(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source='tools/art/source/wild_props_422/wild_trees.blend',
   palette_srgb={k:v for k,v in PALETTE.items() if k.startswith('pine' if i==0 else 'round')},
   material_contract={'roughness':.9,'metallic':0,'specular':.18,'vertex_color_is_srgb':False},
   silhouette='single trunk, three pointed foliage tiers' if i==0 else 'single pale trunk, one broad rounded crown',
   replacement='pond perimeter decoration only; never substitute Timber/Hardwood resource GLBs')
  entries[name]=entry
  for o in K.CURRENT.objects:o.location.x+=i*2.2
  print('WILD_TREE',name,entry['triangles'],entry['bounds'],flush=True)
 p=OUT/'manifest.json';manifest=json.loads(p.read_text());manifest['assets'].update(entries);p.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 p=SRC/'asset_stats.json';stats=json.loads(p.read_text());stats['assets'].update(entries);p.write_text(json.dumps(stats,ensure_ascii=False,indent=2)+'\n')
 (SRC/'tree_stats.json').write_text(json.dumps({'author':'赵云','assets':entries},ensure_ascii=False,indent=2)+'\n')
 bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'wild_trees.blend'),compress=True)
if __name__=='__main__':main()
