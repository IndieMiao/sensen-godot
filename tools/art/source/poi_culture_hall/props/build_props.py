"""Original N3 display modules; local pivots, vertex colour, one glass surface."""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys
import bpy
import bmesh
from mathutils import Vector,Matrix

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
sys.path.insert(0,str(ROOT/'tools/art'))
import scene_room_pipeline as p
KIT=ROOT/'assets/rooms/poi_culture_hall/props'
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'
SPECS={}
COLORS={'ivory':'EFDFBD','bed':'F4E8CE','green':'465823','glass':'C2D8D3','glass_edge':'7C8B75',
    'wood':'E3C696','wood_edge':'C7A06B','paper':'F2E5CA','orange':'C66F3F','orange_light':'DB9A63',
    'sage':'83916D','sage_dark':'536746','ochre':'C1A16C','beige':'DCC9A6','grout':'C7B48E',
    'stone':'B9A27E','stone_light':'D5C09C','stone_dark':'927C5C','fossil':'C7AC82','groove':'93734E',
    'clay':'B86742','clay_light':'D68B5C','clay_inner':'8D4E36'}

def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def box(name,at,size,color,bevel=.01):
    obj=p.cube(name,at,size,color,bevel)
    for m in obj.modifiers:
        if m.type=='BEVEL':m.segments=1
    return obj
