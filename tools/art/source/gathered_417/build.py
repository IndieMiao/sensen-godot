"""SGODOT-417: seven quiet gathered variants, retaining resource-point origins.

Blender 5.2. Reuse actual editable mud/soil/rim/stump/spade parts where specified.
All dimensions below are metres in Godot coordinates (Y up, +Z front).
"""
from pathlib import Path
import hashlib,json,math,sys
import bpy,bmesh
import numpy as np
from mathutils import Matrix,Vector

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/farm/art'
ORIGINALS=json.loads((SRC/'original_metrics.json').read_text())
COLORS={'patch':'A9B581','herb_base':'BEC59D','leaf':'78984B','trunk':'A47A4C',
        'pale_bark':'B18C5C','pale_cut':'D9C192','pale_ring':'9D7C4F',
        'walnut':'78472F','walnut_cut':'D0A575','walnut_ring':'855235',
        'stone':'8F9788','pebble':'9CA591','reed_stem':'92AA4F','reed_cut':'C7CB8A',
        'herb':'B8CCA3','herb_stem':'8BA66F','flax_stem':'799973','flax_cut':'B5C18D',
        'regrowth':'8FA46B','clay':'B27A5A','clay_floor':'9D674B'}
PARTS=[];PROXIES=[];REUSE=[];MATS={};PIVOT=None;SPROUTS=[]

def linear(h):
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in [v/255 for v in bytes.fromhex(h)])
def v(p):return Vector((p[0],-p[2],p[1]))
def game(p):return [p.x,p.z,-p.y]
def material(role):
    if role not in MATS:
        m=bpy.data.materials.new(role);m.use_nodes=True;m.diffuse_color=(*linear(COLORS[role]),1)
        p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color
        p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.16;MATS[role]=m
    return MATS[role]
def own(obj,name,role=None,smooth=False,proxy=False):
    obj.name=name;obj.parent=PIVOT
    if role:
        obj.data.materials.clear();obj.data.materials.append(material(role))
        for f in obj.data.polygons:f.material_index=0;f.use_smooth=smooth
    PARTS.append(obj)
    if proxy:PROXIES.append(obj)
    return obj
def mesh(name,points,faces,roles,smooth=False,proxy=False):
    d=bpy.data.meshes.new(name);d.from_pydata([v(p) for p in points],[],faces);d.update()
    obj=bpy.data.objects.new(name,d);bpy.context.scene.collection.objects.link(obj)
    roles=[roles]*len(faces) if isinstance(roles,str) else roles
    names=list(dict.fromkeys(roles))
    for key in names:d.materials.append(material(key))
    for f,key in zip(d.polygons,roles):f.material_index=names.index(key);f.use_smooth=smooth
    bm=bmesh.new();bm.from_mesh(d);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free()
    return own(obj,name,proxy=proxy)
def lathe(name,profile,role,n=12,at=(0,0,0),xz=(1,1),proxy=False,top_role=None):
    pts=[];rings=[];faces=[];roles=[]
    for y,r in profile:
        ring=[]
        for i in range(n if r else 1):
            a=i*math.tau/n;ring.append(len(pts));pts.append((at[0]+r*math.cos(a)*xz[0],at[1]+y,at[2]+r*math.sin(a)*xz[1]))
        rings.append(ring)
    for a,b in zip(rings,rings[1:]):
        for i in range(n):
            j=(i+1)%n
            faces.append((a[0],b[i],b[j]) if len(a)==1 else (a[i],b[0],a[j]) if len(b)==1 else (a[i],b[i],b[j],a[j]));roles.append(role)
    if len(rings[0])>1:faces.append(tuple(reversed(rings[0])));roles.append(role)
    if len(rings[-1])>1:faces.append(tuple(rings[-1]));roles.append(top_role or role)
    return mesh(name,pts,faces,roles,True,proxy)
def ellipsoid(name,at,size,role,n=6,rings=3,tilt=0,yaw=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=n,ring_count=rings,radius=1,location=v(at));obj=bpy.context.object
    obj.scale=(size[0]/2,size[2]/2,size[1]/2);obj.rotation_euler=(0,tilt,yaw)
    return own(obj,name,role,True)
