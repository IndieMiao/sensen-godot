"""SGODOT-182 Orchard Market: reusable fruit crates, shutters, awning and balance scale."""
from pathlib import Path
import sys,math,random
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop'))
import kit as k
import storefront as s
from kit import begin,cube,cylinder,tube,ellipsoid,lathe,leaf

def geometry():
    k.PALETTE.update({'oak':'B28555','oak_light':'CFA56D','porcelain':'EFE4CF','plaster':'E8D1AF','leaf':'637F43','leaf_light':'8BA153'})
    s.shell(wall='E8D7B7',accent='C58E67',floor='D3AC77',wood=True,door_center=.40)
    # Terracotta top courses, matching the reference instead of the shared cream caps.
    for name in ('back_wall','left_door_wall','front_wall_left','front_wall_right','side_low_wall','corner_pier'):
        for o in k.KITS[name]['objects']:
            if any(w in o.name.lower() for w in ('coping','cap','top lintel')):
                o.data.materials.clear();o.data.materials.append(k.material('CC9875','plaster'))
    begin('wood_display_hutch',at=(.34,.06,-2.42),collision=[{'at':[0,1.25,0],'size':[3.85,2.50,.50]}])
    cube('Recessed shop wood back',(0,1.36,0),(3.85,2.5,.14),'oak_dark',.018,'wood','Y')
    for j in range(18):cube('Backboard plank',(-1.81+j*.213,1.36,.085),(.2,2.46,.018),'oak',.005,'wood','Y')
    for x in (-1.94,-.68,.68,1.94):cube('Hutch upright',(x,1.44,.28),(.087,2.30,.48),'oak_light',.022,'wood','Y')
    cube('Market full sill',(0,.70,.28),(3.95,.075,.64),'oak_light',.022,'wood')
    for y in (1.27,1.84):cube('Market left display shelf',(-.65,y,.28),(2.64,.075,.64),'oak_light',.022,'wood')
    k.CURRENT=k.KITS['wood_display_hutch']
    cube('Scale display shelf',(1.315,1.27,.28),(1.29,.075,.64),'oak_light',.022,'wood')
    begin('striped_awning',at=(.34,2.91,-2.42));s.awning(4.24,.92)
    begin('blue_shutter',at=(-1.82,1.70,-2.11))
    cube('Shutter inset',(0,0,0),(.54,1.22,.07),'6C8D9C',.022)
    for y in (-.60,.60):cube('Shutter rail',(0,y,.05),(.58,.055,.08),'6B8796',.013)
    for x in (-.265,.265):cube('Shutter stile',(x,0,.05),(.05,1.22,.08),'6B8796',.012)
    for j in range(9):
        o=cube('Angled louver',(0,-.49+j*.12,.072),(.47,.095,.040),'7D9BA8',.008);o.rotation_euler.x=.20
    for y in (-.4,.4):cube('Black iron shutter hinge',(.24,y,.12),(.13,.035,.030),'iron',.007)
    k.instance('blue_shutter','blue_shutter_2',(.79,1.70,-2.11))
    k.instance('blue_shutter','blue_shutter_3',(2.54,1.70,-2.11))
    begin('produce_display_table',at=(.18,.06,-1.27),collision=[{'at':[0,.49,0],'size':[4.80,.98,.83]}])
    for x in (-2.24,2.24):
        for z in (-.32,.32):cube('Heavy trestle leg',(x,.47,z),(.14,.94,.14),'oak',.026,'wood','Y')
    cube('Fruit table top',(0,.94,0),(4.95,.12,.91),'oak_light',.035,'wood')
    for j in range(4):cube('Market table front board',(0,.26+j*.17,.34),(4.72,.145,.07),'oak',.017,'wood')
    fruits=['orange','lemon','fig','peach','grape']
    for i,kind in enumerate(fruits):
        begin('crate_'+kind,at=(-1.73+i*.95,1.08,-1.27));s.crate()
        for j in range(9):s.fruit(kind,(-.25+(j%3)*.25,.15,-.19+(j//3)*.18),1.05)
    k.instance('crate_orange','floor_orange_crate',(-1.36,.064,1.10))
    k.instance('crate_fig','floor_fig_crate',(1.35,.064,1.54))
    k.instance('crate_orange','shelf_orange_crate',(-.32,1.94,-2.17))
    k.instance('crate_lemon','shelf_lemon_crate',(-.32,1.37,-2.17))
    begin('analog_scale',at=(1.84,1.37,-2.00))
    cube('Scale heavy base',(0,.035,0),(.37,.07,.31),'stone',.045)
    o=cylinder('Round scale housing',(0,.25,0),.18,.14,'stone',vertices=32);o.rotation_euler.x=math.pi/2
    o=cylinder('Cream scale dial',(0,.25,.078),.151,.014,'porcelain',vertices=32);o.rotation_euler.x=math.pi/2
    for i in range(12):
        a=i*math.tau/12
        tube('Scale tick',[(math.sin(a)*.123,.25+math.cos(a)*.123,.09),(math.sin(a)*.142,.25+math.cos(a)*.142,.09)],.003,'iron',4)
    tube('Red scale pointer',[(0,.25,.098),(.054,.359,.098)],.009,'C56A51',6)
    lathe('Scale weighing bowl',(0,.43,0),[(0,.07),(.04,.12),(.13,.24),(.14,.24),(.12,.219),(.046,.105)],'stone',32)
    begin('striped_table_towel',at=(-1.36,1.15,-1.12))
    cube('Cotton towel over table',(0,0,0),(.38,.018,.64),'porcelain',.005,'cloth')
    cube('Cotton towel drop',(0,-.24,.325),(.38,.48,.016),'porcelain',.006,'cloth')
    for x in (-.11,-.07,.07,.11):
        cube('Blue towel stripe',(x,.012,0),(.018,.005,.64),'7E98A4',.002)
        cube('Blue towel drop stripe',(x,-.24,.335),(.018,.48,.005),'7E98A4',.002)
    k.instance('striped_table_towel','striped_table_towel_2',(1.99,1.15,-1.12))
    begin('olive_planter',at=(-2.41,.07,1.13),collision=[{'at':[0,.39,0],'size':[.61,.78,.61]}])
    lathe('Terracotta olive jar',(0,0,0),[(0,.24),(.12,.31),(.38,.32),(.54,.23),(.58,.27),(.61,.27),(.61,.22),(.55,.20)],'C39363',24)
    cylinder('Planter soil',(0,.565,0),.20,.017,'soil',vertices=20)
    for j in range(22):
        a=j*2.399;end=(math.cos(a)*.40,1.03+(j%5)*.12,math.sin(a)*.38)
        tube('Olive woody branch',[(0,.55,0),(0,.80,0),end],.016,'oak_edge',6)
        for n in range(2,6):
            p=(end[0]*n/5,.78+(end[1]-.78)*n/5,end[2]*n/5)
            for sign in (-1,1):
                b=a+sign*1.15
                leaf('Olive blade',p,(p[0]+math.cos(b)*.17,p[1]+.12,p[2]+math.sin(b)*.17),.074,'leaf' if n%2 else 'leaf_light')
    k.instance('olive_planter','olive_planter_2',(2.52,.07,-1.92))
    begin('flower_border',at=(-2.1,.79,2.68));s.flower_border(1.65)
    k.instance('flower_border','flower_border_2',(2.16,.79,2.68))
    for j,z in enumerate((-.95,.72,2.25)):k.instance('flower_border','flower_border_side_'+str(j),(3,.79,z),90)
    begin('doorway_vine',at=(-2.78,2.95,-1.40),yaw=90)
    for dx in (0,.20):k.vine([(dx+math.sin(j*.4)*.08,-j*.095,.08) for j in range(27)])
    s.menu('orchard_market_sign',(-2.82,1.57,1.75),'ORCHARD',['MARKET'],1.10,.95,'porcelain','leaf_dark')
    r=k.KITS['orchard_market_sign'];r['root'].rotation_euler.z=math.pi/2;r['yaw']=90
    begin('hanging_herbs',at=(2.71,2.23,-2.57))
    for j in range(11):
        a=j*2.399;x=math.cos(a)*.12
        tube('Dried herb stem',[(0,.14,0),(x,-.37,.05)],.006,'oak_dark',5)
        for i in range(3):leaf('Hanging herb leaf',(x*.7,-.08-i*.07,.04),(x+.07,-.14-i*.07,.08),.036,'leaf_dark')
    k.save('545:2957',{'position':[10,9.2,12],'target':[0,1.10,.05],'size':9.5})

if __name__=='__main__':
    k.configure('fruit_shop');args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if '--bake-only' in args:k.load()
    else:geometry()
    if '--geometry-only' not in args:k.bake_and_export()
