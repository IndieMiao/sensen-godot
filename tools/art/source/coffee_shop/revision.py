"""SGODOT-179 R2 art and placement edits; other shop generators retain their defaults."""
import math, random, json
from pathlib import Path
import kit as k
from kit import cube,cylinder,ellipsoid,tube,lathe,mesh,begin

PALETTE={'oak':'C79B6F','oak_light':'E0B17A','oak_edge':'B89571','plaster':'F0D0A0','plaster_light':'F7DFBA','sage':'98A58E','linen_green':'DEDCC6','linen':'F4E7CD','leaf':'678347','leaf_light':'8EA15C','leaf_dark':'3E623D','terra':'C6B797','terra_light':'D6C8A9','jar_green':'AFBEA2','porcelain':'F4EFDF','iron':'596366','iron_edge':'8F9997'}
PLANTS=[]

def put(name,asset,at,yaw=0,scale=1,roll=0,collision=None):
    PLANTS.append({'name':name,'asset':asset,'file':'res://assets/rooms/_shared/plants/'+asset+'.glb','position':list(at),'rotation_degrees':[0,yaw,roll],'scale':[scale]*3,'colliders':collision or []})

def upholstered_chair():
    for x in (-.235,.235):
        for z in (-.22,.22):tube('Splayed solid oak leg',[(x*1.17,.015,z*1.15),(x,.51,z)],.032,'oak',8,'wood')
    cube('Hidden oak seat frame',(0,.49,0),(.43,.045,.40),'oak',.012,'wood')
    ellipsoid('Ivory upholstered seat',(0,.545,0),(.62,.14,.59),'linen',32,12,'cloth')
    # Horseshoe cushion: solid rounded fabric back, with continuous piping.
    path=[(.30*math.cos(i*math.pi/28),.80,-.285*math.sin(i*math.pi/28)) for i in range(29)]
    vs=[];fs=[]
    for i,p in enumerate(path):
        a=i*math.pi/28
        for j in range(12):
            t=j*math.tau/12;rad=.048*math.cos(t)
            vs.append((p[0]+rad*math.cos(a),p[1]+.195*math.sin(t),p[2]-rad*math.sin(a)))
    for i in range(28):
        for j in range(12):fs.append((i*12+j,i*12+(j+1)%12,(i+1)*12+(j+1)%12,(i+1)*12+j))
    fs += [tuple(reversed(range(12))),tuple(28*12+j for j in range(12))]
    mesh('White padded wraparound back',vs,fs,'linen','cloth',True)
    for y in (.62,.985):tube('Cotton edge piping',[(p[0],y,p[2]) for p in path],.008,'E5DFCE',6)
    tube('Upholstery seat piping',[(.298*math.cos(i*math.tau/48),.566,.283*math.sin(i*math.tau/48)) for i in range(49)],.006,'E6D8B8',5)

def slim_table():
    lathe('Graphite disc and slim pedestal',(0,0,0),[(0,.245),(.025,.26),(.047,.23),(.066,.055),(.72,.035),(.76,.12)],'596266',32,'metal')
    cylinder('Soft round oak table',(0,.79,0),.56,.09,'oak_light',vertices=48,kind='wood')
    for z in (-.27,.0,.27):
        span=math.sqrt(.54**2-z*z);tube('Fine tabletop joint',[(-span,.837,z),(span,.837,z)],.0014,'C2A27D',4)

def soft_rug():
    cylinder('Woven flat jute rug',(0,.007,0),.88,.012,'D0BE9C',vertices=64,kind='cloth')
    for r in (.80,.84,.875):tube('Bound jute edging',[(r*math.cos(i*math.tau/64),.016,r*math.sin(i*math.tau/64)) for i in range(65)],.004,'BCA989',5)