def begin(name,module,description,quantity=1,wall=False):
    i=len(SPECS);p.begin(name,((i%6)*2.5,0,(i//6)*2.6))
    SPECS[name]={'name':name,'file':name+'.glb','module':module,'description':description,'quantity':quantity,
        'origin':'back_center' if wall else 'bottom_center','front':'+Z','anchors':[]}

def cabinet():
    begin('display_cabinet','M04','Ivory display cabinet, deep-green plinth and clear five-panel hood',2)
    source_glass=p.b.material('glass');source_glass.diffuse_color=(*p.b.rgb('glass'),.16)
    source_glass.node_tree.nodes['Principled BSDF'].inputs['Alpha'].default_value=.16
    source_glass.surface_render_method='DITHERED'
    box('Deep green floor plinth',(0,.06,0),(.95,.12,1.80),'green',.018)
    box('Ivory cabinet body',(0,.52,0),(.91,.80,1.76),'ivory',.02)
    for side in [-1,1]:
        box('Deep green long rim '+str(side),(side*.46,.96,0),(.03,.08,1.80),'green',.012)
        box('Deep green short rim '+str(side),(0,.96,side*.885),(.89,.08,.03),'green',.012)
    box('Ivory display bed',(0,.993,0),(.89,.014,1.74),'bed',.004)
    for x in [-.445,.445]:
        for z in [-.865,.865]:box('Slim glass corner '+str((x,z)),(x,1.25,z),(.009,.5,.009),'glass_edge',0)
        box('Glass top long edge '+str(x),(x,1.495,0),(.009,.010,1.739),'glass_edge',0)
    for z in [-.865,.865]:box('Glass top short edge '+str(z),(0,1.495,z),(.899,.010,.009),'glass_edge',0)
    panels=[('Front',[(-.445,1.,.865),(.445,1.,.865),(.445,1.495,.865),(-.445,1.495,.865)]),
        ('Back',[(.445,1.,-.865),(-.445,1.,-.865),(-.445,1.495,-.865),(.445,1.495,-.865)]),
        ('Left',[(-.445,1.,-.865),(-.445,1.,.865),(-.445,1.495,.865),(-.445,1.495,-.865)]),
        ('Right',[(.445,1.,.865),(.445,1.,-.865),(.445,1.495,-.865),(.445,1.495,.865)]),
        ('Top',[(-.445,1.495,-.865),(-.445,1.495,.865),(.445,1.495,.865),(.445,1.495,-.865)])]
    for name,verts in panels:
        obj=p.mesh(name+' transparent glass',verts,[(0,1,2,3)],'glass');obj['surface_role']='glass'
    SPECS['display_cabinet'].update(display_height_m=1.,glass_top_m=1.50,
        instance_ids=['glass_case_1','glass_case_2'],
        interior_bounds=[[-.435,1.,-.855],[.435,1.485,.855]],
        colliders=[{'position':[0,.75,0],'size':[.95,1.50,1.80]}])

def plinth():
    begin('exhibit_plinth','M05','Ivory and deep-green square plinth for the upright ammonite')
    box('Green plinth foot',(0,.07,0),(.70,.14,.70),'green',.014)
    box('Ivory plinth body',(0,.595,0),(.66,.91,.66),'ivory',.018)
    for side in [-1,1]:
        box('Green long top border '+str(side),(side*.33,1.065,0),(.04,.07,.70),'green',.01)
        box('Green short top border '+str(side),(0,1.065,side*.33),(.62,.07,.04),'green',.01)
    box('Ivory exhibit surface',(0,1.094,0),(.62,.012,.62),'bed',.003)
    SPECS['exhibit_plinth'].update(display_height_m=1.10,colliders=[{'position':[0,.55,0],'size':[.70,1.10,.70]}])

def polygon(name,points,color,z=.041):
    # The generic closed-mesh normal pass is ambiguous for open canvas overlays.
    obj=p.mesh(name,[(x,y,z) for x,y in points],[tuple(range(len(points)))],color)
    bm=bmesh.new();bm.from_mesh(obj.data)
    for face in bm.faces:
        if face.normal.y>0:face.normal_flip()
    bm.to_mesh(obj.data);bm.free()
    return obj
def rect(name,x,y,w,h,color,z=.041):return polygon(name,[(x-w/2,y-h/2),(x+w/2,y-h/2),(x+w/2,y+h/2),(x-w/2,y+h/2)],color,z)
def disk(name,x,y,rx,ry,color,z=.042):
    return polygon(name,[(x+rx*math.cos(i*math.tau/16),y+ry*math.sin(i*math.tau/16)) for i in range(16)],color,z)
def paintings():
    variants=[{'paper':'F2E5CA','sage':'83916D','ochre':'C1A16C','orange':'C66F3F'},
        {'beige':'E3CFAB','paper':'F3E8D1','sage_dark':'4F674D','orange_light':'E1A36B'},
        {'paper':'EEDFC0','orange':'B8653E','sage':'738166','ochre':'D5BF95'},
        {'beige':'E7D8BA','sage_dark':'687A56','orange_light':'C88B59','paper':'F2E7D1'},
        {'paper':'F0E7D3','sage':'8D9C7A','ochre':'BA9559','orange':'D69461'},
        {'beige':'DCC9A6','sage':'5F7255','orange':'A85F42','paper':'E8D6B2'}]
    for i in range(6):
        name=f'abstract_frame_{i+1:02d}';begin(name,'M06','Original abstract color blocks; no copied artwork or lettering',wall=True)
        box('Light wood frame backing',(0,0,.0125),(.70,.55,.025),'wood',.007)
        for side in [-1,1]:
            box('Frame upright '+str(side),(side*.333,0,.03),(.034,.55,.04),'wood_edge',.005)
            box('Frame rail '+str(side),(0,side*.258,.03),(.632,.034,.04),'wood_edge',.005)
        rect('Blank abstract canvas',0,0,.626,.476,['paper','beige','paper','beige','paper','beige'][i],.038)
        if i==0:
            rect('Muted green field',-.18,.015,.255,.43,'sage',.040)
            rect('Warm ochre field',.10,.13,.35,.20,'ochre',.040)
            polygon('Terracotta arc',[(.005,-.23),(.30,-.23),(.30,-.08)]+[(.15+.15*math.cos(t),-.08+.15*math.sin(t)) for t in [j*math.pi/12 for j in range(13)]],'orange',.042)
        elif i==1:
            rect('Pale upper field',.12,.13,.38,.19,'paper',.040)
            polygon('Green curved field',[(.02,.23),(.30,.23),(.30,-.04),(.14,-.04),(.06,.04)],'sage_dark',.041)
            polygon('Orange rising field',[(-.30,-.23),(.06,-.23),(-.08,.02),(-.13,.17),(-.23,.20),(-.30,.10)],'orange_light',.042)
        elif i==2:
            rect('Orange column',.205,0,.18,.46,'orange',.040)
            rect('Green lower block',-.17,-.13,.27,.20,'sage',.041)
            rect('Ochre upper block',-.15,.12,.29,.20,'ochre',.041)
        elif i==3:
            polygon('Green diagonal',[(-.30,-.23),(.10,-.23),(-.07,.23),(-.30,.23)],'sage_dark',.040)
            rect('Soft clay field',.17,.11,.26,.23,'orange_light',.041)
            polygon('Ivory wedge',[(-.08,-.23),(.30,-.23),(.30,-.01)],'paper',.042)
        elif i==4:
            rect('Sage upper field',-.14,.13,.33,.20,'sage',.040)
            disk('Warm ochre disk',.10,-.025,.19,.19,'ochre',.041)
            rect('Terracotta lower field',-.18,-.14,.24,.18,'orange',.042)
        else:
            rect('Muted green base',-.14,-.11,.32,.23,'sage',.040)
            polygon('Terracotta diagonal',[(-.30,.23),(.06,.23),(.30,-.10),(.30,-.23),(.11,-.23)],'orange',.041)
            rect('Pale corner',.21,.15,.18,.16,'paper',.042)
        for role,color in variants[i].items():
            key=f'art_{i+1:02d}_{role}';p.b.PALETTE[key]=color
            for obj in p.KITS[name]['objects']:
                for slot in obj.material_slots:
                    if slot.material.name.startswith(role+'_'):slot.material=p.b.material(key)
        SPECS[name]['art_palette_srgb']=variants[i]
        SPECS[name]['gallery_offset']=[(i%3-1)*.85,(.35 if i<3 else -.35),0]

def exhibit_begin(name,description,container,slot,z):
    begin(name,'M14',description)
    case=container.startswith('display_cabinet')
    destination=container.replace('display_cabinet','glass_case') if case else 'display_plinth'
    instance=f'case_{container[-1]}_exhibit_'+str({'rear':1,'middle':2,'front':3}[slot]) if case else 'plinth_exhibit'
    SPECS[name]['display_assignment']={'container':destination,'container_asset':'display_cabinet' if case else 'exhibit_plinth',
        'instance_name':instance,'slot':slot,'position':[0,1.0 if case else 1.10,z],'yaw_degrees':0}

def vessels():
    exhibit_begin('exhibit_shallow_bowl','Low open terracotta bowl','display_cabinet_1','rear',-.55)
    bowl=p.lathe('Thick rounded bowl',(0,0,0),[(0,.065),(.015,.085),(.045,.12),(.095,.145),(.11,.147),(.11,.128),(.075,.105),(.025,.055)],'clay',16)
    bowl.data.materials.append(p.b.material('clay_light'))
    for face in bowl.data.polygons:
        if face.center.z>.095:face.material_index=1
    exhibit_begin('exhibit_terracotta_jar','Open necked terracotta jar','display_cabinet_2','middle',0)
    p.lathe('Hollow pottery jar',(0,0,0),[(0,.060),(.025,.080),(.11,.115),(.20,.102),(.25,.062),(.285,.063),(.30,.057),(.30,.040),(.265,.040),(.25,.045)],'clay',16)

def leaf_fossil():
    exhibit_begin('exhibit_leaf_fossil','Small stone slab with original plant impression','display_cabinet_1','front',.55)
    p.ellipsoid('Rounded fossil slab',(0,.032,0),(.32,.064,.24),'stone_light',12,6)
    def surface(x,z):return .032+.032*math.sqrt(max(.03,1-(x/.16)**2-(z/.12)**2))+.0004
    stem=[(0,surface(0,z),z) for z in [-.085,-.04,0,.04,.085]]
    p.tube('Central impression',stem,.0025,'stone_dark',3)
    for j in range(5):
        z=-.06+j*.027
        for side in [-1,1]:
            pts=[(0,surface(0,z),z),(side*.035,surface(side*.035,z+.014),z+.014),(side*.067,surface(side*.067,z+.023),z+.023)]
            p.tube('Leaf impression '+str((j,side)),pts,.0022,'stone_dark',3)

def shell_fragment():
    exhibit_begin('exhibit_shell_fragment','Small fan-shaped shell impression in a pale stone','display_cabinet_1','middle',0)
    p.ellipsoid('Shell fossil stone',(0,.04,0),(.28,.08,.25),'fossil',12,6)
    for j in range(7):
        a=-1.1+j*2.2/6;pts=[]
        for k in range(4):
            t=k/3;x=math.sin(a)*.10*t;z=-.065+math.cos(a)*.15*t
            y=.04+.04*math.sqrt(max(.05,1-(x/.14)**2-(z/.125)**2))+.0004
            pts.append((x,y,z))
        p.tube('Fan impression '+str(j),pts,.0028,'groove',3)

def rock():
    exhibit_begin('exhibit_fossil_rock','Faceted warm stone study with a stable flat contact face','display_cabinet_2','rear',-.55)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1)
    obj=bpy.context.object;face=min(obj.data.polygons,key=lambda f:f.normal.z)
    rotation=face.normal.rotation_difference(Vector((0,0,-1)))
    for vertex in obj.data.vertices:
        v=rotation@vertex.co;vertex.co=Vector((v.x*.15,v.y*.13,v.z*.105))
    obj.data.update();p.b.finish(obj,'Faceted fossil stone','stone',smooth=False)
    obj.data.materials.append(p.b.material('stone_light'));obj.data.materials.append(p.b.material('stone_dark'))
    for f in obj.data.polygons:f.material_index=[0,0,1,0,2][f.index%5]

def ammonite_geometry(radius,center_y,base=False):
    n=20;verts=[];rings=[0.,.28*radius,.63*radius,radius]
    def front(r):return radius*.40-radius*.11*(r/radius)**2
    for r in rings[1:]:
        for i in range(n):
            a=math.tau*i/n;verts.append((r*math.cos(a),center_y+r*math.sin(a),front(r)))
    verts += [(0,center_y,front(0))]
    center=len(verts)-1;faces=[(center,i,(i+1)%n) for i in range(n)]
    for j in range(2):
        for i in range(n):faces.append((j*n+i,(j+1)*n+i,(j+1)*n+(i+1)%n,j*n+(i+1)%n))
    for i in range(n):
        a=math.tau*i/n;verts.append((radius*math.cos(a),center_y+radius*math.sin(a),-radius*.24))
    start=center+1
    for i in range(n):faces.append((2*n+i,start+i,start+(i+1)%n,2*n+(i+1)%n))
    faces.append(tuple(start+i for i in reversed(range(n))))
    p.mesh('Ammonite rounded shell',verts,faces,'fossil',smooth=True)
    pts=[]
    for i in range(33):
        t=i/32;a=-math.pi/4+t*math.pi*4.6;r=radius*(.045+.84*t*t)
        pts.append((r*math.cos(a),center_y+r*math.sin(a),front(r)+.001))
    p.tube('Continuous ammonite spiral',pts,radius*.028,'groove',4)
    for i in range(12):
        a=math.tau*i/12+.1
        p.mesh('Shell radial rib '+str(i),[(r*math.cos(a+da),center_y+r*math.sin(a+da),front(r)+.0015)
            for r,da in [(radius*.77,-.012),(radius*.98,-.012),(radius*.98,.012),(radius*.77,.012)]],[(0,1,2,3)],'stone_light')
    if base:box('Small neutral display foot',(0,.015,0),(.25,.03,.17),'stone_dark',.006)

def ammonites():
    exhibit_begin('exhibit_spiral_fossil','Flat ammonite fossil for the front of cabinet two','display_cabinet_2','front',.55)
    ammonite_geometry(.145,0)
    rotation=Matrix.Rotation(-math.pi/2,4,'X')
    for obj in p.KITS['exhibit_spiral_fossil']['objects']:obj.matrix_local=rotation@obj.matrix_local
    exhibit_begin('exhibit_ammonite','Upright original ammonite study on a small foot','exhibit_plinth','center',0)
    ammonite_geometry(.18,.20,True)

def mosaic():
    begin('floor_mosaic','M03','Thin concentric beige stone medallion; no collision')
    p.cylinder('Thin grout backing',(0,.002,0),.97,.004,'grout',vertices=48)
    radii=[.0,.14,.30,.46,.62,.78,.90,.97];counts=[12,12,18,24,30,36,42]
    for ring,segments in enumerate(counts):
        for i in range(segments):
            start=math.tau*(i+(ring%2)*.5)/segments;end=start+math.tau/segments
            outer=radii[ring+1]-.003;inner=radii[ring]+.003
            da=.003/max(inner,.08)
            if ring==0:
                verts=[(0,.008,0),(outer*math.cos(start+.02),.008,outer*math.sin(start+.02)),(outer*math.cos(end-.02),.008,outer*math.sin(end-.02))]
            else:
                verts=[(r*math.cos(a),.008,r*math.sin(a)) for r,a in [(inner,start+da),(outer,start+da),(outer,end-da),(inner,end-da)]]
            obj=p.mesh('Ring %d stone %02d'%(ring+1,i+1),verts,[tuple(range(len(verts)))],['ivory','beige','paper'][(i+ring*3)%3])
            bm=bmesh.new();bm.from_mesh(obj.data)
            for face in bm.faces:
                if face.normal.z<0:face.normal_flip()
            bm.to_mesh(obj.data);bm.free()
    SPECS['floor_mosaic']['colliders']=[]

def sign():
    begin('name_sign','M15','Blank light-wood runtime sign',wall=True)
    box('Blank light wood plaque',(0,0,.016),(1.38,.34,.032),'wood',.008)
    for side in [-1,1]:
        box('Sign vertical edge '+str(side),(side*.676,0,.026),(.028,.34,.036),'wood_edge',.004)
        box('Sign horizontal edge '+str(side),(0,side*.156,.026),(1.324,.028,.036),'wood_edge',.004)
    SPECS['name_sign']['anchors']=[{'name':'sign_door','position':[0,0,.052],'size':[1.24,.28],'module':'name_sign','yaw_degrees':0,'text':''}]

def combine(name,module,members,wall=False):
    bpy.context.view_layer.update()
    begin(name,module,'Baked single-surface group; named editable components retained',wall=wall)
    target=p.KITS[name];components=[]
    for child_name,offset in members:
        kit=p.KITS[child_name];spec=SPECS[child_name];points=[];triangles=0
        bpy.context.view_layer.update();graph=bpy.context.evaluated_depsgraph_get()
        for obj in kit['objects']:
            evaluated=obj.evaluated_get(graph);mesh=evaluated.to_mesh();mesh.calc_loop_triangles()
            matrix=kit['root'].matrix_world.inverted()@obj.matrix_world
            points.extend(Vector((q.x,q.z,-q.y)) for q in [matrix@v.co for v in mesh.vertices])
            triangles+=sum(t.area>1e-12 for t in mesh.loop_triangles);evaluated.to_mesh_clear()
        lo=Vector(tuple(min(v[i] for v in points) for i in range(3)))
        hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
        pivot=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2 if wall else lo.y,lo.z if wall else (lo.z+hi.z)/2))
        for obj in kit['objects']:
            transform=Matrix.Translation(p.b.v(offset))@Matrix.Translation(-p.b.v(pivot))@kit['root'].matrix_world.inverted()@obj.matrix_world
            for collection in list(obj.users_collection):collection.objects.unlink(obj)
            target['collection'].objects.link(obj);obj.parent=target['root'];obj.matrix_parent_inverse=Matrix.Identity(4);obj.matrix_local=transform
            obj.name=child_name+' / '+obj.name;target['objects'].append(obj)
        component={k:v for k,v in spec.items() if k not in ['file','quantity','display_assignment','gallery_offset']}
        if 'display_assignment' in spec:
            component['slot']=spec['display_assignment']['slot'];component['source_instance_name']=spec['display_assignment']['instance_name']
        components.append({**component,'position':offset,'bounds':[list(lo-pivot),list(hi-pivot)],'triangles':triangles})
        bpy.data.objects.remove(kit['root'],do_unlink=True);bpy.data.collections.remove(kit['collection'])
        del p.KITS[child_name];del SPECS[child_name]
    SPECS[name]['components']=components
    if wall:SPECS[name]['gallery_offset']=[0,0,0]
    else:
        SPECS[name]['origin']='display_surface_center'
        case='glass_case_'+name[-1]
        SPECS[name]['display_assignment']={'container':case,'container_asset':'display_cabinet','instance_name':name,
            'slot':'three baked exhibits','position':[0,1.0,0],'yaw_degrees':0}

