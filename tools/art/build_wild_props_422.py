"""SGODOT-422: twelve small meadow decorations, <=300 triangles per GLB.

Run Blender under flock ~/gs66-render.lock. Godot metres/Y up/+Z front.
Named source objects survive; export copies are merged to one vertex-painted surface.
"""
from pathlib import Path
import hashlib,json,math,struct,sys
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
SRC=ROOT/'tools/art/source/wild_props_422';OUT=ROOT/'assets/farm/art'
COLORS={'stem':'65823B','leaf':'76923D','leaf_light':'94A94E','leaf_dark':'516F35',
 'white':'FFF4DA','yellow':'F4CF59','lilac':'CCADDE','pollen':'D7A649',
 'clover':'758C35','clover_light':'91A644','stone':'B6AF94','stone_light':'D2C7A9',
 'cap':'D8BE8C','cap_light':'EAD6AD','gills':'B2986F','mushroom_stem':'E8D4AE',
 'bark':'947042','bark_dark':'725637','wood':'CFA46C','ring':'AD7C47',
 'moss':'7E983C','moss_light':'9DAA4B','fern':'6D8A3D','fern_light':'94A852',
 'bush_dark':'537338','bush_dark_light':'6D8742','bush_olive':'889A41','bush_olive_light':'A2AD53',
 'reed_leaf':'789543','reed_light':'A3AD56','cattail':'AD7B41','cattail_light':'C69A59'}

def poly(name,points,faces,color,smooth=False):return K.mesh(name,points,faces,color,smooth)
def ico(name,at,size,color,subdivisions=1):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions,radius=1)
 o=bpy.context.object;o.location=K.v(at);o.scale=(size[0]/2,size[2]/2,size[1]/2)
 return K.finish(o,name,color,True)
def blade(name,a,b,width,color):
 a,b=Vector(a),Vector(b);d=b-a;s=Vector((-d.z,0,d.x)).normalized()*width/2
 mid=a.lerp(b,.55)
 pts=[a,mid+s,b,mid-s,mid+Vector((0,.012,0)),mid-Vector((0,.004,0))]
 return poly(name,pts,[(4,i,(i+1)%4) for i in range(4)]+[(5,(i+1)%4,i) for i in range(4)],color,True)
def petal(name,c,theta,r,color):
 u=Vector((math.cos(theta),.10,math.sin(theta)));s=Vector((-math.sin(theta),0,math.cos(theta)))
 c=Vector(c);pts=[c+u*.018,c+u*r*.74+s*r*.23,c+u*r,c+u*r*.74-s*r*.23,c+u*r*.58+Vector((0,.018,0))]
 return poly(name,pts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2),(0,2,1)],color,True)
def pollen(name,at,r):
 c=Vector(at);pts=[c+Vector((0,.015,0)),c-Vector((0,.005,0))]
 pts += [c+Vector((r*math.cos(i*math.tau/6),0,r*math.sin(i*math.tau/6))) for i in range(6)]
 return poly(name,pts,[(0,2+i,2+(i+1)%6) for i in range(6)]+[(1,2+(i+1)%6,2+i) for i in range(6)],'pollen',True)
def flowers(color):
 petals={'white':8,'yellow':7,'lilac':6}[color]
 for i,(x,z,h,r) in enumerate([(-.13,-.07,.24,.095),(.13,-.035,.30,.10),(-.015,.14,.19,.087)]):
  base=(x*.80,0,z*.80);top=(x,h,z)
  K.rod(f'{color} flower {i+1} / stem',base,top,.007,'stem',segments=4,top=.005)
  for j in range(2):
   a=Vector(base).lerp(Vector(top),.3+j*.19);angle=i*1.9+j*2.6
   blade(f'{color} flower {i+1} / leaf {j+1}',a,a+Vector((.105*math.cos(angle),.035,.105*math.sin(angle))),.05,'leaf' if j==0 else 'leaf_light')
  for j in range(petals):petal(f'{color} flower {i+1} / petal {j+1}',top,j*math.tau/petals+i*.7,r,color)
  pollen(f'{color} flower {i+1} / warm centre',Vector(top)+Vector((0,.016,0)),.024)
def clover():
 for i,(x,z,h) in enumerate([(-.16,-.08,.042),(.12,-.12,.06),(.03,.14,.055),(-.20,.15,.032),(.22,.13,.04)]):
  for j in range(3):
   theta=j*math.tau/3+i*.4;c=Vector((x+.063*math.cos(theta),h,z+.063*math.sin(theta)))
   pts=[c+Vector((0,.012,0)),c-Vector((0,.004,0))]
   pts += [c+Vector((math.cos(a*math.tau/8+theta),0,math.sin(a*math.tau/8+theta)))*(.041 if a==0 else .054) for a in range(8)]
   faces=[(0,2+(k+1)%8,2+k) for k in range(8)]+[(1,2+k,2+(k+1)%8) for k in range(8)]
   poly(f'Clover sprig {i+1} / rounded heart leaflet {j+1}',pts,faces,'clover_light' if (i+j)%3 else 'clover',True)
