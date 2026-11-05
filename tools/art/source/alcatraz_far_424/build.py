"""SGODOT-424: independent tower LODs and scenic low-poly cards.
Godot metres, Y up; only alc_* files are owned by this generator.
"""
from pathlib import Path
import hashlib,json,math,random,sys
import bpy,bmesh
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island'
PAL={'white':'EEE8D6','white_light':'FFF5E1','white_shadow':'D6D2C2','stone':'B4AE9B',
 'window':'88B1BB','window_dark':'547981','lantern':'F5D994','roof':'B8AB8C',
 'rust':'A86C48','rust_light':'C48C5E','rust_dark':'80513B','hoop':'765344',
 'bridge':'C97454','bridge_light':'DE8A62','bridge_shade':'AD604A',
 'hills':'9DAE9B','hills_light':'B2BA9B','hill_shadow':'839D9A',
 'city':'D3CBC0','city_light':'E8DACA','city_blue':'AABDC6','city_mid':'B9BEBB','city_shadow':'9FB1BD'}
PARTS=[];MATS={};PIVOT=None
def v(p):return Vector((p[0],-p[2],p[1]))
def rgb(h):return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in [v/255 for v in bytes.fromhex(h)])
def mat(role):
 if role not in MATS:
  m=bpy.data.materials.new(role);m.use_nodes=True;m.diffuse_color=(*rgb(PAL[role]),1)
  q=m.node_tree.nodes['Principled BSDF'];q.inputs['Base Color'].default_value=m.diffuse_color;q.inputs['Roughness'].default_value=.94;q.inputs['Specular IOR Level'].default_value=.15;MATS[role]=m
 return MATS[role]
def mesh(name,pts,faces,role,smooth=False):
 d=bpy.data.meshes.new(name);d.from_pydata([v(p) for p in pts],[],faces);d.update()
 o=bpy.data.objects.new(name,d);bpy.context.scene.collection.objects.link(o);o.parent=PIVOT
 roles=[role]*len(faces) if isinstance(role,str) else role;keys=list(dict.fromkeys(roles))
 for k in keys:d.materials.append(mat(k))
 for f,k in zip(d.polygons,roles):f.material_index=keys.index(k);f.use_smooth=smooth
 bm=bmesh.new();bm.from_mesh(d);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free();PARTS.append(o);return o
def box(name,at,size,role,bevel=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=v(at));o=bpy.context.object;o.name=name;o.parent=PIVOT;o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(mat(role));PARTS.append(o)
 if bevel:
  b=o.modifiers.new('Soft edge','BEVEL');b.width=min(bevel,min(size)*.35);b.segments=1
  n=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');n.keep_sharp=True
 return o
def lathe(name,profile,role,n,center=(0,0,0),smooth=True):
 pts=[];rings=[];faces=[]
 for y,r in profile:
  ring=[]
  for i in range(n if r else 1):
   a=i*math.tau/n;ring.append(len(pts));pts.append((center[0]+r*math.cos(a),center[1]+y,center[2]+r*math.sin(a)))
  rings.append(ring)
 for a,b in zip(rings,rings[1:]):
  for i in range(n):
   j=(i+1)%n
   faces.append((a[0],b[j],b[i]) if len(a)==1 else (a[i],a[j],b[0]) if len(b)==1 else (a[i],a[j],b[j],b[i]))
 if len(rings[0])>1:faces.append(tuple(reversed(rings[0])))
 if len(rings[-1])>1:faces.append(tuple(rings[-1]))
 return mesh(name,pts,faces,role,smooth)
def rod(name,a,b,r,role,n=8):
 a=Vector(a);b=Vector(b);axis=(b-a).normalized();side=axis.cross(Vector((0,1,0)))
 if side.length<.01:side=axis.cross(Vector((1,0,0)))
 side.normalize();up=axis.cross(side)
 pts=[p+r*(math.cos(i*math.tau/n)*side+math.sin(i*math.tau/n)*up) for p in [a,b] for i in range(n)]
 return mesh(name,pts,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]+[tuple(reversed(range(n))),tuple(range(n,2*n))],role,True)
