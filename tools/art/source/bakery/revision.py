"""SGODOT-175: apricot plaster bakery, stocked curved display and brick oven."""
from pathlib import Path
import sys,math,json,random
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from zhaoyun_review import *
from shop_room_parts import *
from build_bakery import bread as initial_bread
from mathutils import Matrix

PALETTE=dict(r2.PALETTE,oak='AB663C',oak_light='C5804D',oak_edge='93542F',oak_end='A46137',floor='B57449',floor_light='BE7D50',floor_shade='B17248',joint='955D38',plaster='F4D6B6',plaster_light='F3DABB',linen='EEDCC0',terra='BB7245')

def wall_lamp(name,at,yaw=0):
    begin(name,at,yaw)
    cylinder('Dark wall mounting disc',(0,.10,0),.095,.055,'iron',vertices=16).rotation_euler.x=math.pi/2
    tube('Black curved lamp bracket',[(0,.10,.02),(0,.22,.14),(0,.19,.28),(0,.02,.35)],.022,'iron',10)
    lathe('Black flared light shade',(0,-.12,.35),[(0,.15),(.03,.16),(.10,.10),(.15,.045)],'iron',20)
    begin(name+'_glow',at,yaw);ellipsoid('Warm wall lamp globe',(0,-.17,.35),(.18,.18,.18),'FFCE75',16,10)

def bread(at=(0,0,0),kind='loaf'):
    if kind not in ('loaf','baguette'):
        return initial_bread(at,kind)
    x,y,z=at;baguette=kind=='baguette'
    crust='D6A061' if baguette else 'D09B5A';crumb='DDB478'
    size=(.19,.19,.62) if baguette else (.34,.22,.28)
    body=ellipsoid('Baguette with recessed scores' if baguette else 'Loaf with recessed scores',(x,y+.105,z),size,crust,22,12)
    inside=material(crumb);body.data.materials.append(inside)
    for j in range(5 if baguette else 3):
        if baguette:
            zz=-.22+j*.11;top=.105+.095*math.sqrt(max(0,1-(zz/.31)**2))
            cutter=ellipsoid('Shallow diagonal baguette scoring cutter',(x,y+top+.003,z+zz),(.16,.032,.028),crumb,12,8)
            cutter.rotation_euler.z=math.radians(-23)
        else:
            dx=(j-1)*.075;top=.105+.11*math.sqrt(max(0,1-(dx/.17)**2))
            cutter=ellipsoid('Shallow loaf scoring cutter',(x+dx,y+top+.006,z),(.033,.040,.17),crumb,12,8)
            cutter.rotation_euler.z=math.radians(9)
        cutter.data.materials.clear();cutter.data.materials.append(material(crust));cutter.data.materials.append(inside)
        for face in cutter.data.polygons:face.material_index=1
        boolean_cut(body,cutter)
    body['bread_score']='Boolean recessed crumb, warm crust-relative tint; no separate white bars'

