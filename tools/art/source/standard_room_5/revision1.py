"""Reference-led R1 of SGODOT-172. Local detail/layout; shared kit stays reusable."""
from pathlib import Path
import math
import json
import random
import bpy
from mathutils import Matrix,Vector
import scene_room_pipeline as p
from scene_room_pipeline import *
from shop_room_parts import garden_tool,pot
from build_standard_room_5 import sofa

ROOT=Path(__file__).resolve().parents[4]
PALETTE={'oak':'BE8548','oak_light':'D19851','oak_edge':'A36A38','oak_end':'B98044',
         'floor':'B27D47','floor_light':'B78049','floor_shade':'AE7844','joint':'956438',
         'plaster':'EBD6B6','plaster_light':'E8D4B4','stone':'C6AF8A','sage':'7B885D',
         'sage_light':'96A271','sage_dark':'5E6C47','linen':'E9DAB9','linen_green':'9FAE77',
         'terra':'B98246','terra_light':'CC985C','leaf':'4A7936','leaf_light':'799C43','leaf_dark':'3A602D'}

def move_kit(name,at,yaw=None):
    k=p.KITS[name];k['root'].location=v(at);k['at']=list(at)
    if yaw is not None:k['root'].rotation_euler.z=math.radians(yaw);k['yaw']=yaw

def scale_kit(name,scale):
    k=p.KITS[name];m=Matrix.Diagonal(Vector((scale[0],scale[2],scale[1],1)))
    for o in k['objects']:o.matrix_basis=m@o.matrix_basis
    for c in k['collision']:
        c['at']=[c['at'][i]*scale[i] for i in range(3)];c['size']=[c['size'][i]*scale[i] for i in range(3)]

def recolor_reused():
    # Match imported Basic Room source to the sampled R1 palette, retaining its
    # explicit GardenUV image material. No original source file is written.
    for kit in p.KITS.values():
        for obj in kit['objects']:
            for slot in obj.material_slots:
                mat=slot.material
                if not mat or any(n.type=='TEX_IMAGE' for n in mat.node_tree.nodes):continue
                key=next((k for k in sorted(p.b.PALETTE,key=len,reverse=True) if mat.name.startswith(k+'_')),None)
                if key:
                    kind='wood' if '_wood_' in mat.name else 'cloth' if '_cloth_' in mat.name else 'plaster' if '_plaster_' in mat.name else 'metal' if '_metal_' in mat.name else 'matte'
                    axis=mat.name.split('_')[-1].split('.')[0]
                    slot.material=material(key,kind,axis if axis in ('X','Y','Z') else 'X')

def room_envelope():
    shell(6.2,6.2,3.35,window_z=.20,door_x=2.36)
    # Regular stagger, fine seams and narrow palette: no alternating light/dark board pattern.
    for o in p.KITS['room_shell']['objects']:
        if 'floorboard' in o.name.lower():
            color=['floor','floor_light','floor','floor_shade','floor'][random.randrange(5)]
            o.data.materials.clear();o.data.materials.append(material(color,'wood'))
            o.scale.x=(o.dimensions.x+.008)/o.dimensions.x
            o.scale.y=(o.dimensions.y+.006)/o.dimensions.y
    k=p.KITS['room_shell']
    k['collision']=[{'at':[0,-.07,0],'size':[6.48,.30,6.48]},
        {'at':[-3.10,1.65,0],'size':[.22,3.3,6.45]},
        {'at':[-.66,1.65,-3.10],'size':[4.66,3.3,.22]},
        {'at':[3.02,1.65,-3.10],'size':[.14,3.3,.22]},
        {'at':[2.36,2.94,-3.10],'size':[1.06,.82,.22]},
        {'at':[3.19,.75,0],'size':[.10,1.5,6.48]},
        {'at':[0,.75,3.19],'size':[6.48,1.5,.10]},
        {'at':[2.36,-.07,-3.42],'size':[1.10,.30,.84]},
        {'at':[1.77,.70,-3.45],'size':[.08,1.4,.85]},
        {'at':[2.95,.70,-3.45],'size':[.08,1.4,.85]},
        {'at':[2.36,.70,-3.85],'size':[1.2,1.4,.08]}]
    # Readable, chunky caps and plinth; keep the accepted door's clear height.
    for name in ('back_wall','window_wall'):
        for o in p.KITS[name]['objects']:
            for mod in o.modifiers:
                if mod.type=='BEVEL':mod.width=min(.11,mod.width*1.25);mod.segments=3
    # Preserve closed-door hero appearance; separate frame and pivot leaf so
    # the benchmark can swing the door open across the real collision gap.
    old=p.KITS['green_door'];frames=[o for o in old['objects'] if 'doorway' in o.name.lower()]
    begin('door_frame',(2.36,.05,-2.985));new=p.KITS['door_frame']
    for o in frames:
        old['objects'].remove(o)
        for c in list(o.users_collection):c.objects.unlink(o)
        new['collection'].objects.link(o);o.parent=new['root'];new['objects'].append(o)
    for o in old['objects']:o.location.x+=.52
    move_kit('green_door',(1.84,.05,-2.985))
    p.MANIFEST_EXTRA['door']={'module':'green_door','open_yaw_degrees':100,'hinge':[1.84,.05,-2.985]}
    move_kit('window_garden',(-3.03,0,.20),90)
    for obj in p.KITS['window_garden']['objects']:
        for vertex in obj.data.vertices:
            vertex.co.z=1.30+(vertex.co.z-1.18)/(3.20-1.18)*1.70
    paint_window_view()