def band(name,y,r,h,role,n):return lathe(name,[(y-h/2,r),(y+h/2,r)],role,n)
def panel(name,x,y,z,w,h,role):return box(name,(x,y,z),(w,h,.025),role)
def lighthouse(far=False):
 n=20 if far else 40
 profile=[(0,2.15),(.32,2.15),(.45,1.80),(2.1,1.72),(11.15,1.12),(11.35,1.40),(11.62,1.40)]
 lathe('Tapered white masonry shaft',profile,'white',n)
 if not far:
  for y,r in [(2.12,1.75),(10.95,1.18)]:lathe('Masonry collar',[(y-.08,r),(y+.05,r+.03),(y+.12,r)],'white_light',n)
  for y in [4.0,7.2,9.7]:
   r=1.72-(y-2.1)/9.05*.60
   # Small closed teal panes with a white masonry surround; no bars.
   for angle in [0,math.pi/2,math.pi,3*math.pi/2]:
    o=box('Simple slit window surround',(0,y,r+.07),(.32,.82,.06),'white_light',.025);o.rotation_euler.z=angle
    o.location=v((math.sin(angle)*(r+.07),y,math.cos(angle)*(r+.07)))
    o=box('Unbarred blue window',(0,y,r+.105),(.20,.64,.02),'window_dark',.006);o.rotation_euler.z=angle
    o.location=v((math.sin(angle)*(r+.105),y,math.cos(angle)*(r+.105)))
  box('Plain visitor door',(0,.92,1.86),(.74,1.38,.035),'window_dark',.01)
 else:
  for y,r in [(4.0,1.60),(7.2,1.39),(9.7,1.23)]:
   for angle in [0,math.pi/2,math.pi,3*math.pi/2]:
    o=box('Distance unbarred pane',(0,y,r+.08),(.20,.64,.02),'window_dark');o.rotation_euler.z=angle;o.location=v((math.sin(angle)*(r+.08),y,math.cos(angle)*(r+.08)))
  box('Distance visitor door',(0,.92,1.86),(.74,1.38,.025),'window_dark')
 lathe('Balcony shallow solid stone ledge',[(11.45,1.40),(11.55,1.85),(11.76,1.85),(11.86,1.52)],'white_light',n)
 # Octagonal lantern glazing reads warm, framed by cream mullions, not prison bars.
 lathe('Lantern warm glazing',[(11.85,1.09),(13.50,1.09)],'lantern',8, smooth=False)
 for i in range(8):
  a=i*math.tau/8
  rod('Lantern cream structural mullion',(1.10*math.cos(a),11.85,1.10*math.sin(a)),(1.10*math.cos(a),13.54,1.10*math.sin(a)),.065,'white_light',4 if far else 8)
 lathe('Lantern roof and small finial',[(13.48,1.45),(13.65,1.48),(14.55,.30),(14.65,.16),(14.82,.12),(15.0,0)],'roof',12 if far else 32)
 if not far:
  for y in [12.0,13.42]:band('Lantern horizontal rim',y,1.16,.10,'white_light',32)
 return {'height_m':15,'style':'White visitor lighthouse, warm lantern, no bars or watchtower details'}
def watertower(far=False):
 n=12 if far else 40;beam_n=4 if far else 10
 for sx in [-1,1]:
  for sz in [-1,1]:
   a=(sx*1.72,.18,sz*1.72);b=(sx*1.15,8.35,sz*1.15)
   box('Concrete tower foot',(sx*1.72,.18,sz*1.72),(.55,.36,.55),'stone',0 if far else .035)
   rod('Splayed timber leg',a,b,.15,'rust_dark',beam_n)
 for y in [2.8,5.55,8.15]:
  r=1.72-(y-.18)/(8.35-.18)*.57
  for axis in range(2):
   for sign in [-1,1]:
    a=(-r,y,sign*r) if axis==0 else (sign*r,y,-r)
    b=(r,y,sign*r) if axis==0 else (sign*r,y,r)
    rod('Horizontal frame tie',a,b,.10,'rust',beam_n)
 for y0,y1 in [(.35,2.8),(2.8,5.55),(5.55,8.15)]:
  r0=1.72-(y0-.18)/8.17*.57;r1=1.72-(y1-.18)/8.17*.57
  for axis in range(2):
   for sign in [-1,1]:
    for flip in [-1,1]:
     a=(flip*r0,y0,sign*r0) if axis==0 else (sign*r0,y0,flip*r0)
     b=(-flip*r1,y1,sign*r1) if axis==0 else (sign*r1,y1,-flip*r1)
     rod('Open X frame brace',a,b,.075,'rust_light',beam_n)
 lathe('Tank platform',[(8.1,2.02),(8.27,2.02)],'rust_dark',n)
 lathe('Rust timber water tank',[(8.25,1.82),(10.72,1.82)],'rust',n,smooth=False)
 for y in ([8.43,10.55] if far else [8.43,9.45,10.55]):band('Tank iron hoop',y,1.85,.10,'hoop',n)
 lathe('Low copper roof',[(10.70,1.94),(10.86,1.94),(11.9,.12),(12,0)],'rust_light',n)
 if not far:
  for i in range(32):
   a=i*math.tau/32
   rod('Tank stave seam',(1.825*math.cos(a),8.48,1.825*math.sin(a)),(1.825*math.cos(a),10.5,1.825*math.sin(a)),.012,'rust_dark',4)
  for y in [2.8,5.55,8.15]:
   for sx in [-1,1]:
    for sz in [-1,1]:
     rr=1.72-(y-.18)/8.17*.57
     box('Broad iron join plate',(sx*rr,y,sz*rr),(.25,.34,.25),'hoop',.025)
 return {'height_m':12,'style':'Rust timber and iron support structure; open X bracing retained in far LOD'}
