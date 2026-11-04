"""SGODOT-408 hardwood: adapted tree_0, ringed stump and stacked walnut billets."""
from pathlib import Path
import hashlib,json,math,struct,sys
import bpy,bmesh
from mathutils import Matrix,Vector

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE))
import build_decor_assets as kit

NAME='hardwood_grove';SOURCE=ROOT/'tools/art/source/hardwood_grove_408';OUT=ROOT/'assets/farm/art'
PALETTE={'walnut':'78472F','walnut_edge':'613827','walnut_light':'945B3D',
         'cut':'BD895C','cut_light':'D0A575','growth_ring':'855235',
         'olive':'7D9145','olive_light':'96A954','olive_shade':'657635'}


def assign(obj,role):
    obj.data.materials.clear();obj.data.materials.append(kit.MATS[role])
    for face in obj.data.polygons:face.material_index=0
    obj['colour_role']=role


def adapt_tree():
    path=ROOT/'tools/art/source/farm_reference_kit.blend'
    with bpy.data.libraries.load(str(path),link=False) as (a,b):b.collections=['tree_0']
    col=b.collections[0];bpy.context.scene.collection.children.link(col);bpy.context.view_layer.update()
    trunk=next(o for o in col.objects if o.name.startswith('Tapered tree trunk'))
    # The accepted farm source is laid out as a contact sheet. Undo its XY offset.
    source_offset=Vector((trunk.location.x,trunk.location.y,0))
    tree_xform=Matrix.Translation(kit.v((0,0,-.10)))@Matrix.Diagonal((.78,.82,2.3/2.68,1))@Matrix.Translation(-source_offset)
    retained=[];removed=[]
    for old in list(col.objects):
        if old.type!='MESH':continue
        if old.name.startswith('Grass at tree roots'):
            removed.append(old.name);continue
        name=old.name
        if name.startswith('Rounded orchard canopy'):
            bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=1)
            obj=bpy.context.object
            for c in list(obj.users_collection):c.objects.unlink(obj)
            kit.CURRENT.objects.link(obj)
            obj.name='tree_0 / '+name+' / reduced 12x8 crown'
            obj.matrix_world=tree_xform@old.matrix_world
            role='olive_light' if old.data.materials[0].name=='leaf_light' else 'olive'
            assign(obj,role)
            for face in obj.data.polygons:face.use_smooth=True
        else:
            obj=old.copy();obj.data=old.data.copy();kit.CURRENT.objects.link(obj)
            obj.name='tree_0 / '+name;obj.matrix_world=tree_xform@old.matrix_world
            for mod in obj.modifiers:
                if mod.type=='BEVEL':mod.segments=1
            assign(obj,'walnut')
        obj['original_part']=name;retained.append(name)
    for obj in list(col.objects):bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.collections.remove(col)
    return dict(source=str(path.relative_to(ROOT)),source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                source_asset='tree_0',source_triangles=1624,retained_parts=retained,removed_root_grass=removed,
                adaptation='Retain trunk and branch meshes; reduce branch bevel to one segment. Crown ellipsoids retain source centres/scales but use 12x8 tessellation. X .78 / Z .82, height 2.30 m; roots replaced by small buttresses.')


def roots():
    for i in range(3):
        angle=i*math.tau/3+.2;axis=Vector((math.cos(angle),math.sin(angle)));side=Vector((-axis.y,axis.x))
        points=[]
        for along,across,y in [(0,-.055,0),(0,.055,0),(.25,-.025,0),(.25,.025,0),(0,0,.24),(.20,0,.055)]:
            x,z=axis*along+side*across;points.append((x,y,z-.10))
        kit.mesh('Walnut root buttress %d'%i,points,[(0,2,3,1),(0,1,4),(0,4,5,2),(1,3,5,4),(2,5,3)],'walnut_edge')


