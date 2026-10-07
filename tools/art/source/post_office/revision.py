"""SGODOT-176: mahogany postal room; P0 waystation visual placeholder only."""
from pathlib import Path
import sys,math,json,random
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from zhaoyun_review import *
from shop_room_parts import *
from build_post_office import parcel
from mathutils import Matrix
PALETTE=dict(r2.PALETTE,oak='9B5031',oak_light='B56C42',oak_edge='773E2B',oak_end='A45B38',oak_dark='703D2B',floor='B4734D',floor_light='BE8058',floor_shade='AC6D47',joint='885036',plaster='F2D2B0',plaster_light='F4DEBE',linen='EBDCC0')

def _mail_source(at=(0,0,0),variant=0,width=.30,height=.20):
    x,y,z=at;color=['F4ECD8','D5E4E2','EFDFC5','F1E8D4'][variant%4]
    cube('Folded postal envelope '+str(variant),at,(width,height,.015),color,.005)
    tube('Envelope triangular paper fold',[(x-width*.45,y+height*.43,z+.01),(x,y-height*.10,z+.012),(x+width*.45,y+height*.43,z+.01)],.0035,'B89679',5)
    for j in range(3):cube('Handwritten envelope address',(x-width*.07,y-height*.06-j*.027,z+.012),(width*(.37-.05*j),.007,.004),'816851',.001)
    cube('Coloured postage stamp',(x+width*.31,y+height*.24,z+.014),(width*.15,height*.24,.004),['AF453D','477894','699268','A77B42'][variant%4],.002)
    if variant%2==0:
        for i in range(4):
            for sign in (-1,1):cube('Red blue airmail dash',(x-width*.34+i*width*.23,y+sign*height*.43,z+.012),(.023,.012,.004),'B44D40' if i%2 else '477B99',.001)

def _package_source(at,variant=0):
    sizes=[(.49,.32,.40),(.37,.43,.32),(.63,.25,.43),(.43,.34,.35)]
    parcel(at,sizes[variant%4],['BA956C','D0AE84','8A999E','C3B7A6'][variant%4])
    x,y,z=at;w,h,d=sizes[variant%4]
    cube('Variant parcel postage mark',(x+w*.24,y+h*.61,z+d/2+.025),(.075,.07,.007),['A25342','426C8A','5E765C','B38447'][variant%4],.006)
    if variant%4==1:
        for dx in (-.08,.08):tube('Parcel this-way-up arrow',[(x+dx,y+h*.43,z+d/2+.034),(x+dx,y+h*.72,z+d/2+.034),(x+dx-.025,y+h*.64,z+d/2+.034)],.006,'oak_dark',5)
    elif variant%4==2:
        cube('Wide blue parcel label stripe',(x,y+h*.29,z+d/2+.036),(w*.78,.038,.009),'315F80',.003)
    elif variant%4==3:
        seal=cylinder('Red circular parcel seal',(x+w*.22,y+h*.31,z+d/2+.036),.052,.009,'A64135',vertices=16);seal.rotation_euler.x=math.pi/2
    for sign in (-1,1):tube('Knotted parcel twine loop',[(x,y+h+.015,z),(x+sign*.08,y+h+.05,z+.035),(x+sign*.11,y+h+.03,z-.025),(x,y+h+.015,z)],.006,'linen',6)

SOURCE_PROTOTYPES={}
def linked_details(kind,key,at,builder,scale=(1,1,1)):
    current=p.b.CURRENT;cache_key=(kind,key)
    if cache_key not in SOURCE_PROTOTYPES:
        name=kind+'_prototype_'+str(key);begin(name,(0,0,0));builder()
        kit=p.KITS.pop(name);kit['collection'].name='PROTOTYPE_'+name
        for obj in kit['objects']:obj.hide_render=True
        SOURCE_PROTOTYPES[cache_key]=kit
    p.b.CURRENT=current
    transform=Matrix.Translation(v(at))@Matrix.Diagonal(Vector((scale[0],scale[2],scale[1],1)))
    for source in SOURCE_PROTOTYPES[cache_key]['objects']:
        obj=source.copy();obj.data=source.data;current['collection'].objects.link(obj)
        obj.parent=current['root'];obj.matrix_basis=transform@source.matrix_basis;obj.hide_render=False
        obj['linked_prototype']=kind+'_'+str(key);current['objects'].append(obj)