def ico(name,at,size,role,subdivisions=1,proxy=False):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions,radius=1,location=v(at));obj=bpy.context.object
    obj.scale=(size[0]/2,size[2]/2,size[1]/2)
    return own(obj,name,role,True,proxy)
def patch(name,width,depth,role='patch'):
    return lathe(name,[(0,width*.46),(.018,width*.5),(.028,width*.48),(.030,0)],role,12,xz=(1,depth/width),proxy=True)
def sprout(at,index):
    # Exactly one unscaled template, one colour, reused by all four plant kinds.
    prefix=f'Regrowth sprout {index}'
    created=[lathe(prefix+' / stem',[(0,.012),(.105,.010)],'regrowth',4,at=at)]
    for sign in [-1,1]:
        p=(at[0]+sign*.055,at[1]+.140,at[2])
        created.append(ellipsoid(prefix+f' / leaf {sign:+}',p,(.15,.080,.060),'regrowth',6,3,tilt=-sign*.55))
    SPROUTS.append({'origin':list(at),'parts':[o.name for o in created],'template':'single pair of oval leaves / 0.012m stem / #8FA46B / scale 1'})
def stump(name,at,radius,height,bark,cut,ring):
    n=10;pts=[];faces=[];roles=[]
    for y,r in [(0,radius),(.04,radius*.96),(height,radius*.86)]:
        for i in range(n):
            a=i*math.tau/n;pts.append((at[0]+r*math.cos(a),at[1]+y,at[2]+r*math.sin(a)))
    faces.append(tuple(reversed(range(n))));roles.append(bark)
    for level in range(2):
        for i in range(n):faces.append((level*n+i,level*n+(i+1)%n,(level+1)*n+(i+1)%n,(level+1)*n+i));roles.append(bark)
    previous=list(range(2*n,3*n))
    for factor,is_ring in [(.66,False),(.56,True),(.32,False),(.22,True)]:
        current=[]
        for i in range(n):
            a=i*math.tau/n;current.append(len(pts));pts.append((at[0]+radius*factor*math.cos(a),at[1]+height,at[2]+radius*factor*math.sin(a)))
        for i in range(n):faces.append((previous[i],previous[(i+1)%n],current[(i+1)%n],current[i]));roles.append(ring if is_ring else cut)
        previous=current
    pts.append((at[0],at[1]+height,at[2]));center=len(pts)-1
    for i in range(n):faces.append((previous[i],previous[(i+1)%n],center));roles.append(cut)
    return mesh(name,pts,faces,roles)
def load_parts(relative,names,proxy_names=()):
    path=ROOT/relative
    with bpy.data.libraries.load(str(path),link=False) as (source,destination):
        assert set(names)<=set(source.objects),(relative,set(names)-set(source.objects))
        destination.objects=list(names)
    loaded=[]
    for obj,requested in zip(destination.objects,names):
        bpy.context.scene.collection.objects.link(obj);bpy.context.view_layer.update();transform=obj.matrix_world.copy()
        obj.parent=PIVOT;obj.matrix_world=transform;obj.name=requested
        PARTS.append(obj);loaded.append(obj)
        if requested in proxy_names:PROXIES.append(obj)
    REUSE.append({'source':relative,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'parts':names})
    return loaded
def evaluated_points(objects):
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();points=[]
    for obj in objects:
        d=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps)
        points.extend(obj.matrix_world@p.co for p in d.vertices);bpy.data.meshes.remove(d)
    return points
def base_center(obj):
    points=evaluated_points([obj]);bottom=min(p.z for p in points)
    return sum((p for p in points if p.z<bottom+1e-4),Vector())/sum(p.z<bottom+1e-4 for p in points)

def grove():
    patch('Quiet grove ground',1.50,1.50)
    # Exact centres of the original three-tree factory, not the stand point.
    lathe('Remaining small tree trunk',[(0,.045),(.46,.032)],'trunk',4,at=(.5,.023,-.35))
    ico('Remaining small round canopy',(.5,.66,-.35),(.47,.58,.48),'leaf',2)
    stump('Light growth-ring stump 1',(-.35,.023,.2),.15,.20,'pale_bark','pale_cut','pale_ring')
    stump('Light growth-ring stump 2',(.55,.023,.6),.15,.18,'pale_bark','pale_cut','pale_ring')
    sprout((-.42,.030,-.28),1);sprout((.05,.030,.36),2)
    return {'remaining_tree_root':[.5,0,-.35],'cut_tree_roots':[[-.35,0,.2],[.55,0,.6]],'appearance':'One much smaller tree; two pale growth-ring stumps; two shared regrowth sprouts'}