def paint_window_view():
    import numpy as np
    size=512;y,x=np.mgrid[0:size,0:size].astype(np.float32)/(size-1)
    def col(h):return np.array([int(h[i:i+2],16)/255 for i in (0,2,4)],dtype=np.float32)
    pixels=np.ones((size,size,4),dtype=np.float32)
    pixels[:,:,:3]=col('D6E9DF')+(col('9ECFDC')-col('D6E9DF'))*y[:,:,None]
    def paint(mask,c):
        a=np.clip(mask,0,1)[:,:,None];pixels[:,:,:3]=pixels[:,:,:3]*(1-a)+col(c)*a
    def disk(cx,cy,rx,ry,c,soft=.09):
        d=np.sqrt(((x-cx)/rx)**2+((y-cy)/ry)**2);paint(np.clip((1+soft-d)/(2*soft),0,1),c)
    for cy,amp,color,phase in [(.43,.04,'BACB94',1),(.31,.035,'A7C277',2),(.17,.022,'8CA75C',4)]:
        hill=cy+amp*np.sin(x*6+phase);paint(np.clip((hill-y+.017)/.034,0,1),color)
    for cx,cy,s in [(.13,.58,.88),(.54,.69,1.02),(.85,.57,.73),(.98,.45,.56)]:
        paint(np.clip((.012*s-abs(x-cx))/.003,0,1)*np.clip((y-.21)/.01,0,1)*np.clip((cy-y)/.02,0,1),'967C51')
        for ox,oy,rx,ry,color in [(-.057,0,.068,.106,'8DAB62'),(.053,.027,.083,.108,'A8BF73'),(0,.083,.079,.102,'BED492')]:
            disk(cx+ox*s,cy+oy*s,rx*s,ry*s,color)
    rng=random.Random(172)
    for i in range(85):
        cx=rng.random();cy=rng.uniform(.015,.23)
        paint(np.clip((.003-abs(x-cx))/.002,0,1)*np.clip((y-cy)/.004,0,1)*np.clip((cy+.035-y)/.008,0,1),'879D52')
        if i%2==0:
            for ox,oy in [(-.006,0),(.006,0),(0,.008),(0,-.008)]:disk(cx+ox,cy+.033+oy,.006,.007,'FFF5D8',.15)
            disk(cx,cy+.033,.004,.005,'D7BC69',.12)
    image=bpy.data.images.new('Standard Room layered garden',width=size,height=size,alpha=False)
    image.colorspace_settings.name='sRGB';image.pixels.foreach_set(pixels.ravel());image.pack()
    image.filepath_raw=str(p.OUT/'window_landscape.png');image.file_format='PNG';image.save()
    for obj in p.KITS['window_garden']['objects']:
        for loop in obj.data.loops:
            co=obj.data.vertices[loop.vertex_index].co
            obj.data.uv_layers['GardenUV'].data[loop.index].uv=((co.x+1.15)/2.3,(co.z-1.30)/1.70)
        for mat in obj.data.materials:
            for node in mat.node_tree.nodes:
                if node.type=='TEX_IMAGE':node.image=image

