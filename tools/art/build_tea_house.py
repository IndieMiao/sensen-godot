"""SGODOT-216 Tea House: named source, metre geometry, one shared runtime atlas."""
from pathlib import Path
import hashlib
import importlib.util
import json
import math
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/art'))
import scene_room_pipeline as p
from scene_room_pipeline import cube,cylinder,ellipsoid,lathe,tube,mesh

SRC=ROOT/'tools/art/source/tea_house'
KIT=ROOT/'assets/rooms/tea_house'
PLAN=json.loads((SRC/'blockout_plan.json').read_text())
FLOOR=.08
PROVENANCE={}
NO_SHADOW=set()
FOLIAGE=set()
REUSED=[]
PAL={'oak':'D5AC79','oak_light':'E6BE8B','oak_edge':'BF9463','oak_dark':'8E6845','oak_end':'D9B181',
     'floor':'D7B58B','floor_light':'E2C29B','floor_shade':'CFAB80','joint':'AD8C64',
     'plaster':'F1E7D6','plaster_light':'F7EEDF','stone':'C5BBA9',
     'sage':'8D9C79','sage_light':'A6B18E','sage_dark':'69765B',
     'linen':'F0E7D5','porcelain':'F5EEDF','brass':'B58F50','iron':'544637'}


def save(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def box(size,at=None,name=None):
    row={'size':size,'at':at or [0,size[1]/2,0]}
    if name:row['name']=name
    return row


def begin(name,at=(0,0,0),yaw=0,colliders=None,changes=None):
    p.begin(name,at,yaw,colliders)
    PROVENANCE[name]={'asset':name,'author':'Huangzhong','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
        'kind':'new authored geometry','reference':'Stark 2681:135483 approved 216-tea.png; director dispatch 2026-10-31',
        'source_script':'tools/art/build_tea_house.py','changes':changes or [],'units':'metres; Y up; +Z front',
        'reference_sha256':hashlib.sha256((SRC/'reference/216-tea.png').read_bytes()).hexdigest()}


def shell():
    begin('room_shell',colliders=[box([6.8,.22,6.4],[0,-.03,0],'Floor')])
    cube('Soft timber foundation',(0,-.08,0),(6.8,.20,6.4),'oak',.07)
    cube('Floor joints',(0,.035,0),(6.58,.07,6.18),'joint',.002)
    for row in range(18):
        z=-3.06+(row+.5)*.34;x=-3.28;column=0
        while x<3.279:
            length=min(1.64 if column or row%2==0 else .82,3.28-x)
            cube('Pale long floor plank %02d_%02d'%(row,column),(x+length/2,.06,z),
                 (length-.008,.04,.332),['floor','floor_light','floor','floor_shade'][(row+column*3)%4],.005,'wood','X')
            x+=length;column+=1
    for x in [-3.35,3.35]:cube('Side floor rim',(x,.01,0),(.10,.14,6.4),'oak_light',.018,'wood','Z')
    for z in [-3.15,3.15]:cube('End floor rim',(0,.01,z),(6.6,.14,.10),'oak_light',.018,'wood','X')
    begin('entry_deck',(.30,0,3.60),colliders=[box([1.30,.22,1.2],[0,-.03,0],'Landing')],
          changes=['Level front landing keeps exit/reentry on continuous supporting floor'])
    cube('Entry honey wood threshold',(0,-.03,0),(1.30,.22,1.2),'oak_light',.025,'wood','Z')
    for name,at,yaw,length in [('left_wall',(-3.30,FLOOR,0),90,6.4),('back_wall',(0,FLOOR,-3.10),0,6.8)]:
        begin(name,at,yaw,[box([length,3.7,.20],[0,1.85,0],name)])
        wall=cube('Warm white plaster',(0,1.85,0),(length,3.7,.20),'plaster',.015,'plaster')
        if name=='left_wall':
            cut=cylinder('True circular aperture',(.40,2.02,0),.75,.80,'plaster',vertices=64)
            cut.rotation_euler.x=math.pi/2;p.boolean_cut(wall,cut)
        for face in wall.data.polygons:face.use_smooth=False
        cube('Pale upper timber beam',(0,3.57,.075),(length,.26,.33),'oak_light',.045,'wood','X')
        if name=='left_wall':cube('Pale timber skirting',(0,.12,.12),(length,.24,.16),'oak',.02,'wood','X')
        else:
            for x,width in [(-.76,5.28),(3.24,.32)]:cube('Rear skirting clear of door',(x,.12,.12),(width,.24,.16),'oak',.02,'wood','X')
        for x in [-length/2+.14,length/2-.14]:
            cube('Rounded timber post',(x,1.85,.09),(.28,3.70,.34),'oak_light',.05,'wood','Y')
            cube('Timber square foot',(x,.12,.10),(.36,.24,.37),'oak',.03,'wood','Y')
        for x in ([-2.10,2.25] if name=='left_wall' else [-1.68,1.75]):
            cube('Slim structural post',(x,1.85,.105),(.13,3.46,.19),'oak',.025,'wood','Y')
    begin('round_window',(-3.17,FLOOR+2.02,-.40),90)
    vertices=[];faces=[];segments=64
    for depth in [-.055,.055]:
        for radius in [.75,.88]:
            vertices.extend([(radius*math.cos(math.tau*i/segments),radius*math.sin(math.tau*i/segments),depth) for i in range(segments)])
    for i in range(segments):
        j=(i+1)%segments
        for a,b in [(0,segments),(2*segments,3*segments),(0,2*segments),(segments,3*segments)]:
            faces.append((a+i,a+j,b+j,b+i))
    ring=mesh('Smooth honey circular window frame',vertices,faces,'oak_light','wood',True)
    for face in ring.data.polygons:face.use_smooth=abs(face.normal.y)<.5
    bevel=ring.modifiers.new('Soft round window edges','BEVEL');bevel.width=.018;bevel.segments=2
    ring.modifiers.new('Weighted normals','WEIGHTED_NORMAL').keep_sharp=True
    begin('window_backdrop',(-3.47,FLOOR+2.02,-.40),90,changes=['Separate replaceable window-view module, no shadows'])
    obj=mesh('Replaceable window scenery',[(-.78,-.78,0),(.78,-.78,0),(.78,.78,0),(-.78,.78,0)],[(0,1,2,3)],'FFFFFF')
    uv=obj.data.uv_layers.new(name='SourceWindowUV')
    for loop,point in zip(uv.data,[(0,0),(1,0),(1,1),(0,1)]):loop.uv=point
    material=obj.data.materials[0];node=material.node_tree.nodes.new('ShaderNodeTexImage')
    node.image=bpy.data.images.load(str(SRC/'reference/window-view.png'))
    coords=material.node_tree.nodes.new('ShaderNodeUVMap');coords.uv_map='SourceWindowUV'
    material.node_tree.links.new(coords.outputs['UV'],node.inputs['Vector'])
    material.node_tree.links.new(node.outputs['Color'],material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    NO_SHADOW.add('window_backdrop')


def teacup(at,scale=.62,color='porcelain'):
    x,y,z=at;s=scale
    lathe('Open glazed teacup',at,[(0,.052*s),(.015*s,.070*s),(.115*s,.088*s),(.125*s,.086*s),
          (.125*s,.071*s),(.10*s,.065*s),(.025*s,.049*s)],color,20)
    cylinder('Tea surface',(x,y+.10*s,z),.063*s,.004,'oak_dark',vertices=20)
    tube('Small cup handle',[(x+.080*s+math.sin(i*math.pi/10)*.048*s,y+.068*s+math.cos(i*math.pi/10)*.040*s,z)
                            for i in range(11)],.010*s,color,6)


def teapot(at,scale=1,color='sage'):
    x,y,z=at;s=scale
    lathe('Rounded teapot body',at,[(0,.065*s),(.015*s,.093*s),(.07*s,.12*s),(.14*s,.112*s),
          (.185*s,.074*s),(.19*s,.070*s)],color,24)
    lathe('Teapot inset lid',(x,y+.183*s,z),[(0,.069*s),(.015*s,.077*s),(.035*s,.040*s)],color,24)
    ellipsoid('Teapot lid knob',(x,y+.23*s,z),(.035*s,.035*s,.035*s),color,12,6)
    tube('Curved teapot spout',[(x-.09*s,y+.08*s,z),(x-.15*s,y+.115*s,z),(x-.18*s,y+.18*s,z)],.026*s,color,10)
    tube('Teapot loop handle',[(x+.10*s+math.sin(i*math.pi/12)*.092*s,y+.10*s+math.cos(i*math.pi/12)*.078*s,z)
                             for i in range(13)],.019*s,color,8)


def vase(at,scale=1,color='sage'):
    x,y,z=at;s=scale
    lathe('Small open flower vase',at,[(0,.040*s),(.04*s,.065*s),(.10*s,.057*s),(.15*s,.029*s),
          (.18*s,.030*s),(.18*s,.020*s),(.14*s,.018*s)],color,20)


def bouquet(name,at,scale=1):
    begin(name,at,changes=['Cut flowers reuse shared botanical blade and flower generators, six triangles per petal'])
    library_path=ROOT/'assets/rooms/_shared/plants/source/build_plants.py'
    spec=importlib.util.spec_from_file_location('tea_botanical',library_path)
    botanical=importlib.util.module_from_spec(spec);spec.loader.exec_module(botanical);botanical.k=p.b
    for i in range(7):
        a=i*2.399;h=(.14+(i%3)*.055)*scale
        end=(math.cos(a)*.105*scale,h,math.sin(a)*.09*scale)
        tube('Slender cut-flower stem',[(0,-.04*scale,0),end],.004*scale,'sage_dark',5)
        botanical.blade('Shared six-triangle bouquet leaf',(0,.035*scale,0),
                        (end[0],.10*scale,end[2]),.042*scale,'64805A',seed=i)
        botanical.flower(end,.75*scale,i)
    PROVENANCE[name]['kind']='derived shared botanical geometry'
    PROVENANCE[name]['source']=str(library_path.relative_to(ROOT))
    NO_SHADOW.add(name);FOLIAGE.add(name)


def tables_and_seats():
    for item in [row for row in PLAN['items'] if row['kind']=='table']:
        name=item['name'];at=item['position']
        begin(name,at,colliders=[{'shape':'cylinder','radius':.47,'height':1.0,'at':[0,.50,0]}],
              changes=['Approved .90m tabletop, 1.00m top, no floor cushions'])
        lathe('Rounded honey table edge',(0,0,0),[(.92,.425),(.935,.445),(.965,.45),(.990,.44),(1.0,.42)],'oak_light',48,'wood')
        cylinder('Table apron',(0,.85,0),.35,.16,'oak',vertices=32,kind='wood')
        for x,z in [(-.24,-.24),(.24,-.24),(-.24,.24),(.24,.24)]:
            cube('Short stout table leg',(x,.46,z),(.095,.92,.095),'oak',.018,'wood','Y')
        for x0,x1,color in [(-.12,-.045,'linen'),(-.045,.045,'sage'),(.045,.12,'linen')]:
            mesh('Cream and sage runner',[(x,y,z) for z,y in [(-.467,.70),(-.456,.98),(-.42,1.006),(.42,1.006),(.456,.98),(.467,.70)] for x in [x0,x1]],
                 [(i*2,i*2+2,i*2+3,i*2+1) for i in range(5)],color,'cloth')
        cube('Tea serving tray',(-.045,1.024,.035),(.44,.035,.23),'oak_dark',.018,'wood')
        teapot((-.15,1.044,.025),.70,'sage' if name!='tea_table_2' else 'porcelain')
        teacup((.065,1.043,.055),.60,'porcelain');teacup((.155,1.043,-.005),.55,'sage')
        vase((.12,1.0,-.18),.85,'sage' if name!='tea_table_2' else 'porcelain')
        bouquet(name+'_flowers',(at[0]+.12,FLOOR+1.145,at[2]-.18),.82)
    for name,color in [('round_stool_sage','sage'),('round_stool_linen','linen')]:
        begin(name,(20,0,0),colliders=[{'shape':'cylinder','radius':.28,'height':.715,'at':[0,.3575,0]}],
              changes=['New .56m round drum with upholstered pad; actual seat top .715m'])
        lathe('Pale rounded stool drum',(0,0,0),[(0,.225),(.025,.25),(.09,.252),(.55,.252),(.62,.26)],'oak',32,'wood')
        lathe('Soft upholstered seat',(0,0,0),[(.605,.25),(.63,.273),(.675,.28),(.705,.265),(.715,.22),(.715,.01)],color,40,'cloth')
        cylinder('Small upholstered centre button',(0,.713,0),.022,.004,color,vertices=12)
    for index,item in enumerate(row for row in PLAN['items'] if row['kind']=='stool'):
        source='round_stool_linen' if index%3==1 else 'round_stool_sage'
        p.instance(source,item['name'],item['position'])
    at=next(row['position'] for row in PLAN['items'] if row['name']=='window_bench')
    begin('window_bench',at,90,[box([2.1,.715,.5])],changes=['Three .70m bench seats; top .715m'])
    cube('Window bench seat plank',(0,.68,0),(2.1,.07,.50),'oak_light',.025,'wood')
    for x in [-.85,0,.85]:
        for z in [-.17,.17]:cube('Stout bench leg',(x,.325,z),(.10,.65,.10),'oak',.018,'wood','Y')
    cube('Bench lower stretcher',(0,.25,0),(1.86,.10,.10),'oak',.012,'wood')


def counter_and_coffee():
    begin('counter',[-.50,FLOOR,-1.95],colliders=[box([2.2,1.15,.65])])
    cube('Grey sage cabinet carcass',(0,.54,0),(2.12,1.08,.58),'sage',.035)
    for x in [-1.04,1.04]:cube('Cabinet corner stile',(x,.56,.29),(.10,.99,.075),'sage_dark',.012,'wood','Y')
    for i in range(15):cube('Sage vertical front board',(-.96+i*.137,.56,.30),(.129,.91,.035),'sage',.008,'wood','Y')
    for y in [.10,1.02]:cube('Cabinet horizontal rail',(0,y,.32),(2.17,.09,.06),'sage_dark',.012,'wood')
    cube('Honey counter top',(0,1.105,0),(2.2,.09,.65),'oak_light',.035,'wood')
    cube('Long dark tea tray',(-.21,1.177,.025),(1.22,.055,.32),'oak_dark',.02,'wood')
    teapot((-.56,1.207,.015),1.05,'sage')
    for x in [-.20,.02,.23]:teacup((x,1.207,.05),.78,'porcelain' if x!=.02 else 'sage')
    teacup((.51,1.15,-.05),.95,'porcelain');vase((.86,1.15,-.03),1.18,'porcelain')
    lathe('Tea-tool cup',(-.91,1.15,.02),[(0,.055),(.16,.073),(.18,.068),(.18,.053),(.025,.044)],'oak',16)
    for i in range(6):
        a=i*2.4;tube('Bamboo tea tool',[(-.91,1.17,.02),(-.91+math.cos(a)*.05,1.47+(i%2)*.025,.02+math.sin(a)*.05)],.007,'oak_dark',5)
    bouquet('counter_flowers',(.36,FLOOR+1.35,-1.98),1.35)
    begin('coffee_console',[1.45,FLOOR,-2.63],colliders=[box([1.0,.72,.50])],changes=['Hana coffee corner with one coffee pot and two cups'])
    cube('Coffee console top',(0,.675,0),(1.0,.09,.50),'oak_light',.025,'wood')
    for x in [-.41,.41]:
        cube('Coffee console leg',(x,.32,0),(.12,.64,.42),'oak',.02,'wood','Y')
    cube('Coffee console lower shelf',(0,.17,0),(.82,.07,.36),'oak',.012,'wood')
    cube('Coffee tray',(0,.745,0),(.64,.05,.30),'oak_dark',.018,'wood')
    lathe('Hana coffee pot',(-.13,.77,0),[(0,.075),(.025,.10),(.08,.095),(.24,.065),(.28,.067)],'iron',20)
    cylinder('Coffee pot lid',(-.13,1.055,0),.071,.025,'oak_dark',vertices=20)
    ellipsoid('Coffee pot lid knob',(-.13,1.085,0),(.04,.04,.04),'oak_dark',10,6)
    tube('Coffee spout',[(-.19,.86,0),(-.27,.96,0),(-.26,1.02,0)],.022,'iron',8)
    tube('Coffee handle',[(-.06,1.01,0),(.025,1.02,0),(.035,.86,0),(-.045,.84,0)],.018,'oak_dark',8)
    teacup((.14,.77,.05),.65,'porcelain');teacup((.27,.77,-.055),.55,'porcelain')


def shelves_and_door():
    begin('wall_shelves',[-.50,FLOOR,-2.98],changes=['Two wall shelves above Ama, with jars, cups and a small shared plant'])
    for y in [2.30,2.90]:
        cube('Wall shelf board',(0,y,.18),(1.90,.085,.36),'oak_light',.024,'wood')
        for x in [-.75,.75]:
            cube('Wall shelf bracket',(x,y-.17,.07),(.10,.34,.11),'oak',.012,'wood','Y')
            tube('Shelf diagonal support',[(x,y-.29,.08),(x,y-.04,.28)],.028,'oak',8)
    for i,x in enumerate([-.65,-.25,.54]):
        y=2.3425
        lathe('Lower shelf tea jar',(x,y,.17),[(0,.086),(.025,.101),(.27,.101),(.29,.085)],'porcelain',20)
        cylinder('Sage jar lid',(x,y+.302,.17),.105,.037,'sage' if i!=2 else 'oak',vertices=24)
        cube('Blank jar paper label',(x,y+.145,.273),(.10,.12,.008),'linen',.004)
    teapot((.14,2.3425,.16),.83,'oak_dark');teacup((.84,2.3425,.20),.70,'sage')
    for x in [-.36,.02]:teacup((x,2.9425,.16),.92,'sage')
    teapot((.51,2.9425,.14),.93,'sage')
    begin('decorative_door',[2.48,FLOOR,-2.96],changes=['Closed decorative rear door; usable entrance remains at the open front'])
    cube('Closed door backing',(0,1.165,0),(1.04,2.33,.075),'oak',.015,'wood','Y')
    for i in range(8):
        cube('Vertical pale door plank',(-.455+i*.13,1.165,.045),(.124,2.27,.035),'oak_light' if i%3==0 else 'oak',.006,'wood','Y')
    for x in [-.565,.565]:cube('Door jamb',(x,1.205,.05),(.09,2.41,.15),'oak_light',.018,'wood','Y')
    cube('Door lintel',(0,2.375,.05),(1.22,.10,.15),'oak_light',.018,'wood')
    cylinder_obj=cylinder('Round wooden door knob',(-.36,1.08,.135),.052,.065,'oak_dark',vertices=16)
    cylinder_obj.rotation_euler.x=math.pi/2
    begin('name_sign',[2.48,2.92,-2.87],changes=['Blank separate sign above the decorative door, clear of Ama nameplate'])
    cube('Blank warm ivory sign',(0,0,0),(1.20,.38,.055),'linen',.024)
    for y in [-.173,.173]:cube('Sign honey horizontal trim',(0,y,.034),(1.18,.028,.04),'oak',.008,'wood')
    for x in [-.583,.583]:cube('Sign honey vertical trim',(x,0,.034),(.028,.32,.04),'oak',.008,'wood','Y')


def lanterns():
    begin('wall_lantern',(24,0,0),changes=['Reusable square wood lantern frame and hanging bracket'])
    cube('Wall bracket pad',(0,.28,-.05),(.14,.24,.10),'oak',.018,'wood','Y')
    cube('Short hanging arm',(0,.36,.12),(.085,.085,.38),'oak',.014,'wood','Z')
    tube('Lantern suspension',[(0,.36,.29),(0,.17,.29)],.014,'brass',8)
    for y in [-.37,.13]:cube('Square lantern cap',(0,y,.29),(.34,.065,.30),'oak_light',.015,'wood')
    for x in [-.135,.135]:
        for z in [.18,.40]:cube('Lantern corner upright',(x,-.12,z),(.036,.49,.036),'oak',.007,'wood','Y')
    begin('lantern_glow',(24,0,0),changes=['Separate warm light panels using the same atlas'])
    cube('Warm matte lantern diffuser',(0,-.12,.29),(.25,.44,.21),'FFE1A2',.008)
    for i,(at,yaw) in enumerate([([-3.13,2.62,2.42],90),([-3.13,2.78,-2.22],90),([1.02,2.67,-2.97],0)],1):
        p.instance('wall_lantern','wall_lantern_'+str(i),at,yaw)
        p.instance('lantern_glow','lantern_glow_'+str(i),at,yaw)


def shared_plant(name,source,at,scale=1.):
    path=ROOT/'assets/rooms/_shared/plants/source/plants.blend'
    with bpy.data.libraries.load(str(path),link=False) as (_,dst):dst.collections=['KIT_'+source]
    collection=dst.collections[0];bpy.context.scene.collection.children.link(collection)
    collection.name='REUSE_'+name
    root=next(obj for obj in collection.objects if obj.type=='EMPTY')
    root.name=name;root.location=p.v(at);root.scale=(scale,scale,scale)
    PROVENANCE[name]={'asset':name,'author':'Huangzhong','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
        'kind':'shared plant mesh reuse','source':'assets/rooms/_shared/plants/'+source+'.glb',
        'source_sha256':hashlib.sha256((ROOT/'assets/rooms/_shared/plants'/f'{source}.glb').read_bytes()).hexdigest(),
        'changes':['Retain geometry and shared leaf detail; remap source atlas into Tea House atlas quadrant',f'Uniform scale {scale}'],
        'source_blend':str(path.relative_to(ROOT))}
    REUSED.append({'name':name,'source':source,'position':at,'yaw_degrees':0,'scale':[scale]*3,
                   'colliders':[{'shape':'cylinder','radius':.32,'height':.55,'at':[0,.275,0]}] if name=='corner_tree' else []})
    NO_SHADOW.add(name);FOLIAGE.add(name)


def finish():
    anchors=PLAN['anchors']
    for anchor in anchors:
        if anchor['name']=='sign_name':anchor['position']=[2.48,2.92,-2.812]
        obj=bpy.data.objects.new(anchor['name'],None);bpy.context.scene.collection.objects.link(obj)
        obj.location=p.v(anchor['position']);obj.rotation_euler.z=math.radians(anchor.get('yaw_degrees',0))
        obj.empty_display_type='ARROWS';obj.empty_display_size=.14
    boundaries=[box([.12,3,6.4],[3.26,1.58,0],'RightBoundary'),
        box([2.85,3,.12],[-1.775,1.58,3.06],'FrontLeftBoundary'),box([2.25,3,.12],[2.075,1.58,3.06],'FrontRightBoundary'),
        box([.12,3,1.2],[-.41,1.58,3.6],'LandingLeft'),box([.12,3,1.2],[1.01,1.58,3.6],'LandingRight'),
        box([1.3,3,.12],[.30,1.58,4.26],'LandingEnd')]
    points=[{'position':[-2.80,2.50,2.42],'color':'FFDC9C','energy':1.25,'range':2.0},
            {'position':[-2.80,2.66,-2.22],'color':'FFDC9C','energy':1.1,'range':1.9},
            {'position':[1.02,2.55,-2.64],'color':'FFDC9C','energy':1.1,'range':1.9}]
    p.MANIFEST_EXTRA.update({'anchors':anchors,'spawn':[.30,.08,2.55],'floor_y':.08,'footprint_m':[6.8,6.4],
        'boundaries':boundaries,'local_lights':points,'preflight':PLAN['preflight'],
        'author':'Huangzhong','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
        'source_dimensions':{'counter_height_m':1.15,'tabletop_height_m':1.0,'seat_height_m':.715,'door_height_m':2.33},
        'anchor_yaw_convention':'0 faces -Z; 180 faces +Z; seats are absolute world surface positions'})
    for image in bpy.data.images:
        if image.source=='FILE' and image.packed_file is None:image.pack()
    pitch=math.radians(43);distance=22;focus=[.10,1.1,.4]
    direction=[math.sin(math.pi/4)*math.cos(pitch),math.sin(pitch),math.cos(math.pi/4)*math.cos(pitch)]
    p.finalize({'position':[focus[i]+direction[i]*distance for i in range(3)],'target':focus,'size':6.72},
        {'background':'DDE8E7','ambient_color':'F1EBDD','ambient':.54,'sun_color':'FFF1D8','sun':1.05,
         'sun_position':[-6,7,2],'sun_target':[0,0,0],'points':[],'shadow':'single orthographic cascade; lantern lights live in art scene'})
    layout=json.loads((KIT/'layout.json').read_text())
    for asset in layout['assets']:
        name=asset['name'];asset.update({'review_only':name in ['round_stool_sage','round_stool_linen','wall_lantern','lantern_glow'],
            'cast_shadow':name not in NO_SHADOW,'vegetation':name in FOLIAGE,
            'material':'backdrop' if name=='window_backdrop' else 'glow' if name=='lantern_glow' else 'foliage' if name in FOLIAGE else 'opaque',
            'provenance':f'tools/art/source/tea_house/modules/{name}/reuse_provenance.json'})
    for asset in REUSED:
        layout['assets'].append({**asset,'file':asset['name']+'.glb','review_only':False,'cast_shadow':False,'vegetation':True,
            'material':'foliage','provenance':f'tools/art/source/tea_house/modules/{asset["name"]}/reuse_provenance.json'})
    save(KIT/'layout.json',layout)
    for name,record in PROVENANCE.items():save(SRC/'modules'/name/'reuse_provenance.json',record)
    save(SRC/'reuse_provenance.json',PROVENANCE)
    if '--geometry-only' not in sys.argv:p.bake_and_export()
    print('TEA_AUTHORED',len(layout['assets']),len(layout['instances']),flush=True)


def main():
    assert PLAN['preflight']['passed'],'Resolve twelve-seat layout before detailed modeling'
    p.start('tea_house','2681:135483 / approved Stark tea design')
    p.b.PALETTE.update(PAL);p.BAKE_SETTINGS.update({'ao_strength':.18,'floor_ao_strength':.08,'ao_distance':.28})
    shell();tables_and_seats();counter_and_coffee();shelves_and_door();lanterns()
    shared_plant('corner_tree','olive_tree',[-2.50,FLOOR,2.22])
    shared_plant('shelf_pothos','pothos',[-1.17,FLOOR+2.9425,-2.77],.62)
    finish()


if __name__=='__main__':main()