def rock():
    bpy.ops.import_scene.gltf(filepath=str(KIT/'rock.glb'))
    imported=[o for o in bpy.context.selected_objects if o.type=='MESH'];assert len(imported)==1
    obj=imported[0];obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4)
    pts=[p.co.copy() for p in obj.data.vertices];lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)));hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    for vertex in obj.data.vertices:
        p=vertex.co.copy();vertex.co=((p.x-(lo.x+hi.x)/2)*.82/(hi.x-lo.x),(p.y-(lo.y+hi.y)/2)*.62/(hi.y-lo.y)+.04,(p.z-lo.z)*.15/(hi.z-lo.z))
    for attr in list(obj.data.color_attributes):obj.data.color_attributes.remove(attr)
    own(obj,'Large remaining flat stone','stone',False,True)
    REUSE.append({'source':'assets/farm/art/rock.glb','sha256':hashlib.sha256((KIT/'rock.glb').read_bytes()).hexdigest(),
                  'changes':'Retain rock topology; flatten to .15m high, .82m wide, .62m deep; muted fieldstone vertex colour'})
    for i,(x,z,r) in enumerate([(.36,.30,.055),(-.39,.25,.06),(.29,-.43,.055),(-.15,.37,.05)]):
        ico(f'Tidy pebble {i+1}',(x,r*.45,z),(r*2,r*.9,r*1.8),'pebble')
    return {'main_stone_height_m':.15,'pebble_count':4,'appearance':'Large flat remaining stone and four small pebbles; no sprouts'}
def reed():
    source='tools/art/source/reed_clay_416/reed_bank.blend'
    load_parts(source,['Small dark wet-mud footprint','Small bank pebble 1','Small bank pebble 2'],['Small dark wet-mud footprint'])
    with bpy.data.libraries.load(str(ROOT/source),link=False) as (available,dest):dest.objects=[n for n in available.objects if n.startswith('Reed leaf ')]
    roots=[]
    for obj in dest.objects:
        bpy.context.scene.collection.objects.link(obj);bpy.context.view_layer.update()
        root=sum((obj.matrix_world@p.co for p in list(obj.data.vertices)[:4]),Vector())/4;roots.append(game(root))
        bpy.data.objects.remove(obj,do_unlink=True)
    for i,(x,y,z) in enumerate(roots):lathe(f'Even cut reed {i+1:02}',[(0,.023),(.33-y,.021)],'reed_stem',4,at=(x,y,z),top_role='reed_cut')
    sprout((-.31,.038,-.30),1);sprout((.30,.038,.24),2)
    return {'cut_height_m':.33,'stubble_count':len(roots),'appearance':'Same wet mud and pebbles; neat one-third-height cuts, no cattails; shared sprouts'}
def clay():
    source='tools/art/source/reed_clay_416/clay_pit.blend'
    load_parts(source,['Low grassy rim and shallow ochre pit'],['Low grassy rim and shallow ochre pit'])
    tool=load_parts(source,['Thin spade blade in clay','Slender wooden spade shaft','Open wooden spade grip'])
    pts=np.array([game(p) for p in evaluated_points(tool)]);center=pts.mean(axis=0)
    _,axes=np.linalg.eigh(np.cov((pts-center).T));axes=axes[:,::-1]
    if np.linalg.det(axes)<0:axes[:,-1]*=-1
    # Place the unchanged tool flat and tangent to the front rim.
    target=np.array([[1,0,0],[0,0,1],[0,-1,0]],dtype=float);rotation=target@axes.T
    rotated=(pts-center)@rotation.T;floor=rotated[:,1].min()
    g2b=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
    transform=Matrix(rotation.tolist()).to_4x4()
    transform.translation=Vector((.10,.070-floor,.405))-Matrix(rotation.tolist())@Vector(center.tolist())
    for obj in tool:
        for modifier in list(obj.modifiers):
            bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.data.transform(g2b@transform@g2b.inverted()@obj.matrix_world)
        if obj.data.has_custom_normals:obj.data.normals_split_custom_set([(0,0,0)]*len(obj.data.loops))
        obj.matrix_world=Matrix.Identity(4)
    floor=lathe('Thin remaining red-ochre clay',[(0,.34),(.006,.35),(.008,0)],'clay_floor',12,at=(0,.008,0),xz=(1,.90))
    for face in floor.data.polygons:face.use_smooth=False
    return {'appearance':'Empty original pit, flat thin v1.1 red-ochre clay layer, original spade laid flat; no blocks or sprouts','clay_srgb':'9D674B'}