def mail(at=(0,0,0),variant=0,width=.30,height=.20):
    linked_details('envelope',variant%4,at,lambda:_mail_source((0,0,0),variant%4),[width/.30,height/.20,1])

def package(at,variant=0):
    linked_details('parcel',variant%4,at,lambda:_package_source((0,0,0),variant%4))

def prepare_left_door():
    # A real west-wall aperture, leaf with a hinge pivot and separate frame.
    k=p.KITS['postal_blue_door'];frames=[o for o in k['objects'] if any(t in o.name.lower() for t in ('door upright','lintel'))]
    begin('postal_door_frame',(-3.19,.075,1.29),90);new=p.KITS['postal_door_frame']
    for o in frames:
        k['objects'].remove(o)
        for c in list(o.users_collection):c.objects.unlink(o)
        new['collection'].objects.link(o);o.parent=new['root'];new['objects'].append(o)
    for o in k['objects']:o.location.x+=.53
    r2.move_kit('postal_blue_door',(-3.19,.075,1.82),90)
    begin('postal_door_glass',(-3.19,.075,1.82),90);glass=p.KITS['postal_door_glass']
    for obj in list(k['objects']):
        if 'frosted door glass' not in obj.name.lower():continue
        k['objects'].remove(obj)
        for c in list(obj.users_collection):c.objects.unlink(obj)
        glass['collection'].objects.link(obj);obj.parent=glass['root'];glass['objects'].append(obj)
    p.MANIFEST_EXTRA['door']={'module':'postal_blue_door','companions':['postal_door_glass'],'closed_yaw_degrees':90,'open_yaw_degrees':0}
    p.KITS['room_shell']['collision']=[{'at':[0,-.07,0],'size':[6.9,.30,6.3]},
      {'at':[-3.3,1.85,-1.155],'size':[.22,3.7,3.69]}, {'at':[-3.3,1.85,2.445],'size':[.22,3.7,1.11]},
      {'at':[-3.3,3.08,1.29],'size':[.22,1.24,1.2]}, {'at':[0,1.85,-3],'size':[6.8,3.7,.22]},
      {'at':[3.40,.75,0],'size':[.10,1.5,6.3]}, {'at':[0,.75,3.10],'size':[6.9,1.5,.10]},
      {'at':[-3.68,-.07,1.29],'size':[.94,.30,1.2]}, {'at':[-3.72,.7,.66],'size':[.95,1.4,.08]},
      {'at':[-3.72,.7,1.92],'size':[.95,1.4,.08]}, {'at':[-4.17,.7,1.29],'size':[.08,1.4,1.3]}]