def export_window_card():
    # Keep the small landscape's own 512px texture resolution. This raw card
    # uses its source UVs and shares no duplicated image inside the GLB.
    source=p.KITS['window_garden']['objects'][0]
    obj=bpy.data.objects.new('window_garden_mobile',source.data.copy());bpy.context.scene.collection.objects.link(obj)
    for uv in list(obj.data.uv_layers):
        if uv.name!='GardenUV':obj.data.uv_layers.remove(uv)
    obj.data.uv_layers.active_index=0;obj.data.uv_layers.active.active_render=True
    for loop in obj.data.loops:
        co=obj.data.vertices[loop.vertex_index].co
        obj.data.uv_layers.active.data[loop.index].uv=((co.x+1.15)/2.3,(co.z-1.30)/1.70)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.gltf(filepath=str(p.OUT/'window_garden.glb'),export_format='GLB',use_selection=True,
        export_yup=True,export_normals=True,export_texcoords=True,export_image_format='NONE',export_animations=False)
    bpy.data.objects.remove(obj,do_unlink=True)

def shared_plant(name,asset,at,scale=1.0,yaw=0,collider=None):
    # Consume Liu Bei's library without rebaking or changing it. Append source
    # only for editable context/orthographic views; runtime references its GLB.
    source=ROOT/'assets/rooms/_shared/plants/source/plants.blend'
    with bpy.data.libraries.load(str(source),link=False) as (src,dst):dst.collections=['KIT_'+asset]
    collection=dst.collections[0];bpy.context.scene.collection.children.link(collection)
    collection.name='SHARED_'+name
    root=next(o for o in collection.objects if o.type=='EMPTY')
    root.name=name;root.location=v(at);root.rotation_euler.z=math.radians(yaw);root.scale=(scale,scale,scale)
    root['shared_source']='res://assets/rooms/_shared/plants/'+asset+'.glb'
    # Per-placement collision remains authored in this scene and independent of
    # the library. Its numbers are unscaled module coordinates.
    p.MANIFEST_EXTRA.setdefault('shared_plants',[]).append({'name':name,'file':asset+'.glb',
        'position':list(at),'rotation_degrees':[0,yaw,0],'scale':[scale]*3,'colliders':collider or []})

def hearth():
    begin('hearth',(-1.59,.082,-2.61),collision=[{'at':[0,.70,0],'size':[1.03,1.4,.94]}])
    cube('Broad rounded hearth foot',(0,.075,.05),(1.13,.15,1.04),'stone',.065)
    body=cube('Rounded lime plaster stove',(0,.68,0),(1.05,1.20,.91),'plaster_light',.14,'plaster')
    # Narrower upper body, organic shoulder. Keep a true cutout, dark lining.
    cut=arch_solid('Arched firebox opening',.67,.17,.59,.29,1.6,.12,'iron');boolean_cut(body,cut)
    arch_trim('Thick rounded plaster firebox arch',.67,.17,.59,.29,.067,.11,.455,'stone')
    cube('Warm red firebox lining',(0,.47,-.27),(.73,.75,.09),'653529',.03)
    cube('Hearth rounded cooking ledge',(0,1.22,.01),(1.11,.16,.98),'plaster_light',.09,'plaster')
    breast=cube('Tapered soft plaster chimney breast',(0,1.81,-.22),(.72,1.18,.52),'plaster_light',.13,'plaster')
    for vert in breast.data.vertices:
        if vert.co.z>0:vert.co.x*=.82
    cylinder('Black stove pipe',(0,2.61,-.24),.122,.56,'iron',vertices=24,kind='metal')
    for y in (2.35,2.88):cylinder('Iron stovepipe collar',(0,y,-.24),.156,.085,'iron_edge',vertices=24,kind='metal')
    tube('Stove pipe elbow',[(0,2.74,-.24),(0,2.78,-.43),(0,2.78,-.57)],.12,'iron',14,'metal')
    cube('Pipe timber mount',(0,2.98,-.32),(.34,.24,.33),'oak',.055,'wood')
    reuse('fire',(-1.59,.30,-2.29));scale_kit('fire',(1.12,1.10,1.0))
    reuse('kettle',(-1.59,1.40,-2.42))
    for o in p.KITS['kettle']['objects']:
        if any(t in o.name.lower() for t in ['pot','kettle']):o.data.materials.clear();o.data.materials.append(material('sage'))
    begin('firewood_alcove',(-.66,.082,-2.68),collision=[{'at':[0,.54,0],'size':[.69,1.08,.82]}])
    body=cube('Rounded plaster wood niche',(0,.53,0),(.69,1.06,.77),'plaster_light',.065,'plaster')
    cut=arch_solid('Open firewood niche',.52,.11,.45,.24,1.4,.12,'iron');boolean_cut(body,cut)
    cube('Wood niche dark back',(0,.37,-.29),(.52,.53,.09),'oak_dark',.02)
    arch_trim('Wood niche curved surround',.52,.11,.45,.24,.034,.073,.397,'oak_edge')
    cube('Firewood cabinet countertop',(0,1.06,0),(.77,.13,.89),'oak_light',.04,'wood')
    for i,(x,y) in enumerate([(-.16,.22),(.06,.22),(.21,.23),(-.11,.40),(.13,.42),(0,.58)]):
        z=.03+(i%2)*.05;r=.095+(i%3)*.008
        o=cylinder('Cross stacked split log',(x,y,z),r,.46,'oak',vertices=12);o.rotation_euler.x=math.pi/2
        o=cylinder('Visible warm end grain',(x,y,z+.237),r*.85,.012,'oak_light',vertices=14);o.rotation_euler.x=math.pi/2
        for rad in (.034,.060):tube('Endgrain arc',[(x+rad*math.cos(a),y+rad*math.sin(a),z+.246) for a in [j*math.pi/8 for j in range(17)]],.0035,'oak_edge',4)

