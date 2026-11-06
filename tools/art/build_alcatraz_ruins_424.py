"""Five public heritage ruin detail modules; <=400 triangles and one surface each.
Run under flock ~/gs66-render.lock. Godot metres, Y up, front +Z.
"""
from pathlib import Path
import hashlib,json,math,struct,sys
import bpy
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
SRC=ROOT/'tools/art/source/alcatraz_ruins_424';OUT=ROOT/'assets/landmarks/alcatraz_island'
COLORS={'stone':'D4BF9B','stone_light':'E8D5B2','stone_edge':'BCA581','stone_shade':'AF9875',
 'moss':'829449','moss_light':'9FAC5C','stem':'688248','leaf':'78964C','leaf_light':'9DB15F','leaf_dark':'547339',
 'white':'FFF2D4','yellow':'E9C765','pollen':'C9A74B','plaque_frame':'8F8162','plaque_face':'C8BEA2','plaque_leg':'6E7D6B'}
def ico(name,at,size,color):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1);o=bpy.context.object;o.location=K.v(at);o.scale=(size[0]/2,size[2]/2,size[1]/2)
 return K.finish(o,name,color,True)
def arch():
 # Seven separate voussoirs in a curved fallen fragment, tipped 68deg backwards.
 # It is a horizontal remnant, never a barred or intact doorway.
 rotation=Matrix.Rotation(math.radians(68),4,'X')
 for j in range(7):
  a=math.radians(15+j*19.0+.6);b=math.radians(15+(j+1)*19.0-.6)
  points=[]
  for depth in [-.145,.145]:
   for r,angle in [(1.0,a),(1.34,a),(1.34,b),(1.0,b)]:
    p=rotation@Vector((r*math.cos(angle),r*math.sin(angle),depth));points.append(p)
  o=K.mesh(f'Fallen arch / limestone wedge {j+1}',points,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'stone')
  o.data.materials.append(K.MATS['stone_light']);o.data.materials.append(K.MATS['stone_edge'])
  for p in o.data.polygons:p.material_index=1 if p.index==1 else 2 if p.index in [2,4] else 0
 # Low moss follows the exposed broad top surface, without a soil mound.
 for i,(x,z) in enumerate([(-.68,.88),(.04,1.12),(.62,.95)]):
  a=math.radians(68);y=(z+.145*math.cos(a))/math.tan(a)+.145*math.sin(a)+.008
  ico(f'Arch / weathered moss island {i+1}',(x,y,z),(.23,.045,.14),'moss_light' if i==1 else 'moss')
def slab(name,at,width,depth,height,angle,color):
 c,s=math.cos(angle),math.sin(angle);outline=[(-.50,-.35),(-.12,-.50),(.48,-.28),(.42,.38),(-.30,.47)]
 points=[]
 for y,scale in [(0,1),(height,.88)]:
  for x,z in outline:points.append((at[0]+(x*width*c+z*depth*s)*scale,y,at[2]+(-x*width*s+z*depth*c)*scale))
 n=len(outline);o=K.mesh(name,points,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],color)
 o.data.materials.append(K.MATS['stone_light']);o.data.polygons[1].material_index=1
 return o
def rubble():
 for i,(x,z,w,d,h,a) in enumerate([(-.58,-.30,.44,.36,.105,.2),(-.02,-.38,.36,.28,.075,-.3),(.50,-.24,.45,.30,.12,.65),(-.40,.23,.33,.42,.08,.25),(.10,.18,.46,.33,.10,-.45),(.58,.40,.24,.25,.06,.4),(-.70,.45,.17,.18,.055,-.4)]):
  slab(f'Rubble sheet / separated masonry shard {i+1}',(x,0,z),w,d,h,a,'stone' if i%2 else 'stone_edge')
def vine_leaf(name,c,angle,color):
 c=Vector(c);u=Vector((math.cos(angle),math.sin(angle),0));v=Vector((-u.y,u.x,0))
 outline=[(-.04,0),(.015,.065),(.075,.072),(.145,0),(.075,-.072),(.015,-.065)]
 points=[c+u*x+v*y for x,y in outline]+[c+u*.06+Vector((0,0,.022)),c+u*.06-Vector((0,0,.004))]
 return K.mesh(name,points,[(6,j,(j+1)%6) for j in range(6)]+[(7,(j+1)%6,j) for j in range(6)],color,True)
def vine():
 path=[(0,0,.018),(.10,.38,.018),(-.08,.79,.018),(.08,1.19,.018),(.14,1.64,.018)]
 for i,(a,b) in enumerate(zip(path,path[1:])):K.rod(f'Vine / climbing stem {i+1}',a,b,.009,'stem',segments=3,top=.006)
 for i in range(18):
  y=.12+i*.084;x=.07*math.sin(y*6);side=-1 if i%2 else 1
  vine_leaf(f'Vine / ivy leaf {i+1}',(x,y,.038),math.radians(42 if side>0 else 138),'leaf_light' if i%3==0 else 'leaf' if i%3==1 else 'leaf_dark')
 for i,(a,b) in enumerate([((.02,.48,.018),(-.24,.76,.018)),((.02,1.05,.018),(.30,1.35,.018))]):
  K.rod(f'Vine / side twig {i+1}',a,b,.006,'stem',segments=3,top=.003)
  for j,t in enumerate([.40,.85]):vine_leaf(f'Vine / twig {i+1} leaf {j+1}',Vector(a).lerp(Vector(b),t)+Vector((0,0,.025)),math.radians(135 if i==0 else 40),'leaf_light')