def pastry_geometry(kind):
    if kind==1:return bread(kind='croissant')
    if kind==2:return bread(kind='loaf')
    if kind==10:return bread(kind='baguette')
    if kind in (0,4):
        cylinder('Vanilla or chocolate cake',(0,.10,0),.16,.20,'F0D5AC' if kind==0 else '754B36',vertices=24)
        cylinder('Cream or dark ganache top',(0,.215,0),.166,.055,'FFF1DF' if kind==0 else '71462F',vertices=24)
        cylinder('Cake strawberry cream band',(0,.115,0),.162,.044,'EE9DA8' if kind==0 else 'AE7866',vertices=24)
        for j in range(4):
            a=j*math.tau/4;ellipsoid('Cake berry topping',(.085*math.cos(a),.285,.085*math.sin(a)),(.068,.081,.068),'D8465D' if kind==0 else '97415A',12,8)
    elif kind in (3,5):
        lathe('Fluted golden tart',(0,0,0),[(0,.10),(.04,.14),(.075,.15),(.09,.13)],'D9AD6C',20)
        cylinder('Pink strawberry or lemon tart filling',(0,.080,0),.125,.025,'ED8DAA' if kind==3 else 'F3D450',vertices=24)
        for j in range(4):
            a=j*math.tau/4
            ellipsoid('Strawberry or lemon garnish',(.072*math.cos(a),.135,.072*math.sin(a)),(.06,.072,.06),'D84961' if kind==3 else 'FBE36E',12,8)
        ellipsoid('Soft cream tart centre',(0,.127,0),(.073,.055,.073),'FFF0DE',14,8)
    elif kind==6:
        outline=[(-.14,-.13),(.14,-.13),(.04,.17)]
        for bottom,top,color in [(0,.075,'F6DEB6'),(.075,.116,'EE9BB5'),(.116,.190,'FFF2E2'),(.190,.22,'F5C4D2')]:
            verts=[(x,y,z) for y in (bottom,top) for x,z in outline]
            mesh('White pink layer cake slice',verts,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],color)
        ellipsoid('Cake slice cream rosette',(0,.255,-.03),(.10,.065,.09),'FFF2E2',14,8)
        ellipsoid('Cake slice strawberry',(0,.298,-.02),(.063,.07,.06),'D44B61',12,8)
    else:
        color={7:'EB98BA',8:'9EBA84',9:'EACD65'}[kind]
        ellipsoid('Macaron lower shell',(0,.058,0),(.26,.11,.245),color,20,10)
        cylinder('Macaron cream filling',(0,.105,0),.114,.035,'FFF0DC',vertices=24)
        ellipsoid('Macaron upper shell',(0,.154,0),(.26,.11,.245),color,20,10)

def pastries():
    # Deliberate layer composition, never a repeated modulo pattern.
    sequences=[[1,2,10,1,2,1,10,2],[7,3,8,9,5,7,8,3],[6,5,0,3,6,4,5,0]]
    names=['cream strawberry cake','croissant','scored loaf','pink strawberry tart','chocolate berry cake','lemon tart','white pink cake slice','pink macaron','green macaron','yellow macaron','scored baguette']
    for kind in range(11):
        begin('pastry_'+str(kind),(0,0,0));pastry_geometry(kind)
        r2.scale_kit('pastry_'+str(kind),(.76,.76,.76))
    rng=random.Random(17521);placements=[]
    for row,sequence in enumerate(sequences):
        for i,kind in enumerate(sequence):
            at=(1.20+[0,.25,.48,.72,.96,1.20,1.44,1.70][i]+rng.uniform(-.020,.020),.965+row*.37,.92-row*.15+rng.uniform(-.035,.035))
            angle=rng.uniform(-20,20);size=rng.uniform(.94,1.05)
            instance('pastry_'+str(kind),'display_pastry_'+str(row)+'_'+str(i),at,angle,size)
            placements.append({'layer':row+1,'kind':names[kind],'position':list(at),'yaw_degrees':angle,'scale':size})
    p.MANIFEST_EXTRA['pastry_display']={'layers_bottom_to_top':[[names[i] for i in row] for row in sequences],'placed_count':len(placements),'prototype_count':11,'placements':placements}

def chair(at):
    begin('cafe_chair',at,collision=[{'at':[0,.64,0],'size':[.59,1.28,.60]}])
    cylinder('Round curved cafe chair seat',(0,.625,0),.285,.10,'oak',vertices=28)
    cylinder('Green round cafe cushion',(0,.695,0),.254,.07,'sage',vertices=28)
    for x in (-.20,.20):
        for z in (-.20,.20):tube('Bent cafe chair leg',[(x*1.12,0,z*1.12),(x,.63,z)],.042,'oak',10)
    tube('Single arched bentwood back',[(.27*math.cos(a),.70+.68*math.sin(a),.24) for a in [j*math.pi/24 for j in range(25)]],.042,'oak_light',10)
    for x in (-.13,0,.13):tube('Curving chair back spindle',[(x,.69,.24),(x,.97,.28),(x,1.26-.10*abs(x)/.13,.24)],.022,'oak',8)