def build():
    draft_scene('post_office');p.b.PALETTE.update(PALETTE);p.b.MATS.clear();prepare_left_door()
    for obj in p.KITS['window_wall']['objects']:
        if 'plaster infill' in obj.name.lower():obj.data.materials.clear();obj.data.materials.append(material('F2C6B2','plaster'))
    r2.remove_named('room_shell',['floorboard']);p.b.CURRENT=p.KITS['room_shell']
    for row in range(30):
        z=-3+(row+.5)*.2;x=-3.3;i=0
        while x<3.29:
            length=min(.76 if row%2 and i==0 else 1.49,3.3-x)
            cube('Narrow mahogany floorboard',(x+length/2,.05,z),(length-.010,.065,.195),['floor','floor_light','floor','floor_shade'][(row+i)%4],.01,'wood');x+=length;i+=1
    drop_modules('post_office_sign','counter_computer','mail_stack','brown_parcel','blue_parcel','mail_sacks','floor_plant','counter_plant','cabinet_plant','parcel_shelf_plant','door_light','entry_rug','packing_rug','door_notice','desk_airmail')
    # Main counter carries a real monitor and keyboard, with no till housing.
    begin('counter_computer',(-1.49,1.397,-.52))
    cube('Computer monitor foot',(0,.025,0),(.36,.05,.28),'iron',.022)
    cube('Monitor upright support',(0,.22,-.055),(.09,.39,.08),'iron_edge',.014)
    cube('Thin computer screen casing',(0,.43,-.09),(.65,.43,.062),'303634',.028)
    cube('Computer flat display',(0,.43,-.054),(.585,.36,.012),'29414A',.016)
    cube('Computer keyboard',(0,.025,.22),(.53,.035,.17),'iron_edge',.012)
    for j in range(3):
        for i in range(10):cube('Keyboard key',(-.23+i*.051,.045,.165+j*.048),(.040,.012,.032),'iron',.003)
    # Wall plaque has an arched upper envelope crest and no hanging hooks.
    begin('post_office_sign',(-3.14,2.78,-1.64),90)
    outline=[(-1.16,-.32),(1.16,-.32),(1.16,.25),(.66,.25)]
    outline += [(.64*math.cos(a),.23+.43*math.sin(a)) for a in [j*math.pi/20 for j in range(21)]]
    outline += [(-1.16,.25)]
    n=len(outline);verts=[(x,y,z) for z in (-.025,.06) for x,y in outline];faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    obj=mesh('Arched deep red postal wall sign',verts,faces,'A63830');mod=obj.modifiers.new('Soft sign edge','BEVEL');mod.width=.022;mod.segments=3
    bold_lettering('POST OFFICE',(0,-.16,.092),2.12,'linen')
    cube('White envelope emblem',(0,.35,.090),(.39,.255,.014),'linen',.006)
    tube('Postal plaque envelope fold',[(-.18,.45,.102),(0,.29,.102),(.18,.45,.102)],.009,'A63830',6)
    # Each mail slot holds individual varied envelopes, tilted and offset.
    begin('sorted_letters',(0,0,0));rng=random.Random(176)
    for row in range(3):
        for col in range(4):
            for j in range(4+(row+col)%3):
                x=-1.46+col*.50+rng.uniform(-.025,.025);y=1.01+row*.39+j*.023;z=-2.43+rng.uniform(-.025,.015)
                before=len(p.KITS['sorted_letters']['objects']);mail((0,0,0),(row+col+j)%4,.28+.025*((col+j)%3),.21)
                mat=Matrix.Translation(v((x,y,z)))@Matrix.Rotation(math.pi/2,4,'X')@Matrix.Rotation(rng.uniform(-.08,.08),4,'Z')
                for o in p.KITS['sorted_letters']['objects'][before:]:o.matrix_basis=mat@o.matrix_basis
    p.b.CURRENT=p.KITS['sorting_cabinet']
    for x in (-.51,.51):tube('Drawer brass pull',[(x-.115,.39,.29),(x-.10,.36,.36),(x+.10,.36,.36),(x+.115,.39,.29)],.018,'brass',8)
    p.KITS['parcel_shelves']['collision']=[{'at':[0,1.12,0],'size':[1.28,2.38,.67]}]
    begin('parcel_shelf_stock',(0,0,0))
    for row in range(3):
        y=1.06+row*.75
        for col in range(2):package((1.78+col*.55,y,-2.51+.03*(row%2)),(row*2+col)%4)
    package((-.53,2.41,-2.62),2);package((-1.19,2.41,-2.62),0)
    begin('mail_sacks',(2.10,.082,-2.12),collision=[{'at':[0,.45,0],'size':[1.0,.9,.54]}])
    for x in (-.26,.26):
        ellipsoid('Standing linen mailbag',(x,.37,0),(.44,.74,.43),'linen',18,12)
        lathe('Tied gathered mailbag neck',(x,.69,0),[(0,.09),(.07,.055),(.13,.072)],'linen',16)
        tube('Mailbag neck tie',[(x-.06,.75,0),(x+.07,.75,0),(x+.11,.68,.04)],.009,'oak_dark',6)
        for i in range(5):cube('Red blue mailbag stripe',(x-.16+i*.08,.18,.212),(.052,.065,.015),'B64B3D' if i%2 else '406D86',.004)
        mail((x,.40,.224),0,.23,.17)
    r2.scale_kit('mail_sacks',(1,1.20,1));r2.move_kit('red_post_box',(2.98,.082,0))
    drop_modules('counter_bell');begin('counter_bell',(-.65,1.397,-.42))
    lathe('Service bell black foot',(0,0,0),[(0,.17),(.035,.17),(.04,.145)],'iron',24)
    lathe('Rounded brass service bell',(0,.035,0),[(0,.155),(.025,.158),(.075,.143),(.125,.116),(.165,.079),(.183,.038),(.185,.012)],'brass',32)
    cylinder('Brass bell button',(0,.258,0),.033,.065,'brass',vertices=16)
    # Counter documents: front-facing, visibly folded, varied stamps.
    begin('counter_document_stand',(.16,1.397,-.68))
    cube('Sloped form stand',(0,.13,0),(.34,.25,.09),'oak',.018,'wood')
    mail((0,.15,.06),1,.28,.22)
    p.b.CURRENT=p.KITS['counter_stamps']
    for j,o in enumerate([o for o in p.KITS['counter_stamps']['objects'] if 'red stamp handle' in o.name.lower()]):
        if j==1:o.data.materials.clear();o.data.materials.append(material('iron'))
    # Clear readable notices, wall lamp and magazine rack beside the blue door.
    for i,(z,y) in enumerate([(.39,1.85),(-.14,2.15)]):
        frame('door_notice_'+str(i),(-3.14,y,z),90,width=.34,height=.49)
        r2.remove_named('door_notice_'+str(i),['botanical']);p.b.CURRENT=p.KITS['door_notice_'+str(i)]
        cube('Notice steel clip',(0,.265,.063),(.12,.055,.025),'brass',.008)
        for j in range(5):cube('Notice written line',(0,.13-j*.055,.052),(.24-.022*(j%3),.012,.006),'467188',.001)
    begin('magazine_rack',(-2.82,.082,.05),90,[{'at':[0,.46,0],'size':[.65,.92,.40]}])
    cube('Magazine rack back',(0,.45,-.10),(.63,.90,.10),'oak',.025,'wood')
    for row in range(3):
        yy=.16+row*.25
        cube('Magazine ledge',(0,yy,.02),(.65,.065,.34),'oak_light',.018,'wood')
        for col in range(3):
            mail((-.20+col*.20,yy+.14,.13),row+col,.18,.24)
    begin('brass_wall_lamp',(-3.12,2.92,1.36),90)
    cylinder('Lamp brass backplate',(0,.10,0),.10,.07,'brass',vertices=20).rotation_euler.x=math.pi/2
    tube('Curved polished brass arm',[(0,.10,.02),(0,.25,.16),(0,.24,.31),(0,.04,.37)],.032,'brass',12)
    lathe('Brass lamp shade',(0,-.10,.37),[(0,.18),(.04,.18),(.22,.06)],'brass',24)
    begin('door_lamp_glow',(-3.12,2.79,1.36),90);ellipsoid('Warm brass lamp diffuser',(0,0,.37),(.24,.18,.24),'FFE4AB',20,12)
    begin('blue_entry_mat',(-2.83,.092,1.29),90)
    cube('Blue woven door mat',(0,.01,0),(1.27,.035,.82),'365E79',.025,'cloth')
    for x in (-.38,.38):cube('Door mat cream end stripe',(x,.035,0),(.13,.009,.76),'linen',.005,'cloth')
    r2.move_kit('packing_stool',(-2.12,.082,2.31))
    begin('packing_documents',(.52,1.142,1.89))
    for j in range(7):
        before=len(p.KITS['packing_documents']['objects']);mail((0,0,0),j%4,.32,.23)
        mat=Matrix.Translation(v((.08,j*.021,.04)))@Matrix.Rotation(math.pi/2,4,'X')
        for o in p.KITS['packing_documents']['objects'][before:]:o.matrix_basis=mat@o.matrix_basis
    r2.mug((-.32,0,-.30),'linen')
    package((-.76,0,-.14),1)
    begin('corner_letter_crate',(2.68,.082,2.45),collision=[{'at':[0,.26,0],'size':[.65,.52,.50]}]);crate(width=.63,height=.39,depth=.46)
    for j in range(6):mail((-.12+.04*(j%3),.42,-.14+j*.052),j%4,.36,.28)
    begin('front_floor_runner',(.26,.094,2.74))
    cube('Dark green woven front runner',(0,.015,0),(2.33,.038,.46),'526849',.022,'cloth')
    for x in (-.94,.94):cube('Runner warm binding',(x,.039,0),(.09,.008,.43),'terra_light',.004,'cloth')
    for name,asset,at,sc,yaw,collide in [
       ('door_floor_greenery','peace_lily',(-2.95,.083,2.59),.94,35,True),
       ('counter_trailing','pothos',(-2.13,1.40,-.62),1.05,0,False),
       ('cabinet_greenery','peace_lily',(.12,2.405,-2.65),.54,0,False),
       ('shelf_trailing','pothos',(2.43,2.64,-2.53),1.37,0,False),
       ('corner_floor_greenery','peace_lily',(3.05,.083,1.91),.76,40,True),
       ('door_hanging_pothos','pothos',(-3.0,2.65,.37),1.10,90,False)]:
        r2.shared_plant(name,asset,at,sc,yaw,[{'at':[0,.2,0],'size':[.45,.4,.45]}] if collide else None)
    # Open, coloured storage faces are not hidden inside full-height crates.
    drop_modules('underdesk_boxes');begin('underdesk_boxes',(.32,.30,1.65))
    for i,(x,col) in enumerate([(-.80,'315B78'),(0,'AA3D35'),(.8,'B8956D')]):
        cube('Coloured postal storage bin',(x,.23,0),(.62,.46,.73),col,.025)
        cube('Storage box lid',(x,.475,0),(.66,.05,.77),col,.022)
        cube('Storage address label',(x,.25,.377),(.23,.14,.014),'linen',.006)
        for j in range(3):cube('Storage label handwriting',(x,.27-j*.035,.389),(.15-j*.02,.01,.005),'oak_dark',.001)
    # Source originals remain named; runtime dressing is grouped by use/zone.
    merge_modules('counter_dressing',['counter_stamps','counter_mail_tray','counter_document_stand'])
    merge_modules('wall_dressing',['door_notice_0','door_notice_1','brass_wall_lamp'])
    merge_modules('packing_dressing',['packing_mat','packing_parcel','postal_scale','packing_supplies','packing_documents','underdesk_boxes'])
    p.MANIFEST_EXTRA['review_views']=[{'name':'detail-counter','position':[6,4.5,6],'target':[-.55,1.60,-1.45],'size':5.4},{'name':'detail-mail','position':[6,4.2,6],'target':[1.35,1.24,.75],'size':5.0},{'name':'detail-door','position':[4,3.3,6],'target':[-2.7,1.5,.95],'size':4.3}]
    light={'ambient':.53,'ambient_color':'FFE8D0','sun':1.12,'sun_color':'FFE9C7','sun_position':[-6,7,2],'sun_target':[0,0,0],'shadow_bias':.065,'shadow_normal_bias':.7,'shadow_distance':25,'background':'D6E5E1','background_gradient':True,'points':[{'position':[-2.72,2.78,1.36],'energy':.72,'color':'FFE1A2','range':2.5}]}
    finish(json.loads(Path(__file__).with_name('camera-review.json').read_text())['camera'],light,json.loads(Path(__file__).with_name('bench-review.json').read_text()),materials={'door_lamp_glow':'glow','postal_door_glass':'window_glass','counter_bell':'metal'},no_shadow=[],botanical=[])

if __name__=='__main__':build()
