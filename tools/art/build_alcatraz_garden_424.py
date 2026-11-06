"""Five matte vertex-colour garden modules, each one mesh/surface for MultiMesh.
Run Blender under flock ~/gs66-render.lock. Godot metres, Y up, +Z front.
"""
from pathlib import Path
import hashlib,json,math,struct,sys
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
SRC=ROOT/'tools/art/source/alcatraz_garden_424';OUT=ROOT/'assets/landmarks/alcatraz_island'
COLORS={'stem':'668347','leaf':'7F9950','leaf_light':'9FB165','poppy':'E98931','poppy_light':'FFB34C','poppy_inner':'DA6D25',
 'pollen':'D8B649','daisy':'FFF4D6','daisy_shade':'E8DDAD','lavender':'9274B9','lavender_light':'B19ACF','lavender_dark':'785F9D',
 'hedge':'708A40','hedge_top':'95A952','hedge_shade':'5C7738','pot':'BF8155','pot_edge':'D9A474','soil':'6C6548'}

def leaf(name,a,b,width,color):
 a,b=Vector(a),Vector(b);d=b-a;side=Vector((-d.z,0,d.x)).normalized()*width*.5;mid=a.lerp(b,.55)
 points=[a,mid+side,b,mid-side,mid+Vector((0,.013,0)),mid-Vector((0,.004,0))]
 return K.mesh(name,points,[(4,i,(i+1)%4) for i in range(4)]+[(5,(i+1)%4,i) for i in range(4)],color,True)
def stem(name,a,b,color='stem',n=4):return K.rod(name,a,b,.009,color,segments=n,top=.005)
def core(name,center,r,color='pollen'):
 c=Vector(center);points=[c+Vector((0,.015,0)),c-Vector((0,.005,0))]+[c+Vector((math.cos(i*math.tau/4)*r,0,math.sin(i*math.tau/4)*r)) for i in range(4)]
 return K.mesh(name,points,[(0,2+i,2+(i+1)%4) for i in range(4)]+[(1,2+(i+1)%4,2+i) for i in range(4)],color,True)
def poppy_flower(name,at,spin):
 c=Vector(at)
 for i in range(4):
  a=spin+i*math.tau/4;u=Vector((math.cos(a),0,math.sin(a)));v=Vector((-u.z,0,u.x))
  points=[c+u*.012,c+u*.10+v*.13+Vector((0,.048,0)),c+u*.18+v*.08+Vector((0,.10,0)),c+u*.205+Vector((0,.105,0)),c+u*.18-v*.08+Vector((0,.10,0)),c+u*.10-v*.13+Vector((0,.048,0)),c+u*.12+Vector((0,.069,0)),c+u*.12+Vector((0,.055,0))]
  # Closed thin cupped petals: no coincident front/back sheets or alpha surface.
  faces=[(6,j,(j+1)%6) for j in range(6)]+[(7,(j+1)%6,j) for j in range(6)]
  o=K.mesh(name+f' / cup petal {i+1}',points,faces,'poppy',True)
  o.data.materials.append(K.MATS['poppy_light']);o.data.materials.append(K.MATS['poppy_inner'])
  for p in o.data.polygons:p.material_index=1 if p.index in [1,2,3] else 2 if p.index>=6 else 0
 core(name+' / yellow centre',c+Vector((0,.024,0)),.04)
def poppies():
 for i,(x,z,h) in enumerate([(-.18,-.09,.48),(.17,-.06,.59),(.01,.20,.39)]):
  a=Vector((x*.7,0,z*.7));b=Vector((x,h,z));stem(f'Poppy {i+1} / stem',a,b)
  for j in range(2 if i<2 else 1):
   theta=i*1.7+j*2.8;p=a.lerp(b,.24+j*.17)
   leaf(f'Poppy {i+1} / narrow leaf {j+1}',p,p+Vector((.18*math.cos(theta),.04,.18*math.sin(theta))),.065,'leaf_light' if j else 'leaf')
  poppy_flower(f'California poppy {i+1}',b,i*.65)
def daisy_flower(name,at,spin):
 c=Vector(at)
 for i in range(8):
  theta=spin+i*math.tau/8;u=Vector((math.cos(theta),0,math.sin(theta)));side=Vector((-u.z,0,u.x));r=.143
  points=[c+u*.023,c+u*r*.72+side*.036,c+u*r,c+u*r*.72-side*.036,c+u*r*.64+Vector((0,.017,0))]
  o=K.mesh(name+f' / white ray {i+1}',points,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2),(0,2,1)],'daisy',True)
  o.data.materials.append(K.MATS['daisy_shade'])
  for p in o.data.polygons:
   if p.index>=4:p.material_index=1
 core(name+' / yellow centre',c+Vector((0,.025,0)),.036)
def daisies():
 for i,(x,z,h) in enumerate([(-.17,-.10,.35),(.16,-.03,.45),(-.01,.18,.28)]):
  a=Vector((x*.7,0,z*.7));b=Vector((x,h,z));stem(f'Daisy {i+1} / stem',a,b)
  p=a.lerp(b,.37);theta=i*2.2;leaf(f'Daisy {i+1} / lance leaf',p,p+Vector((.14*math.cos(theta),.03,.14*math.sin(theta))),.055,'leaf')
  daisy_flower(f'Daisy {i+1}',b,i*.4)
