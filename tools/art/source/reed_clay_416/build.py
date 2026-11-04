"""SGODOT-416 approved A/A: compact cattails and a shallow ochre clay pit.

Blender 5.2; coordinates are Godot metres (Y up, +Z front). Each asset has an
editable named source and one merged, opaque Farm vertex paint export.
"""
from pathlib import Path
import hashlib
import json
import math
import random
import bpy
import bmesh
from mathutils import Vector

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/farm/art'
COLORS={'reed':'92AA4F','reed_light':'A9BD62','reed_dark':'768D3B','stem':'75823B',
        'cattail':'916139','cattail_light':'A27346','mud':'68523B','mud_edge':'806448',
        'pebble':'ADA68B','grass':'A4BC5E','grass_edge':'8CA149',
        'clay':'C48A4D','clay_light':'D5A063','clay_shade':'AC713E','pit_wall':'98663D',
        'wood':'BD935A','wood_light':'D3AC73','spade':'A49C85'}
PARTS=[];MATS={};PIVOT=None

def linear(h):
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in [v/255 for v in bytes.fromhex(h)])
def v(p):return Vector((p[0],-p[2],p[1]))
def mat(role):
    if role not in MATS:
        m=bpy.data.materials.new(role);m.use_nodes=True;m.diffuse_color=(*linear(COLORS[role]),1)
        p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color
        p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.16
        MATS[role]=m
    return MATS[role]
def mesh(name,points,faces,roles,smooth=True):
    d=bpy.data.meshes.new(name);d.from_pydata([v(p) for p in points],[],faces);d.update()
    o=bpy.data.objects.new(name,d);bpy.context.scene.collection.objects.link(o);o.parent=PIVOT
    roles=[roles]*len(faces) if isinstance(roles,str) else roles
    names=list(dict.fromkeys(roles))
    for key in names:d.materials.append(mat(key))
    for f,key in zip(d.polygons,roles):f.material_index=names.index(key);f.use_smooth=smooth
    bm=bmesh.new();bm.from_mesh(d);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free()
    PARTS.append(o);return o
def lathe(name,profile,role,segments=12,center=(0,0,0),xz=(1,1),cap_bottom=True):
    pts=[];rings=[];faces=[]
    for y,r in profile:
        ring=[]
        for i in range(segments if r else 1):
            a=i*math.tau/segments;ring.append(len(pts));pts.append((center[0]+r*math.cos(a)*xz[0],center[1]+y,center[2]+r*math.sin(a)*xz[1]))
        rings.append(ring)
    for a,b in zip(rings,rings[1:]):
        for i in range(segments):
            j=(i+1)%segments
            faces.append((a[0],b[i],b[j]) if len(a)==1 else (a[i],b[0],a[j]) if len(b)==1 else (a[i],b[i],b[j],a[j]))
    if cap_bottom and len(rings[0])>1:faces.append(tuple(reversed(rings[0])))
    if len(rings[-1])>1:faces.append(tuple(rings[-1]))
    return mesh(name,pts,faces,role)