def goldengate():
 # A compressed scenic card, not a traversable full-scale bridge.
 # Width 4.8 m and low relief are deliberate; placement/scale is a separate contract.
 box('Orange suspended roadway',(0,.28,0),(4.8,.065,.16),'bridge',.008)
 for x in [-1.15,1.15]:
  for dx in [-.09,.09]:box('Golden Gate tower pier',(x+dx,.63,0),(.075,1.26,.15),'bridge',.01)
  for y in [.48,.78,1.08,1.25]:box('Tower horizontal brace',(x,y,0),(.27,.055,.16),'bridge_light',.006)
  box('Bridge pale footing',(x,.045,0),(.30,.09,.23),'bridge_shade',.008)
 # Parabolic suspension segments and hanging wires on the camera-facing side.
 curves=[]
 for x0,x1,end0,end1,sag in [(-2.4,-1.15,.30,1.20,.10),(-1.15,1.15,1.20,1.20,.77),(1.15,2.4,1.20,.30,.10)]:
  pts=[]
  for i in range(17):
   t=i/16;x=x0+(x1-x0)*t;y=end0*(1-t)+end1*t-sag*4*t*(1-t);pts.append((x,y,.10))
  for a,b in zip(pts,pts[1:]):rod('Continuous suspension cable',a,b,.015,'bridge_light',4)
  for i in range(1,16,2):
   x,y,z=pts[i]
   if y>.33:rod('Sparse suspension hanger',(x,.32,z),(x,y,z),.007,'bridge',4)
 return {'scenic_card':True,'real_scale_structure':False,'style':'Orange-red Golden Gate silhouette; two towers, broad roadway, continuous sagging cables','default_shadow':False}
def skyline():
 rng=random.Random(424);x=-6
 # Layered pastel city blocks, with two unmistakable named silhouettes.
 while x<6:
  w=rng.uniform(.25,.55);h=rng.uniform(.35,1.3)
  box('Distant waterfront block',(x+w*.5,h*.5,-.12),(w-.025,h,.08),rng.choice(['city','city_light','city_blue','city_mid']))
  x+=w
 for i,(x,w,h) in enumerate([(-4.3,.48,1.6),(-3.7,.45,1.85),(-2.9,.52,2.2),(-1.9,.40,1.7),(.5,.55,1.8),(1.25,.45,2.15),(2.2,.60,1.7),(3.65,.62,2.2),(4.5,.45,1.5)]):
  box('Mid-distance skyline tower',(x,h*.5,.02),(w,h,.10),'city_light' if i%2 else 'city_blue')
  box('Soft side facade',(x+w*.35,h*.5,.08),(w*.3,h,.012),'city_shadow')
  for y in [.3,.6,.9,1.2,1.5]:
   if y<h-.2:box('Quiet facade band',(x,y,.082),(w*.72,.018,.015),'city_mid')
 # Salesforce: broad rounded taper with a domed crown.
 shape=[(-.45,0),(.45,0),(.43,2.8),(.35,3.35),(.19,3.52),(0,3.57),(-.19,3.52),(-.35,3.35),(-.43,2.8)]
 mesh('Salesforce rounded crown silhouette',[(x-.75,y,.15) for x,y in shape],[tuple(range(len(shape)))],'city_blue')
 for i in range(6):box('Salesforce soft horizontal band',(-.75,.6+i*.43,.17),(.72,.026,.015),'city_light')
 # Transamerica: pointed four-sided pyramid, recognizable without lettering.
 pts=[(2.5,0,.08),(3.25,0,.08),(3.25,0,.24),(2.5,0,.24),(2.875,3.42,.16)]
 mesh('Transamerica Pyramid',pts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2,1)],['city_light','city','city','city_light','city'])
 rod('Transamerica slender spire',(2.875,3.42,.16),(2.875,3.7,.16),.018,'city_light',4)
 return {'scenic_card':True,'landmark_silhouettes':['Salesforce Tower','Transamerica Pyramid'],'default_shadow':False,'style':'Pastel low-relief skyline, no lettering or photo texture'}