def cooker():
    begin('range_cooker',(1.43,.082,-2.72),collision=[{'at':[0,.65,0],'size':[.67,1.30,.84]}])
    cube('Cream enamel range',(0,.64,0),(.65,1.26,.75),'porcelain',.055)
    cube('Range oak plinth',(0,.07,0),(.69,.14,.80),'oak',.03,'wood')
    cube('Cooktop warm timber rim',(0,1.25,0),(.76,.13,.86),'oak_light',.045,'wood')
    cube('Four burner black enamel hob',(0,1.325,0),(.60,.033,.63),'iron',.018,'metal')
    for x in (-.145,.145):
        for z in (-.165,.165):
            lathe('Cast iron burner',(x,1.35,z),[(0,.098),(.017,.098),(.017,.061),(0,.061)],'iron_edge',20)
            for dz in (-.071,.071):cube('Burner grate',(x,1.366,z+dz),(.21,.018,.02),'iron',.006)
    for x in (-.21,0,.21):ellipsoid('Black hob dial',(x,1.05,.415),(.10,.10,.063),'iron_edge',16,8)
    cube('Cream oven door frame',(0,.56,.406),(.56,.68,.055),'porcelain',.04)
    cube('Recessed dark oven window',(0,.52,.442),(.405,.39,.022),'iron',.025)
    cube('Dark oven door handle',(0,.87,.48),(.39,.047,.07),'iron_edge',.018)

def bookcase():
    begin('bookshelf',(-2.59,.082,-2.59),collision=[{'at':[0,1.02,0],'size':[.91,2.04,.52]}])
    cube('Bookcase oak back',(0,1.0,-.20),(.84,2.0,.06),'oak_edge',.018,'wood','Y')
    for x in (-.43,.43):cube('Thick rounded bookcase upright',(x,1.05,0),(.11,2.10,.48),'oak',.04,'wood','Y')
    for y in (.10,.65,1.24,1.93):cube('Rounded shelf',(0,y,.025),(.92,.12,.55),'oak_light',.04,'wood')
    cube('Rounded bookcase crown',(0,2.14,.015),(1.03,.14,.61),'oak_light',.05,'wood')
    for row,y in enumerate((.72,1.31)):
        x=-.32
        for i in range(4 if row==0 else 5):
            before=len(p.KITS['bookshelf']['objects']);h=[.39,.44,.36,.46,.41][(i+row)%5];w=[.10,.115,.09,.105,.12][i]
            book((x,y,.04),h,w,['sage','oak_light','terra_light','linen_green','sage_dark'][(i+row)%5])
            pivot=v((x,y,.04));m=Matrix.Translation(pivot)@Matrix.Rotation(math.radians([-5,3,-2,6,0][i]),4,'Y')@Matrix.Translation(-pivot)
            for o in p.KITS['bookshelf']['objects'][before:]:o.matrix_basis=m@o.matrix_basis
            x+=w+.031
        if row==0:
            for j in range(2):cube('Horizontal book pile',(.22,y+.043+j*.07,.04),(.23,.065,.27),'linen_green' if j==0 else 'oak_light',.012,'cloth')
    basket((0,.17,.035),.63,.36,.37)