def espresso_machine():
    begin('espresso_machine',at=(.45,1.26,-1.76))
    cube('Retro cream enamel housing',(0,.35,-.025),(.68,.44,.36),'E9D7B6',.08)
    cube('Chrome base and drip tray',(0,.065,.055),(.70,.07,.59),'C5C7BC',.035,'metal')
    cube('Recessed dark brew bay',(0,.29,.172),(.47,.26,.025),'77746A',.018)
    cube('Chrome brew fascia',(0,.42,.18),(.57,.07,.060),'C9CBC0',.018,'metal')
    cube('Dark drip grille',(0,.108,.14),(.58,.018,.31),'5A5952',.012)
    for j in range(8):cube('Chrome grille slat',(-.24+j*.069,.12,.14),(.012,.006,.27),'C9CBC0',.001)
    for x in (-.16,.16):
        cylinder('Chrome brew group',(x,.315,.23),.065,.09,'C9CBC0',vertices=20,kind='metal')
        tube('Black portafilter grip',[(x,.278,.25),(x-.026,.265,.44)],.021,'494B45',8)
    tube('Curved steam wand',[(.31,.36,.12),(.35,.21,.16),(.34,.15,.30)],.012,'CDD0C5',8,'metal')
    dial=cylinder('Single pressure gauge',(-.20,.48,.171),.055,.021,'7D8077',vertices=24);dial.rotation_euler.x=math.pi/2
    dial=cylinder('Ivory pressure gauge face',(-.20,.48,.185),.043,.007,'F4ECD6',vertices=24);dial.rotation_euler.x=math.pi/2
    tube('Gauge needle',[(-.2,.48,.193),(-.222,.505,.193)],.003,'5E6354',4)
    for i,x in enumerate((.08,.19)):cube('Small rectangular brew key',(x,.48,.18),(.047,.065,.025),'858B7F',.006)
    cube('Chrome warming tray',(0,.578,-.025),(.66,.027,.35),'C9CDC1',.018,'metal')
    for i,(x,z,scale) in enumerate(((-.19,-.04,.66),(.10,.015,.73),(.25,-.09,.60))):
        before=len(k.CURRENT['objects']);k.cup((x,.598,z),scale,coffee=False)
        for o in k.CURRENT['objects'][before:]:o.rotation_euler.z+=math.radians((-7,5,11)[i])

def pastry_piece(kind,x,y,z,scale,angle):
    before=len(k.CURRENT['objects'])
    if kind=='croissant':
        for j in range(5):
            xx=(j-2)*.034;zz=abs(j-2)*.027
            ellipsoid('Curved croissant folded lobe',(xx,.056,zz),(.081,.11-.018*abs(j-2),.115),'C78E43' if j%2 else 'DAAA61',10,6)
    elif kind=='muffin':
        cylinder('Muffin fluted paper',(0,.042,0),.063,.078,'D6B78E',top=.080,vertices=12)
        ellipsoid('Irregular muffin crown',(0,.104,0),(.176,.10,.168),'B88342',12,6)
        for j in range(3):ellipsoid('Muffin crust chip',(.046*math.cos(j*2.3),.147,.043*math.sin(j*2.3)),(.025,.012,.022),'DFAD62',8,4)
    else:
        cylinder('Fluted tart shell',(0,.031,0),.084,.059,'C88D48',top=.094,vertices=14)
        cylinder('Golden custard centre',(0,.067,0),.074,.018,'F1CE78',vertices=16)
        for j in range(2):ellipsoid('Custard toasted spot',(.027*math.cos(j*3),.078,.029*math.sin(j*3)),(.026,.008,.021),'AD7035',8,4)
    c,s=math.cos(angle),math.sin(angle)
    for o in k.CURRENT['objects'][before:]:
        px,py,pz=o.location.x,-o.location.y,o.location.z
        o.location=k.v((x+scale*(c*px-s*py),y+scale*pz,z+scale*(s*px+c*py)))
        o.scale*=scale;o.rotation_euler.z-=angle

