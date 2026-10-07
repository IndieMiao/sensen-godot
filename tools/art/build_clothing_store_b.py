"""SGODOT-185 pastel boutique with modular fashion displays and true apertures."""
from pathlib import Path
import sys,math
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop'))
import kit as k
from liubei_r2 import enable_lettering
enable_lettering()
import boutique as b
from kit import begin,cube,cylinder,tube,ellipsoid,lathe,leaf


def geometry():
    k.PALETTE.update({'brass':'D7AD54','oak_light':'D9B576','porcelain':'F1E5CD','leaf':'699B44','leaf_light':'91BA59'})
    b.shell();b.entrance()
    begin('left_gold_rack',at=(-2.69,.07,-1.29),yaw=90,collision=[{'at':[0,1.28,0],'size':[2.28,2.56,.53]}]);b.rack()
    begin('right_gold_rack',at=(1.61,.07,-2.39),collision=[{'at':[0,1.28,0],'size':[2.28,2.56,.53]}]);b.rack()
    for j,(name,color) in enumerate((('ivory','EADCCC'),('rose','D995A8'),('cream','E7C6AF'),('blue','91B7CC'),('mint','A9C4AF'))):
        begin('hanging_dress_'+name,at=(-2.57,2.23,-.42-j*.435),yaw=90);b.garment(color,'dress',j==0)
    for j,(name,color) in enumerate((('blue','91B7CC'),('ivory','EADCCC'),('mint','A9C4AF'))):
        begin('hanging_blouse_'+name,at=(.77+j*.55,2.23,-2.25));b.garment(color,'shirt')
    k.instance('hanging_dress_rose','right_pattern_dress',(2.41,2.23,-2.25))
    begin('scarf_rail',at=(1.61,.07,-2.29))
    tube('Lower scarf rail',[(-1.10,.88,.12),(1.10,.88,.12)],.022,'brass',8)
    for j,c in enumerate(('D995A8','91B7CC','E7C6AF','EADCCC')):
        x=-.79+j*.50
        cube('Folded hanging scarf',(x,.67,.135),(.34,.45,.039),c,.02,'cloth')
        for n in range(6):tube('Scarf fringe',[(x-.14+n*.054,.444,.145),(x-.14+n*.054,.405,.15)],.004,c,4)
    for name,c,bow in [('pink','D995A8',True),('cream','EEE1C9',True),('green','A2BEA8',False),('blue','95B9CA',False)]:
        # First placements sit on the left rack shelf; later instances reuse the same mesh.
        j=['pink','cream','green','blue'].index(name)
        begin('handbag_'+name,at=(-2.65,2.475,-.53-j*.49),yaw=90);b.handbag(c,bow)
    k.instance('handbag_pink','right_pink_bag',(.90,2.475,-2.37))
    k.instance('handbag_blue','right_blue_bag',(1.75,2.475,-2.37))
    begin('changing_room_arch',at=(-1.62,.06,-2.56))
    k.arch_trim('Pink fitting room arch',1.07,.035,2.12,.48,.115,.20,0,'D995A8')
    begin('changing_curtain',at=(-1.62,.06,-2.80));b.curtain('D79AAA',1.03,2.45)
    cylinder('Changing stool brass base',(0,.17,.23),.235,.34,'brass',vertices=28)
    cylinder('Changing stool cushion',(0,.385,.23),.25,.12,'D995A8',vertices=32)
    begin('standing_mirror',at=(-.55,.07,-2.23),collision=[{'at':[0,1.06,0],'size':[.77,2.12,.25]}]);b.mirror()
    begin('pink_round_rug',at=(-.27,.07,.25));cylinder('Soft circular rug',(0,.009,0),1.55,.018,'DEA0AF',vertices=96,kind='cloth')
    tube('Round rug ivory border',[(math.cos(j*math.tau/128)*1.51,.019,math.sin(j*math.tau/128)*1.51) for j in range(129)],.014,'porcelain',6)
    tube('Scalloped rug stitching',[(math.cos(j*math.tau/160)*(1.40+.018*math.cos(j*math.tau/10)),.021,math.sin(j*math.tau/160)*(1.40+.018*math.cos(j*math.tau/10))) for j in range(161)],.005,'D995A8',5)
    begin('round_display_island',at=(-.27,.09,.25),collision=[{'at':[0,.37,0],'size':[2.34,.74,2.34]}])
    cylinder('Island brass plinth',(0,.115,0),1.17,.23,'brass',vertices=64)
    cylinder('Lower ivory display tier',(0,.34,0),1.17,.22,'porcelain',vertices=64)
    cylinder('Upper tier brass edge',(0,.5825,0),.73,.265,'brass',vertices=56)
    cylinder('Upper ivory display',(0,.7425,0),.73,.055,'porcelain',vertices=64)
    for name,at in [('pink',(-.66,.86,.40)),('green',(.09,.86,.43)),('cream',(-.27,.86,-.10))]:k.instance('handbag_'+name,'island_bag_'+name,at)
    begin('pink_pumps',at=(-.66,.54,1.05));b.shoes('D995A8')
    begin('black_pumps',at=(.13,.54,1.06));b.shoes('56565B')
    begin('folded_ivory_knit',at=(-.25,.54,-.66));b.folded('EADCCC')
    begin('folded_blue_knit',at=(.72,.54,.22),yaw=90);b.folded('91B7CC')
    k.instance('folded_ivory_knit','stacked_knit',(-.25,.65,-.66))
    begin('island_bouquet',at=(-.27,.86,.19));k.bouquet(scale=1.02)
    begin('pink_tufted_bench',at=(-1.24,.07,2.12),collision=[{'at':[0,.29,0],'size':[1.90,.58,.56]}])
    for x in (-.78,.78):
        for z in (-.19,.19):ellipsoid('Bench brass foot',(x,.055,z),(.13,.11,.13),'brass',12,6)
    cube('Bench upholstered body',(0,.34,0),(1.91,.52,.58),'D995A8',.22,'cloth')
    for j in range(7):
        x=-.80+j*.266
        cube('Channel tuft cushion',(x,.36,0),(.247,.50,.60),'E0A4B5',.12,'cloth')
    begin('jewelry_display',at=(2.43,.07,1.13),yaw=90,collision=[{'at':[0,.48,0],'size':[2.43,.96,.68]}])
    cube('Sage jewelry cabinet',(0,.18,0),(2.43,.36,.68),'ACBFB2',.05)
    cube('Jewelry brass bottom line',(0,.37,0),(2.47,.047,.72),'brass',.025)
    cube('Display linen lining',(0,.411,0),(2.31,.035,.60),'porcelain',.02,'cloth')
    for x in (-1.18,1.18):
        for z in (-.32,.32):cube('Jewelry brass corner',(x,.67,z),(.035,.58,.035),'brass',.012)
    for z in (-.32,.32):cube('Case long top rail',(0,.95,z),(2.40,.035,.035),'brass',.012)
    for x in (-1.18,1.18):cube('Case end top rail',(x,.95,0),(.035,.035,.65),'brass',.012)
    for j in range(3):
        x=-.83+j*.78
        lathe('Necklace bust',(x,.43,-.035),[(0,.12),(.07,.14),(.17,.10),(.26,.055),(.31,.052)],'porcelain' if j!=1 else 'D7AD54',24)
        b.ring('Displayed necklace',(x,.60,.085),.098,.103,'brass',.012)
        ellipsoid('Necklace pendant',(x,.498,.092),(.045,.065,.021),'D7AD54',10,6)
        for n in range(2):
            xx=x-.09+n*.18
            cylinder('Ring display mount',(xx,.458,.20),.043,.066,'D995A8',vertices=12)
            b.ring('Jewelry ring',(xx,.515,.216),.037,.037,'brass',.007)
    begin('jewelry_glass',at=(2.43,.07,1.13),yaw=90)
    cube('Glass display lid',(0,.945,0),(2.33,.012,.61),'porcelain',0)
    for z in (-.321,.321):cube('Glass display long side',(0,.685,z),(2.33,.51,.012),'porcelain',0)
    for x in (-1.18,1.18):cube('Glass display end',(x,.685,0),(.012,.51,.62),'porcelain',0)
    begin('window_display_frame',at=(-2.85,.06,.50),yaw=90)
    for x in (-.455,.455):cube('Display window ivory stile',(x,1.59,0),(.08,2.12,.13),'porcelain',.035)
    for y in (.56,2.64):cube('Display window rail',(0,y,0),(.96,.08,.15),'porcelain',.035)
    cube('Display window base',(0,.57,.035),(.90,.09,.40),'porcelain',.03)
    cube('Blue display recess',(0,1.61,-.14),(.83,1.99,.017),'ABC9D0',.015)
    cylinder('Mannequin floor stand',(0,.665,.03),.15,.035,'brass',vertices=24)
    tube('Mannequin support',[(0,.68,.03),(0,1.48,.03)],.018,'brass',8)
    begin('display_mannequin_dress',at=(-2.71,2.28,.50),yaw=90);b.garment('E0A4B5','dress')
    # Replace the display hanger with the mannequin neck.
    for o in list(k.CURRENT['objects']):
        if 'Hanger hook' in o.name or 'Wood clothes hanger' in o.name:k.CURRENT['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
    cylinder('Dress mannequin neck',(0,-.18,0),.055,.18,'D7AD54',vertices=16)
    begin('gift_boxes',at=(-2.62,.68,.50),yaw=90)
    for x,c in ((-.25,'A9C4AF'),(.25,'D995A8')):
        cube('Window gift box',(x,.15,.02),(.28,.30,.25),c,.025)
        cube('Gift ribbon vertical',(x,.15,.149),(.036,.30,.013),'porcelain',.005)
        cube('Gift ribbon horizontal',(x,.19,.153),(.28,.035,.013),'porcelain',.005)
        for dx in (-.041,.041):ellipsoid('Gift bow',(x+dx,.335,.02),(.094,.08,.065),'porcelain',12,6)
    begin('petal_pendant',at=(-1.63,3.66,-1.94))
    tube('Pendant stem',[(0,0,0),(0,-.43,0)],.017,'brass',10)
    cylinder('Pendant gold hub',(0,-.45,0),.105,.065,'brass',vertices=24)
    for j in range(8):
        a=j*math.tau/8
        o=ellipsoid('Cream flower lampshade petal',(math.cos(a)*.15,-.60,math.sin(a)*.15),(.27,.27,.31),'FFF0C9',20,10);o.rotation_euler.z=-a
    ellipsoid('Pendant diffuser',(0,-.68,0),(.30,.18,.30),'FFF1CA',20,12)
    begin('wall_sconce',at=(-.88,2.0,-2.56));b.sconce()
    for name,at,yaw in [('sconce_left',(-2.84,1.68,2.74),90),('sconce_fitting',(-2.35,2.05,-2.56),0),('sconce_right',(2.87,1.92,-2.56),0)]:k.instance('wall_sconce',name,at,yaw)
    begin('entrance_plant',at=(-2.65,.07,2.53));k.plant(scale=1.15)
    begin('fitting_plant',at=(-2.39,.07,-2.21));k.plant(scale=1.27)
    begin('trailing_rack_plant',at=(-2.65,2.49,-.26),yaw=90);k.plant(scale=.57,trailing=True)
    k.instance('trailing_rack_plant','right_trailing_plant',(2.55,2.49,-2.29))
    begin('pink_entry_mat',at=(-2.42,.079,1.96),yaw=90);cube('Pink entry mat',(0,0,0),(1.12,.024,.62),'D995A8',.04,'cloth')
    sys.path.insert(0,str(Path(__file__).resolve().parent/'source/clothing_store_b'))
    import revision
    revision.revise()
    k.save('545:2963',{'position':[10,9.2,12],'target':[0,1.28,.05],'size':9.6})
    revision.manifest()

if __name__=='__main__':
    k.configure('clothing_store_b');args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if '--bake-only' in args:k.load()
    else:geometry()
    if '--geometry-only' not in args:k.bake_and_export(ao_strength=.45,ao_distance=.36,coherent_swatches=True)
    if '--geometry-only' not in args:
        from series_batch import build
        build('clothing_store_b')