def kitchen_details():
    reuse('sink_cabinet',(.36,.082,-2.71));scale_kit('sink_cabinet',(.75,1,1))
    begin('wall_shelf',(.39,2.33,-2.88))
    cube('Rounded kitchen pantry ledge',(0,0,.10),(1.54,.13,.42),'oak',.045,'wood')
    for x in (-.50,.51):cube('Pantry corbel',(x,-.14,.025),(.14,.27,.18),'oak_edge',.035,'wood')
    for i,x in enumerate([-.62,-.39,-.17,.06,.28,.50]):
        h=[.25,.30,.21,.26,.33,.22][i];r=[.085,.087,.074,.086,.092,.079][i]
        z=.09+[.00,.025,-.018,.01,-.01,.03][i]
        lathe('Glazed spice jar',(x,.07,z),[(0,r*.81),(.04,r),(h*.76,r),(h*.87,r*.80),(h,r*.78)],['jar_green','terra','jar_ochre','porcelain','jar_green','terra_light'][i],18)
        cylinder('Spice jar cork',(x,.09+h,z),r*.87,.052,'oak_edge',vertices=16)
    begin('hanging_cookware',(.30,1.66,-2.92))
    cube('Oak utensil rack',(0,.39,0),(.88,.085,.10),'oak',.026,'wood')
    for i,x in enumerate([-.27,.06,.31]):
        tube('Black S hook',[(x,.44,.05),(x,.48,.10),(x,.36,.16),(x,.29,.13)],.013,'iron',8)
    o=cylinder('Pan dark bowl',(-.27,.07,.16),.17,.041,'iron',vertices=28);o.rotation_euler.x=math.pi/2
    ring=lathe('Pan rolled edge',(-.27,0,0),[(0,.18),(.025,.18),(.025,.157),(0,.157)],'iron_edge',28)
    # Move the ring from a horizontal profile into the wall plane.
    pivot=v((-.27,0,0));ring.matrix_basis=Matrix.Translation(v((0,.07,.165)))@Matrix.Translation(pivot)@Matrix.Rotation(math.pi/2,4,'X')@Matrix.Translation(-pivot)@ring.matrix_basis
    tube('Pan handle',[(-.27,.19,.16),(-.27,.37,.16)],.029,'iron_edge',10)
    for x in (.06,.31):
        tube('Hanging spoon shaft',[(x,.27,.13),(x,-.08,.14)],.019,'oak')
        ellipsoid('Hanging spoon bowl',(x,-.12,.14),(.09,.13,.035),'oak_light',14,8)
    reuse('hanging_towel',(.94,1.72,-2.96))
    reuse('utensil_crock',(-.83,1.27,-2.78));scale_kit('utensil_crock',(.80,.85,.80))
    begin('counter_board',(-.73,1.27,-2.54))
    cube('Small cutting board',(0,.015,0),(.35,.028,.26),'oak_light',.038,'wood')
    cube('Cutting board handle',(-.22,.015,0),(.18,.026,.078),'oak',.018,'wood')
    pot((.08,.035,-.01),.07,.15,'terra')
    for i in range(6):
        a=i*2.40;leaf('Counter herb leaf',(.08,.13,-.01),(.08+math.cos(a)*.105,.24+random.random()*.07,math.sin(a)*.095),.065,'leaf_light' if i%2 else 'leaf')