def pebbles(variant):
 positions=[(-.22,-.13,.17,.10),(.13,-.10,.13,.07),(-.05,.17,.11,.065),(.25,.18,.09,.045)] if variant=='a' else [(-.26,.10,.12,.07),(0,-.16,.19,.12),(.24,.12,.15,.085)]
 for i,(x,z,w,h) in enumerate(positions):
  o=ico(f'Scattered stone {i+1} / separate footprint',(x,h*.40,z),(w,h,w*.75),'stone_light' if i%2==0 else 'stone')
  # Flatten bottom without making a pile or a soil patch.
  for v in o.data.vertices:v.co.z=max(v.co.z,-.8)
def mushrooms():
 for i,(x,z,h,r) in enumerate([(-.12,-.06,.21,.08),(.11,.025,.27,.09),(-.025,.12,.13,.065)]):
  K.rod(f'Mushroom {i+1} / ivory stem',(x,0,z),(x,h*.78,z),.018,'mushroom_stem',segments=5,top=.013)
  o=K.lathe(f'Mushroom {i+1} / domed buff cap',[(r*.55,h*.65),(r,h*.70),(r*.85,h*.89),(r*.25,h)],'cap',segments=8,at=(x,0,z))
  o.data.materials.append(K.MATS['gills']);o.data.materials.append(K.MATS['cap_light'])
  for p in o.data.polygons:
   if p.index<8 or p.index==24:p.material_index=1
   elif 16<=p.index<24:p.material_index=2
def log_moss():
 # One slender fallen trunk, not the upright stump + stacked timber of hardwood.
 n=10;radius=.135;yc=.13;ends=[-.48,.48]
 verts=[(x,yc+radius*math.sin(i*math.tau/n),radius*math.cos(i*math.tau/n)) for x in ends for i in range(n)]
 body=poly('Fallen log / bark sleeve',verts,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]+[tuple(reversed(range(n))),tuple(range(n,2*n))],'bark',True)
 body.data.materials.append(K.MATS['bark_dark'])
 for p in body.data.polygons:
  if p.index in [1,5,8]:p.material_index=1
 for side in [-1,1]:
  # Two broad growth rings are vertex-painted geometry, no bitmap decal.
  pts=[(side*.481,yc,0)]
  for r in [.038,.048,.080,.091,.118]:
   pts += [(side*.481,yc+r*math.sin(i*math.tau/n),r*math.cos(i*math.tau/n)) for i in range(n)]
  faces=[(0,1+i,1+(i+1)%n) for i in range(n)]
  for row in range(4):faces.extend((1+row*n+i,1+row*n+(i+1)%n,1+(row+1)*n+(i+1)%n,1+(row+1)*n+i) for i in range(n))
  # Only the near cut end needs the two rings at this scale. Rear end stays a simple disc.
  if side==1:pts=pts[:11];faces=faces[:10];pts=[(side*.481,yc+(p[1]-yc)*3.10,p[2]*3.10) for p in pts]
  if side==1:faces=[tuple(reversed(f)) for f in faces]
  obj=poly(f'Log end {side} / growth rings',pts,faces,'wood')
  obj.data.materials.append(K.MATS['ring'])
  if side==-1:
   for p in obj.data.polygons:
    if 10<=p.index<20 or 30<=p.index<40:p.material_index=1
 for i,(x,z,sx,sz) in enumerate([(-.28,-.025,.36,.18),(-.015,.02,.36,.20),(.27,-.025,.30,.18)]):
  # Irregular low moss islands conform to the crown of the log.
  pts=[]
  for j in range(7):
   a=j*math.tau/7;zz=z+sz*.5*math.sin(a);pts.append((x+sx*.5*math.cos(a),yc+math.sqrt(max(.001,radius**2-zz**2))+.003,zz))
  pts.append((x,yc+radius+.018,z))
  poly(f'Moss island {i+1}',pts,[(7,(j+1)%7,j) for j in range(7)],'moss_light' if i==1 else 'moss',True)
