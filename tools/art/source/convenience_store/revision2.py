"""R2 readable signage, four low-poly packaging designs and stocked cold shelves."""
import math,json,random
from mathutils import Matrix
import kit as k
import series_revision as r
from kit import begin,cube,cylinder,lathe,mesh,tube
COLORS=['C64637','327C6A','E7A833','327CAE','BE637A','638945','E5A561','505CA0']
PACKAGE_STATS={}
def panel(name,vs,c):return mesh(name,vs,[tuple(range(len(vs)))],c)
def package(at,index=0,kind='bag'):
    x,y,z=at;variant=index%4;c=COLORS[(index+index//4)%8];start=len(k.CURRENT['objects']);rng=random.Random(index*29+len(kind))
    if kind=='bag':
        vs=[]
        for h,w,dep in [(0,.103,.033),(.14,.123,.087),(.29,.105,.032)]:
            vs.extend([(x-w,y+h,z-dep),(x+w,y+h,z-dep),(x+w,y+h,z+dep),(x-w,y+h,z+dep)])
        faces=[(0,3,2,1),(8,9,10,11)]+[(j*4+i,j*4+(i+1)%4,(j+1)*4+(i+1)%4,(j+1)*4+i) for j in range(2) for i in range(4)]
        mesh('Puffed creased chips bag v'+str(variant),vs,faces,c,smooth=True)
        for h in (.012,.278):panel('Crimped sealed packet edge',[(x-.105,y+h-.007,z+.034),(x+.105,y+h-.007,z+.034),(x+.105,y+h+.007,z+.034),(x-.105,y+h+.007,z+.034)],'E3BE88')
        for side in (-1,1):panel('Triangular foil fold',[(x+side*.11,y+.038,z+.052),(x+side*.083,y+.14,z+.088),(x+side*.103,y+.258,z+.049)],COLORS[(index+2)%8])
    elif kind in ('bottle','drink','wash'):
        h=.27 if kind=='drink' else .32
        lathe('Coloured shaped bottle '+kind+' v'+str(variant),at,[(0,.077),(h*.72,.079),(h*.88,.039),(h,.039)],c,5)
        cylinder('Coloured twist cap',(x,y+h+.012,z),.043,.024,['C83F33','E2BC56','367666','5772A6'][variant],vertices=5)
    elif kind=='roll':lathe('Hollow paper roll',at,[(0,.088),(.25,.088),(.25,.031),(0,.031)],'EEE6D7',6)
    elif kind=='can':
        cylinder('Colourful soda or food can',(x,y+.12,z),.083,.24,c,vertices=8)
        panel('Metal can lid',[(x-.046,y+.241,z-.037),(x+.046,y+.241,z-.037),(x+.046,y+.241,z+.037),(x-.046,y+.241,z+.037)],'A7B6B5')
        panel('Can pull tab',[(x-.013,y+.243,z-.012),(x+.013,y+.243,z-.012),(x+.013,y+.243,z+.020),(x-.013,y+.243,z+.020)],'4A6465')
    else:cube(('Soap bar' if kind=='soap' else 'Tall snack carton')+' v'+str(variant),(x,y+.13,z),(.19,.26,.135),c,0)
    dep=.089 if kind=='bag' else .081 if kind in ('bottle','drink','wash','can','roll') else .070
    accent=['F7DC91','F0B4A2','D4E5DC','E8C04B'][variant]
    def graphic(points,color):panel('Printed label pattern '+str(variant),[(x+u,y+v,z+dep+.002) for u,v in points],color)
    if variant==0:
        graphic([(math.cos(j*math.tau/8)*.057,.135+math.sin(j*math.tau/8)*.048) for j in range(8)],accent)
        graphic([(-.052,.205),(.052,.205),(.052,.218),(-.052,.218)],'435649')
    elif variant==1:
        graphic([(-.060,.077),(.059,.170),(.059,.199),(-.060,.106)],accent)
        graphic([(-.060,.110),(.059,.203),(.059,.216),(-.060,.123)],'F1DDBC')
        graphic([(-.017,.108),(.022,.108),(.022,.136),(-.017,.136)],'427658')
    elif variant==2:
        for h in (.085,.194):graphic([(-.055,h),(.055,h),(.055,h+.018),(-.055,h+.018)],accent)
        graphic([(-.032,.14),(0,.174),(.032,.14),(0,.109)],'E8B238')
        graphic([(-.006,.170),(.003,.193),(.041,.186)],'315E48')
    else:
        graphic([(-.052,.112),(-.033,.09),(.02,.09),(.050,.121),(.050,.152),(.022,.18),(-.028,.18),(-.052,.148)],accent)
        graphic([(-.022,.12),(.038,.145),(.030,.161),(-.030,.136)],'8C464B')
    tilt=math.radians(6 if index%7==2 else -4 if index%9==5 else 0)
    base=Matrix.Translation(k.v(at));change=base@Matrix.Rotation(tilt,4,'Y')@Matrix.Rotation(math.radians((index%3-1)*3),4,'Z')@base.inverted()
    count=0
    for o in k.CURRENT['objects'][start:]:
        o['atlas_constant_colour']=True;o.matrix_basis=change@o.matrix_basis;o.data.calc_loop_triangles();count+=len(o.data.loop_triangles)
    assert count<=60,(kind,variant,count)
    PACKAGE_STATS[kind+'_'+str(variant)]=count

def delete_matching(name,predicate):
    rec=k.KITS[name]
    for o in list(rec['objects']):
        if predicate(o):rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)

def icon(kind,at,size=.10):
    x,y,z=at
    if kind=='cup':
        panel('White cup icon',[(x-size*.7,y-size,z),(x+size*.7,y-size,z),(x+size,y+size,z),(x-size,y+size,z)],'EFEADD')
        tube('Cup handle',[(x+size,y+.065,z),(x+size*1.6,y+.055,z),(x+size*1.6,y-.035,z),(x+size*.8,y-.045,z)],.015,'EFEADD',5)
        tube('Cup straw',[(x,y+.08,z),(x+.045,y+.17,z)],.012,'EFEADD',5)
    else:
        tube('Shopping basket outline',[(x-size,y+size*.5,z),(x-size*.7,y-size,z),(x+size*.7,y-size,z),(x+size,y+size*.5,z),(x-size,y+size*.5,z)],.016,'EFEADD',5)
        tube('Shopping basket arch',[(x-size*.7,y+size*.5,z),(x,y+size*1.5,z),(x+size*.7,y+size*.5,z)],.014,'EFEADD',5)
        for dx in (-.03,.03):tube('Basket slat',[(x+dx,y-size*.55,z),(x+dx,y+size*.3,z)],.011,'EFEADD',4)

def signage():
    for name,title,y,size,x,kind in [('convenience_sign','CONVENIENCE',.002,.222,.10,'basket'),('drinks_header','DRINKS',-.005,.28,.08,'cup'),('snacks_wall_rack','SNACKS',1.61,.24,.12,'basket'),('essentials_wall_rack','DAILY ESSENTIALS',1.625,.185,.12,'basket')]:
        delete_matching(name,lambda o:o.name.startswith('Lettering') or 'Category icon' in o.name or any(t in o.name for t in ['Shopping basket','Basket slat','White cup icon','Cup handle','Cup straw']))
        depth=.164 if 'rack' in name else .083
        k.CURRENT=k.KITS[name];o=k.text_label(title,(x,y,depth),size,'EFEADD')
        k.bpy.context.view_layer.update()
        maxw=1.53 if name=='convenience_sign' else 1.82
        if o.dimensions.x>maxw:o.scale.x*=maxw/o.dimensions.x
        icon(kind,(-.83 if name=='convenience_sign' else -.95 if 'rack' in name else -.77,y+.08,depth+.010),.095)
def revise():
    signage()
    for name in ('back_wall','left_door_wall'):
        r.recolor(name,'E9D3C8',lambda o:any(m and m.name.startswith('E9D3C8_') for m in o.data.materials),kind='plaster')
    # Remove the previous stock and replace with tightly spaced saturated bottles.
    delete_matching('drink_cabinet',lambda o:any(t in o.name for t in ['Bottle','bottle','Coloured twist cap','label','Label','Printed','Chiller shelf','Cold cabinet light strip']))
    k.CURRENT=k.KITS['drink_cabinet']
    r.recolor('drink_cabinet','466B60',lambda o:'back' in o.name.lower())
    for row in range(5):
        y=.25+row*.355
        cube('Thin silver refrigerator shelf',(0,y,.08),(.65,.026,.46),'A5BCBB',.008)
        for col in range(4):
            start=len(k.CURRENT['objects']);at=(-.235+col*.156,y+.015,.07)
            package(at,col+row*3,'drink')
            base=Matrix.Translation(k.v(at));sz=base@Matrix.Diagonal((.90,.99,.90,1))@base.inverted()
            for o in k.CURRENT['objects'][start:]:o.matrix_basis=sz@o.matrix_basis
    begin('cold_light_strips',at=(-2.68,.065,-.72),yaw=90)
    for x in (-.285,.285):cube('Cold white internal light',(x,1.21,.21),(.015,1.89,.018),'DCEBFF',0)
    k.instance('cold_light_strips','cold_light_strips_second',(-2.68,.065,-1.48),90)
    rec=k.KITS['entry_step'];k.CURRENT=rec
    for o in rec['objects']:
        if 'mat' in o.name.lower():o.location.x*=1.58;o.scale.x*=1.58;o.scale.y*=1.30
    r.sync_instances()

def manifest(d):
    d['revision']='R2'
    d['material_overrides']['chiller_glass']={'alpha':.045}
    d['material_overrides']['cold_light_strips']={'emission':'D7E8FF','emission_energy':.45}
    for field in ('lighting','review_lighting'):
        for lamp in d[field].get('lamps',[]):
            if lamp['color']=='DAF0FF':lamp['energy']=.28
    d['bench']['scale']['chair']={'applicable':False,'reason':'No chair is present in this reference/shop.'}
    from liubei_r2 import fit_camera
    fit_camera(d,(1544,1544),[(44,934),(790,1413),(1490,991)])
    d['review_views']=[{'name':'signs-stock-detail','position':[4.0,3.3,5.2],'target':[-1.6,1.6,-1.5],'size':4.9},{'name':'groceries-detail','position':[3,3.4,4.5],'target':[.55,1.3,-.15],'size':4.8}]
