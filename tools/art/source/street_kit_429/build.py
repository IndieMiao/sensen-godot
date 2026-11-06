"""SGODOT-429. Metre-scale street furniture, named editable parts, one surface.
Run Blender under flock ~/gs66-render.lock. Never writes existing art directories.
"""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,importlib.util,sys
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
KIT=ROOT/'assets/landmarks/_shared/street_kit'
spec=importlib.util.spec_from_file_location('primitives',SRC.parent/'alcatraz_far_424/build.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
PAL={'stone':'CBB48F','stone_light':'D9C4A3','stone_shade':'BCA781','cream':'F0E1C2',
 'wood':'BB8B52','wood_light':'D0A56C','wood_dark':'9A7046','wood_seam':'795B43',
 'metal':'5D4C38','metal_light':'6D5746','teal':'35696A','teal_light':'608F99',
 'lamp':'F2DC9F','sage':'8AAFA2','canvas':'EFE7D4','leaf':'86A84F','leaf_light':'9AB55D',
 'leaf_dark':'759448','flower':'DFC570','soil':'897A53','basin':'A4A08F','drain':'4E4C43'}
p.PAL=PAL
box=p.box;rod=p.rod;lathe=p.lathe;mesh=p.mesh

def begin(name):
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.context.preferences.filepaths.save_version=0;p.PARTS=[];p.MATS={}
 p.PIVOT=bpy.data.objects.new(name+' / installation pivot',None);bpy.context.scene.collection.objects.link(p.PIVOT)
 p.PIVOT['author']='黄忠';p.PIVOT['module']=name

def tube(name,points,r,role,n=6):
 points=[Vector(x) for x in points];verts=[]
 for i,c in enumerate(points):
  axis=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
  a=axis.cross(Vector((1,0,0)))
  if a.length<.01:a=axis.cross(Vector((0,0,1)))
  a.normalize();b=axis.cross(a).normalized()
  verts.extend(c+r*(math.cos(j*math.tau/n)*a+math.sin(j*math.tau/n)*b) for j in range(n))
 faces=[]
 for i in range(len(points)-1):
  for j in range(n):k=(j+1)%n;faces.append((i*n+j,i*n+k,(i+1)*n+k,(i+1)*n+j))
 faces += [tuple(reversed(range(n))),tuple(range((len(points)-1)*n,len(points)*n))]
 return mesh(name,verts,faces,role,True)

def lantern(at):
 x,y,z=at
 lathe('Octagonal warm lantern',[(0,.12),(.035,.17),(.30,.20),(.34,.16)],'lamp',8,at)
 lathe('Solid lantern footing',[(0,.16),(.05,.18)],'metal',8,at)
 lathe('Soft sloping lantern cap',[(.33,.21),(.38,.23),(.48,.10),(.51,.05)],'metal',8,at)
 for angle in [0,math.pi/2,math.pi,math.pi*1.5]:
  rod('Four quiet lantern mullions',(x+.165*math.cos(angle),y+.03,z+.165*math.sin(angle)),(x+.19*math.cos(angle),y+.33,z+.19*math.sin(angle)),.018,'metal',4)

def lamp(dual=False):
 lathe('Flared cast base',[(0,.16),(.07,.18),(.14,.14),(.35,.11),(.45,.07),(2.9,.045),(2.94,.06)],'metal',10)
 lathe('Brass foot collar',[(.10,.145),(.15,.145)],'wood_light',10)
 if dual:
  for side in [-1,1]:
   tube('Curved twin arm',[(0,2.76,0),(side*.17,2.83,0),(side*.39,2.88,0),(side*.65,2.88,0)],.038,'metal',6)
   lantern((side*.65,2.88,0))
 else:lantern((0,2.91,0))
 return {'placement_cell_m':[2,2],'lamp_style':'Opaque warm glass, no light/emission node'}

def bench(stone=False):
 if stone:
  for x in [-.62,.62]:
   box('Stone pedestal foot',(x,.08,0),(.35,.16,.62),'stone_shade',.035)
   box('Tapered-looking stone support',(x,.37,0),(.23,.48,.40),'stone',.035)
  box('Rounded limestone seat',(0,.6425,0),(1.80,.145,.57),'stone_light',.055)
  for x in [-.70,.70]:box('Stone back support',(x,.89,-.23),(.15,.60,.15),'stone',.025)
  box('Simple low stone back',(0,1.12,-.26),(1.80,.34,.15),'cream',.045)
 else:
  for x in [-.67,.67]:
   for z in [-.20,.20]:rod('Iron bench leg',(x,0,z+.07),(x,.68,z),.038,'metal',6)
   box('Seat bearer',(x,.63,0),(.085,.09,.57),'metal',.01)
   rod('Back upright',(x,.61,-.24),(x,1.27,-.34),.034,'metal',6)
   tube('Rounded armrest',[(x,.67,.23),(x,.91,.23),(x,.96,.13),(x,.96,-.27)],.028,'metal',6)
  for j in range(4):box('Oak seat slat '+str(j+1),(0,.6825,(j-1.5)*.13),(1.80,.065,.12),['wood','wood_light'][j%2],.012)
  for j in range(3):
   o=box('Oak back slat '+str(j+1),(0,.90+j*.14,-.28-j*.025),(1.80,.115,.06),'wood_light' if j==2 else 'wood',.012)
   o.rotation_euler.x=math.radians(10)
 return {'placement_cell_m':[2,2],'seat_height_m':.715,'front':'+Z','usable_seat_width_m':1.80}

def railing_axis(a,b):
 for y in [.23,.93]:
  rod('Rounded horizontal rail',(a[0],y,a[1]),(b[0],y,b[1]),.032,'metal',6)
 length=math.dist(a,b);count=7 if length>1.5 else 3
 for i in range(1,count+1):
  t=i/(count+1);x=a[0]*(1-t)+b[0]*t;z=a[1]*(1-t)+b[1]*t
  rod('Even open railing baluster',(x,.23,z),(x,.93,z),.021,'metal',5)

def endpost():
 lathe('Square-ish rounded base',[(0,.10),(.09,.10),(.13,.07),(.92,.055),(.97,.078),(1.04,.078),(1.08,.035)],'metal',8)
 lathe('Warm post collar',[(.94,.08),(.98,.08)],'wood_light',8)
 return {'attachment_axis':'post centre','height_m':1.08}

def rail(corner=False):
 if corner:
  endpost();railing_axis((0,0),(1,0));railing_axis((0,0),(0,1))
  return {'grid_m':2,'corner_arm_m':1,'connectors':{'x_end':[1,0,0],'z_end':[0,0,1]},'pivot':'bend at bottom; arms +X,+Z'}
 railing_axis((-1,0),(1,0))
 # Two tiny feet ground the local origin while the handrails meet post centres.
 for x in [-.75,.75]:rod('Grounding foot',(x,0,0),(x,.23,0),.021,'metal',5)
 return {'grid_m':2,'connectors':{'left':[-1,0,0],'right':[1,0,0]},'post_policy':'Place separate endposts on exposed endpoints; consecutive spans share a post'}

def bollard():
 lathe('Low rounded street bollard',[(0,.13),(.06,.14),(.12,.10),(.60,.085),(.66,.10),(.71,.075),(.73,0)],'metal',10)
 lathe('Cream visible collar',[(.57,.088),(.63,.088)],'cream',10)
 return {'placement_cell_m':[2,2],'height_m':.73}

def contour(w,d):
 c=min(w,d)*.14
 return [(-w/2+c,-d/2),(w/2-c,-d/2),(w/2,-d/2+c),(w/2,d/2-c),(w/2-c,d/2),(-w/2+c,d/2),(-w/2,d/2-c),(-w/2,-d/2+c)]

def planter_body(w,d):
 profile=[(0,.90),(.08,1.0),(.13,.91),(.56,1.0),(.60,1.04),(.65,1.0),(.65,.82),(.54,.80)]
 pts=[(x,y,z) for y,scale in profile for x,z in contour(w*scale,d*scale)]
 faces=[];roles=[]
 for ring in range(len(profile)-1):
  for j in range(8):faces.append((ring*8+j,ring*8+(j+1)%8,(ring+1)*8+(j+1)%8,(ring+1)*8+j));roles.append('cream' if ring in [0,3,4,5] else 'stone')
 faces += [tuple(reversed(range(8))),tuple(range(56,64))];roles+=['stone_shade','soil']
 mesh('Hollow octagonal-edged stone planter',pts,faces,roles)

def ico(name,at,scale,role):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=p.v(at));o=bpy.context.object;o.name=name;o.parent=p.PIVOT;o.scale=(scale[0],scale[2],scale[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(p.mat(role));p.PARTS.append(o)

def planter(long=False):
 w,d=(1.90,.58) if long else (.85,.85);planter_body(w,d)
 spots=[(-.65,.80,0),(-.32,.93,.04),(0,.82,-.03),(.33,.95,0),(.66,.80,.02)] if long else [(-.17,.82,-.10),(.17,.85,-.03),(0,1.00,.12)]
 for i,pos in enumerate(spots):ico('Rounded clipped foliage',pos,(.25,.23,.24),['leaf','leaf_light','leaf_dark'][i%3])
 # Small cream flower centres, shared whole-family palette; no scattering clutter.
 for x,y,z in [spots[0],spots[-1]]:lathe('Simple flower',( [(0,.045),(.035,.06),(.065,0)] ),'flower',6,(x,y+.23,z))
 return {'placement_cell_m':[2,2],'contains':'Planter, inset soil and compact foliage merged as one mesh'}

def litter_bin():
 lathe('Bin inset body',[(0,.24),(.06,.27),(.10,.25),(.77,.25),(.82,.26),(.82,.17),(.77,.17)],'teal',12)
 for i in range(12):
  a=i*math.tau/12;o=box('Quiet vertical bin slat',(.254*math.cos(a),.43,.254*math.sin(a)),(.045,.62,.03),'teal_light' if i%3==0 else 'teal');o.rotation_euler.z=-a
 lathe('Open rounded bin rim',[(.77,.25),(.81,.30),(.87,.29),(.90,.24),(.90,.18),(.80,.17)],'metal',12)
 lathe('Dark recessed bin opening',[(.78,.17),(.785,.17)],'drain',12)
 lathe('Muted warm retaining hoop',[(.17,.263),(.20,.263)],'wood_light',12)
 return {'placement_cell_m':[2,2],'height_m':.90}

def board(at=(0,0,0)):
 x,y,z=at
 box('Rounded timber sign frame',(x,y,z+.05),(1.15,.58,.10),'wood_dark',.035)
 box('Blank cream graphic field',(x,y,z+.108),(1.01,.44,.025),'cream',.018)
 # A blank circular inset reserves a graphic, without text or a baked icon.
 ob=lathe('Blank graphic medallion',[(0,.145),(.012,.145)],'teal_light',16)
 ob.rotation_euler.x=math.pi/2;ob.location=p.v((x-.31,y,z+.13))
 return {'graphic_area_m':[1.01,.44],'graphic_area_center':[x,y,z+.125],'content':'Blank; circular inset is a reserved graphic field, no letters/icon baked'}

def sign(wall=False):
 if wall:
  return {**board(),'pivot':'back plane centre; +Z front','placement_cell_m':[2,2]}
 lathe('Sign pole with modest foot',[(0,.12),(.08,.12),(.13,.065),(1.88,.045)],'metal',8)
 return {**board((0,1.62,0)),'placement_cell_m':[2,2]}

def bike_rack():
 for z in [-.30,.30]:box('Rack ground rail',(0,.035,z),(1.84,.07,.12),'metal',.018)
 for x in [-.65,0,.65]:
  pts=[(x,.07,-.30),(x,.60,-.30)]
  pts += [(x,.60+.30*math.sin(t),-.30*math.cos(t)) for t in [math.pi*i/8 for i in range(1,9)]]
  pts.append((x,.07,.30));tube('U-loop bike support',pts,.028,'metal',6)
 return {'placement_cell_m':[2,2],'front':'+Z; three bicycle bays across X'}

def umbrella_table():
 lathe('Warm round tabletop',[(1.035,.44),(1.055,.50),(1.105,.50),(1.12,.46)],'wood_light',12)
 lathe('Table pedestal',[(0,.25),(.06,.27),(.13,.10),(1.04,.085)],'metal',10)
 rod('Umbrella central mast',(0,0,0),(0,2.86,0),.036,'wood_dark',8)
 # Closed fabric shell, with broad alternating panels, no texture/transparency.
 profile=[(2.86,0),(2.79,.30),(2.62,.72),(2.43,1.0),(2.35,1.0)]
 pts=[(0,2.86,0)]+[(r*math.cos(i*math.tau/12),y,r*math.sin(i*math.tau/12)) for y,r in profile[1:] for i in range(12)]
 faces=[];roles=[]
 for i in range(12):faces.append((0,1+i,1+(i+1)%12));roles.append('canvas' if i%2==0 else 'sage')
 for ring in range(3):
  for i in range(12):faces.append((1+ring*12+i,1+ring*12+(i+1)%12,1+(ring+1)*12+(i+1)%12,1+(ring+1)*12+i));roles.append('canvas' if i%2==0 else 'sage')
 faces.append(tuple(reversed(range(37,49))));roles.append('canvas')
 mesh('Twelve broad fabric umbrella panels',pts,faces,roles)
 for x in [-.73,.73]:
  lathe('Round matching stool',[(.65,.18),(.67,.22),(.715,.22)],'wood',10,(x,0,0))
  lathe('Stool pedestal',[(0,.17),(.05,.18),(.10,.07),(.65,.055)],'metal',8,(x,0,0))
 return {'placement_cell_m':[2,2],'canopy_diameter_m':2,'tabletop_height_m':1.12,'seat_height_m':.715}

def drinking_fountain():
 lathe('Stone drinking fountain pedestal',[(0,.22),(.08,.25),(.14,.19),(.78,.14),(.87,.20)],'stone',10)
 lathe('Recessed drinking bowl',[(.82,.19),(.89,.25),(1.02,.29),(1.05,.27),(1.05,.22),(.95,.16),(.93,0)],'stone_light',12)
 lathe('Small grey drain',[(.932,.04),(.936,.04)],'drain',10)
 tube('Curved modest drinking spout',[(0,1.00,-.19),(0,1.13,-.19),(0,1.17,-.13),(0,1.15,-.06)],.024,'basin',6)
 lathe('Small brass push button',[(0,.028),(.025,.028)],'wood_light',8,(.17,1.04,-.08))
 return {'placement_cell_m':[2,2],'bowl_height_m':1.05,'front':'+Z','water':'No particles, water surface or runtime interaction'}

BUILDERS=[('lamp_single',lambda:lamp(False)),('lamp_double',lambda:lamp(True)),('bench_wood',lambda:bench(False)),('bench_stone',lambda:bench(True)),('railing_straight_2m',lambda:rail(False)),('railing_endpost',endpost),('railing_corner',lambda:rail(True)),('bollard',bollard),('planter_square',lambda:planter(False)),('planter_long',lambda:planter(True)),('litter_bin',litter_bin),('sign_standing',lambda:sign(False)),('sign_wall',lambda:sign(True)),('bicycle_rack',bike_rack),('umbrella_table',umbrella_table),('drinking_fountain',drinking_fountain)]

def export(name,builder):
 begin(name);extra=builder();bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
 if name!='sign_wall':
  low=min((obj.matrix_world@v.co).z for obj in p.PARTS for v in obj.evaluated_get(deps).data.vertices)
  for obj in p.PARTS:obj.location.z-=low
  bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
 if name=='bench_wood':
  extra['seat_height_m']=max((obj.matrix_world@v.co).z for obj in p.PARTS if obj.name.startswith('Oak seat slat') for v in obj.evaluated_get(deps).data.vertices)
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
 mat=bpy.data.materials.new('Street kit matte vertex colour');mat.use_nodes=True;mat.use_backface_culling=True
 bs=mat.node_tree.nodes['Principled BSDF'];bs.inputs['Roughness'].default_value=.90;bs.inputs['Specular IOR Level'].default_value=.15
 node=mat.node_tree.nodes.new('ShaderNodeVertexColor');node.layer_name='Color';mat.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
 original=bpy.context.scene;scene=bpy.data.scenes.new('Export '+name);copies=[]
 for obj in p.PARTS:
  data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps));data.transform(obj.matrix_world)
  for uv in list(data.uv_layers):data.uv_layers.remove(uv)
  colors=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
  for face in data.polygons:
   color=data.materials[face.material_index].diffuse_color
   for i in face.loop_indices:colors.data[i].color=color
  data.materials.clear();data.materials.append(mat)
  for face in data.polygons:face.material_index=0
  data.color_attributes.active_color=colors;data.color_attributes.render_color_index=0
  ob=bpy.data.objects.new(obj.name,data);scene.collection.objects.link(ob);copies.append(ob)
 bpy.context.window.scene=scene
 for ob in copies:ob.select_set(True)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();ob=bpy.context.object
 ob.name=name;ob.data.name=name+'_mobile'
 bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.calc_loop_triangles()
 count=len(ob.data.loop_triangles);assert count<=800,(name,count)
 path=KIT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
 pts=[(v.co.x,v.co.z,-v.co.y) for v in ob.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
 row={'file':path.name,'triangles':count,'surfaces':1,'bounds':[lo,hi],'dimensions_m':[hi[i]-lo[i] for i in range(3)],'pivot':'base centre, Y up, +Z front','source':'tools/art/source/street_kit_429/'+name+'.blend','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),**extra}
 bpy.context.window.scene=original;bpy.data.scenes.remove(scene);print('STREET_ASSET',name,count,row['dimensions_m'],flush=True);return row

def main():
 KIT.mkdir(parents=True,exist_ok=True);rows={}
 only=sys.argv[sys.argv.index('--only')+1] if '--only' in sys.argv else None
 if only:rows=json.loads((KIT/'kit_manifest.json').read_text())['assets']
 for name,builder in BUILDERS:
  if not only or only==name:rows[name]=export(name,builder)
 m={'task':'SGODOT-429','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','grid_m':2,'units':'metres; Y up; +Z front','palette_srgb':PAL,'assets':rows,'unique_triangles':sum(x['triangles'] for x in rows.values()),'unique_surfaces':len(rows),'scope':'Reusable furniture only; example is review-only, no game layout or location'}
 (KIT/'kit_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
 (KIT/'palette.json').write_text(json.dumps({'colors_srgb':PAL,'source':'Alcatraz bf0c31b1 palette + Grace Cathedral cream/iron; see source reference/provenance.json'},indent=2)+'\n')
 for name,row in rows.items():
  folder=SRC/'modules'/name;folder.mkdir(parents=True,exist_ok=True)
  (folder/'reuse_provenance.json').write_text(json.dumps({'author':m['author'],'virtual_user_id':m['virtual_user_id'],'module':name,'geometry':'New modular geometry; no old GLB edited','palette':'Alcatraz bf0c31b1 + Grace Cathedral warm iron/cream','source':row['source'],'generator':'tools/art/source/street_kit_429/build.py'},ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