def grouped_delivery():
    combine('artwork_set','M06',[(f'abstract_frame_{i:02d}',SPECS[f'abstract_frame_{i:02d}']['gallery_offset']) for i in range(1,7)],wall=True)
    for i in [1,2]:
        members=[(s['name'],[0,0,s['display_assignment']['position'][2]]) for s in SPECS.values()
            if s.get('display_assignment',{}).get('container')=='glass_case_'+str(i)]
        combine('case_exhibits_'+str(i),'M14',members)

def export():
    bpy.context.view_layer.update()
    materials=[]
    for name,roughness in [('CulturePropsVertex',.9),('CultureGlass',.16)]:
        mat=bpy.data.materials.new(name);mat.use_nodes=True;bsdf=mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value=(1,1,1,1);bsdf.inputs['Roughness'].default_value=roughness;bsdf.inputs['Specular IOR Level'].default_value=.18 if len(materials)==0 else .35
        color=mat.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='Color'
        mat.node_tree.links.new(color.outputs['Color'],bsdf.inputs['Base Color']);materials.append(mat)
    original=bpy.context.scene;temp=bpy.data.scenes.new('Temporary prop export')
    for name,kit in p.KITS.items():
        copies=[];points=[]
        for source in kit['objects']:
            graph=bpy.context.evaluated_depsgraph_get();data=bpy.data.meshes.new_from_object(source.evaluated_get(graph),preserve_all_data_layers=True,depsgraph=graph)
            data.transform(kit['root'].matrix_world.inverted()@source.matrix_world)
            layer=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
            role=1 if source.get('surface_role')=='glass' else 0
            for face in data.polygons:
                color=data.materials[face.material_index].diffuse_color
                for index in face.loop_indices:layer.data[index].color=(*color[:3],1)
                face.material_index=role
            data.materials.clear()
            for material in materials[:2 if name=='display_cabinet' else 1]:data.materials.append(material)
            for face in data.polygons:face.material_index=role
            data.color_attributes.active_color=layer;data.color_attributes.render_color_index=0
            for uv in list(data.uv_layers):data.uv_layers.remove(uv)
            obj=bpy.data.objects.new(name+'_part',data);temp.collection.objects.link(obj);copies.append(obj)
            points.extend(Vector((v.co.x,v.co.z,-v.co.y)) for v in data.vertices)
        lo=Vector(tuple(min(v[i] for v in points) for i in range(3)));hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
        pivot=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2 if SPECS[name]['origin']=='back_center' else lo.y,
            lo.z if SPECS[name]['origin']=='back_center' else (lo.z+hi.z)/2))
        if SPECS[name]['origin']=='display_surface_center':pivot=Vector((0,0,0))
        for obj in copies:
            for v in obj.data.vertices:v.co-=p.b.v(pivot)
        for source in kit['objects']:source.location-=p.b.v(pivot)
        for anchor in SPECS[name]['anchors']:anchor['position']=list(Vector(anchor['position'])-pivot)
        bpy.context.window.scene=temp;bpy.ops.object.select_all(action='DESELECT')
        for obj in copies:obj.select_set(True)
        bpy.context.view_layer.objects.active=copies[0]
        if len(copies)>1:bpy.ops.object.join()
        obj=bpy.context.object;obj.name='Body';obj.data.name=name+'_mobile'
        bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=list(bm.faces))
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_area()<1e-12],context='FACES');bm.to_mesh(obj.data);bm.free();obj.data.calc_loop_triangles()
        anchors=[]
        for anchor in SPECS[name]['anchors']:
            node=bpy.data.objects.new(anchor['name'],None);temp.collection.objects.link(node);node.parent=obj;node.location=p.b.v(anchor['position'])
            node['size']=anchor['size'];node['module']=name;node.select_set(True);anchors.append(node)
        path=KIT/(name+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,
            export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,
            export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False,export_extras=True)
        raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length]);tail=raw[20+length:]
        for material in doc['materials']:
            if material['name']=='CultureGlass':
                material.update(alphaMode='BLEND',doubleSided=True)
                material['pbrMetallicRoughness'].update(baseColorFactor=[1,1,1,.16],metallicFactor=0,roughnessFactor=.16)
        encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
        path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
        spec=SPECS[name];spec.update(triangles=len(obj.data.loop_triangles),surfaces=2 if name=='display_cabinet' else 1,
            bounds=[list(lo-pivot),list(hi-pivot)],dimensions_m=list(hi-lo),sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        for node in anchors:bpy.data.objects.remove(node,do_unlink=True)
        bpy.data.objects.remove(obj,do_unlink=True);bpy.context.window.scene=original
        provenance={'asset':name,'module':spec['module'],'author':'黄忠','virtual_user_id':AUTHOR,'kind':'new authored geometry',
            'reference':'SGODOT-318 R3 main and director 323 dimensions; rear 2m layout belongs to scene owner',
            'source_script':'tools/art/source/poi_culture_hall/props/build_props.py','source_blend':'tools/art/source/poi_culture_hall/props/culture_props.blend',
            'changes':[spec['description']],'material':'matte vertex colour; cabinet glass is a separate transparent surface'}
        write(SRC/'modules'/name/'reuse_provenance.json',provenance);spec['provenance']=str((SRC/'modules'/name/'reuse_provenance.json').relative_to(ROOT))
        print('PROP',name,spec['triangles'],spec['dimensions_m'],flush=True)
    bpy.data.scenes.remove(temp);bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'culture_props.blend'))
    manifest={'revision':'v1','author':'黄忠','virtual_user_id':AUTHOR,'baseline_height_m':1.745,'axes':'metres; Y up; +Z front',
        'scope':'8 grouped GLBs, 9 placed instances; 17 authored components. Scene layout owned by Zhaoyun.',
        'gallery':{'layout':'two rows of three','local_width_m':2.40,'local_height_m':1.25},'assets':list(SPECS.values()),
        'unique_triangles':sum(s['triangles'] for s in SPECS.values()),'placed_triangles':sum(s['triangles']*s['quantity'] for s in SPECS.values()),
        'unique_surfaces':sum(s['surfaces'] for s in SPECS.values()),'placed_surfaces':sum(s['surfaces']*s['quantity'] for s in SPECS.values())}
    write(KIT/'prop_manifest.json',manifest)
    assert len(SPECS)==8 and all(all(c['triangles']<=600 for c in s['components']) if 'components' in s else s['triangles']<=600 for s in SPECS.values())
    print('CULTURE_PROPS_READY',manifest['unique_triangles'],manifest['placed_triangles'],manifest['placed_surfaces'],flush=True)

if __name__=='__main__':
    p.start('poi_culture_hall/props','SGODOT-323 original props / 318 R3');p.b.PALETTE.update(COLORS)
    cabinet();plinth();paintings();vessels();leaf_fossil();shell_fragment();rock();ammonites();mosaic();sign();grouped_delivery();export()