def build():
    draft_scene('bakery',lambda module:setattr(module,'bread',bread));p.b.PALETTE.update(PALETTE);p.b.MATS.clear()
    for name in ('window_wall','back_wall'):r2.remove_named(name,['upright oak timber','timber joint cap','post foot','beam peg'])
    for name in ('window_wall','back_wall'):
        for o in p.KITS[name]['objects']:
            if 'heavy top beam' in o.name.lower():o.data.materials.clear();o.data.materials.append(material('A85E35','wood'))
    for o in p.KITS['window_wall']['objects']:
        if 'plaster infill' in o.name.lower():o.data.materials.clear();o.data.materials.append(material('F3CFB6','plaster'))
    # Narrower reddish boards, removing the draft's wide warm-wood slabs.
    r2.remove_named('room_shell',['floorboard']);p.b.CURRENT=p.KITS['room_shell']
    for row in range(31):
        z=-3.2+(row+.5)*6.4/31;x=-3.6;j=0
        while x<3.59:
            length=min(.82 if row%2 and j==0 else 1.58,3.6-x)
            cube('Narrow staggered reddish bakery floor',(x+length/2,.05,z),(length-.009,.065,6.4/31-.005),['floor','floor_light','floor','floor_shade'][(row+j)%4],.01,'wood');x+=length;j+=1
    open_front_bounds(7.2,6.4,3.65,.65,1.18)
    drop_modules('bakery_sign','left_wall_light','right_wall_light','pantry_plant','floor_plant','display_plant','chair','pastry_trays','fire')
    # Enlarge the domed oven while retaining the real mouth/storage apertures.
    r2.scale_kit('brick_oven',(1.12,.91,1.08));r2.move_kit('brick_oven',(-2.28,.082,-2.20))
    for o in p.KITS['brick_oven']['objects']:
        if 'dome' in o.name.lower():o.data.materials.clear();o.data.materials.append(material('F2D3A7','plaster'))
    r2.fire();r2.move_kit('fire',(-2.28,1.09,-1.79));r2.scale_kit('fire',(1.30,1.06,1));r2.export_fire()
    r2.move_kit('baking_loaves',(-2.28,1.10,-1.82))
    move_zone(['pastry_display','display_frame','display_glass'],[.27,0,.10])
    p.KITS['pastry_display']['collision']=[{'at':[0,.95,0],'size':[2.20,1.90,1.16]}]
    begin('display_shelves',(2.06,.92,.81))
    for row in range(3):cube('Full pastry tray shelf',(0,row*.37,-row*.15),(2.04,.042,.76-row*.08),'oak_light',.018,'wood')
    pastries()
    r2.move_kit('checkout_counter',(3.0,.082,-.74));r2.move_kit('register',(3.0,1.245,-.74))
    # Separate preparation zone from display by >.8m.
    r2.move_kit('baking_workbench',(-.99,.082,-.22));r2.scale_kit('baking_workbench',(.91,1,1))
    move_zone(['workbench_baking_props','flour_storage'],[-.33,-.083,-.25])
    begin('bakers_scale',(-.39,1.117,-.48))
    cube('Vintage scale dark base',(0,.055,0),(.32,.11,.29),'iron',.035)
    body=cylinder('Round mechanical scale dial',(0,.25,.10),.137,.085,'iron_edge',vertices=24);body.rotation_euler.x=math.pi/2
    dial=cylinder('Cream scale face',(0,.25,.149),.114,.012,'linen',vertices=24);dial.rotation_euler.x=math.pi/2
    tube('Scale needle',[(0,.25,.16),(.049,.319,.16)],.008,'iron',5)
    cube('Scale platform stem',(0,.36,-.05),(.09,.30,.09),'iron_edge',.015)
    cube('Scale weighing tray',(0,.50,-.05),(.34,.045,.28),'iron_edge',.025)
    begin('workbench_cloth',(-.92,1.13,-.22))
    r2.metric_cloth('Baker folded red checked towel',[(-.2,0),(.44,0),(.54,-.08),(.55,-.56)],.17,.48,.09)
    # Larger stocked rack, staggered buns rather than a perfect grid.
    r2.move_kit('bakery_rack',(-2.94,.082,-.29));r2.scale_kit('bakery_rack',(1.07,1,1.1))
    p.b.CURRENT=p.KITS['bakery_rack']
    for j in range(5):bread((.04,.28+j*.32,.22 if j%2 else -.16),'croissant' if j%2 else 'baguette')
    # Twelve original jars plus 12 varied jars in front of the open wall shelf.
    begin('extra_jars',(-3.18,.79,1.49),90)
    for row in range(4):
        for i in range(3):bottle((i*.28,row*.51,.14),['jar_ochre','terra','porcelain'][(i+row)%3],.19+.035*((i+row)%3))
    begin('back_bread_basket',(.72,1.26,-2.48));basket(width=.55,height=.28,depth=.35)
    for i in range(4):
        before=len(p.KITS['back_bread_basket']['objects']);bread((0,0,0),'baguette')
        transform=Matrix.Translation(v((-.18+i*.12,.52,0)))@Matrix.Rotation(math.pi/2,4,'X')
        for o in p.KITS['back_bread_basket']['objects'][before:]:o.matrix_basis=transform@o.matrix_basis
    drop_modules('baguette_basket');begin('baguette_basket',(.30,2.51,-2.74));basket(width=.38,height=.25,depth=.30)
    for i in range(3):
        before=len(p.KITS['baguette_basket']['objects']);bread(kind='baguette')
        transform=Matrix.Translation(v((-.10+i*.10,.42,0)))@Matrix.Rotation(math.pi/2,4,'X')
        for obj in p.KITS['baguette_basket']['objects'][before:]:obj.matrix_basis=transform@obj.matrix_basis
    r2.remove_named('bread_motto',['sign hanging hook','sign good bread']);p.b.CURRENT=p.KITS['bread_motto']
    for i,line in enumerate(('Good','Bread','Brighter','Days')):bold_lettering(line,(0,.30-i*.19,.112),.36 if i!=2 else .42,'linen')
    # Wall-mounted curved cream sign with red wood edge and wheat decoration.
    begin('bakery_sign',(1.02,3.14,-3.045))
    outline=[(-1.04,-.34),(-1.17,-.25),(-1.17,.15),(-1.06,.26),(-.56,.34),(0,.37),(.56,.34),(1.06,.26),(1.17,.15),(1.17,-.25),(1.04,-.34)]
    verts=[(x,y,z) for z in (-.025,.06) for x,y in outline];n=len(outline)
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh('Curved red-brown bakery wall plaque',verts,faces,'oak')
    mesh('Cream plaque inset',[(x*.93,y*.88,.066) for x,y in outline],[tuple(reversed(range(n)))],'linen')
    bold_lettering('BAKERY',(0,-.07,.098),2.05,'oak_dark')
    for sign in (-1,1):
        tube('Painted wheat stem',[(0,-.24,.088),(sign*.29,-.19,.088)],.007,'oak_dark',6)
        for i in range(4):leaf('Wheat ear print',(sign*(.05+i*.06),-.23+i*.01,.09),(sign*(.09+i*.06),-.15+i*.01,.09),.025,'oak_dark')
    wall_lamp('left_wall_light',(-3.42,2.73,2.02),90);wall_lamp('right_wall_light',(2.26,2.86,-3.035))
    begin('green_pendant',(-.92,4.25,.35));tube('Long pendant cord',[(0,0,0),(0,-1.32,0)],.014,'iron',8)
    lathe('Green enamel pendant',(0,-1.59,0),[(0,.32),(.04,.33),(.16,.25),(.34,.10)],'sage_dark',28)
    begin('pendant_glow',(-.92,2.65,.35));ellipsoid('Pendant warm bulb',(0,0,0),(.22,.16,.22),'FFD990',16,10)
    frame('wheat_wall_print',(-3.45,1.98,2.63),90,width=.48,height=.72)
    r2.remove_named('wheat_wall_print',['botanical']);p.b.CURRENT=p.KITS['wheat_wall_print']
    tube('Wheat art stem',[(0,-.27,.035),(0,.27,.035)],.01,'terra',6)
    for j in range(5):
        for sign in (-1,1):leaf('Wheat print ear',(0,-.14+j*.07,.04),(sign*.09,-.06+j*.07,.04),.05,'terra_light')
    # Real curved cafe chairs retain the Basic Room seated height family.
    chair((-2.40,.082,2.22));p.KITS['cafe_chair']['root'].rotation_euler.z=math.radians(-90);p.KITS['cafe_chair']['yaw']=-90
    instance('cafe_chair','cafe_chair_opposite',(-.84,.082,2.22),90)
    r2.scale_kit('cafe_flowers',(.68,.68,.68))
    r2.scale_kit('cafe_table',(1,1.12,1));move_zone(['cafe_flowers','cafe_cup'],[0,.055,0])
    r2.remove_named('cafe_cup',['']);p.b.CURRENT=p.KITS['cafe_cup'];r2.mug()
    for name,asset,at,sc,yaw,collide in [
       ('left_olive','olive_tree',(-3.12,.083,2.61),.68,10,True),('left_back_olive','olive_tree',(-3.14,.083,1.94),.55,100,True),
       ('front_peace_lily','peace_lily',(3.23,.083,-1.86),1.10,-15,True),
       ('window_left_pothos','pothos',(-.98,1.40,-2.91),.68,0,False),('window_right_pothos','pothos',(2.41,1.40,-2.91),.74,0,False),
       ('shelf_pothos','pothos',(1.19,2.51,-2.74),.93,0,False)]:
        r2.shared_plant(name,asset,at,sc,yaw,[{'at':[0,.25,0],'size':[.51,.5,.51]}] if collide else None)
    merge_modules('back_counter_dressing',['utensil_crock','pantry_jars','baguette_basket','back_bread_basket','register'])
    merge_modules('prep_dressing',['workbench_baking_props','flour_storage','bakers_scale','workbench_cloth'])
    merge_modules('wall_and_cafe_dressing',['extra_jars','jar_collection','cafe_flowers','cafe_cup','wheat_wall_print'])
    merge_modules('wall_lamps',['left_wall_light','right_wall_light','green_pendant'])
    merge_modules('warm_lamps_glow',['left_wall_light_glow','right_wall_light_glow','pendant_glow'])
    # Batch all placed pastries by display zone, but keep linked named source
    # meshes and the five local-pivot prototypes in an explicit source library.
    begin('stocked_pastries',(0,0,0));dest=p.KITS['stocked_pastries'];bpy.context.view_layer.update()
    for name in ['pastry_'+str(i) for i in range(11)]:
        kit=p.KITS[name]
        kit['collection'].name='PROTOTYPE_'+name
        for o in kit['collection'].objects:o.hide_render=True
        del p.KITS[name]
    for root in [o for o in bpy.context.scene.objects if o.type=='EMPTY' and str(o.get('linked_asset','')).startswith('pastry_')]:
        for obj in list(root.children):
            world=obj.matrix_world.copy()
            for c in list(obj.users_collection):c.objects.unlink(obj)
            dest['collection'].objects.link(obj);obj.parent=dest['root'];obj.matrix_world=world;dest['objects'].append(obj)
        bpy.data.objects.remove(root,do_unlink=True)
    p.INSTANCES[:]=[i for i in p.INSTANCES if not i['asset'].startswith('pastry_')]
    p.MANIFEST_EXTRA['review_views']=[{'name':'detail-oven','position':[4,4,5],'target':[-2.0,1.55,-1.75],'size':5.0},{'name':'detail-pastries','position':[6,3.8,6],'target':[1.6,1.30,.55],'size':4.5}]
    light={'ambient':.48,'ambient_color':'FFE5C6','sun':1.22,'sun_color':'FFE3B6','sun_position':[-4,7,3],'sun_target':[0,0,0],'shadow_bias':.08,'shadow_normal_bias':.7,'shadow_distance':25,'background':'C4DFE5','background_gradient':True,'points':[{'position':[-2.25,1.52,-1.40],'energy':1.30,'color':'FF9137','range':3.0},{'position':[-.92,2.60,.35],'energy':.6,'color':'FFD391','range':2.3},{'position':[-3.05,2.55,2.02],'energy':.55,'color':'FFD68D','range':1.8},{'position':[2.26,2.66,-2.7],'energy':.55,'color':'FFD68D','range':1.8}]}
    finish(json.loads(Path(__file__).with_name('camera-review.json').read_text())['camera'],light,json.loads(Path(__file__).with_name('bench-review.json').read_text()),materials={'display_glass':'glass','fire':'fire','warm_lamps_glow':'glow'},no_shadow=['wall_and_cafe_dressing'],botanical=['wall_and_cafe_dressing'],post_export=r2.export_fire)

if __name__=='__main__':build()
