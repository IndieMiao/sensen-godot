"""Seven original N4 prop modules, using the existing room primitive helpers."""
from pathlib import Path
import hashlib
import json
import math
import sys
import bpy
import bmesh
from mathutils import Vector

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
sys.path.insert(0,str(ROOT/'tools/art'))
import scene_room_pipeline as p

KIT=ROOT/'assets/rooms/poi_classroom/props'
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'
H=1.745;DESK_TOP=.65*H
SPECS={}
COLORS={'wood':'E5C6A0','wood_edge':'C59E75','ivory':'E8D8C0','paper':'F6F0DF',
    'chalkboard':'354D42','board_edge':'416052','blue':'487594','sea':'78A4B4','land':'D9CB9B',
    'brass':'C2A064','sage':'87936B','sage_dark':'6E795B','plaster':'E9E5DA','plaster_shade':'C9C7BE',
    'red':'A7614E','graphite':'4D4943','cup':'ADB8B3'}

def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def box(name,at,size,color,bevel=.01):
    obj=p.cube(name,at,size,color,bevel)
    for modifier in obj.modifiers:
        if modifier.type=='BEVEL':modifier.segments=1
    return obj

def begin(name,module,description,quantity=1,wall=False):
    p.begin(name,(len(SPECS)*2.2,0,0))
    SPECS[name]={'name':name,'file':name+'.glb','module':module,'description':description,
        'quantity':quantity,'origin':'back_center' if wall else 'bottom_center','front':'+Z','anchors':[]}

def blackboard():
    begin('blackboard','M06','Blank dark-green chalkboard with softened wood frame and chalk ledge',wall=True)
    box('Blank green writing panel',(0,0,.023),(1.90,1.10,.046),'chalkboard',.012)
    for side in [-1,1]:
        box('Wood frame upright '+str(side),(side*.919,0,.044),(.062,1.10,.055),'wood',.01)
        box('Wood frame rail '+str(side),(0,side*.519,.044),(1.78,.062,.055),'wood',.01)
    box('Empty chalk ledge',(0,-.508,.080),(1.88,.034,.16),'wood_edge',.009)
    SPECS['blackboard']['usable_area_m']=[1.77,.96]

def lectern():
    begin('teacher_desk','M07','Ivory paneled teacher desk with wood top; scenery only, no NPC or use anchors')
    box('Ivory cabinet body',(0,.54,0),(1.22,1.02,.64),'ivory',.025)
    box('Rounded wood desktop',(0,DESK_TOP-.035,0),(1.30,.07,.72),'wood',.02)
    box('Cabinet plinth',(0,.055,0),(1.27,.11,.69),'ivory',.018)
    box('Inset front panel',(0,.56,.326),(1.06,.79,.018),'paper',.009)
    for side in [-1,1]:
        box('Front panel stile '+str(side),(side*.56,.56,.345),(.05,.91,.036),'ivory',.008)
    for y in [.11,1.01]:box('Front horizontal molding '+str(y),(0,y,.345),(1.14,.048,.036),'ivory',.008)
    box('Closed teaching book pages',(.32,DESK_TOP+.025,.07),(.30,.038,.23),'paper',.003)
    for y in [DESK_TOP+.004,DESK_TOP+.046]:
        box('Green teaching book cover '+str(y),(.32,y,.07),(.32,.008,.25),'sage',.003)
    SPECS['teacher_desk']['desktop_height_m']=DESK_TOP
    SPECS['teacher_desk']['mounts']=[{'name':'globe_mount','position':[-.32,DESK_TOP,0]}]
    SPECS['teacher_desk']['colliders']=[{'position':[0,DESK_TOP/2,0],'size':[1.30,DESK_TOP,.72]}]