def pastry_case():
    begin('pastry_case',at=(-.92,1.26,-1.80))
    cube('Display oak base',(0,.025,0),(1.16,.05,.68),'oak_light',.025,'wood')
    rng=random.Random(17902)
    for tier,y in enumerate((.10,.34,.58)):
        cube('White patisserie tray',(0,y,0),(1.09,.022,.59),'porcelain',.01)
        for i in range(5):
            x=-.37+(i%3)*.34+(0.055 if i>=3 else 0);z=-.13 if i<3 else .15
            kind=('croissant','tart','muffin')[(i+tier)%3]
            pastry_piece(kind,x+rng.uniform(-.018,.018),y+.014,z+rng.uniform(-.012,.012),rng.uniform(.82,1.03),rng.uniform(-.30,.30))
    for x in (-.565,.565):tube('Polished display side frame',[(x,.04,.32),(x,.66,.32),(x,.83,-.25),(x,.04,-.31)],.012,'B5B9AF',6,'metal')
    for z,y in ((.32,.66),(-.25,.83),(-.31,.05)):tube('Display crossbar',[(-.565,y,z),(.565,y,z)],.012,'B5B9AF',6,'metal')
    begin('display_glass',at=(-.92,1.26,-1.80))
    mesh('Clear display front',[(-.55,.08,.319),(.55,.08,.319),(.55,.657,.319),(-.55,.657,.319)],[(0,1,2,3)],'CADFD9')
    mesh('Clear sloped display top',[(-.55,.663,.317),(.55,.663,.317),(.55,.827,-.25),(-.55,.827,-.25)],[(0,1,2,3)],'CADFD9')
    for x in (-.553,.553):mesh('Clear display side',[(x,.06,.31),(x,.66,.31),(x,.82,-.25),(x,.06,-.30)],[(0,1,2,3)],'CADFD9')