def stump():
    n=12;at=Vector((-.42,0,.41))
    profile=[(0,.18),(.04,.175),(.24,.155)]
    vertices=[tuple(at+Vector((r*math.cos(i*math.tau/n),y,r*math.sin(i*math.tau/n)))) for y,r in profile for i in range(n)]
    faces=[tuple(reversed(range(n)))]
    for j in range(len(profile)-1):faces.extend((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for i in range(n))
    bark=kit.mesh('Independent ringed stump / walnut bark',vertices,faces,'walnut')
    if bark.data.polygons[0].normal.z>0:
        bm=bmesh.new();bm.from_mesh(bark.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(bark.data);bm.free();bark.data.update()
    bark.data.materials.append(kit.MATS['walnut_light'])
    for f in bark.data.polygons:
        if f.index%3==1:f.material_index=1
    # A single tessellated top: bands touch at shared edges, so no coplanar overlays.
    radii=[0,.035,.054,.066,.094,.106,.137,.155]
    verts=[tuple(at+Vector((0,.24,0)))];rings=[]
    for radius in radii[1:]:
        rings.append(list(range(len(verts),len(verts)+n)))
        verts.extend(tuple(at+Vector((radius*math.cos(i*math.tau/n),.24,radius*math.sin(i*math.tau/n)))) for i in range(n))
    faces=[];roles=[]
    for i in range(n):faces.append((0,rings[0][i],rings[0][(i+1)%n]));roles.append('cut')
    for j in range(len(rings)-1):
        for i in range(n):faces.append((rings[j][i],rings[j+1][i],rings[j+1][(i+1)%n],rings[j][(i+1)%n]));roles.append('growth_ring' if j in [1,3,5] else 'cut_light')
    top=kit.mesh('Stump cut / three visible growth rings',verts,[tuple(reversed(f)) for f in faces],'cut')
    assert all(f.normal.z>.99 for f in top.data.polygons),'growth-ring top must face up'
    for role in ['cut_light','growth_ring']:top.data.materials.append(kit.MATS[role])
    for f,role in zip(top.data.polygons,roles):f.material_index=['cut','cut_light','growth_ring'].index(role)


def timber():
    for i,(x,y,z,yaw) in enumerate([(.28,.055,.33,1.82),(.28,.055,.50,1.82),(.30,.165,.415,1.82)],1):
        obj=kit.box('Stacked walnut billet %d'%i,(x,y,z),(.14,.11,.60),'walnut_light',.008)
        obj.rotation_euler.z=yaw
        obj.data.materials.append(kit.MATS['cut'])
        for face in obj.data.polygons:
            # Blender -Y is the game's +Z-facing end grain.
            if abs(face.normal.y)>.99:face.material_index=1


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
    for name,value in PALETTE.items():
        mat=bpy.data.materials.new(name);mat.diffuse_color=(*kit.rgb(value),1);mat.use_nodes=True
        bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=mat.diffuse_color
        bsdf.inputs['Roughness'].default_value=.9;bsdf.inputs['Specular IOR Level'].default_value=.18;kit.MATS[name]=mat
    kit.begin(NAME,[1,1],1200,generator='tools/art/build_hardwood_grove.py',pivot='whole footprint bottom centre',front='+Z',
              author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',
              slot_limit_m=[1.5,1.5],height_target_m=2.3,placement_preview=dict(pond='pond_san_francisco_03',slot='L2',xz=[-.3,-9.0],player_xz=[.95,-8.4]),
              harvested_variant=False,collision='none in GLB; runtime resource system owns navigation')
    kit.META[NAME].pop('footprint_cells',None)  # Pond slot dimensions are metres, not farm decor cells.
    provenance=adapt_tree();roots();stump();timber()
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();points=[];parts=[]
    for obj in kit.CURRENT.objects:
        if obj.type!='MESH':continue
        mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps);mesh.calc_loop_triangles()
        points.extend(obj.matrix_world@p.co for p in mesh.vertices);parts.append(dict(name=obj.name,triangles=len(mesh.loop_triangles)))
        bpy.data.meshes.remove(mesh)
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)));hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    offset=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    for obj in kit.CURRENT.objects:obj.location-=offset
    mat=bpy.data.materials.new('Farm vertex paint');mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=.9;bsdf.inputs['Specular IOR Level'].default_value=.18
    vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';mat.node_tree.links.new(vc.outputs['Color'],bsdf.inputs['Base Color'])
    entry=kit.export_asset(NAME,kit.CURRENT,mat)
    path=OUT/(NAME+'.glb');raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:]
    doc['meshes'][0]['name']=NAME+'_mobile';encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    path.write_bytes(struct.pack('<III',0x46546C67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+tail)
    entry.update(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),palette_srgb=PALETTE,
                 source='tools/art/source/hardwood_grove_408/hardwood_grove.blend',parts=parts,reuse_provenance=provenance,
                 material_contract=dict(vertex_color_is_srgb=False,roughness=.9,metallic=0,specular=.18,light_baking=1))
    check_size=[entry['bounds'][1][i]-entry['bounds'][0][i] for i in range(3)]
    assert check_size[0]<=1.5 and check_size[2]<=1.5 and abs(check_size[1]-2.3)<1e-4,check_size
    mpath=OUT/'manifest.json';manifest=json.loads(mpath.read_text());manifest['assets'][NAME]=entry;mpath.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
    SOURCE.mkdir(parents=True,exist_ok=True);(SOURCE/'spec.json').write_text(json.dumps(entry,indent=2,ensure_ascii=False)+'\n')
    bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'hardwood_grove.blend'),compress=True)
    print('HARDWOOD_GROVE',entry['triangles'],'triangles',check_size,flush=True)

if __name__=='__main__':main()
