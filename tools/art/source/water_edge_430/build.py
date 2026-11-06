"""SGODOT-430: five single-layer foam sheets matching coast kit ports.
Run Blender under flock ~/gs66-render.lock. Godot (x,y,z) -> Blender(x,-z,y).
"""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,shutil
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
OUT=ROOT/'assets/landmarks/_shared/water_edge';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
texture=ROOT/'assets/landmarks/alcatraz_island/alc_foam_soft.png'
shutil.copy2(texture,OUT/'water_edge_soft.png')
mat=bpy.data.materials.new('Water edge / shared foam');mat.use_nodes=True;mat.use_backface_culling=True
p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(.87,.92,.86,.3);p.inputs['Roughness'].default_value=1
records={};objects=[]
def make(name,sections,closed=False,ports=None):
    pts=[];uv=[];faces=[]
    for i,section in enumerate(sections):
        for j,(x,z) in enumerate(section):pts.append((x,-z,0));uv.append((i/(len(sections)-1),j/2))
    for i in range(len(sections)-1):
        for j in range(2):faces.append((i*3+j,(i+1)*3+j,(i+1)*3+j+1,i*3+j+1))
    mesh=bpy.data.meshes.new(name+' / editable ribbon');mesh.from_pydata(pts,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bm.normal_update()
    for f in bm.faces:
        if f.normal.z<0:f.normal_flip()
    bm.to_mesh(mesh);bm.free()
    mesh.materials.append(mat);layer=mesh.uv_layers.new(name='UVMap')
    for loop in mesh.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
    col=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(col)
    obj=bpy.data.objects.new(name,mesh);col.objects.link(obj);objects.append(obj)
    mesh.calc_loop_triangles();assert len(mesh.loop_triangles)<=80
    records[name]={'file':name+'.glb','triangles':len(mesh.loop_triangles),'surfaces':1,'closed':closed,'ports':ports or [],'local_water_y':0,'root_scale':[1,1,1]}
D=[.40,.64,.88]
for kind in ['straight','outer','inner']:
    sec=[]
    for i in range(11):
        t=i/10;s=math.sin(t*math.pi/2);c=math.cos(t*math.pi/2)
        if i==0:s,c=0,1
        if i==10:s,c=1,0
        sec.append([(-1+2*t,d) if kind=='straight' else (-1+(1+d)*s,-1+(1+d)*c) if kind=='outer' else (-1+(1-d)*s,1-(1-d)*c) for d in D])
    make('water_edge_'+kind,sec,ports=[{'coast_port':[-1,0,0],'edge_xz':sec[0],'uv_u':0},{'coast_port':[1,0,0] if kind=='straight' else [0,0,-1 if kind=='outer' else 1],'edge_xz':sec[-1],'uv_u':1}])
sec=[]
for i in range(17):
    a=math.tau*i/16;sec.append([(r*math.cos(a),r*math.sin(a)) for r in [.08,.215,.35]])
make('water_edge_pile_ring',sec,True)
# At nominal sea Y=.2, the last .15 m tread is submerged. Contact is z=.75.
make('water_edge_steps',[[(x,z) for z in [.68,.93,1.18]] for x in [-1+2*i/10 for i in range(11)]])
scene=bpy.context.scene
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'water_edge.blend'))
for obj in objects:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    path=OUT/(obj.name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_normals=True,export_texcoords=True,export_animations=False,export_cameras=False,export_lights=False)
    records[obj.name].update(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
manifest={'task':'SGODOT-430','author':'刘备','coast_reference_commit':'d72d74f4c0ccbcc922c5691cb8b6866eca1ca8f9','foam_reference_commit':'1442acaf2d4e00cf64ca0c57349e8ed179e84ffe','module_m':2,'water_y_reference':.2,'surface_lift_m':.018,'shore_distance_m':D,'assets':records,'unique_triangles':sum(v['triangles'] for v in records.values()),'texture':{'file':'water_edge_soft.png','source':'#824 alc_foam_soft.png, unchanged bytes','sha256':hashlib.sha256(texture.read_bytes()).hexdigest(),'size':[512,128]},'budget':{'texture_reads':1,'transparent_passes':1,'maximum_foam_layers':1,'triangle_limit_each':80},'source':'tools/art/source/water_edge_430/water_edge.blend'}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
print('WATER_EDGE_BUILT',manifest['unique_triangles'])