def finishing_details():
    begin('straw_hat',(2.99,1.96,-2.79),0)
    o=lathe('Broad straw hat brim',(0,0,0),[(0,.29),(.028,.31),(.045,.27),(.05,.12)],'terra_light',40)
    o.rotation_euler.x=math.pi/2
    o=ellipsoid('Straw hat rounded crown',(0,0,.055),(.32,.32,.19),'oak_light',24,14)
    for r in (.20,.24,.28):tube('Straw hat weave ring',[(r*math.cos(a),r*math.sin(a),.038) for a in [j*math.pi/32 for j in range(65)]],.007,'oak',5)
    begin('door_garden_fork',(2.99,.083,-2.77),-4);garden_tool('fork',height=1.40)
    begin('entry_basket',(2.79,.083,-2.39));basket(width=.43,height=.34,depth=.35,handle=True)
    for i,(x,z) in enumerate([(-.13,.06),(.04,-.07),(.12,.08),(-.10,-.08)]):
        ellipsoid('Basket red apple',(x,.34,z),(.16,.165,.16),['D7683F','C95836','E39249','C9AA51'][i],16,10)
        leaf('Apple basket leaf',(x,.40,z),(x+.05,.46,z+.04),.048,'leaf')
    begin('garden_boots',(2.56,.083,-1.93),-7)
    for x,z in [(-.13,0),(.13,.045)]:
        lathe('Open green rubber boot',(x,0,z),[(0,.105),(.13,.10),(.38,.082),(.40,.091),(.40,.070),(.15,.067)],'sage_dark',20)
        ellipsoid('Rounded boot toe',(x,.09,z+.12),(.20,.17,.29),'sage_dark',18,10)
    frame('botanical_picture',(-2.96,1.90,1.73),90,width=.43,height=.61)
    frame('bookcase_picture',(-2.77,2.47,-2.73),width=.28,height=.34)
    # Window flowers use the original editable daisy geometry with a smaller
    # ceramic vessel. Greenery is swapped for the shared plant kit separately.
    reuse('window_daisies',(-2.82,1.40,.73),original='daisy_jug');scale_kit('window_daisies',(.68,.68,.68))
    k=p.KITS['window_daisies'];p.b.CURRENT=k
    for o in list(k['objects']):
        if 'jug' in o.name.lower() or 'handle' in o.name.lower():k['objects'].remove(o);bpy.data.objects.remove(o,do_unlink=True)
    lathe('White window flower pot',(0,0,0),[(0,.075),(.02,.085),(.14,.116),(.18,.121),(.19,.122),(.19,.097),(.04,.057)],'porcelain',24)
    begin('window_hanging_basket',(-2.84,2.57,-1.18))
    pot((0,0,0),.135,.22)
    for x in (-.12,.12):tube('Hanging pot rope',[(x,.17,0),(0,.55,-.01)],.009,'linen_dark',6)