def hills():
 for layer,z,role,h in [(0,-.20,'hill_shadow',1.8),(1,0,'hills',2.5),(2,.18,'hills_light',1.35)]:
  points=[]
  for i in range(21):
   x=-10+i;y=(.2+(.5+.5*math.sin(i*.53+layer))*.52+(.5+.5*math.cos(i*.87+layer))*.28)*h
   points.extend([(x,0,z),(x,y,z)])
  faces=[]
  for i in range(20):faces.append((2*i,2*i+2,2*i+3,2*i+1))
  mesh('Layered soft shore hill %d'%layer,points,faces,role)
 return {'scenic_card':True,'default_shadow':False,'style':'Three broad low-contrast hill layers, deliberately sparse silhouette'}
def export(name,builder):
 global PARTS,MATS,PIVOT
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
 PARTS=[];MATS={};PIVOT=bpy.data.objects.new(name+' / ground-centre',None);bpy.context.scene.collection.objects.link(PIVOT)
 PIVOT['task']='SGODOT-424';PIVOT['author']='黄忠';extra=builder();bpy.context.view_layer.update()
 source=bpy.context.scene;deps=bpy.context.evaluated_depsgraph_get()
 coords=[o.matrix_world@p.co for o in PARTS for p in o.evaluated_get(deps).data.vertices]
 shift=Vector(((min(p.x for p in coords)+max(p.x for p in coords))*.5,(min(p.y for p in coords)+max(p.y for p in coords))*.5,min(p.z for p in coords)))
 for o in PARTS:o.location-=shift
 bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
 flat=bpy.data.materials.new('Alcatraz matte vertex colour');flat.use_nodes=True;flat.use_backface_culling=not extra.get('scenic_card',False)
 q=flat.node_tree.nodes['Principled BSDF'];q.inputs['Base Color'].default_value=(1,1,1,1);q.inputs['Roughness'].default_value=.94;q.inputs['Metallic'].default_value=0;q.inputs['Specular IOR Level'].default_value=.15
 c=flat.node_tree.nodes.new('ShaderNodeVertexColor');c.layer_name='Color';flat.node_tree.links.new(c.outputs['Color'],q.inputs['Base Color'])
 exp=bpy.data.scenes.new('Temporary export');copies=[]
 for obj in PARTS:
  d=bpy.data.meshes.new_from_object(obj.evaluated_get(deps));d.transform(obj.matrix_world)
  col=d.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
  for f in d.polygons:
   color=d.materials[f.material_index].diffuse_color
   for i in f.loop_indices:col.data[i].color=color
  d.materials.clear();d.materials.append(flat)
  for f in d.polygons:f.material_index=0
  d.color_attributes.active_color=col;d.color_attributes.render_color_index=0
  o=bpy.data.objects.new('Export part',d);exp.collection.objects.link(o);copies.append(o)
 bpy.context.window.scene=exp
 for o in copies:o.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();body=bpy.context.object;body.name=name;body.data.name=name+'_mobile'
 bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
 body.data.calc_loop_triangles();tri=len(body.data.loop_triangles)
 path=KIT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
 pts=[(p.co.x,p.co.z,-p.co.y) for p in body.data.vertices];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
 entry={'file':name+'.glb','triangles':tri,'surfaces':1,'bounds':[lo,hi],'dimensions_m':[hi[i]-lo[i] for i in range(3)],'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source':str((SRC/(name+'.blend')).relative_to(ROOT)),**extra}
 bpy.context.window.scene=source;bpy.data.scenes.remove(exp);print(name,tri,lo,hi,flush=True);return entry
def main():
 SRC.mkdir(parents=True,exist_ok=True);KIT.mkdir(parents=True,exist_ok=True)
 entries={}
 builders=[('alc_lighthouse',lambda:lighthouse(False)),('alc_lighthouse_far',lambda:lighthouse(True)),('alc_watertower',lambda:watertower(False)),('alc_watertower_far',lambda:watertower(True)),('alc_far_goldengate',goldengate),('alc_far_skyline',skyline),('alc_far_hills',hills)]
 for name,build in builders:entries[name]=export(name,build)
 m={'task':'SGODOT-424','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','units':'metres; Y up; +Z front; bottom-centre origin','palette_srgb':PAL,'assets':entries,
  'placement_status':'pending v2 coordinate/camera confirmation with Marco Polo',
  'lod_pairs':[['alc_lighthouse','alc_lighthouse_far'],['alc_watertower','alc_watertower_far']]}
 (KIT/'alc_far_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