def beam(name,a,b,radius,role,sides=6):
    a=Vector(a);b=Vector(b);axis=(b-a).normalized();side=axis.cross(Vector((1,0,0))).normalized();up=axis.cross(side)
    pts=[p+radius*(side*math.cos(i*math.tau/sides)+up*math.sin(i*math.tau/sides)) for p in [a,b] for i in range(sides)]
    faces=[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
    faces.extend([tuple(reversed(range(sides))),tuple(range(sides,sides*2))])
    return mesh(name,pts,faces,role)
def leaf(name,base,angle,height,lean,width,role):
    base=Vector(base);out=Vector((math.cos(angle),0,math.sin(angle)));side=Vector((-out.z,0,out.x))
    pts=[]
    # Three diamond cross-sections make a soft solid blade with a pointed tip.
    for t,w in [(0,.060),(.35,width),(.72,width*.80)]:
        p=base+out*(lean*t*t)+Vector3(0,height*t,0)
        for sw,th in [(1,0),(0,1),(-1,0),(0,-1)]:pts.append(p+side*(w*.5*sw)+out*(width*.24*th))
    pts.append(base+out*lean+Vector((0,height,0)))
    faces=[(3,2,1,0)]
    for ring in range(2):
        for i in range(4):faces.append((ring*4+i,ring*4+(i+1)%4,(ring+1)*4+(i+1)%4,(ring+1)*4+i))
    for i in range(4):faces.append((8+i,8+(i+1)%4,12))
    return mesh(name,pts,faces,role)

# A small helper to keep the authoring formulas in familiar Y-up coordinates.
def Vector3(x,y,z):return Vector((x,y,z))
def box(name,at,size,role,bevel=.012,yaw=0,lean=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=v(at));o=bpy.context.object;o.name=name;o.parent=PIVOT
    o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.rotation_euler=(0,math.radians(-lean),math.radians(yaw))
    o.data.materials.append(mat(role));PARTS.append(o)
    mod=o.modifiers.new('Soft silhouette','BEVEL');mod.width=bevel;mod.segments=1
    mod=o.modifiers.new('Weighted broad faces','WEIGHTED_NORMAL');mod.keep_sharp=True
    return o
def grip(name,center,width,height,thick,role):
    # Open wooden D grip, rounded rectangle in the XY plane, thickness along Z.
    outline=[(-.5,-.3),(-.3,-.5),(.3,-.5),(.5,-.3),(.5,.3),(.3,.5),(-.3,.5),(-.5,.3)]
    pts=[]
    for z in [-thick*.5,thick*.5]:
        for factor in [1,.55]:
            for x,y in outline:pts.append((center[0]+x*width*factor,center[1]+y*height*factor,center[2]+z))
    faces=[]
    for i in range(8):
        j=(i+1)%8
        faces.extend([(i,j,8+j,8+i),(16+i,24+i,24+j,16+j),(i,16+i,16+j,j),(8+i,8+j,24+j,24+i)])
    return mesh(name,pts,faces,role)

def reed():
    lathe('Small dark wet-mud footprint',[(0,.56),(.018,.60),(.035,.56),(.038,0)],'mud',12,xz=(1,.92))
    rng=random.Random(416)
    for ring,count,reach,height,lean,width in [(0,8,.38,.43,.20,.24),(1,8,.21,.59,.25,.25),(2,6,.07,.71,.20,.23)]:
        for i in range(count):
            angle=(i+ring*.37)*math.tau/count
            base=(reach*math.cos(angle),.027,reach*math.sin(angle))
            leaf(f'Reed leaf {ring+1}-{i+1:02}',base,angle,height*rng.uniform(.91,1.02),lean*rng.uniform(.93,1.05),width,
                 ['reed_light','reed','reed_dark'][(i+ring)%3])
    heads=[]
    for i,(x,z,top) in enumerate([(-.31,.10,.88),(-.20,-.21,.94),(.04,-.26,.99),(.27,-.12,.94),(.31,.15,.88),(.02,.25,.85)]):
        center=(x,top-.095,z)
        beam(f'Cattail {i+1} / slender stem',(x*.7,.032,z*.7),(x,top-.075,z),.013,'stem',4)
        lathe(f'Cattail {i+1} / rounded brown head',[(-.095,0),(-.07,.045),(.055,.045),(.08,.031),(.095,0)],
              'cattail_light' if i%3==0 else 'cattail',6,center)
        heads.append({'center':list(center),'top_m':top,'diameter_m':.09})
    lathe('Small bank pebble 1',[(0,0),(.018,.09),(.06,.075),(.09,0)],'pebble',6,center=(.24,.001,.43),xz=(1,.8))
    lathe('Small bank pebble 2',[(0,0),(.014,.06),(.038,.05),(.054,0)],'pebble',6,center=(.39,.001,.36),xz=(1,.9))
    return {'cattail_count':6,'cattail_heads':heads,'leaf_count':22,'placement':'Bank L / R / B only; not F2',
            'footprint_limit_m':[1.4,1.4],'height_range_m':[.8,1.0]}

def clay():
    n=18;pts=[];faces=[];roles=[]
    for r,y in [(.57,0),(.59,.025),(.52,.065),(.445,.053),(.425,.008)]:
        for i in range(n):
            a=i*math.tau/n;wobble=1+.022*math.sin(3*a)+.011*math.sin(7*a)
            pts.append((math.cos(a)*r*wobble,y,math.sin(a)*r*wobble*.94))
    faces.append(tuple(reversed(range(n))));roles.append('grass_edge')
    for k,role in enumerate(['grass_edge','grass','grass','pit_wall']):
        for i in range(n):faces.append((k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i));roles.append(role)
    pts.append((0,.008,0))
    for i in range(n):faces.append((5*n,4*n+i,4*n+(i+1)%n));roles.append('clay_shade')
    mesh('Low grassy rim and shallow ochre pit',pts,faces,roles)
    lathe('Smooth raw clay mound',[(0,.28),(.035,.34),(.105,.29),(.18,.18),(.215,0)],'clay',16,center=(-.06,.009,.035),xz=(1,.92))
    lathe('Small raw clay lobe',[(0,0),(.035,.14),(.075,.12),(.11,0)],'clay_light',8,center=(.18,.009,-.14),xz=(1,.85))
    box('Small clay block 1',(.32,.065,.24),(.15,.095,.12),'clay',.016,yaw=12)
    box('Small clay block 2',(.41,.055,.07),(.13,.075,.105),'clay_light',.014,yaw=-10)
    box('Thin spade blade in clay',(-.18,.16,-.10),(.125,.13,.023),'spade',.009,lean=-14)
    beam('Slender wooden spade shaft',(-.18,.16,-.10),(-.235,.410,-.15),.016,'wood',6)
    grip('Open wooden spade grip',(-.238,.443,-.15),.13,.082,.027,'wood_light')
    return {'clay_blocks':2,'footprint_limit_m':[1.2,1.2],'height_limit_m':.5,
            'placement':'F2 (7.6, -1.4); verify >=12px clearance to the switch outer ring',
            'shallow_pit':'Interior at .008m, rim .065m; no negative vertices or terrain shader changes',
            'clay_palette_note':'Muted red-ochre; HSV saturation reduced 17.7–18.6%, value reduced 8.7–9.2% from v1. Wood and grass unchanged.'}

def export_asset(name,builder):
    global PARTS,MATS,PIVOT
    original_colors=dict(COLORS)
    if name=='clay_pit':
        patch=json.loads((SRC/'clay_palette_v11.json').read_text())
        COLORS.update({role:colors['after'] for role,colors in patch['changes'].items()})
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    PARTS=[];MATS={};PIVOT=bpy.data.objects.new(name+' / bottom-centre pivot',None);bpy.context.scene.collection.objects.link(PIVOT)
    PIVOT['task']='SGODOT-416';PIVOT['author']='黄忠';meta=builder();bpy.context.view_layer.update()
    points=[obj.matrix_world@p.co for obj in PARTS for p in obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices]
    center=Vector(((min(p.x for p in points)+max(p.x for p in points))*.5,
                   (min(p.y for p in points)+max(p.y for p in points))*.5,0))
    for obj in PARTS:obj.location-=center
    for head in meta.get('cattail_heads',[]):
        head['center'][0]-=center.x;head['center'][2]+=center.y
    bpy.context.view_layer.update()
    source=bpy.context.scene;parts_stats={}
    depsgraph=bpy.context.evaluated_depsgraph_get()
    for obj in PARTS:
        d=bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph));d.calc_loop_triangles()
        parts_stats[obj.name]=len(d.loop_triangles);bpy.data.meshes.remove(d)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    flat=bpy.data.materials.get('Farm vertex paint') or bpy.data.materials.new('Farm vertex paint');flat.use_nodes=True
    p=flat.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=(1,1,1,1)
    p.inputs['Roughness'].default_value=.9;p.inputs['Metallic'].default_value=0;p.inputs['Specular IOR Level'].default_value=.16
    color=flat.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='Color';flat.node_tree.links.new(color.outputs['Color'],p.inputs['Base Color'])
    exp=bpy.data.scenes.new('Temporary export');copies=[]
    for obj in PARTS:
        d=bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph));d.transform(obj.matrix_world)
        layer=d.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        for f in d.polygons:
            color=d.materials[f.material_index].diffuse_color
            for i in f.loop_indices:layer.data[i].color=color
        d.materials.clear();d.materials.append(flat)
        for f in d.polygons:f.material_index=0
        d.color_attributes.active_color=layer;d.color_attributes.render_color_index=0
        o=bpy.data.objects.new('Export part',d);exp.collection.objects.link(o);copies.append(o)
    bpy.context.window.scene=exp
    for obj in copies:obj.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();body=bpy.context.object;body.name=name;body.data.name=name+'_mobile'
    bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
    body.data.calc_loop_triangles();tri=len(body.data.loop_triangles);assert tri<=900,(name,tri)
    path=KIT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,
        export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,
        export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
    coords=[(p.co.x,p.co.z,-p.co.y) for p in body.data.vertices]
    lo=[min(p[i] for p in coords) for i in range(3)];hi=[max(p[i] for p in coords) for i in range(3)]
    result={'task':'SGODOT-416','revision':'v1.1' if name=='clay_pit' else 'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
        'generator':'tools/art/source/reed_clay_416/build.py','source':f'tools/art/source/reed_clay_416/{name}.blend',
        'triangles':tri,'triangle_limit':900,'surfaces':1,'bytes':path.stat().st_size,'mesh':name+'_mobile',
        'bounds':[lo,hi],'bounds_blender':[[lo[0],-hi[2],lo[1]],[hi[0],-lo[2],hi[1]]],
        'dimensions_xyz':[hi[i]-lo[i] for i in range(3)],'origin':'bottom footprint centre; Y up, +Z front; metres',
        'material':'Farm vertex paint / FarmArt.material(), linear vertex colour, matte .9, no textures',
        'palette_srgb':dict(COLORS),'source_parts_triangles':parts_stats,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),**meta}
    bpy.context.window.scene=source;bpy.data.scenes.remove(exp)
    COLORS.clear();COLORS.update(original_colors)
    print('ASSET_READY',name,tri,lo,hi,flush=True);return result

bpy.context.preferences.filepaths.save_version=0
manifest=KIT/'manifest.json';content=json.loads(manifest.read_text())
import sys
selection=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for name,build in [('reed_bank',reed),('clay_pit',clay)]:
    if not selection or name in selection:content['assets'][name]=export_asset(name,build)
manifest.write_text(json.dumps(content,ensure_ascii=False,indent=2)+'\n')