def remove_objects(module,predicate):
    record=k.KITS[module]
    for o in list(record['objects']):
        if predicate(o):record['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)

def replace(name,fn):
    record=k.KITS[name];remove_objects(name,lambda o:True);k.CURRENT=record;fn()

def architecture():
    replace('entry_steps',lambda:None)
    r=k.KITS['entry_steps'];r['root'].location=k.v((.15,0,2.82));r['at']=[.15,0,2.82]
    cube('Joined lower entrance tread',(0,-.235,.38),(1.78,.15,.78),'plaster',.055)
    cube('Joined upper entrance tread',(0,-.095,.01),(1.74,.13,.50),'plaster_light',.055)
    for x in (-.87,.87):
        cube('Entrance stair side cheek',(x,-.12,.28),(.14,.30,.72),'plaster',.035)
    r['collision']=[{'at':[0,0,0],'points':[[x,y,z] for x in (-.85,.85) for y,z in ((-.34,-.22),(.05,-.22),(.05,.21),(-.31,.88),(-.34,.88))]}]
    k.KITS['floor']['collision']=[{'at':[0,-.080,0],'size':[6.20,.259,5.70]}]
    # Back and left windows: architecture has real open panels, glazing is separate.
    for name in ('left_window','back_counter_wall','right_arch_window'):
        remove_objects(name,lambda o:any(s in o.name for s in ('Garden glazing','Blurred garden','Clerestory glass','Pale frosted','Garden leaf','Living vine','Ivy leaf','Daisy')))
    begin('window_glass_left',at=(-3,.04,-1.83),yaw=90)
    cube('Clear left window',(0,1.57,-.026),(1.62,2.55,.006),'CAE1D8',0)
    begin('window_glass_back',at=(-.81,.04,-2.72))
    cube('Clear transom glass',(0,2.45,-.026),(4.14,.93,.006),'CAE1D8',0)
    begin('window_glass_arch',at=(2.24,.04,-2.72))
    k.arch_solid('Clear arched pane',1.30,.05,2.12,.65,.006,-.026,'CAE1D8')
    # Replace floor with staggered, subtle joints. Warm window-distance colour baked per board.
    replace('floor',lambda:None)
    cube('Thick softened limestone foundation',(0,-.15,0),(6.25,.32,5.75),'plaster',.13)
    rng=random.Random(1007)
    for j in range(20):
        z=-2.70+j*.282;start=-3.09
        cuts=[-3.09]+sorted(x for x in [-2.30+(j%3)*.54+i*1.66 for i in range(4)] if -3.05<x<3.05)+[3.09]
        for a,b in zip(cuts,cuts[1:]):
            tone=['DFAD73','E4B780','DDA971','E7BD88'][rng.randrange(4)]
            cube('Staggered oak board',((a+b)/2,.017,z),(b-a-.003,.065,.277),tone,.008,'wood')
    # Window-facing floor tint is authored into broad albedo, not baked shadows.
    for m in k.MATS.values():
        if not any(m.name.startswith(t) for t in ('DFAD73','E4B780','DDA971','E7BD88')):continue
        nt=m.node_tree;p=nt.nodes.get('Principled BSDF');base=p.inputs['Base Color'].links[0].from_socket
        geo=nt.nodes.new('ShaderNodeNewGeometry');sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(geo.outputs['Position'],sep.inputs[0])
        mapping=nt.nodes.new('ShaderNodeMapRange');mapping.inputs['From Min'].default_value=-3;mapping.inputs['From Max'].default_value=3;mapping.inputs['To Min'].default_value=.17;mapping.inputs['To Max'].default_value=.0
        nt.links.new(sep.outputs['X'],mapping.inputs['Value']);mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';nt.links.new(mapping.outputs[0],mix.inputs[0]);nt.links.new(base,mix.inputs[1]);mix.inputs[2].default_value=(1,.83,.66,1);nt.links.new(mix.outputs[0],p.inputs['Base Color'])
    replace('hanging_cafe_sign',lambda:None)
    for label,rx,ry,z,depth,color in [('Oval oak sign',.66,.47,0,.10,'oak_light'),('Inset cream face',.60,.41,.065,.045,'porcelain')]:
        n=48;vs=[(rx*math.cos(j*math.tau/n),ry*math.sin(j*math.tau/n),z+d) for d in (-depth/2,depth/2) for j in range(n)]
        fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
        o=mesh(label,vs,fs,color,'wood',True)
        b=o.modifiers.new('Soft sign rim','BEVEL');b.width=.018;b.segments=3
        o.modifiers.new('Sign weighted normals','WEIGHTED_NORMAL')
    k.text_label('GREENHOUSE',(0,.065,.092),.129,'leaf_dark')
    k.text_label('CAFE',(0,-.12,.092),.18,'leaf_dark')
    for x in (-.33,.33):tube('Iron suspension',[(x,.38,0),(x,.69,0)],.012,'iron',6)
    tube('Outward wrought iron arm',[(-.68,.69,0),(.78,.69,0)],.022,'iron',8)
    tube('Curled iron wall bracket',[(.66,.69,0),(.66,.95,0),(.42,.95,0),(.40,.84,0),(.52,.84,0)],.016,'iron',6)
    for i,x in enumerate((-.18,-.07,.07,.18)):k.leaf('Sign olive motif',(0,-.26,.094),(x,-.24+(i%2)*.025,.095),.06,'leaf')
    # Quiet sage boarding with four variants.
    rec=k.KITS['back_counter_wall'];k.CURRENT=rec
    for i,o in enumerate(rec['objects']):
        if 'Vertical painted' in o.name:o.data.materials.clear();o.data.materials.append(k.material(['A5AC88','B0B494','A0A783','ABB18E'][i%4],'wood','Y'))
    begin('window_garden_backdrop')
    for layer,(z,tone) in enumerate(((-3.35,'C8D7BF'),(-3.25,'AEC6A2'),(-3.13,'90AA77'))):
        for j in range(9):
            x=-2.9+j*.72+(layer%2)*.23
            ellipsoid('Layered distant canopy', (x,2.03+.18*math.sin(j*1.8+layer),z),(.95,.95+.20*math.cos(j),.12),tone,10,6)
    for layer,(x,tone) in enumerate(((-3.5,'CADBC7'),(-3.39,'B2CBA9'),(-3.27,'94B181'))):
        for j in range(4):
            ellipsoid('Layered side canopy',(x,1.25+(j%2)*.56,-2.60+j*.43),(.12,1.18,.76),tone,10,6)
    # Wall shelf / intentionally varied crockery sizes and rotations.
    begin('wall_shelf',at=(-.75,1.68,-2.45))
    cube('Oak wall shelf',(0,0,0),(1.58,.065,.29),'oak_light',.025,'wood')
    for x in (-.59,.59):tube('Small shelf bracket',[(x,-.20,-.10),(x,-.025,.10),(x,-.025,-.10)],.016,'iron',6)
    for i,x in enumerate((-.60,-.31,.03,.36)):
        k.cup((x,.036,.015),.67+i*.035,['porcelain','D9D6BE','B4C0A6','E1D8C5'][i],False)

def foliage():
    # Pots follow reference plant corners, never occupy the center walk lane.
    put('LargeMonsteraLeft','monstera',(-2.47,.065,-1.51),-15,1.05,collision=[{'at':[0,.30,0],'size':[.60,.60,.60]}])
    put('WhitePeaceLily','peace_lily',(-2.58,.065,-.68),22,.95,collision=[{'at':[0,.21,0],'size':[.46,.42,.46]}])
    put('SmallCornerPlant','pothos',(-2.88,.065,1.98),35,.9)
    put('MonsteraWovenCorner','monstera_woven',(2.55,.065,-1.70),-28,.94,collision=[{'at':[0,.3,0],'size':[.60,.60,.60]}])
    put('TallOliveCorner','olive_tree',(1.97,.065,-2.26),45,.66,collision=[{'at':[0,.22,0],'size':[.40,.44,.40]}])
    put('SmallWhiteLilyRight','peace_lily',(2.14,.065,-1.76),-20,.52)
    # Dense contour-following segments: the source vine points down local Y.
    for i,a in enumerate([math.pi-j*math.pi/7 for j in range(8)]):
        at=(-2.80,1.96+.93*math.sin(a),.65-.93*math.cos(a))
        put('ArchCrown%02d'%i,'ivy_short',at,90,.75,math.degrees(a))
    for side,z in [('front',1.65),('back',-.35)]:
        for i,y in enumerate((2.02,1.50,.94)):
            put('ArchSide_'+side+str(i),['ivy_short','ivy_medium'][i%2],(-2.80,y,z),90,.78,(-7 if i%2 else 8))
    for i,x in enumerate((-2.71,-1.55,-.30,1.20)):
        put('TransomTrailing%02d'%i,['ivy_long','ivy_medium','ivy_short'][i%3],(x,2.93,-2.59),0,.76+(i%2)*.12,(-6+i*4))
    for i,a in enumerate([math.pi-j*math.pi/5 for j in range(6)]):
        put('WindowArchCrown%02d'%i,'ivy_short',(2.24+.75*math.cos(a),2.14+.76*math.sin(a),-2.48),0,.75,math.degrees(a))
    for i,y in enumerate((2.14,1.57,1.0)):
        put('RightPillarVine%02d'%i,['ivy_medium','ivy_short'][i%2],(2.94,y,-2.57),0,.90,4)
    for i,x in enumerate((1.25,1.65,2.08)):
        put('FrontFlowerCluster%02d'%i,'flower_shrub',(x,.82,2.66),i*37,.86)
        put('FrontFlowerDrape%02d'%i,'ivy_short',(x,.94,2.91),0,.83,i*8-8)
    put('LeftPierFlowers','flower_shrub',(-2.93,.9,2.58),40,.90)
    put('LeftPierDrape','ivy_medium',(-3.03,1.16,2.53),-90,.72,-8)
    # Far-to-near low-poly canopy masses are authored in the backdrop module.


def append_source_plants():
    source=k.ROOT/'assets/rooms/_shared/plants/source/plants.blend'
    if not source.exists():return
    with k.bpy.data.libraries.load(str(source),link=False) as (data,dst):dst.collections=[n for n in data.collections if n.startswith('KIT_')]
    kits={c.name.removeprefix('KIT_'):c for c in dst.collections}
    collection=k.bpy.data.collections.new('Shared botanical instances');k.bpy.context.scene.collection.children.link(collection)
    for p in PLANTS:
        root=k.bpy.data.objects.new(p['name'],None);collection.objects.link(root);root.location=k.v(p['position']);root.rotation_euler=(math.radians(p['rotation_degrees'][0]),-math.radians(p['rotation_degrees'][2]),math.radians(p['rotation_degrees'][1]));root.scale=p['scale'];root['shared_asset']=p['file']
        for o in kits[p['asset']].objects:
            if o.type!='MESH':continue
            copy=o.copy();copy.data=o.data;copy.parent=root;collection.objects.link(copy)

def finish():
    architecture();foliage()
    for inst in k.INSTANCES:
        if inst['name']=='chair_2':inst['position'][0]=-.62
        if inst['name']=='chair_3':inst['position'][0]=.84
    # Match the accepted room's furniture-to-avatar ratios without enlarging footprints.
    for name,factor in [('table',1.20),('chair',1.13)]:
        rec=k.KITS[name]
        for o in rec['objects']:
            o.location.z*=factor;o.scale.z*=factor
        for box in rec['collision']:
            box['at'][1]*=factor;box['size'][1]*=factor
    for name in ('table_bouquet','table_coffee'):
        rec=k.KITS[name];rec['at'][1]+= .167;rec['root'].location.z+=.167
    for inst in k.INSTANCES:
        if inst['asset'] in ('table_bouquet','table_coffee'):inst['position'][1]+=.167
        root=k.bpy.data.objects[inst['name']];root.location=k.v(inst['position'])
        for o in list(root.children):k.bpy.data.objects.remove(o,do_unlink=True)
        for source in k.KITS[inst['asset']]['objects']:
            o=source.copy();o.data=source.data;k.bpy.context.scene.collection.objects.link(o);o.parent=root
    k.save('545:2956',{'position':[10.85,11.0,11.15],'target':[-.15,1.27,.15],'size':9.6})
    path=k.OUT/'layout.json';d=json.loads(path.read_text());d['shared_plants']=PLANTS
    d['material_overrides']={'window_garden_backdrop':{'unshaded':True},'espresso_machine':{'roughness':.40,'metallic':.12},'table':{'roughness':.54},'window_glass_left':{'alpha':.08},'window_glass_back':{'alpha':.08},'window_glass_arch':{'alpha':.08}}
    d['lighting']={'background':'D3E7D8','ambient':'C0ADA9','ambient_energy':.58,'sun_color':'FFE0AE','sun_energy':1.55,'sun_position':[6,9,-4],'sun_target':[0,0,.8],'angular_distance':4.5,'lamps':[{'position':[-1.20,2.25,-1.32],'color':'FFE0A3','energy':1.2,'range':1.45},{'position':[.30,2.25,-1.32],'color':'FFE0A3','energy':1.2,'range':1.45}]}
    d['spawn']=[.15,-.12,3.25]
    d['boundaries']=[{'name':'left_open_arch_boundary','at':[-3.11,1.20,0],'size':[.10,2.7,5.8]},{'name':'entry_landing_floor','at':[.15,-.36,3.34],'size':[1.74,.10,.90]},{'name':'landing_front_edge','at':[.15,.45,3.79],'size':[1.90,1.7,.08]},{'name':'landing_left_edge','at':[-.76,.4,3.25],'size':[.08,1.7,1.15]},{'name':'landing_right_edge','at':[1.06,.4,3.25],'size':[.08,1.7,1.15]}]
    d['bench']={'route':[{'name':'entry_step','position':[.15,-.18,3.2]},{'name':'entry_inside','position':[.15,.07,2.20]},{'name':'between_tables','position':[.05,.07,.60]},{'name':'counter_front','position':[.05,.07,-.70]},{'name':'plant_corner_left','position':[-2.0,.07,-.70]},{'name':'center_return','position':[.05,.07,-.70]},{'name':'plant_corner_right','position':[2.2,.07,-.70]},{'name':'center_return_right','position':[.05,.07,-.70]},{'name':'between_tables_return','position':[.05,.07,.60]},{'name':'door_return','position':[.15,.07,2.20]}],
      'blocked':[{'name':'counter','from':[0,.07,-.65],'toward':[0,.07,-1.8]},{'name':'table_left','from':[-1.34,.07,1.9],'toward':[-1.34,.07,.5]},{'name':'large_pot','from':[-2.47,.07,-.72],'toward':[-2.47,.07,-1.51]},{'name':'front_low_wall','from':[-1.6,.07,2.05],'toward':[-1.6,.07,3.35]},{'name':'side_low_wall','from':[2.35,.07,.0],'toward':[3.5,.07,0]}],
      'gaps':[{'name':'tables_center','from':[.10,.07,1.3],'to':[.10,.07,-.25],'width':.80},{'name':'tables_counter','from':[-1.7,.07,-.50],'to':[2.1,.07,-.50],'width':.87},{'name':'entry','from':[.15,-.2,3.20],'to':[.15,.07,2.1],'width':1.27}],
      'scale_reference':'Basic Room unchanged Avatar fixture; capsule r=.21 h=1.25; speed=3.75',
      'harness_status':'Awaiting shared harness from SGODOT-172; data are not execution evidence'}
    from bench_data import apply
    d=apply(d)
    path.write_text(json.dumps(d,indent=2)+'\n')
    append_source_plants();k.bpy.ops.wm.save_as_mainfile(filepath=str(k.SOURCE/'coffee_shop.blend'))