def lavenders():
 for i,(x,z,h) in enumerate([(-.18,-.06,.62),(.13,-.12,.77),(.20,.15,.57),(-.08,.17,.69)]):
  a=Vector((x*.75,0,z*.75));b=Vector((x,h-.10,z));stem(f'Lavender {i+1} / stem',a,b,n=3)
  for j in range(1):
   p=a.lerp(b,.30+j*.2);theta=i*1.9+j*2.6;leaf(f'Lavender {i+1} / grey-green leaf {j+1}',p,p+Vector((.14*math.cos(theta),.035,.14*math.sin(theta))),.038,'leaf')
  o=K.lathe(f'Lavender {i+1} / tiered flowering spike',[(.019,h-.26),(.048,h-.22),(.030,h-.17),(.043,h-.12),(.029,h-.055),(.006,h)],'lavender',segments=4,at=(x,0,z))
  o.data.materials.append(K.MATS['lavender_light']);o.data.materials.append(K.MATS['lavender_dark'])
  for p in o.data.polygons:p.material_index=1 if 8<=p.index<12 or p.index>=16 else 2 if p.index<4 else 0
def ico(name,at,size,color):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1);o=bpy.context.object;o.location=K.v(at);o.scale=(size[0]/2,size[2]/2,size[1]/2)
 return K.finish(o,name,color,True)
def hedge():
 # A softly undulating clipped canopy, not extra balls stuck onto a box.
 # End profiles remain identical, allowing 1m MultiMesh pieces to touch exactly.
 cross=[(-.23,0),(.23,0),(.28,.30),(.20,.55),(0,.64),(-.20,.55),(-.28,.30)]
 n=len(cross);xs=[-.5,-.25,0,.25,.5];wave=[0,.025,-.015,.018,0]
 points=[(x,y+(wave[j] if y>.3 else 0),z) for j,x in enumerate(xs) for z,y in cross]
 faces=[tuple(reversed(range(n))),tuple(range((len(xs)-1)*n,len(xs)*n))]+[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(xs)-1) for i in range(n)]
 o=K.mesh('Hedge / one metre rounded core',points,faces,'hedge',True);o.data.materials.append(K.MATS['hedge_top']);o.data.materials.append(K.MATS['hedge_shade'])
 for p in o.data.polygons:
  p.use_smooth=p.index>=2
  edge=(p.index-2)%n
  p.material_index=1 if p.index>=2 and edge in [3,4] else 2 if p.index>=2 and edge==0 else 0
def planter():
 # Small unglazed terracotta pot, open dark soil and a fan of eight broad leaves.
 profile=[(.205,0),(.24,.06),(.31,.48),(.34,.51),(.34,.57),(.29,.57),(.287,.528)]
 n=8;points=[(r*math.cos(i*math.tau/n),y,r*math.sin(i*math.tau/n)) for r,y in profile for i in range(n)]
 faces=[tuple(reversed(range(n)))]+[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(profile)-1) for i in range(n)]
 o=K.mesh('Planter / open terracotta pot and rim',points,faces,'pot',True)
 o.data.materials.append(K.MATS['pot_edge'])
 for p in o.data.polygons:
  if p.index>=24:p.material_index=1
 K.cylinder('Planter / recessed soil',(0,.529,0),.287,.018,'soil',segments=8)
 for i in range(8):
  theta=i*math.tau/8;reach=.30 if i%2==0 else .22;height=.94 if i%2==0 else 1.14
  leaf(f'Planter / broad fan leaf {i+1}',(.045*math.cos(theta),.54,.045*math.sin(theta)),(reach*math.cos(theta),height,reach*math.sin(theta)),.16,'leaf_light' if i%2 else 'leaf')

BUILDERS=[('alc_flowers_poppy',poppies,250),('alc_flowers_lavender',lavenders,250),('alc_flowers_daisy',daisies,250),('alc_hedge',hedge,80),('alc_planter',planter,300)]
def main():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;K.OUT=OUT;OUT.mkdir(parents=True,exist_ok=True)
 for role,value in COLORS.items():
  m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);m.use_nodes=True;p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18;K.MATS[role]=m
 mat=bpy.data.materials.new('Garden matte vertex paint');mat.use_nodes=True;p=mat.node_tree.nodes['Principled BSDF'];p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18
 vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';mat.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
 entries={}
 for i,(name,build,limit) in enumerate(BUILDERS):
  K.begin(name,[1,1],limit,generator='tools/art/build_alcatraz_garden_424.py',author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',pivot='footprint bottom centre',front='+Z',collision='none; noninteractive garden decoration')
  build();bpy.context.view_layer.update()
  pts=[o.matrix_world@v.co for o in K.CURRENT.objects for v in o.data.vertices];lo=Vector([min(v[k] for v in pts) for k in range(3)]);hi=Vector([max(v[k] for v in pts) for k in range(3)])
  for o in K.CURRENT.objects:o.location+=Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z))
  entry=K.export_asset(name,K.CURRENT,mat);path=OUT/(name+'.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:];doc['meshes'][0]['name']=name+'_mobile'
  encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4);path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
  entry.update(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source='tools/art/source/alcatraz_garden_424/alcatraz_garden.blend',material_contract={'roughness':.9,'metallic':0,'specular':.18,'vertex_color_is_srgb':False})
  entries[name]=entry
  for o in K.CURRENT.objects:o.location.x+=i*1.6
  print('ALC_GARDEN',name,entry['triangles'],entry['bounds'],flush=True)
 data={'author':'赵云','assets':entries,'palette_srgb':COLORS,'placement_reference':'b16c31982f34a64cdd4f9c6683064edbf20837a0'}
 (OUT/'garden_manifest.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');(SRC/'asset_stats.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'alcatraz_garden.blend'),compress=True)
if __name__=='__main__':main()