def color_and_bake():
    recolor_reused()
    # Hand-painted material variation, with low-contrast endgrain and plaster.
    for mat in list(bpy.data.materials):
        if not mat.use_nodes:continue
        nt=mat.node_tree;bsdf=nt.nodes.get('Principled BSDF')
        if not bsdf:continue
        bsdf.inputs['Roughness'].default_value=.76
        if '_wood_' in mat.name:
            for node in nt.nodes:
                if node.type=='VALTORGB':
                    high=node.color_ramp.elements[-1].color
                    node.color_ramp.elements[0].color=tuple(float(c)*.92 for c in high[:3])+(1,)
        if '_plaster_' in mat.name:
            bsdf.inputs['Roughness'].default_value=.9
            if mat.name.startswith('plaster_plaster'):
                base=bsdf.inputs['Base Color'].links[0].from_socket
                geo=nt.nodes.new('ShaderNodeNewGeometry');sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(geo.outputs['Position'],sep.inputs[0])
                fade=nt.nodes.new('ShaderNodeMapRange');fade.inputs['From Min'].default_value=0;fade.inputs['From Max'].default_value=3.35;fade.inputs['To Min'].default_value=.16;fade.inputs['To Max'].default_value=.025
                nt.links.new(sep.outputs['Z'],fade.inputs['Value'])
                tint=nt.nodes.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[2].default_value=(*rgb('F5D6A4'),1)
                nt.links.new(fade.outputs['Result'],tint.inputs[0]);nt.links.new(base,tint.inputs[1]);nt.links.new(tint.outputs[0],bsdf.inputs['Base Color'])
    # A broad, low-opacity floor tint is baked; the detailed muntin shadows
    # below come from the real directional light and window aperture.
    for mat in {o.data.materials[0] for o in p.KITS['room_shell']['objects'] if 'floorboard' in o.name.lower()}:
        nt=mat.node_tree;bsdf=nt.nodes.get('Principled BSDF');base=bsdf.inputs['Base Color'].links[0].from_socket
        geo=nt.nodes.new('ShaderNodeNewGeometry');sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(geo.outputs['Position'],sep.inputs[0])
        ramp=nt.nodes.new('ShaderNodeMapRange');ramp.inputs['From Min'].default_value=-3.1;ramp.inputs['From Max'].default_value=1.6;ramp.inputs['To Min'].default_value=.18;ramp.inputs['To Max'].default_value=0
        nt.links.new(sep.outputs['X'],ramp.inputs['Value'])
        mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='SCREEN';mix.inputs[2].default_value=(*rgb('D8A24F'),1)
        nt.links.new(ramp.outputs['Result'],mix.inputs[0]);nt.links.new(base,mix.inputs[1]);nt.links.new(mix.outputs[0],bsdf.inputs['Base Color'])
        def math_node(op,a,b=0):
            n=nt.nodes.new('ShaderNodeMath');n.operation=op
            for i,value in enumerate((a,b)):
                if isinstance(value,(int,float)):n.inputs[i].default_value=value
                else:nt.links.new(value,n.inputs[i])
            return n.outputs[0]
        # A restrained authored window-light stencil requested in the review.
        # Coordinate math is the same left-window sun ray used by the preset.
        dx=math_node('ADD',sep.outputs['X'],3.1)
        ray_height=math_node('ADD',math_node('MULTIPLY',dx,4.5/7),.08)
        local_z=math_node('ADD',math_node('MULTIPLY',sep.outputs['Y'],-1),math_node('SUBTRACT',math_node('MULTIPLY',dx,.2),.2))
        horizontal=math_node('LESS_THAN',math_node('ABSOLUTE',local_z),.84)
        vertical=math_node('MULTIPLY',math_node('GREATER_THAN',ray_height,1.37),math_node('LESS_THAN',ray_height,2.91))
        open_bar_x=math_node('GREATER_THAN',math_node('ABSOLUTE',local_z),.037)
        open_bar_y=math_node('GREATER_THAN',math_node('ABSOLUTE',math_node('SUBTRACT',ray_height,2.15)),.033)
        mask=math_node('MULTIPLY',math_node('MULTIPLY',horizontal,vertical),math_node('MULTIPLY',open_bar_x,open_bar_y))
        warm=nt.nodes.new('ShaderNodeMixRGB');warm.blend_type='SCREEN';warm.inputs[2].default_value=(*rgb('EDB45B'),1)
        nt.links.new(math_node('MULTIPLY',mask,.27),warm.inputs[0]);nt.links.new(mix.outputs[0],warm.inputs[1]);nt.links.new(warm.outputs[0],bsdf.inputs['Base Color'])
    p.BAKE_SETTINGS.update(ao_distance=.88,ao_strength=.78,floor_ao_strength=.48)

