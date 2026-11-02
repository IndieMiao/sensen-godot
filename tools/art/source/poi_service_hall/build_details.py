"""N2 independent detailed props; immutable shared shell and seating dependencies."""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix
from mathutils.geometry import interpolate_bezier

SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[3]
sys.path.insert(0,str(ROOT/'tools/art'))
import scene_room_pipeline as p
from scene_room_pipeline import cube, cylinder, ellipsoid, mesh, lathe, tube

KIT=ROOT/'assets/rooms/poi_service_hall'
HALL=ROOT/'output/poi-service-hall-321/dependencies/assets/rooms/_shared/shell_hall'
PALETTE=json.loads((HALL/'hall_palette.json').read_text())
OVERRIDES={'cloth_green':'435B76','print_landscape':'6180A3','print_portrait':'BC4536','sky':'78A8C9'}
SPECS={}
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'


def save(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def begin(name,description,dimensions,quantity=1,colliders=None):
    index=len(SPECS)
    p.begin(name,((index%5)*2.5,0,(index//5)*3.0))
    SPECS[name]={'name':name,'file':name+'.glb','description':description,
                 'nominal_dimensions_m':dimensions,'quantity':quantity,
                 'colliders':colliders or [],'pivot':'local floor or mounting centre; Y up, front +Z'}


def box(size,center):return {'size':size,'at':center}


def leaf(name,center,size,angle=0):
    obj=ellipsoid(name,center,size,'leaf' if angle%2 else 'leaf_light',8,4)
    obj.rotation_euler.z=math.radians(angle)
    return obj


def flower(name,at,radius=.045,color='print_portrait',phase=0):
    x,y,z=at
    for i in range(5):
        a=math.tau*i/5+phase
        ellipsoid(name+' petal '+str(i+1),(x+math.cos(a)*radius*.62,y,z+math.sin(a)*radius*.62),
                  (radius*.95,.025,radius*.95),color,6,4)
    ellipsoid(name+' pollen',(x,y+.012,z),(.025,.025,.025),'accent_gold',6,4)


def planted_base():
    begin('sculpture_base','Separate stone flower-ring plinth; total planted height .40m',
          [1.86,.40,1.86],colliders=[box([1.30,.4,1.30],[0,.2,0]),
          box([1.84,.4,.26],[0,.2,0]),box([.26,.4,1.84],[0,.2,0])])
    lathe('Rounded outer stone ring',(0,0,0),[(0,.88),(.018,.92),(.055,.93),(.135,.93),
          (.155,.91),(.155,.78),(.075,.76),(.06,.76)],'stone',64)
    cylinder('Recessed soil',(0,.12,0),.79,.06,'soil',vertices=48)
    lathe('Central sculpture pedestal',(0,0,0),[(0,.29),(.03,.34),(.08,.35),(.12,.30),
          (.32,.28),(.37,.32),(.40,.32)],'porcelain',40)
    for i in range(24):
        a=i*math.tau/24
        for j in range(2):
            r=.59+j*.12;angle=a+j*.12
            leaf('Flower ring foliage %02d_%d'%(i,j),
                 (r*math.cos(angle),.21+.02*(i%3),r*math.sin(angle)),(.19,.16,.16),i*29+j*61)
        if i%4!=3:
            flower('Flower ring blossom %02d'%i,(.66*math.cos(a),.325,.66*math.sin(a)),
                   .05,'petal' if i%5==0 else 'print_portrait',a)


def bezier_chain(segments,resolution=17):
    points=[]
    for controls in segments:
        part=interpolate_bezier(*[Vector(v) for v in controls],resolution)
        points.extend(part if not points else part[1:])
    return points


def ribbon(name,points,widths):
    vertices=[];faces=[];sides=10
    for i,point in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        side=Vector((-tangent.y,tangent.x,0)).normalized()
        front=tangent.cross(side).normalized()
        width=widths(i/(len(points)-1))
        for j in range(sides):
            a=math.tau*j/sides
            vertices.append(point+side*width*math.cos(a)+front*width*.65*math.sin(a))
    for i in range(len(points)-1):
        for j in range(sides):
            faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces += [tuple(reversed(range(sides))),tuple((len(points)-1)*sides+j for j in range(sides))]
    return mesh(name,vertices,faces,'porcelain','metal',True)


def sculpture():
    begin('sculpture_body','Open asymmetric spiral ribbons and pearl; local height 1.20m on .40m base',
          [.60,1.20,.24])
    outer=bezier_chain([
        [(0,.035,0),(.20,.08,-.02),(.28,.24,-.015),(.22,.49,0)],
        [(.22,.49,0),(.18,.70,.015),(-.14,.74,.03),(-.15,.53,.045)],
        [(-.15,.53,.045),(-.16,.40,.055),(-.01,.37,.06),(.055,.43,.05)]])
    ribbon('Open curling spiral',outer,lambda t:.065-.040*t*t)
    rising=bezier_chain([
        [(0,.03,-.015),(-.24,.12,-.035),(-.25,.37,-.025),(-.18,.64,-.01)],
        [(-.18,.64,-.01),(-.12,.89,0),(.12,1.04,.015),(.09,1.197,.02)]])
    ribbon('Tapered rising ribbon',rising,lambda t:.070*(1-t)**.55+.003)
    ellipsoid('Central pearl',(0,.51,.035),(.19,.19,.19),'porcelain',20,12,'metal')
    # Set the authored module to the approved envelope before export.
    bpy.context.view_layer.update()
    points=np.array([tuple(obj.matrix_basis @ v.co) for obj in p.b.CURRENT['objects'] for v in obj.data.vertices])
    lo=points.min(0);hi=points.max(0)
    factor_x=min(1,.60/(hi[0]-lo[0]));factor_y=1.20/(hi[2]-lo[2])
    for obj in p.b.CURRENT['objects']:
        transform=Matrix.Translation((0,0,-lo[2])) @ obj.matrix_basis
        obj.matrix_basis=Matrix.Diagonal((factor_x,1,factor_y,1)) @ transform


def arc_frame(name,outer,inner,bottom,shoulder,depth,z,color):
    for side in [-1,1]:
        cube(name+' upright '+str(side),(side*(outer+inner)/4,(bottom+shoulder)/2,z),
             ((outer-inner)/2,shoulder-bottom,depth),color,.018)
    vertices=[];faces=[];segments=32
    for zz in [z-depth/2,z+depth/2]:
        for radius in [outer/2,inner/2]:
            vertices.extend([(math.cos(math.pi*i/segments)*radius,
                              shoulder+math.sin(math.pi*i/segments)*radius,zz) for i in range(segments+1)])
    stride=segments+1
    for i in range(segments):
        for a,b in [(0,stride),(2*stride,3*stride),(0,2*stride),(stride,3*stride)]:
            faces.append((a+i,a+i+1,b+i+1,b+i))
    faces += [(0,stride,3*stride,2*stride),(segments,segments+stride,segments+3*stride,segments+2*stride)]
    obj=mesh(name+' rounded arch',vertices,faces,color,smooth=True)
    for face in obj.data.polygons:face.use_smooth=abs(face.normal.y)<.5
    bevel=obj.modifiers.new('Soft stone edge','BEVEL');bevel.width=.012;bevel.segments=2
    bevel.harden_normals=True
    obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL').keep_sharp=True


def niche(name,variant):
    begin(name,'Applied arch niche with deep blue back and visible display set; no wall opening',
          [1.10,2.40,.35],colliders=[box([1.10,2.40,.35],[0,1.20,.175])])
    cube('Niche lower plinth',(0,.32,.175),(1.08,.64,.35),'plaster_solid',.025)
    cube('Niche base moulding',(0,.055,.175),(1.10,.11,.35),'stone',.02)
    cube('Exhibition shelf',(0,.705,.175),(1.10,.09,.35),'porcelain',.025)
    p.arch_solid('Deep blue arched back',.88,.75,1.85,.44,.025,.13,'cloth_green')
    arc_frame('Stone niche',1.10,.85,.75,1.85,.30,.175,'plaster_solid')
    arc_frame('Slim gold inset',.89,.85,.76,1.85,.025,.334,'brass')
    cube('Gold shelf edge',(0,.765,.336),(.85,.025,.025),'brass',.008)
    for i in [-1,0,1]:
        a=math.pi/2+i*.55
        tube('Gold fan spoke '+str(i),[(0,1.85,.32),(.39*math.cos(a),1.85+.39*math.sin(a),.32)],.009,'brass',6)
    if variant==1:
        lathe('Tall ivory vase',(-.17,.75,.24),[(0,.07),(.03,.085),(.12,.095),(.27,.09),
              (.38,.07),(.44,.042),(.46,.048),(.48,.048),(.48,.03),(.43,.03)],'porcelain',24)
        cube('Small display pedestal',(.22,.805,.25),(.16,.11,.17),'stone',.015)
        ellipsoid('Faceted pale gemstone',(.22,.91,.25),(.14,.15,.14),'accent_gold',6,4)
    else:
        lathe('Small ceramic bowl',(-.23,.75,.25),[(0,.055),(.04,.065),(.14,.085),
              (.17,.087),(.17,.065),(.06,.043)],'porcelain',20)
        cube('Tall geometric display',(.03,.975,.25),(.15,.45,.15),'linen',.012)
        cube('Small geometric display',(.25,.815,.25),(.14,.13,.15),'accent_gold',.015)


def brochure():
    begin('brochure_rack','Three inclined rows with nine blank brochures', [.71,1.10,.48],
          colliders=[box([.71,1.10,.48],[0,.55,0])])
    for side in [-1,1]:
        tube('Rack slanted side '+str(side),[(side*.337,.04,.205),(side*.337,1.07,-.205)],.018,'wood_mid',8)
        tube('Rack rear leg '+str(side),[(side*.337,.025,-.20),(side*.337,1.05,-.205)],.017,'oak',8)
        cube('Rack foot '+str(side),(side*.33,.025,0),(.05,.05,.48),'wood_mid',.012)
    for row in range(3):
        y=.22+row*.30;z=.16-row*.115
        back=cube('Rack sloped back %d'%row,(0,y+.12,z-.045),(.65,.27,.027),'oak',.012)
        back.rotation_euler.x=math.radians(-21)
        cube('Rack shelf lip %d'%row,(0,y-.005,z+.035),(.67,.055,.045),'oak_light',.012)
        for col in range(3):
            page=cube('Blank brochure %d_%d'%(row,col),((col-1)*.21,y+.12,z+.004),(.177,.225,.014),
                      'linen' if col!=1 else 'porcelain',.008)
            page.rotation_euler.x=math.radians(-21)
    cube('Rack top rail',(0,1.08,-.205),(.71,.04,.045),'oak',.012)


def dispenser():
    begin('water_dispenser','Rounded dispenser and blue refill bottle; no markings', [.44,1.30,.54],
          colliders=[box([.44,1.30,.54],[0,.65,0])])
    cube('Rounded ivory body',(0,.47,0),(.44,.94,.48),'porcelain',.055)
    cube('Body base foot',(0,.035,0),(.42,.07,.46),'stone',.02)
    cube('Recessed tap panel',(0,.665,.242),(.31,.31,.018),'stone',.025)
    cube('Recess dark backing',(0,.65,.253),(.24,.20,.014),'iron',.02)
    cube('Drip tray',(0,.53,.26),(.31,.035,.08),'porcelain',.012)
    for side,color in [(-1,'print_portrait'),(1,'sky')]:
        cube('Tap '+str(side),(side*.075,.69,.27),(.035,.06,.045),color,.014)
    lathe('Bottle collar',(0,.94,0),[(0,.105),(.015,.115),(.035,.115),(.05,.095)],'sky',28)
    lathe('Rounded blue water bottle',(0,.975,0),[(0,.075),(.025,.085),(.045,.117),(.075,.13),
          (.255,.13),(.30,.115),(.325,.09)],'sky',32)
    for y in [1.065,1.15,1.225]:
        lathe('Bottle moulded rib',(0,y,0),[(0,.129),(.007,.135),(.017,.135),(.024,.129)],'sky',32)


def wall_boards():
    begin('call_screen','Exactly three coloured dots on blue screen; centre mounting at 1.75m', [.80,.50,.05])
    cube('Call display blue frame',(0,0,0),(.80,.50,.05),'cloth_green',.018)
    cube('Call display inset',(0,0,.027),(.73,.43,.012),'print_landscape',.01)
    for i,color in enumerate(['accent_gold','linen_green','terra_light']):
        dot=cylinder('Colour dot '+str(i+1),((i-1)*.225,0,.038),.067,.008,color,vertices=32)
        dot.rotation_euler.x=math.pi/2
    begin('notice_board','Four blank paper sheets; centre mounting at 1.55m', [.70,.90,.055])
    cube('Cork board',(0,0,0),(.70,.90,.04),'oak',.02)
    for side in [-1,1]:
        cube('Vertical board frame '+str(side),(side*.328,0,.018),(.044,.90,.055),'oak_light',.008)
        cube('Horizontal board frame '+str(side),(0,side*.428,.018),(.65,.044,.055),'oak_light',.008)
    for i in range(4):
        cube('Blank paper '+str(i+1),((i%2-.5)*.29,(.5-i//2)*.37,.027),(.235,.30,.008),'linen',.004)
    begin('name_plaque','Blank plaque; runtime sign_name usable area .88 x .23m', [1.0,.35,.045])
    cube('Blank ivory name plate',(0,0,0),(1.0,.35,.035),'porcelain',.012)
    for side in [-1,1]:
        cube('Plaque horizontal brass trim '+str(side),(0,side*.164,.02),(1.0,.022,.025),'brass',.006)
        cube('Plaque vertical brass trim '+str(side),(side*.489,0,.02),(.022,.31,.025),'brass',.006)
    SPECS['name_plaque']['anchors']=[{'name':'sign_name','position':[0,0,.035],'size':[.88,.23]}]


def flowerbox():
    begin('window_flowerbox','Shallow stone window box with red and cream flowers', [1.0,.20,.22],2)
    cube('Stone planter box',(0,.055,0),(1.0,.11,.22),'stone',.018)
    cube('Recessed dark soil',(0,.114,0),(.94,.012,.17),'soil',.005)
    for i in range(9):
        x=(i-4)*.104
        leaf('Window foliage %d'%i,(x,.145,.025*(1 if i%2 else -1)),(.12,.08,.14),i*31)
        if i%3!=2:flower('Window blossom %d'%i,(x,.176,0),.027,'petal' if i%4==0 else 'print_portrait',i)


def export():
    bpy.context.view_layer.update()
    material=bpy.data.materials.new('N2_hall_atlas');material.use_nodes=True
    node=material.node_tree.nodes.new('ShaderNodeTexImage')
    atlas_path=KIT/'hall_albedo_ao_n2.png'
    node.image=bpy.data.images.load(str(atlas_path));node.image.pack()
    material.node_tree.links.new(node.outputs['Color'],material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    material.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.85
    original_scene=bpy.context.scene
    export_scene=bpy.data.scenes.new('Export temporary')
    for name,kit in p.KITS.items():
        copies=[]
        for source in kit['objects']:
            evaluated=source.evaluated_get(bpy.context.evaluated_depsgraph_get())
            data=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=bpy.context.evaluated_depsgraph_get())
            data.transform(kit['root'].matrix_world.inverted() @ source.matrix_world)
            obj=bpy.data.objects.new(name+'_part',data);export_scene.collection.objects.link(obj)
            for layer in list(data.uv_layers):data.uv_layers.remove(layer)
            uv=data.uv_layers.new(name='HallAtlas')
            for face in data.polygons:
                mat=data.materials[face.material_index]
                slot=next(key for key in sorted(PALETTE['slots'],key=len,reverse=True) if mat.name.startswith(key+'_'))
                rect=PALETTE['slots'][slot]['uv_rect_blender'];center=((rect[0]+rect[2])/2,(rect[1]+rect[3])/2)
                for j,loop in enumerate(face.loop_indices):
                    uv.data[loop].uv=(center[0]+.001*math.cos(j*math.tau/len(face.loop_indices)),
                                      center[1]+.001*math.sin(j*math.tau/len(face.loop_indices)))
                face.material_index=0
            data.materials.clear();data.materials.append(material)
            copies.append(obj)
        bpy.context.window.scene=export_scene
        bpy.ops.object.select_all(action='DESELECT')
        for obj in copies:obj.select_set(True)
        bpy.context.view_layer.objects.active=copies[0]
        bpy.ops.object.join();obj=bpy.context.object;obj.name='Body';obj.data.name=name+'_mobile'
        triangulate=obj.modifiers.new('Export triangles','TRIANGULATE')
        bpy.ops.object.modifier_apply(modifier=triangulate.name)
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.delete(bm,geom=[face for face in bm.faces if face.calc_area()<1e-12],context='FACES')
        bm.to_mesh(obj.data);bm.free()
        obj.data.calc_loop_triangles()
        SPECS[name]['triangles']=len(obj.data.loop_triangles)
        SPECS[name]['surfaces']=1
        bpy.ops.export_scene.gltf(filepath=str(KIT/(name+'.glb')),export_format='GLB',use_selection=True,use_active_scene=True,
            export_materials='NONE',export_texcoords=True,export_normals=True,export_yup=True,
            export_animations=False,export_cameras=False,export_lights=False,export_extras=False)
        path=KIT/(name+'.glb');raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
        doc=json.loads(raw[20:20+length]);tail=raw[20+length:]
        doc['images']=[{'uri':'hall_albedo_ao_n2.png'}];doc['textures']=[{'source':0}]
        doc['materials']=[{'name':'N2HallAtlas','pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],
            'baseColorTexture':{'index':0},'metallicFactor':0,'roughnessFactor':.85}}]
        for mesh_data in doc['meshes']:
            for primitive in mesh_data['primitives']:primitive['material']=0
        encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
        path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+
            struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
        bpy.data.objects.remove(obj,do_unlink=True)
        bpy.context.window.scene=original_scene
        provenance={'asset':name,'author':'Huangzhong','virtual_user_id':AUTHOR,'kind':'new authored geometry',
                    'reference':'SGODOT-316 R3 main; dimensions from director dispatch, sculpture amendment 64efe200',
                    'source_script':'tools/art/source/poi_service_hall/build_details.py',
                    'source_blend':'tools/art/source/poi_service_hall/service_hall_details.blend',
                    'atlas':'Same fixed hall_palette layout; no shared shell edits',
                    'changes':[SPECS[name]['description']],
                    'reference_sha256':hashlib.sha256((SRC/'reference/SGODOT-316_Service_Hall_Main_2026-10-31.png').read_bytes()).hexdigest()}
        save(SRC/'modules'/name/'reuse_provenance.json',provenance)
        SPECS[name]['provenance']=str((SRC/'modules'/name/'reuse_provenance.json').relative_to(ROOT))
    bpy.data.scenes.remove(export_scene)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'service_hall_details.blend'))
    save(KIT/'prop_manifest.json',{'revision':'v1','phase':'Independent detailed props; full B assembly awaits user approval',
         'author':'Huangzhong','virtual_user_id':AUTHOR,'axes':'metres; Y up; +Z front',
         'atlas':'hall_albedo_ao_n2.png','palette_overrides':OVERRIDES,'assets':list(SPECS.values()),
         'sculpture_assembly':{'sculpture_base':[0,0,0],'sculpture_body':[0,.40,0],'total_height_m':1.60}})
    print('N2_DETAILS_READY',len(SPECS),sum(a['triangles']*a['quantity'] for a in SPECS.values()),flush=True)


def main():
    p.start('poi_service_hall','SGODOT-316 R3 approved main / 321 64efe200 sculpture amendment')
    p.b.PALETTE.update({name:OVERRIDES.get(name,slot['hex_srgb']) for name,slot in PALETTE['slots'].items()})
    planted_base();sculpture();niche('display_niche_1',1);niche('display_niche_2',2)
    brochure();dispenser();wall_boards();flowerbox();export()


if __name__=='__main__':main()