def herb():
    patch('Pale clipped herb ground',.88,.82,'herb_base')
    for i in range(8):
        a=i*math.tau/8
        ellipsoid(f'Low remaining mint leaf {i+1}',(.24*math.cos(a),.105,.24*math.sin(a)),(.25,.09,.17),'herb',6,3,yaw=-a)
    for i,(x,z) in enumerate([(-.16,.03),(.14,.05),(0,-.14)]):
        lathe(f'Clipped herb stem {i+1}',[(0,.021),(.105,.019)],'herb_stem',4,at=(x,.027,z),top_role='herb')
    return {'appearance':'Clipped, low mint leaves over a pale visible base; leaf clump at least half original width; no separate regrowth sprout'}
def hardwood():
    source='tools/art/source/hardwood_grove_408/hardwood_grove.blend'
    load_parts(source,['Independent ringed stump / walnut bark','Stump cut / three visible growth rings'])
    temporary=load_parts(source,['tree_0 / Tapered tree trunk'])[0]
    REUSE[-1]['usage']='Measure the original trunk base only; trunk geometry is not retained'
    root=game(base_center(temporary));PARTS.remove(temporary);bpy.data.objects.remove(temporary,do_unlink=True)
    patch('Quiet walnut grove ground',1.30,1.20)
    stump('Large walnut growth-ring stump',(root[0],.023,root[2]),.29,.32,'walnut','walnut_cut','walnut_ring')
    sprout((.39,.03,.25),1);sprout((-.32,.03,-.36),2)
    return {'original_tree_root':root,'appearance':'Large walnut stump at original trunk; unchanged small stump; no crown or timber; shared sprouts'}
def flax():
    source='tools/art/source/flax_408/flax_patch.blend'
    load_parts(source,['Soft light-brown soil border'],['Soft light-brown soil border'])
    with bpy.data.libraries.load(str(ROOT/source),link=False) as (available,dest):
        dest.objects=[n for n in available.objects if n.startswith('Stem ') and '/' not in n or n.startswith('Young stem ') and '/' not in n]
    roots=[]
    for obj in dest.objects:
        bpy.context.scene.collection.objects.link(obj);bpy.context.view_layer.update()
        root=sum((obj.matrix_world@p.co for p in list(obj.data.vertices)[:4]),Vector())/4;roots.append(game(root))
        bpy.data.objects.remove(obj,do_unlink=True)
    for i,(x,y,z) in enumerate(roots):lathe(f'Cut flax stem {i+1:02}',[(0,.010),(.135-y,.009)],'flax_stem',4,at=(x,y,z),top_role='flax_cut')
    sprout((-.27,.047,-.25),1);sprout((.26,.047,.24),2)
    return {'cut_height_m':.135,'stubble_count':len(roots),'appearance':'Exact original pale-brown soil; short cut stems, no blue flowers; shared sprouts'}