def petal(name,at,angle,color):
 c=Vector(at);u=Vector((math.cos(angle),0,math.sin(angle)));s=Vector((-u.z,0,u.x))
 points=[c+u*.014,c+u*.075+s*.028,c+u*.11,c+u*.075-s*.028,c+u*.055+Vector((0,.017,0))]
 return K.mesh(name,points,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2),(0,2,1)],color,True)
def flowers():
 for i,(x,z,h) in enumerate([(-.24,-.10,.34),(.02,-.18,.46),(.23,.04,.39),(-.12,.18,.26),(.17,.24,.22)]):
  a=Vector((x*.7,0,z*.7));b=Vector((x,h,z));K.rod(f'Ruin wildflower {i+1} / stem',a,b,.006,'stem',segments=3,top=.004)
  # Small ground leaf, using an opaque closed oval; no blue resource-like flowers.
  K.leaf(f'Ruin wildflower {i+1} / leaf',a.lerp(b,.28),.11,.045,'leaf',angle=i*1.4,tilt=.3)
  for j in range(7):petal(f'Ruin wildflower {i+1} / ray {j+1}',b,j*math.tau/7+i*.3,'white' if i%2==0 else 'yellow')
  c=b+Vector((0,.023,0));points=[c+Vector((0,.012,0)),c-Vector((0,.006,0))]+[c+Vector((.022*math.cos(j*math.tau/4),0,.022*math.sin(j*math.tau/4))) for j in range(4)]
  K.mesh(f'Ruin wildflower {i+1} / pollen',points,[(0,2+j,2+(j+1)%4) for j in range(4)]+[(1,2+(j+1)%4,2+j) for j in range(4)],'pollen',True)
def plaque():
 for side in [-1,1]:
  K.box(f'Interpretive plaque / quiet support {side}',(side*.22,.34,0),(.055,.68,.07),'plaque_leg',0)
  K.box(f'Interpretive plaque / foot {side}',(side*.22,.025,0),(.11,.05,.22),'stone_edge',0)
 for name,at,size,color in [('border',(0,.78,0),(.70,.37,.045),'plaque_frame'),('blank face',(0,.78,.027),(.63,.30,.014),'plaque_face')]:
  obj=K.box('Interpretive plaque / '+name,(0,0,0),size,color,.008 if name=='border' else 0)
  obj.rotation_euler.x=-math.radians(50)
  # Apply the same tilted-plane offset to the face, so it stays above the border.
  obj.location=K.v((0,.78,0))+Matrix.Rotation(-math.radians(50),3,'X')@K.v((0,0,at[2]))

BUILDERS=[('alc_ruin_arch',arch),('alc_ruin_rubble',rubble),('alc_ruin_vine',vine),('alc_ruin_flowers',flowers),('alc_ruin_plaque',plaque)]
def main():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;K.OUT=OUT;OUT.mkdir(parents=True,exist_ok=True)
 for role,value in COLORS.items():
  mat=bpy.data.materials.new(role);mat.diffuse_color=(*K.rgb(value),1);mat.use_nodes=True;p=mat.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=mat.diffuse_color;p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18;K.MATS[role]=mat
 mat=bpy.data.materials.new('Old garden masonry / matte vertex paint');mat.use_nodes=True;p=mat.node_tree.nodes['Principled BSDF'];p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18;vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';mat.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
 entries={}
 for i,(name,build) in enumerate(BUILDERS):
  K.begin(name,[1,1],400,generator='tools/art/build_alcatraz_ruins_424.py',author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',pivot='bottom centre; wall-back plane Z=0' if name=='alc_ruin_vine' else 'footprint bottom centre',front='+Z',collision='none; noninteractive heritage decoration')
  build();bpy.context.view_layer.update()
  pts=[o.matrix_world@v.co for o in K.CURRENT.objects for v in o.data.vertices];lo=Vector([min(v[k] for v in pts) for k in range(3)]);hi=Vector([max(v[k] for v in pts) for k in range(3)])
  for o in K.CURRENT.objects:o.location+=Vector((-(lo.x+hi.x)/2,-hi.y if name=='alc_ruin_vine' else -(lo.y+hi.y)/2,-lo.z))
  entry=K.export_asset(name,K.CURRENT,mat);path=OUT/(name+'.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:];doc['meshes'][0]['name']=name+'_mobile';encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
  path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
  entry.update(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source='tools/art/source/alcatraz_ruins_424/alcatraz_ruins_details.blend',material_contract={'roughness':.9,'metallic':0,'specular':.18,'vertex_color_is_srgb':False})
  entries[name]=entry
  for o in K.CURRENT.objects:o.location.x+=i*3
  print('ALC_RUIN',name,entry['triangles'],entry['bounds'],flush=True)
 data={'author':'赵云','assets':entries,'palette_srgb':COLORS,'layout_reference':'b16c31982f34a64cdd4f9c6683064edbf20837a0'}
 (OUT/'ruin_details_manifest.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');(SRC/'asset_stats.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'alcatraz_ruins_details.blend'),compress=True)
if __name__=='__main__':main()
