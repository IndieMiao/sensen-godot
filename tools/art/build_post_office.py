"""Post Office, Figma 545:2967. Named modular postal interior."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from shop_room_parts import *
import scene_room_pipeline as p


def envelope(at=(0,0,0),width=.30,height=.20):
    x,y,z=at
    cube('Cream envelope',(x,y,z),(width,height,.018),'porcelain',.008)
    tube('Envelope folded flap',[(x-width*.47,y+height*.43,z+.015),(x,y-height*.09,z+.018),(x+width*.47,y+height*.43,z+.015)],.007,'B6523C',5)
    for i in range(4):
        for yy in (-height*.44,height*.44):cube('Airmail edge stripe',(x-width*.36+i*width*.24,y+yy,z+.014),(.027,.015,.008),'B6523C' if i%2 else '467D98',.002)


def parcel(at=(0,0,0),size=(.55,.40,.45),color='B98956'):
    x,y,z=at;w,h,d=size
    cube('Parcel carton',(x,y+h/2,z),(w,h,d),color,.035)
    cube('Parcel lid seam',(x,y+h*.77,z+d/2+.006),(w,.009,.009),'oak_edge',.002)
    for dx in (-w*.22,w*.22):cube('Parcel paper strap',(x+dx,y+h/2,z),(w*.045,h+.012,d+.015),'linen',.004)
    cube('Parcel cross strap',(x,y+h/2,z),(w+.016,h+.014,d*.04),'linen',.003)
    cube('Postal address label',(x-.06,y+h*.5,z+d/2+.018),(w*.29,h*.29,.008),'porcelain',.004)
    for j in range(3):cube('Address label line',(x-.06,y+h*.46+j*.024,z+d/2+.024),(w*.20,.006,.006),'oak_edge',.001)


def blue_door():
    p.b.CURRENT=p.KITS['window_wall']
    target=next(o for o in p.KITS['window_wall']['objects'] if 'plaster infill' in o.name)
    cut=cube('Rectangular door aperture',(-1.29,1.21,0),(1.12,2.43,.70),'plaster',0);boolean_cut(target,cut)
    begin('postal_blue_door',(-3.19,.075,1.29),90)
    cube('Blue door panel',(0,1.15,0),(1.06,2.30,.12),'366B81',.025,'wood','Y')
    for x in (-.62,.62):cube('Blue door upright',(x,1.22,.07),(.15,2.50,.18),'366B81',.034,'wood','Y')
    cube('Blue lintel',(0,2.47,.07),(1.42,.18,.19),'366B81',.035,'wood')
    cube('Lower inset door panel',(0,.49,.075),(.73,.52,.05),'315A6B',.027,'wood','Y')
    for i in range(2):
        for j in range(3):cube('Frosted door glass',(-.19+i*.38,1.03+j*.38,.08),(.30,.30,.02),'hill_back',.01)
    tube('Brass curved door handle',[(.36,.87,.11),(.36,.73,.23),(.22,.70,.23)],.028,'brass',10)
    cube('Brass mail slot',(0,.69,.13),(.37,.075,.025),'brass',.018)
    cube('Mail slot dark opening',(0,.69,.146),(.29,.025,.008),'iron',.005)


def mail_cabinet():
    begin('sorting_cabinet',(-.70,.082,-2.63),collision=[{'at':[0,1.05,0],'size':[2.03,2.1,.48]}])
    cube('Sorting cabinet back',(0,1.10,-.20),(2.02,2.2,.075),'oak_edge',.025,'wood','Y')
    for x in (-1.02,1.02):cube('Sorting cabinet stile',(x,1.10,0),(.12,2.23,.52),'oak',.025,'wood','Y')
    cube('Cabinet oak crown',(0,2.24,0),(2.21,.15,.61),'oak_light',.04,'wood')
    for j in range(4):cube('Mail cubby shelf',(0,.91+j*.39,0),(1.99,.055,.50),'oak_light',.015,'wood')
    for x in (-.49,0,.49):cube('Vertical cubby separator',(x,1.50,0),(.056,1.16,.48),'oak',.01,'wood','Y')
    for x in (-.51,.51):
        cube('Sorting bottom drawer',(x,.42,.06),(.92,.76,.42),'oak',.025,'wood','Y')
        cube('Drawer brass label frame',(x,.60,.293),(.29,.12,.025),'brass',.014)
        cube('Drawer label',(x,.60,.31),(.23,.067,.012),'linen',.003)
    begin('mail_stack',(-1.46,1.075,-2.50))
    for j in range(6):cube('Individual sorted letter',(0,j*.023,0),(.35,.015,.29),'porcelain',.002)
    for row in range(3):
        for col in range(4):
            if row==0 and col==0:continue
            instance('mail_stack','mail_stack_'+str(row)+'_'+str(col),(-1.46+col*.50,1.075+row*.39,-2.50))


def mailbox():
    begin('red_post_box',(2.75,.082,-1.37),collision=[{'at':[0,.88,0],'size':[.74,1.76,.74]}])
    cylinder('Post box dark foot',(0,.18,0),.39,.36,'iron',vertices=32)
    body=cylinder('Red pillar box',(0,.97,0),.33,1.34,'B7342F',vertices=40)
    cut=cube('True letter opening',(0,1.29,.31),(.40,.13,.28),'iron',0);boolean_cut(body,cut)
    cube('Letter slot black backing',(0,1.29,.18),(.43,.15,.03),'iron',.012)
    for y in (.38,1.56):lathe('Raised pillar box ring',(0,y,0),[(0,.35),(.045,.35),(.045,.32),(0,.32)],'CF4438',40)
    ellipsoid('Domed post box cap',(0,1.68,0),(.78,.20,.78),'C63B32',32,16)
    cube('White postal emblem panel',(0,.97,.334),(.35,.27,.019),'linen',.007)
    tube('Post box envelope emblem',[(-.16,1.08,.35),(0,.95,.35),(.16,1.08,.35)],.012,'B7342F',6)


def wall_map():
    begin('world_map',(1.07,2.68,-2.85))
    cube('World map paper',(0,0,0),(1.46,1.02,.025),'linen',.007)
    for x in (-.77,.77):cube('Map frame side',(x,0,0),(.075,1.12,.08),'oak',.021,'wood','Y')
    for y in (-.54,.54):cube('Map frame top',(0,y,0),(1.59,.075,.08),'oak_light',.021,'wood')
    # Original simplified silhouettes; decorative atlas, not navigation data.
    continents=[ [(-.65,.30),(-.40,.39),(-.22,.22),(-.31,.12),(-.44,.06),(-.49,-.08),(-.55,.06)],
                 [(-.42,-.08),(-.26,-.15),(-.25,-.31),(-.39,-.46),(-.45,-.21)],
                 [(-.05,.24),(.09,.34),(.26,.30),(.33,.42),(.66,.27),(.56,.12),(.36,.11),(.28,-.04),(.14,.15)],
                 [(-.06,.09),(.15,.09),(.23,-.06),(.11,-.34),(.02,-.24),(-.11,-.04)],
                 [(.45,-.27),(.62,-.25),(.68,-.38),(.50,-.43)],
                 [(-.30,.40),(-.22,.46),(-.17,.39),(-.23,.30)] ]
    for points in continents:
        o=mesh('Decorative continent silhouette',[(x,y,.025) for x,y in points],[tuple(range(len(points)))],'558B9D')
        o.modifiers.new('Printed silhouette thickness','SOLIDIFY').thickness=.004
    begin('wall_clock',(-.59,3.09,-2.86))
    o=cylinder('Clock oak rim',(0,0,0),.39,.09,'oak',vertices=40);o.rotation_euler.x=math.pi/2
    o=cylinder('Clock cream dial',(0,0,.058),.337,.012,'linen',vertices=40);o.rotation_euler.x=math.pi/2
    for i in range(12):
        a=i*math.pi/6;tube('Clock hour mark',[(math.sin(a)*.28,math.cos(a)*.28,.074),(math.sin(a)*.31,math.cos(a)*.31,.074)],.010,'iron',6)
    tube('Clock hour hand',[(0,0,.08),(-.11,.09,.08)],.013,'iron',6)
    tube('Clock minute hand',[(0,0,.09),(0,.25,.09)],.009,'iron',6)


def build():
    start('post_office','545:2967')
    p.b.PALETTE.update({'oak':'A76739','oak_light':'C58750','oak_edge':'87522F','floor':'B67E47','floor_light':'C48E58','floor_shade':'AD6E3C'})
    shell(6.6,6,3.7,open_left=False,open_back=False)
    blue_door();mail_cabinet();mailbox();wall_map()
    sign('post_office_sign','POST OFFICE',(-3.14,2.96,-1.65),2.17,.65,90,'A72E2B','linen')
    counter('postal_counter',(-.58,.082,-.54),3.64,.78,1.18,'366B81')
    begin('counter_computer',(-1.49,1.40,-.52));register()
    begin('counter_bell',(-.65,1.40,-.42))
    lathe('Brass service bell',(0,0,0),[(0,.15),(.03,.16),(.09,.13),(.19,.075),(.20,.02)],'brass',24)
    cylinder('Bell button',(0,.23,0),.034,.06,'brass',vertices=12)
    begin('counter_stamps',(.07,1.42,-.45))
    cube('Stamp storage stand',(0,.03,0),(.45,.07,.22),'oak_dark',.02)
    for x in (-.15,0,.15):
        cylinder('Stamp black base',(x,.10,0),.058,.06,'iron',vertices=16)
        cylinder('Red stamp handle',(x,.23,0),.042,.15,'B7342F',vertices=16)
    begin('counter_mail_tray',(.74,1.43,-.49));crate(width=.51,height=.19,depth=.40)
    for j in range(5):envelope((0,.23,.12-j*.055),.35,.27)
    shelf('parcel_shelves',(2.09,.27,-2.58),1.18,2.27,.57,4)
    begin('brown_parcel',(1.86,1.10,-2.51));parcel(size=(.48,.40,.40))
    instance('brown_parcel','parcel_above',(2.28,1.86,-2.51))
    instance('brown_parcel','parcel_top',(1.82,2.62,-2.51))
    begin('blue_parcel',(2.28,1.10,-2.51));parcel(size=(.40,.39,.40),color='366B81')
    instance('blue_parcel','blue_parcel_cabinet_top',(-.32,2.41,-2.64))
    begin('mail_sacks',(2.09,.34,-2.52))
    for x in (-.26,.26):
        ellipsoid('Tied canvas mailbag',(x,.34,0),(.43,.67,.41),'linen',20,14)
        lathe('Gathered mailbag neck',(x,.58,0),[(0,.10),(.12,.06),(.18,.08)],'linen',16)
        envelope((x,.31,.203),.21,.16)
    worktable('packing_table',(.31,.082,1.64),2.65,1.28,.94)
    begin('packing_mat',(.31,1.113,1.64));cube('Green cutting mat',(0,0,0),(2.38,.024,1.03),'sage_dark',.018)
    begin('packing_parcel',(-.27,1.14,1.48));parcel(size=(.68,.49,.57))
    begin('postal_scale',(1.12,1.15,1.65))
    cube('Postal scale cream base',(0,.11,0),(.48,.20,.40),'porcelain',.04)
    cube('Scale digital screen',(0,.16,.215),(.22,.10,.016),'366B81',.008)
    cylinder('Scale platform stem',(0,.27,0),.065,.18,'iron_edge',vertices=16)
    cube('Scale weighing pan',(0,.38,0),(.56,.07,.46),'iron_edge',.035)
    begin('packing_supplies',(.36,1.14,1.69))
    pot((0,0,0),.10,.21,'oak')
    for i in range(5):tube('Packing pencil',[(0,.04,0),((i-2)*.024,.38,0)],.010,'iron',6)
    lathe('Twine roll',(-.28,0,0),[(0,.10),(.22,.10),(.22,.042),(.03,.042)],'terra_light',20)
    for j in range(9):lathe('Twine thread',(-.28,.012+j*.023,0),[(0,.106),(.008,.106),(.008,.101),(0,.101)],'oak_light',20)
    begin('desk_airmail',(.65,1.165,1.98))
    for j in range(5):
        cube('Paper letter stack',(0,j*.022,0),(.37,.015,.26),'linen',.002)
    begin('underdesk_boxes',(.32,.34,1.65))
    for x,col in [(-.80,'366B81'),(0,'B7342F'),(.8,'B98956')]:
        crate((x,0,0),.64,.45,.88)
        parcel((x,.02,0),(.49,.34,.54),col)
    stool('packing_stool',(-1.71,.082,2.19),height=.53)
    rug('entry_rug',(-2.71,.094,1.32),.75,1.13)
    rug('packing_rug',(.34,.094,2.69),2.4,.53)
    reuse('floor_plant',(-2.86,.083,2.43))
    reuse('counter_plant',(-2.13,1.44,-.68),original='shelf_plant')
    reuse('cabinet_plant',(-1.32,2.42,-2.61),original='shelf_plant')
    reuse('parcel_shelf_plant',(2.38,2.64,-2.60),original='shelf_plant')
    frame('door_notice',(-3.16,1.76,.19),90,width=.39,height=.55)
    lantern('door_light',(-3.05,2.94,1.28),90)
    finalize({'position':[10,8.9,11.3],'target':[0,1.5,0],'size':11.3});complete()


if __name__=='__main__':build()
