"""SGODOT-186 BLOCK THEORY: streetwear variant reusing the editable boutique fixture kit."""
from pathlib import Path
import sys,math,random
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent/'source/coffee_shop'))
import kit as k
import boutique as b
from kit import begin,cube,cylinder,tube,ellipsoid,lathe,leaf

BLACK='383A3D';BLUE='3458AD';WHITE='DAD9CC'

def lettering(body,at,size,color):
    curve=bpy.data.curves.new('Raised brand type '+body,'FONT');curve.body=body;curve.align_x='CENTER'
    curve.size=size;curve.offset=.003*size/.49;curve.extrude=.018*size/.49;curve.bevel_depth=.001;curve.bevel_resolution=1;curve.resolution_u=3
    o=bpy.data.objects.new('Raised brand type '+body,curve);bpy.context.scene.collection.objects.link(o)
    o.location=k.v(at);o.rotation_euler.x=math.pi/2
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH')
    k.finish(bpy.context.object,'Raised lettering '+body,color)

def globe(at,r=.10):
    x,y,z=at;b.ring('Globe emblem rim',at,r,r,'porcelain',.006)
    for rx in (r*.38,r*.73):b.ring('Globe longitude',at,rx,r,'porcelain',.004)
    for dy in (-.045,0,.045):
        reach=math.sqrt(max(.001,r*r-dy*dy))
        tube('Globe latitude',[(x-reach,y+dy,z),(x+reach,y+dy,z)],.004,'porcelain',5)

def cap():
    ellipsoid('Cap crown',(0,.105,0),(.32,.21,.31),BLACK,24,12,'cloth')
    ellipsoid('Cap brim',(0,.042,.18),(.36,.035,.24),BLACK,24,8,'cloth')
    ellipsoid('Top cap button',(0,.215,0),(.04,.017,.04),BLACK,12,6)
    for j in range(6):
        a=j*math.tau/6
        tube('Cap crown seam',[(math.cos(a)*.156*math.sin(n*math.pi/16),.105+.107*math.cos(n*math.pi/16),math.sin(a)*.15*math.sin(n*math.pi/16)) for n in range(9)],.0025,'575B60',4)
    globe((0,.132,.15),.063)

def street_plant(scale=1.1,trailing=False):
    k.plant(scale=scale,trailing=trailing)
    for o in list(k.CURRENT['objects']):
        if o.name.startswith('Terracotta pot'):k.CURRENT['objects'].remove(o);bpy.data.objects.remove(o,do_unlink=True)
    cube('Black square planter',(0,.15*scale,0),(.35*scale,.30*scale,.35*scale),BLACK,.025)

def graphic_fold(color):
    b.folded(color)
    ink=BLACK if color==WHITE else 'porcelain'
    for j in range(7):
        x=-.13+j*.039
        tube('Original folded shirt graphic',[(x,.116,-.055),(x+.059,.116,.065),(x-.015,.116,.035)],.004,ink,4)

def poster(name,at,lines,yaw=0,globe_mark=False):
    begin(name,at=at,yaw=yaw)
    cube('Black framed poster',(0,0,0),(.82,.75,.07),'171B21',.025)
    cube('Poster paper',(0,0,.041),(.75,.68,.012),'25282D',.010)
    for j,line in enumerate(lines):lettering(line,(0,.21-j*.14,.052),.115,'porcelain')
    if globe_mark:globe((0,-.16,.062),.14)

