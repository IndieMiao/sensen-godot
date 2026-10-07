"""R2.1 sculpted smoke and volumetric flames, using accepted 172's height palette."""
import math, json, shutil, hashlib
from pathlib import Path
import bpy
import scene_room_pipeline as p
from scene_room_pipeline import mesh, material, ellipsoid, v
import takeover as t
ROOT=Path(__file__).resolve().parents[4]

def smoke():
    t.clear('smoke')
    # Four joined, softly remeshed cloud volumes. No equal-spaced sphere chain.
    groups=[((0,.10,0),(.31,.35,.29),'9BA3A7'),((.07,.43,.015),(.52,.52,.44),'B3BABC'),((.31,.87,-.04),(.74,.65,.56),'C9CED0'),((.72,1.29,-.10),(1.02,.77,.69),'DDE0DF')]
    for i,(center,size,color) in enumerate(groups):
        parts=[]
        for j,(dx,dy,dz,factor) in enumerate([(0,0,0,1),(-.34,.02,.12,.73),(.31,.12,-.04,.66),(.03,.29,.15,.69),(.15,-.20,-.18,.61)]):
            at=tuple(center[k]+[dx,dy,dz][k]*size[k] for k in range(3))
            parts.append(ellipsoid('Cloud lobe',at,tuple(s*factor for s in size),color,16,12))
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();o=parts[0]
        rec=p.KITS['smoke'];rec['objects'][:]=[q for q in rec['objects'] if q not in parts or q is o]
        o.name='Smoke cloud %d fused irregular volume'%(i+1)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        mod=o.modifiers.new('Unify overlapping lobes','REMESH');mod.mode='VOXEL';mod.voxel_size=.026;mod.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Soft cloud transitions','SMOOTH');mod.factor=1.25;mod.iterations=4;bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Mobile cloud silhouette','DECIMATE');mod.ratio=.40;bpy.ops.object.modifier_apply(modifier=mod.name)
        for poly in o.data.polygons:poly.use_smooth=True
        # Single swatch per named cloud keeps top paler than bottom, without baked contact stripes.
        o.data.materials.clear();o.data.materials.append(material(color));o['atlas_constant_colour']=True

def fire():
    t.clear('fire')
    source=ROOT/'assets/rooms/standard_room_5/fire_gradient.png';target=p.OUT/'fire_gradient.png';shutil.copy2(source,target)
    image=bpy.data.images.load(str(target),check_existing=True);image.pack()
    mat=bpy.data.materials.new('172 orange red fire height gradient');mat.use_nodes=True
    nt=mat.node_tree;tex=nt.nodes.new('ShaderNodeTexImage');tex.image=image;uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='FireHeightUV';nt.links.new(uv.outputs[0],tex.inputs[0]);bs=nt.nodes.get('Principled BSDF');nt.links.new(tex.outputs['Color'],bs.inputs['Base Color']);nt.links.new(tex.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.22
    for i,(x,z,h,lean) in enumerate([(-.39,-.03,.37,-.09),(-.23,-.085,.64,.10),(-.05,-.08,.76,-.07),(.17,-.06,.59,.11),(.35,.015,.43,.04),(-.14,.12,.35,.06),(.13,.16,.30,-.07)]):
        verts=[];faces=[];rows=11;sides=14
        for row in range(rows):
            f=row/(rows-1);cx=x+lean*f+math.sin(f*math.pi*2+i)*.035*f
            r=max(.003,(.038+.092*math.sin(math.pi*f)**.8)*(1-f**1.45))
            for j in range(sides):
                a=j*math.tau/sides;verts.append((cx+math.cos(a)*r,f*h,z+math.sin(a)*r*.88+.03*math.sin(f*math.pi)))
        for row in range(rows-1):
            for j in range(sides):faces.append((row*sides+j,row*sides+(j+1)%sides,(row+1)*sides+(j+1)%sides,(row+1)*sides+j))
        faces += [tuple(reversed(range(sides))),tuple((rows-1)*sides+j for j in range(sides))]
        o=mesh('Volumetric curling flame %d'%(i+1),verts,faces,'EB4C12',smooth=True);o.data.materials.clear();o.data.materials.append(mat)
        layer=o.data.uv_layers.new(name='FireHeightUV')
        for loop in o.data.loops:layer.data[loop.index].uv=(.5,max(0,min(1,o.data.vertices[loop.vertex_index].co.z/h)))
    # Dark red clinker bed, with small fissures glowing between darker crusts.
    t.clear('forge_coals')
    for row in range(3):
        for col in range(9):
            x=-.48+col*.117+.017*math.sin(row*9+col);z=-.17+row*.15
            o=ellipsoid('Dark red ember clinker',(x,.035+.011*math.sin(col),z),(.15,.095,.145),['6B1710','8A2514','4E1811','A13516'][(row+col)%4],10,6);o['atlas_constant_colour']=True
            p.tube('Glowing coal fissure',[(x-.039,.077,z+.027),(x,.084,z+.042),(x+.036,.074,z+.02)],.009,'C64C1C',5)
    (p.SOURCE/'fire-gradient-reuse.json').write_text(json.dumps({'source':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'copied_to':str(target.relative_to(ROOT)),'source_read_only':True,'uv':'FireHeightUV, each tongue base 0 / tip 1'},indent=2)+'\n')

def export_fire():
    verts=[];faces=[];uvs=[]
    for source in p.KITS['fire']['objects']:
        off=len(verts);verts.extend(source.data.vertices[i].co.copy() for i in range(len(source.data.vertices)))
        for poly in source.data.polygons:
            faces.append(tuple(off+i for i in poly.vertices));uvs.extend(source.data.uv_layers['FireHeightUV'].data[i].uv.copy() for i in poly.loop_indices)
    data=bpy.data.meshes.new('Seven volumetric fire tongues');data.from_pydata(verts,[],faces);data.update();uv=data.uv_layers.new(name='FireHeightUV')
    for i,co in enumerate(uvs):uv.data[i].uv=co
    for poly in data.polygons:poly.use_smooth=True
    data.materials.append(p.KITS['fire']['objects'][0].data.materials[0]);o=bpy.data.objects.new('Fire local pivot export',data);bpy.context.scene.collection.objects.link(o)
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    bpy.ops.export_scene.gltf(filepath=str(p.OUT/'fire.glb'),export_format='GLB',use_selection=True,export_yup=True,export_normals=True,export_texcoords=True,export_image_format='NONE',export_animations=False)
    bpy.data.objects.remove(o,do_unlink=True)
    stats_path=p.OUT/'asset_stats.json';stats=json.loads(stats_path.read_text())
    for a in stats['assets']:
        if a['name']=='fire':a['bytes']=(p.OUT/'fire.glb').stat().st_size
    stats['glb_bytes']=sum(a['bytes'] for a in stats['assets']);stats['fire_gradient']={'file':'fire_gradient.png','size':[32,128],'source':'accepted SGODOT-172 R2.1','bytes':(p.OUT/'fire_gradient.png').stat().st_size};stats_path.write_text(json.dumps(stats,indent=2)+'\n')