def globe():
    begin('globe','M08','Separate tilted classroom globe; vertex-colored continents and matte brass meridian')
    p.lathe('Stepped round globe foot',(0,0,0),[(0,.082),(.012,.09),(.030,.075),(.043,.048)],'brass',12)
    p.cylinder('Globe pedestal',(0,.083,0),.019,.09,'brass',vertices=8)
    center=Vector((0,.285,0));radius=.16;tilt=math.radians(18)
    obj=p.ellipsoid('Globe sphere',center,(radius*2,)*3,'sea',16,8)
    obj.data.materials.append(p.b.material('land'))
    def ellipse(lon,lat,x,y,rx,ry):return ((lon-x)/rx)**2+((lat-y)/ry)**2<1
    for face in obj.data.polygons:
        n=face.center.normalized();lon=math.degrees(math.atan2(n.x,-n.y));lat=math.degrees(math.asin(n.z))
        land=(ellipse(lon,lat,-105,47,43,26) or ellipse(lon,lat,-59,-20,20,36)
            or ellipse(lon,lat,20,-1,26,36) or ellipse(lon,lat,66,48,85,23)
            or ellipse(lon,lat,135,-26,23,16) or ellipse(lon,lat,-42,75,15,12))
        face.material_index=1 if land else 0
    obj.rotation_euler.y=tilt
    points=[]
    for i in range(17):
        a=math.tau*i/16;x=.177*math.sin(a);y=.177*math.cos(a)
        points.append((x*math.cos(tilt)-y*math.sin(tilt),center.y+x*math.sin(tilt)+y*math.cos(tilt),0))
    p.tube('Brass meridian hoop',points,.008,'brass',4)
    p.tube('Tilted polar axle',[(-math.sin(tilt)*.185,center.y+math.cos(tilt)*.185,0),
        (math.sin(tilt)*.185,center.y-math.cos(tilt)*.185,0)],.007,'brass',6)

def stationery():
    begin('desk_stationery','M05','Open blank book and hollow pencil cup with three pencils',quantity=2)
    x=-.09;z=.015
    box('Open book lower cover',(x,.008,z),(.37,.016,.27),'blue',.003)
    verts=[]
    for zz in [-.112,.112]:
        for xx,yy in [(-.174,.027),(-.09,.040),(0,.020),(.09,.040),(.174,.027)]:
            verts.append((x+xx,yy,z+zz))
    for zz in [-.112,.112]:
        for xx in [-.174,-.09,0,.09,.174]:verts.append((x+xx,.013,z+zz))
    faces=[(i,i+1,i+6,i+5) for i in range(4)]
    faces += [(10+i,15+i,16+i,11+i) for i in range(4)]
    faces += [(i,10+i,11+i,i+1) for i in range(4)]
    faces += [(5+i,6+i,16+i,15+i) for i in range(4)]
    faces += [(0,5,15,10),(4,14,19,9)]
    p.mesh('Gently curved blank pages',verts,faces,'paper',smooth=True)
    p.mesh('Open book center crease',[(x-.0015,.0208,z-.11),(x+.0015,.0208,z-.11),
        (x+.0015,.0208,z+.11),(x-.0015,.0208,z+.11)],[(0,1,2,3)],'ivory')
    p.lathe('Hollow gray pencil cup',(.22,0,-.02),[(0,.045),(.015,.047),(.112,.05),(.12,.047),(.12,.036),(.025,.033)],'cup',8)
    for i,color in enumerate(['wood','blue','red']):
        start=(.20+i*.018,.035,-.025+(i%2)*.018)
        end=(start[0]+(i-1)*.013,.205+i*.018,start[2]-.018+i*.007)
        p.tube('Pencil shaft '+str(i+1),[start,end],.0055,color,5)
        p.cylinder('Pencil graphite '+str(i+1),(end[0],end[1]+.007,end[2]),.0055,.014,'graphite',top=.0008,vertices=5)

def ring_form(name,center,rings,color,sides=10):
    verts=[]
    for y,rx,rz,zshift in rings:
        for i in range(sides):
            a=math.tau*i/sides
            verts.append((center[0]+rx*math.cos(a),y,center[2]+zshift+rz*math.sin(a)))
    faces=[tuple(reversed(range(sides))),tuple((len(rings)-1)*sides+i for i in range(sides))]
    for j in range(len(rings)-1):
        for i in range(sides):faces.append((j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i))
    return p.mesh(name,verts,faces,color,smooth=True)