def geometry():
    k.PALETTE.update({'brass':'706656','oak':'A17D59','oak_light':'C0986F','porcelain':'E2DDCE','terra':BLACK,'leaf':'577B44','leaf_light':'799956','iron':'303237','iron_edge':'555456'})
    b.shell(True);b.entrance('iron')
    begin('street_left_rack',at=(-2.65,.07,-.66),yaw=90,collision=[{'at':[0,1.28,0],'size':[2.27,2.56,.55]}]);b.rack(2.23,'iron','59564F')
    tube('Trouser rail',[(-1.09,1.10,.055),(1.09,1.10,.055)],.022,'iron',8)
    begin('street_right_rack',at=(2.03,.07,-2.38),collision=[{'at':[0,1.28,0],'size':[1.87,2.56,.55]}]);b.rack(1.81,'iron','59564F')
    tube('Trouser rail',[(-.88,1.10,.055),(.88,1.10,.055)],.022,'iron',8)
    garments=[('gray','999A97','hoodie'),('black',BLACK,'hoodie'),('ivory',WHITE,'hoodie'),('blue',BLUE,'varsity')]
    for j,(name,color,kind) in enumerate(garments):
        begin('street_top_'+name,at=(-2.51,2.23,.23-j*.57),yaw=90);b.garment(color,kind)
        for o in k.CURRENT['objects']:o.location.x*=.84;o.scale.x*=.84
    begin('street_top_purple',at=(2.24,2.23,-2.23));b.garment('71529D','hoodie')
    for o in k.CURRENT['objects']:o.location.x*=.84;o.scale.x*=.84
    begin('street_top_varsity',at=(2.68,2.23,-2.23));b.garment(BLACK,'varsity')
    for o in k.CURRENT['objects']:o.location.x*=.84;o.scale.x*=.84
    k.instance('street_top_black','right_black_hoodie',(1.39,2.23,-2.23))
    k.instance('street_top_ivory','right_ivory_hoodie',(1.81,2.23,-2.23))
    for j,(name,color) in enumerate((('olive','71785B'),('black','454749'),('sand','B9AB91'))):
        begin('cargo_trousers_'+name,at=(-2.49,.235,.12-j*.72),yaw=90);b.trousers(color)
        for x in (-.14,.14):tube('Trouser hanger clip',[(x,.92,0),(x,.84,.03)],.010,'iron_edge',6)
        k.instance('cargo_trousers_'+name,'right_cargo_'+name,(1.40+j*.58,.235,-2.21))
    begin('dark_changing_arch',at=(-1.62,.06,-2.56));k.arch_trim('Dark changing room arch',1.07,.035,2.12,.48,.115,.20,0,'49474A')
    begin('black_changing_curtain',at=(-1.62,.06,-2.80));b.curtain('46464B',1.03,2.45)
    cylinder('Changing stool base',(0,.17,.23),.23,.34,'iron',vertices=28)
    cylinder('Changing stool cushion',(0,.385,.23),.25,.12,'58585C',vertices=32)
    begin('standing_mirror',at=(-1.77,.07,-1.68),yaw=15,collision=[{'at':[0,1.06,0],'size':[.77,2.12,.25]}]);b.mirror('706656','657580')
    begin('brand_wall_panel',at=(.18,.06,-2.57))
    cube('Blue brand field',(0,1.68,0),(2.28,2.84,.034),'214D9A',.015)
    for pts,color in [([(-1.07,.55),(-.68,.95),(-1.02,.94),(-.42,1.53),(-.68,1.03),(-.31,1.10),(-.90,.44)],'D38B38'),([(.65,1.49),(.90,2.11),(.49,1.93),(1.10,2.86),(.87,2.30),(1.09,2.47),(.91,1.62)],'7051B2')]:
        o=b.extruded('Painted angular wall stroke',pts,.012,color,0,'matte');o.location.y=-.031
    begin('block_theory_brand',at=(.13,2.10,-2.48))
    lettering('BLOCK',(0,.23,0),.49,'porcelain');lettering('THEORY',(0,-.20,0),.43,'porcelain')
    b.extruded('Original crown mark',[(-.42,.80),(-.53,1.02),(-.19,.83),(-.16,1.08),(.12,.85),(.36,.98),(.30,.78),(.55,.81),(.24,.68),(-.20,.72)],.018,'D78C31',0,'matte')
    begin('entry_graffiti',at=(-2.85,2.76,1.96),yaw=90)
    b.extruded('Entry angular mural',[(-.61,.0),(-.34,.37),(-.17,.14),(.10,.45),(.07,.16),(.55,.48),(.19,.03),(-.10,.07),(-.23,-.06),(-.36,.17)],.012,'D78C31',0,'matte')
    begin('black_checkout',at=(.01,.07,-2.05),collision=[{'at':[0,.55,0],'size':[2.40,1.10,.64]}])
    cube('Checkout dark cabinet',(0,.55,0),(2.40,1.06,.64),BLACK,.09)
    for j in range(19):cube('Checkout vertical channel',(-1.11+j*.123,.56,.329),(.014,.93,.013),'24262A',.004)
    cube('Checkout wood top',(0,1.13,0),(2.55,.12,.79),'oak_light',.07,'wood')
    cube('Checkout kickplate',(0,.055,0),(2.43,.10,.67),'555456',.044)
    cube('Tablet stand',(-.53,1.28,0),(.10,.18,.12),'747675',.02)
    screen=cube('Tablet till',(-.53,1.43,-.013),(.41,.30,.035),'BDBBB2',.023);screen.rotation_euler.x=-.15
    cube('Tablet screen',(-.53,1.43,.014),(.352,.246,.009),'6B7372',.012)
    lathe('Counter pencil cup',(.54,1.195,.0),[(0,.07),(.19,.073)],BLACK,16)
    for j in range(6):tube('Counter pencil',[(.54+math.cos(j)*.042,1.25,math.sin(j)*.042),(.54+math.cos(j)*.062,1.54+(j%2)*.08,math.sin(j)*.062)],.006,'oak_light',5)
    begin('checkout_plant',at=(.92,1.20,-2.02));street_plant(.54)
    begin('display_rug',at=(-.21,.074,.46));cube('Woven graphite display rug',(0,0,0),(3.38,.023,1.93),'55514B',.035,'cloth')
    for x in (-1.65,1.65):cube('Rug woven side stripe',(x,.014,0),(.025,.007,1.85),'868071',.004)
    for z in (-.925,.925):cube('Rug woven end stripe',(0,.014,z),(3.28,.007,.025),'868071',.004)
    begin('central_display_table',at=(-.21,.087,.44),collision=[{'at':[0,.44,0],'size':[2.92,.88,1.34]}])
    for x in (-1.38,1.38):
        for z in (-.59,.59):cube('Steel table leg',(x,.405,z),(.060,.81,.060),'iron',.015)
    for y in (.15,.81):
        for z in (-.59,.59):cube('Steel table stretcher',(0,y,z),(2.80,.055,.055),'iron',.011)
    cube('Lower wood display shelf',(0,.195,0),(2.90,.072,1.28),'oak',.025,'wood')
    cube('Upper wood display table',(0,.865,0),(2.95,.083,1.34),'oak_light',.033,'wood')
    for j,(name,color) in enumerate((('black',BLACK),('ivory',WHITE),('blue',BLUE))):
        begin('graphic_fold_'+name,at=(-1.08+j*.66,1.00,.77));graphic_fold(color)
        k.instance('graphic_fold_'+name,'lower_fold_'+name,(-1.08+j*.54,.319,.71))
        k.instance('graphic_fold_'+name,'lower_fold_stack_'+name,(-1.08+j*.54,.429,.71))
    begin('black_cap',at=(.09,1.00,.08));cap()
    k.instance('black_cap','left_rack_cap',(-2.55,2.475,-.83),90)
    k.instance('black_cap','right_rack_cap',(1.65,2.475,-2.35))
    begin('blue_sneaker_pair',at=(.86,1.00,.46),yaw=-12);b.shoes('344C78',True)
    k.instance('blue_sneaker_pair','lower_sneaker_pair',(.81,.319,.68),-8)
    begin('folded_black_trousers',at=(-.84,1.00,.03));b.folded('34363A');cube('Folded trouser pocket',(0,.125,.023),(.22,.029,.15),'34363A',.025,'cloth')
    k.instance('graphic_fold_ivory','rack_folded_knit',(2.40,2.475,-2.33))
    begin('display_storage_crate',at=(.80,.32,-.03))
    cube('Crate bottom',(0,.023,0),(.62,.046,.43),'iron',.012)
    for z in (-.21,.21):
        for y in (.07,.17,.27):cube('Open crate horizontal rail',(0,y,z),(.63,.030,.030),'iron_edge',.008)
        for x in (-.285,-.142,0,.142,.285):cube('Crate open rib',(x,.15,z),(.021,.30,.029),'iron_edge',.006)
    for x in (-.30,.30):
        for z in (-.20,-.10,0,.10,.20):cube('Crate end rib',(x,.15,z),(.029,.30,.02),'iron_edge',.006)
    begin('black_tufted_bench',at=(-.82,.07,2.13),collision=[{'at':[0,.25,0],'size':[2.29,.50,.55]}])
    for x in (-1.04,1.04):
        for z in (-.22,.22):cube('Bench steel leg',(x,.20,z),(.065,.40,.065),'iron',.012)
        cube('Bench end foot',(x,.04,0),(.065,.065,.50),'iron',.012)
    cube('Bench steel frame',(0,.35,0),(2.29,.095,.54),'iron',.026)
    for j in range(6):
        x=-.95+j*.38
        for z in (-.135,.135):cube('Bench leather tuft',(x,.44,z),(.371,.16,.265),'484B50',.065)
    poster('good_fit_poster',(-2.83,2.77,-1.27),['GOOD','FIT','BIGGER','MOVES'],90)
    poster('wear_ideas_poster',(2.17,2.82,-2.55),['WEAR','IDEAS'],0,True)
    begin('monochrome_poster',at=(-2.83,2.77,-.30),yaw=90)
    cube('Monochrome framed print',(0,0,0),(.76,.97,.07),'iron',.020)
    cube('Monochrome paper',(0,0,.043),(.67,.88,.016),'B1B2A9',.009)
    for j in range(10):
        x=-.25+(j%4)*.16;y=-.34+(j//4)*.27
        tube('Original monochrome print stroke',[(x,y,.059),(x+.10,y+.20,.059),(x-.06,y+.16,.059)],.012,'iron',6)
    begin('black_pendant',at=(-1.99,2.87,-1.84))
    lathe('Black bell shade',(0,0,0),[(0,.235),(.045,.25),(.12,.221),(.23,.135),(.28,.061),(.34,.052)],BLACK,32)
    cylinder('Warm pendant diffuser',(0,-.009,0),.218,.018,'F2DFB7',vertices=32)
    tube('Pendant black cable',[(0,.33,0),(0,.82,0)],.010,'iron',8)
    k.instance('black_pendant','black_pendant_middle',(-1.04,2.71,-1.20))
    k.instance('black_pendant','black_pendant_back',(-.44,2.92,-2.04))
    begin('street_wall_sconce',at=(-.92,2.0,-2.56));b.sconce('706656')
    for name,at,yaw in [('sconce_door',(-2.84,1.69,2.74),90),('sconce_arch',(-2.35,2.05,-2.56),0),('sconce_right',(2.89,1.89,-2.56),0)]:k.instance('street_wall_sconce',name,at,yaw)
    begin('front_square_plant',at=(2.49,.07,2.13));street_plant(1.40)
    begin('entrance_square_plant',at=(-2.62,.07,2.55));street_plant(1.18)
    begin('left_trailing_plant',at=(-2.59,2.48,.14),yaw=90);street_plant(.60,True)
    k.instance('left_trailing_plant','right_trailing_plant',(2.74,2.48,-2.29))
    begin('entry_mat',at=(-2.41,.078,1.96),yaw=90)
    cube('Graphite entrance mat',(0,0,0),(1.19,.023,.66),'474744',.024,'cloth')
    k.mesh('Entrance bolt mark',[(-.05,.013,-.24),(.12,.013,-.04),(.035,.013,-.04),(.11,.013,.23),(-.13,.013,.015),(-.04,.013,.015)],[(0,1,2,3,4,5)],'A5A59B')
    k.save('545:2959',{'position':[10,9.2,12],'target':[0,1.28,.05],'size':9.6})

if __name__=='__main__':
    k.configure('clothing_store_a');args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if '--bake-only' in args:k.load()
    else:geometry()
    if '--geometry-only' not in args:k.bake_and_export()