def export(name,builder):
    global PARTS,PROXIES,REUSE,MATS,PIVOT,SPROUTS
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    PARTS=[];PROXIES=[];REUSE=[];MATS={};SPROUTS=[]
    full=name+'_gathered';PIVOT=bpy.data.objects.new(full+' / resource-point origin',None);bpy.context.scene.collection.objects.link(PIVOT)
    PIVOT['author']='黄忠';PIVOT['task']='SGODOT-417';extra=builder();bpy.context.view_layer.update()
    proxy=[game(p) for p in evaluated_points(PROXIES)]
    source=bpy.context.scene;deps=bpy.context.evaluated_depsgraph_get();stats={}
    for obj in PARTS:
        d=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps);d.calc_loop_triangles();stats[obj.name]=len(d.loop_triangles);bpy.data.meshes.remove(d)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(full+'.blend')))
    flat=bpy.data.materials.get('Farm vertex paint') or bpy.data.materials.new('Farm vertex paint');flat.use_nodes=True
    p=flat.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=(1,1,1,1);p.inputs['Roughness'].default_value=.9;p.inputs['Metallic'].default_value=0;p.inputs['Specular IOR Level'].default_value=.16
    vc=flat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';flat.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
    exp=bpy.data.scenes.new('Temporary export');copies=[]
    for obj in PARTS:
        d=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps);d.transform(obj.matrix_world)
        existing=d.color_attributes.active_color
        paint=[]
        for face in d.polygons:
            for i in face.loop_indices:
                paint.append(tuple(existing.data[i if existing.domain=='CORNER' else d.loops[i].vertex_index].color) if existing else tuple(d.materials[face.material_index].diffuse_color))
        for attr in list(d.color_attributes):d.color_attributes.remove(attr)
        layer=d.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
        for datum,color in zip(layer.data,paint):datum.color=color
        d.materials.clear();d.materials.append(flat)
        for face in d.polygons:face.material_index=0
        d.color_attributes.active_color=layer;d.color_attributes.render_color_index=0
        obj=bpy.data.objects.new('Export part',d);exp.collection.objects.link(obj);copies.append(obj)
    bpy.context.window.scene=exp
    for obj in copies:obj.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();body=bpy.context.object;body.name=full;body.data.name=full+'_mobile'
    bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free();body.data.calc_loop_triangles()
    triangles=len(body.data.loop_triangles);assert triangles<=600,(full,triangles)
    path=KIT/(full+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,
        export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_normals=True,export_texcoords=False,
        export_animations=False,export_cameras=False,export_lights=False)
    points=[game(vertex.co) for vertex in body.data.vertices]
    lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
    original=ORIGINALS[name]['bounds']
    assert all(lo[i]>=original[0][i]-1e-5 and hi[i]<=original[1][i]+1e-5 for i in [0,2]),(full,lo,hi,original)
    assert hi[1]<original[1][1],(full,'not lower')
    result={'task':'SGODOT-417','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
        'triangles':triangles,'triangle_limit':600,'surfaces':1,'bytes':path.stat().st_size,'bounds':[lo,hi],
        'dimensions_xyz':[hi[i]-lo[i] for i in range(3)],'origin':'unchanged original resource-point origin; metres; Y up; +Z front',
        'gathered_from':ORIGINALS[name]['source'],'original_bounds':original,'mesh':full+'_mobile','gathered_variant':True,
        'material':'Farm vertex paint / FarmArt.material(); matte .9, linear vertex colours',
        'source':f'tools/art/source/gathered_417/{full}.blend','generator':'tools/art/source/gathered_417/build.py',
        'reuse_provenance':REUSE,'source_parts_triangles':stats,'regrowth_sprouts':SPROUTS,
        'visibility_parts':[obj.name for obj in PROXIES],'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),**extra}
    review={**result,'visibility_vertices':proxy}
    bpy.context.window.scene=source;bpy.data.scenes.remove(exp)
    print('GATHERED_READY',full,triangles,lo,hi,flush=True);return result,review

bpy.context.preferences.filepaths.save_version=0
manifest_path=KIT/'manifest.json';manifest=json.loads(manifest_path.read_text());reports={}
selection=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for name,builder in [('grove',grove),('rock_pile',rock),('reed_bank',reed),('clay_pit',clay),('herb_patch',herb),('hardwood_grove',hardwood),('flax_patch',flax)]:
    if selection and name not in selection:continue
    result,review=export(name,builder);manifest['assets'][name+'_gathered']=result;reports[name]=review
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
stats_path=SRC/'asset_stats.json';combined=json.loads(stats_path.read_text()) if stats_path.exists() else {};combined.update(reports)
stats_path.write_text(json.dumps(combined,ensure_ascii=False,indent=2)+'\n')