def study():
    begin('plaster_study','M12','Neutral plaster head-and-shoulders study plus faceted geometric solid; no religious motifs')
    x=-.20
    p.lathe('Plaster display foot',(x,0,0),[(0,.105),(.025,.11),(.045,.085)],'plaster',10)
    ring_form('Cropped shoulder bust',(x,0,0),[(.043,.074,.052,0),(.14,.15,.07,0),(.21,.095,.067,0),(.235,.044,.044,0)],'plaster',10)
    p.cylinder('Neck',(x,.247,0),.042,.08,'plaster',vertices=8)
    ring_form('Sculpted head',(x,0,0),[(.275,.038,.043,.015),(.31,.065,.060,.012),(.35,.078,.071,.006),
        (.395,.088,.077,0),(.44,.085,.079,-.004),(.48,.07,.069,-.005),(.505,.032,.035,-.005)],'plaster',10)
    nose=[(x-.014,.405,.073),(x+.014,.405,.073),(x+.018,.35,.076),(x-.018,.35,.076),
          (x-.008,.372,.109),(x+.008,.372,.109)]
    p.mesh('Defined nose bridge',nose,[(0,1,5,4),(0,4,3),(1,2,5),(3,4,5,2),(0,3,2,1)],'plaster')
    for side in [-1,1]:
        box('Sculpted brow '+str(side),(x+side*.037,.41,.072),(.042,.012,.014),'plaster',0)
        p.mesh('Recessed eye '+str(side),[(x+side*.037-.015,.397,.075),(x+side*.037+.015,.397,.075),
            (x+side*.037+.011,.391,.078),(x+side*.037-.011,.391,.078)],[(0,1,2,3)],'plaster_shade')
        p.ellipsoid('Ear '+str(side),(x+side*.085,.375,-.002),(.028,.052,.035),'plaster',6,4)
    p.mesh('Subtle mouth crease',[(x-.021,.331,.072),(x+.021,.331,.072),(x+.014,.327,.073),(x-.014,.327,.073)],[(0,1,2,3)],'plaster_shade')
    box('Geometric study plinth',(.19,.012,0),(.22,.024,.22),'plaster',.006)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.14,location=p.b.v((.19,.15,0)))
    solid=bpy.context.object
    bottom=min(solid.data.polygons,key=lambda face:face.normal.z)
    rotation=bottom.normal.rotation_difference(Vector((0,0,-1)))
    solid.rotation_mode='QUATERNION';solid.rotation_quaternion=rotation
    solid.location.z=.024-min((rotation@vertex.co).z for vertex in solid.data.vertices)
    p.b.finish(solid,'Faceted geometric study','plaster',smooth=False)

def cushion():
    begin('reading_cushion','M13','Soft sage reading cushion; decoration only, no seat anchor',quantity=2)
    obj=p.lathe('Soft domed cushion',(0,0,0),[(0,.22),(.015,.275),(.05,.30),(.11,.285),(.15,.19),(.16,.045)],'sage',16)
    obj.data.materials.append(p.b.material('sage_dark'))
    for face in obj.data.polygons:
        if face.center.z<.025:face.material_index=1

def sign():
    begin('name_sign','M19','Blank ivory runtime sign with thin wood frame',wall=True)
    box('Blank sign panel',(0,0,.018),(1.45,.38,.036),'paper',.01)
    for side in [-1,1]:
        box('Sign frame vertical '+str(side),(side*.710,0,.026),(.03,.38,.04),'wood_edge',.005)
        box('Sign frame horizontal '+str(side),(0,side*.175,.026),(1.39,.03,.04),'wood_edge',.005)
    SPECS['name_sign']['anchors']=[{'name':'sign_door','position':[0,0,.052],'yaw_degrees':0,
        'size':[1.30,.28],'module':'name_sign','text':'','front':'+Z'}]