def fern():
 for frond,angle in enumerate([.2,2.3,4.35]):
  reach=.27;h=[.42,.34,.29][frond];u=Vector((math.cos(angle),0,math.sin(angle)));side=Vector((-u.z,0,u.x))
  base=Vector((0,0,0));tip=u*reach+Vector((0,h,0))
  K.rod(f'Fern frond {frond+1} / rib',base,tip,.006,'stem',segments=3,top=.002)
  for j in range(4):
   t=.24+j*.16;c=base.lerp(tip,t);length=.17*(1-t*.65)
   for sign in [-1,1]:blade(f'Fern frond {frond+1} / leaflet {j+1}/{sign}',c,c+side*sign*length+u*.045+Vector((0,.015,0)),.085*(1-t*.5),'fern_light' if j>1 else 'fern')
def bush(kind):
 # Low, rounded lobes; no visible tree trunk and no mint herb colour.
 for i,(x,z,y,s) in enumerate([(-.16,0,.18,.38),(.14,-.04,.22,.42),(0,.14,.13,.32)]):
  ico(f'{kind} bush / rounded lobe {i+1}',(x,y,z),(s,s*.95,s*.92),'bush_'+kind+('_light' if i==1 else ''),2)
def cattail():
 for i,(x,z,h,lean) in enumerate([(-.14,-.03,.59,-.03),(.13,.025,.72,.025)]):
  tip=Vector((x+lean,h,z));base=Vector((x,0,z));head=tip-Vector((0,.085,0))
  K.rod(f'Water cattail {i+1} / slender stalk',base,tip,.008,'reed_leaf',segments=4,top=.005)
  K.rod(f'Water cattail {i+1} / narrow warm seed head',head-Vector((0,.070,0)),head+Vector((0,.070,0)),.023,'cattail_light' if i else 'cattail',segments=6,top=.018)
  for j in range(2):
   angle=i*2.4+j*2.1;end=base+Vector((.14*math.cos(angle),.38+j*.09,.14*math.sin(angle)))
   blade(f'Water cattail {i+1} / sparse ribbon {j+1}',base,end,.027,'reed_light' if j else 'reed_leaf')

BUILDERS=[('wild_flower_'+c,lambda c=c:flowers(c)) for c in ['white','yellow','lilac']]+[
 ('wild_clover',clover),('wild_pebbles_a',lambda:pebbles('a')),('wild_pebbles_b',lambda:pebbles('b')),
 ('wild_mushrooms',mushrooms),('wild_log_moss',log_moss),('wild_fern',fern),
 ('wild_bush_dark',lambda:bush('dark')),('wild_bush_olive',lambda:bush('olive')),('wild_cattail_water',cattail)]
def main():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 SRC.mkdir(parents=True,exist_ok=True);(SRC/'.gdignore').touch()
 for role,value in COLORS.items():
  m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);m.use_nodes=True
  p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18;K.MATS[role]=m
 material=bpy.data.materials.new('Farm matte vertex paint');material.use_nodes=True
 p=material.node_tree.nodes['Principled BSDF'];p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18
 vc=material.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';material.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
 entries={}
 for index,(name,build) in enumerate(BUILDERS):
  K.begin(name,[1,1],300,generator='tools/art/build_wild_props_422.py',author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',pivot='footprint bottom centre',purpose='non-interactive decorative scenery',collision='none')
  build();bpy.context.view_layer.update()
  points=[o.matrix_world@v.co for o in K.CURRENT.objects for v in o.data.vertices]
  lo=Vector([min(p[k] for p in points) for k in range(3)]);hi=Vector([max(p[k] for p in points) for k in range(3)])
  offset=Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z))
  for o in K.CURRENT.objects:o.location+=offset
  entry=K.export_asset(name,K.CURRENT,material)
  path=OUT/(name+'.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:]
  doc['meshes'][0]['name']=name+'_mobile';encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
  path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
  entry.update(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source='tools/art/source/wild_props_422/wild_props.blend',material_contract={'roughness':.9,'metallic':0,'specular':.18,'vertex_color_is_srgb':False})
  if name.startswith('wild_pebbles'):assert entry['bounds'][1][1]<=.15
  entries[name]=entry
  # Source inspection grid. Exported files above retain their local bottom pivots.
  for o in K.CURRENT.objects:o.location+=Vector(((index%4)*1.6,(index//4)*1.5,0))
 manifest_path=OUT/'manifest.json';manifest=json.loads(manifest_path.read_text());manifest['assets'].update(entries)
 manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 (SRC/'asset_stats.json').write_text(json.dumps({'author':'赵云','palette_srgb':COLORS,'assets':entries},ensure_ascii=False,indent=2)+'\n')
 bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'wild_props.blend'),compress=True)
 for name,e in entries.items():print('WILD_PROP',name,e['triangles'],e['bounds'])
if __name__=='__main__':main()