def build():
    start('standard_room_5','545:2969');p.b.PALETTE.update(PALETTE)
    room_envelope();hearth();cooker();bookcase();kitchen_details();finishing_details()
    sofa((-2.57,.082,.82),90)
    p.KITS['sofa']['collision']=[{'at':[0,.55,0],'size':[2.08,1.1,.90]}]
    rug('round_rope_rug',(-1.70,.096,1.16),1.49,1.49,True)
    rug('dining_rug',(.42,.093,1.28),2.72,2.20)
    stool('reading_stool',(-2.15,.083,2.02),height=.46)
    begin('reading_cup',(-2.15,.615,2.02));cube('Reading book',(0,0,0),(.32,.067,.24),'sage',.014);mug((0,.043,0))
    stool('bookcase_stool',(-2.30,.083,-1.77),height=.57,radius=.24)
    reuse('dining_table',(.43,.082,1.23));scale_kit('dining_table',(.95,1,1))
    reuse('checked_runner',(.43,1.233,1.23),90);scale_kit('checked_runner',(1,1,.95))
    reuse('chair',(.22,.082,2.02),0);instance('chair','chair_far',(.64,.082,.44),180)
    begin('chair_cushion',(.22,.082,2.02));cube('Sage chair seat pad',(0,.719,0),(.53,.12,.48),'sage_light',.055,'cloth')
    cube('Chair lower back cross rail',(0,1.05,.245),(.51,.078,.07),'oak_light',.02,'wood')
    instance('chair_cushion','far_chair_cushion',(.64,.082,.44),180)
    begin('rug_fringe',(.42,.097,1.28))
    for s in (-1,1):
        for i in range(30):
            z=-.98+i*.067
            tube('Grouped linen rug fringe',[(s*1.33,.008,z),(s*1.40,.012,z+.007),(s*1.44,.009,z+.008)],.008,'linen',5)
    reuse('daisy_jug',(.05,1.262,1.15))
    begin('tabletop_still_life',(.54,1.262,1.23))
    lathe('Oak apple bowl',(.10,0,0),[(0,.13),(.05,.21),(.20,.27),(.24,.27),(.24,.235),(.06,.14)],'oak',28)
    for i,(x,z) in enumerate([(-.005,-.03),(.22,.05),(.10,-.14)]):
        ellipsoid('Fresh red apple',(x,.24,z),(.20,.215,.20),['D9653E','C75833','E18045'][i],18,12)
        tube('Apple stem',[(x,.33,z),(x+.02,.39,z)],.01,'oak_dark',6)
        leaf('Apple leaf',(x,.37,z),(x+.11,.40,z+.035),.04,'leaf')
    mug((.59,0,.19))
    color_and_bake()
    shared_plant('floor_monstera','monstera',(-2.72,.083,2.10),.77,35,[{'at':[0,.30,0],'size':[.64,.60,.64]}])
    shared_plant('entry_peace_lily','peace_lily',(2.92,.083,-2.13),.69,-28,[{'at':[0,.20,0],'size':[.46,.40,.46]}])
    shared_plant('window_pothos','pothos',(-2.70,1.40,-.47),.77,98)
    shared_plant('bookcase_pothos','pothos',(-2.26,2.30,-2.38),.68,-18)
    shared_plant('pantry_pothos','pothos',(1.14,2.42,-2.65),.59,9)
    shared_plant('hanging_pothos','pothos',(-2.84,2.57,-1.18),.51,102)
    p.MANIFEST_EXTRA.update(json.loads((Path(__file__).with_name('bench-r1.json')).read_text()))
    p.MANIFEST_EXTRA['review_views']=[{'name':'detail-kitchen','position':[5.4,4.2,5.1],'target':[-.60,1.72,-2.44],'size':5.6},
                                    {'name':'detail-living','position':[5.5,4.8,7.4],'target':[-1.74,.91,.90],'size':5.5}]
    lighting={'ambient':.53,'ambient_color':'C3D6D6','sun':1.25,'sun_color':'FFE0AE',
              'sun_position':[-7,4.5,1.4],'sun_target':[0,0,0],'background':'DBE5CD','background_gradient':True,
              'points':[{'position':[-1.59,.56,-1.98],'energy':1.1,'color':'FF973D','range':2.0}]}
    finalize({'position':[10,7.50,11.2],'target':[0,1.42,0],'size':12.65},lighting)
    if '--geometry-only' not in __import__('sys').argv:
        p.bake_and_export()
        export_window_card()
        stats=json.loads((p.OUT/'asset_stats.json').read_text())
        catalogue=json.loads((ROOT/'assets/rooms/_shared/plants/asset_stats.json').read_text())
        lookup={a['name']+'.glb':a for a in catalogue['assets']}
        placements=p.MANIFEST_EXTRA['shared_plants']
        used={a['file'] for a in placements}
        stats['atlas']['purpose']='base colour + strengthened contact AO + authored warm window-light stencil; not a full beauty bake'
        stats['local_scene_triangles']=stats['scene_triangles']
        stats['shared_scene_triangles']=sum(lookup[a['file']]['triangles'] for a in placements)
        stats['scene_triangles']+=stats['shared_scene_triangles']
        stats['shared_assets']=[lookup[name] for name in sorted(used)]
        stats['shared_placed_instances']=len(placements)
        stats['placed_instances']+=len(placements)
        stats['static_draw_surfaces']+=len(placements)
        stats['materials']=4
        stats['shared_atlas']='res://assets/rooms/_shared/plants/room_albedo_ao.png'
        stats['window_texture']={'file':'window_landscape.png','size':[512,512],'purpose':'Original layered landscape outside real aperture','bytes':(p.OUT/'window_landscape.png').stat().st_size}
        for item in stats['assets']:
            if item['name']=='window_garden':item['bytes']=(p.OUT/'window_garden.glb').stat().st_size
        stats['glb_bytes']=sum(a['bytes'] for a in stats['assets'])
        (p.OUT/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
        if '--views' in __import__('sys').argv:p.render_views()