def export():
    bpy.context.view_layer.update()
    mat=bpy.data.materials.new('ClassroomPropsVertex');mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(1,1,1,1)
    bsdf.inputs['Roughness'].default_value=.9;bsdf.inputs['Specular IOR Level'].default_value=.18
    color=mat.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='Color'
    mat.node_tree.links.new(color.outputs['Color'],bsdf.inputs['Base Color'])
    original=bpy.context.scene;temp=bpy.data.scenes.new('Temporary GLB export')
    for name,kit in p.KITS.items():
        copies=[];points=[]
        for src in kit['objects']:
            graph=bpy.context.evaluated_depsgraph_get();data=bpy.data.meshes.new_from_object(src.evaluated_get(graph),preserve_all_data_layers=True,depsgraph=graph)
            data.transform(kit['root'].matrix_world.inverted()@src.matrix_world)
            layer=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
            for face in data.polygons:
                rgb=data.materials[face.material_index].diffuse_color
                for index in face.loop_indices:layer.data[index].color=rgb
                face.material_index=0
            data.materials.clear();data.materials.append(mat)
            data.color_attributes.active_color=layer;data.color_attributes.render_color_index=0
            for uv in list(data.uv_layers):data.uv_layers.remove(uv)
            obj=bpy.data.objects.new(name+'_part',data);temp.collection.objects.link(obj);copies.append(obj)
            points.extend(Vector((v.co.x,v.co.z,-v.co.y)) for v in data.vertices)
        low=Vector(tuple(min(v[i] for v in points) for i in range(3)));high=Vector(tuple(max(v[i] for v in points) for i in range(3)))
        pivot=Vector(((low.x+high.x)/2,(low.y+high.y)/2 if SPECS[name]['origin']=='back_center' else low.y,
            low.z if SPECS[name]['origin']=='back_center' else (low.z+high.z)/2))
        for obj in copies:
            for vertex in obj.data.vertices:vertex.co-=p.b.v(pivot)
        for source in kit['objects']:source.location-=p.b.v(pivot)
        for anchor in SPECS[name]['anchors']:anchor['position']=list(Vector(anchor['position'])-pivot)
        for mount in SPECS[name].get('mounts',[]):mount['position']=list(Vector(mount['position'])-pivot)
        for collider in SPECS[name].get('colliders',[]):collider['position']=list(Vector(collider['position'])-pivot)
        bpy.context.window.scene=temp;bpy.ops.object.select_all(action='DESELECT')
        for obj in copies:obj.select_set(True)
        bpy.context.view_layer.objects.active=copies[0]
        if len(copies)>1:bpy.ops.object.join()
        obj=bpy.context.object
        obj.name='Body';obj.data.name=name+'_mobile'
        bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=list(bm.faces))
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_area()<1e-12],context='FACES')
        bm.to_mesh(obj.data);bm.free();obj.data.calc_loop_triangles()
        extras=[]
        for anchor in SPECS[name]['anchors']:
            node=bpy.data.objects.new(anchor['name'],None);temp.collection.objects.link(node)
            node.location=p.b.v(anchor['position']);node.parent=obj
            node['size']=anchor['size'];node['module']=name;node.select_set(True);extras.append(node)
        bpy.ops.export_scene.gltf(filepath=str(KIT/(name+'.glb')),export_format='GLB',use_selection=True,use_active_scene=True,
            export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,
            export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False,export_extras=True)
        spec=SPECS[name];spec['triangles']=len(obj.data.loop_triangles);spec['surfaces']=1
        spec['bounds']=[list(low-pivot),list(high-pivot)];spec['dimensions_m']=list(high-low)
        spec['sha256']=hashlib.sha256((KIT/spec['file']).read_bytes()).hexdigest()
        for node in extras:bpy.data.objects.remove(node,do_unlink=True)
        bpy.data.objects.remove(obj,do_unlink=True);bpy.context.window.scene=original
        provenance={'asset':name,'module':spec['module'],'author':'黄忠','virtual_user_id':AUTHOR,
            'kind':'new authored geometry','reference':'SGODOT-317 R3 approved main and prop/module lists',
            'source_blend':'tools/art/source/poi_classroom/props/classroom_props.blend','source_script':'tools/art/source/poi_classroom/props/build_props.py',
            'changes':[spec['description']],'material':'one matte vertex-color material, no texture'}
        write(SRC/'modules'/name/'reuse_provenance.json',provenance)
        spec['provenance']=str((SRC/'modules'/name/'reuse_provenance.json').relative_to(ROOT))
        print('PROP',name,spec['triangles'],spec['dimensions_m'],flush=True)
    bpy.data.scenes.remove(temp)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'classroom_props.blend'))
    manifest={'revision':'v1','author':'黄忠','virtual_user_id':AUTHOR,'baseline_height_m':H,
        'axes':'metres, Y up, +Z front','material':'ClassroomPropsVertex; matte vertex colours; zero textures',
        'scope':'Seven unique modules / nine placed instances. No room assembly or seat/NPC anchors.',
        'assets':list(SPECS.values()),'unique_triangles':sum(s['triangles'] for s in SPECS.values()),
        'placed_triangles':sum(s['triangles']*s['quantity'] for s in SPECS.values())}
    write(KIT/'prop_manifest.json',manifest)
    assert all(s['triangles']<=600 for s in SPECS.values())
    assert manifest['placed_triangles']<=3000,manifest['placed_triangles']
    print('CLASSROOM_PROPS_READY',manifest['unique_triangles'],manifest['placed_triangles'],flush=True)

if __name__=='__main__':
    p.start('poi_classroom/props','SGODOT-322 independent props / 317 R3');p.b.PALETTE.update(COLORS)
    blackboard();lectern();globe();stationery();study();cushion();sign();export()
