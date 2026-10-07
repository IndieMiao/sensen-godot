"""SGODOT-186 R2: hung cargo silhouette, four print families, registered review."""
import math,json
import kit as k
import boutique as b
import series_revision as r
from kit import begin,cube,tube,ellipsoid

def solid(o):
    o['atlas_constant_colour']=True
    return o

def cargo(color):
    # Two separated tapered cloth legs, folded over a thin clipped hanger.
    for side in (-1,1):
        pts=[(side*x,y) for x,y in [(.035,.69),(.035,.52),(.064,.06),(.228,.06),(.245,.18),(.220,.58),(.194,.76),(.055,.76)]]
        b.extruded('Separate tapered cargo leg',pts,.13,color,.020)
        cuff=cube('Stitched folded trouser cuff',(side*.148,.083,.009),(.175,.070,.157),color,.014,'cloth')
        cube('Cargo bellows pocket',(side*.176,.39,.086),(.134,.173,.040),color,.017,'cloth')
        cube('Cargo pocket flap',(side*.176,.475,.111),(.143,.047,.025),color,.010,'cloth')
        solid(tube('Cargo stitched pocket edge',[(side*.225,.464,.128),(side*.225,.32,.112),(side*.121,.32,.112)],.0025,'555B49' if color=='71785B' else '77746A',4))
        solid(tube('Cargo leg fabric crease',[(side*.10,.59,.070),(side*.126,.30,.073),(side*.108,.13,.073)],.003,color,4))
        solid(tube('Cargo cuff seam',[(side*.065,.093,.091),(side*.225,.093,.091)],.0025,'746F61',4))
    # Short return flap on the rear shows the drape over the rail without filling the leg gap.
    b.extruded('Folded waistband return',[(-.19,.78),(-.205,.58),(-.12,.55),(0,.60),(.12,.55),(.205,.58),(.19,.78)],.052,color,.014).location.y=.076
    cube('Folded waistband over hanger',(0,.772,0),(.408,.070,.153),color,.021,'cloth')
    solid(tube('Visible metal trouser hanger',[(-.225,.805,0),(.225,.805,0),(.05,.89,0),(0,.89,0),(0,.945,0),(.031,.97,0),(.061,.949,0)],.007,'6C727A',6))
    for x in (-.16,.16):cube('Trouser hanger clamp',(x,.795,.094),(.027,.071,.021),'A8A49A',.005)

def graphic(style,ink,flat=False):
    created=len(k.CURRENT['objects'])
    if style==0:
        k.text_label('BT',(0,-.55,.110),.16,ink)
        tube('Print bold underline',[(-.115,-.585,.112),(.115,-.585,.112)],.009,ink,5)
        k.text_label('42',(0,-.675,.110),.095,ink)
    elif style==1:
        b.ring('Print orbital globe',(0,-.545,.11),.092,.092,ink,.005)
        for rx in (.038,.068):b.ring('Print globe longitude',(0,-.545,.11),rx,.092,ink,.003)
        for dy in (-.04,0,.04):tube('Print globe latitude',[(-.08,-.545+dy,.111),(.08,-.545+dy,.111)],.003,ink,4)
        tube('Print orbit',[(-.13,-.59,.112),(-.04,-.57,.112),(.065,-.515,.112),(.13,-.49,.112)],.005,'D48948',5)
    elif style==2:
        o=b.extruded('Print mountain silhouette',[(-.12,-.64),(-.03,-.49),(.013,-.56),(.062,-.51),(.13,-.64)],.004,ink,0,'matte');o.location.y=-.11
        b.ring('Print rising moon',(.068,-.462,.11),.032,.032,'D29E52',.008)
        tube('Print mountain horizon',[(-.13,-.67,.111),(.13,-.67,.111)],.004,ink,4)
    else:
        paths=[[(-.12,-.59),(-.085,-.47),(-.02,-.62),(.065,-.49)], [(-.10,-.65),(.01,-.47),(-.01,-.68),(.13,-.52)], [(-.13,-.56),(.13,-.58)], [(-.10,-.68),(.09,-.63)]]
        for j,p in enumerate(paths):tube('Print hand-drawn graffiti',[(x,y,.112+j*.0005) for x,y in p],.006,ink if j%2==0 else '9D78B5',5)
    for o in k.CURRENT['objects'][created:]:
        solid(o)
        if flat:
            # Transform all local front X/Y/Z into horizontal X/Z/-Y around print centre.
            from mathutils import Matrix,Vector
            k.bpy.context.view_layer.update()
            M=Matrix(((1,0,0,0),(0,0,1,.545),(0,-.15,0,.100),(0,0,0,1)))
            o.matrix_basis=M @ o.matrix_basis

def remove_old_prints():
    for rec in k.KITS.values():
        for o in list(rec['objects']):
            if any(s in o.name for s in ('Original shirt stroke','Original tee screenprint','Original folded shirt graphic')):
                rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)

def revise():
    for name,color in [('olive','71785B'),('black','454749'),('sand','B9AB91')]:r.clear('cargo_trousers_'+name);cargo(color)
    remove_old_prints()
    for name,style,ink in [('street_top_gray',3,'30353E'),('street_top_black',1,'DDDACE'),('street_top_ivory',2,'373C48'),('street_top_purple',0,'E5DBCE'),('printed_tee_black',3,'E2DED6'),('printed_tee_white',0,'323B46')]:
        k.CURRENT=k.KITS[name];graphic(style,ink)
    for name,style,ink in [('graphic_fold_black',0,'E4DED2'),('graphic_fold_ivory',1,'38414B'),('graphic_fold_blue',2,'E5DECF')]:
        k.CURRENT=k.KITS[name];graphic(style,ink,True)
    # Fourth family replaces one existing lower stack; total placements unchanged.
    p=next(p for p in k.INSTANCES if p['name']=='lower_fold_stack_black')
    at=p['position'];root=k.bpy.data.objects[p['name']]
    for o in list(root.children):k.bpy.data.objects.remove(o,do_unlink=True)
    k.bpy.data.objects.remove(root,do_unlink=True);k.INSTANCES.remove(p)
    begin('graphic_fold_graffiti',at=at);b.folded('756B80');graphic(3,'E5D9D1',True)
    for p in k.INSTANCES:
        if p['name']=='lower_fold_blue':p['asset']='graphic_fold_graffiti'
        if p['name']=='rack_folded_knit':p['asset']='graphic_fold_black'
    rec=k.KITS['boutique_floor'];colors=['918B83','99918A','89847B'];i=0
    for o in rec['objects']:
        if 'Large mottled concrete slab' in o.name:
            o.data.materials.clear();o.data.materials.append(k.material(colors[i%3],'plaster'));i+=1
    r.recolor('boutique_floor','827D77',lambda o:'Boutique slab' in o.name,kind='plaster')
    r.move('entry_mat',(-2.46,.079,1.50))
    r.recolor('black_tufted_bench','49474F',lambda o:'Leather continuous cushion' in o.name,kind='cloth')
    for rec in k.KITS.values():
        for o in rec['objects']:
            if any(s in o.name.lower() for s in ['lettering','print','seam','stitch','cord','hanger','neckline','knit rib','entrance bolt','moulding','stile','skirting','panel rail']):solid(o)
    r.sync_instances()

def manifest(d):
    d['lighting']['lamps'].append({'position':[-2.65,.75,1.40],'color':'88BFFF','energy':1.5,'range':2.2})
    d['review_lighting']['points']=d['lighting']['lamps']
    d['lighting']['ambient']='B9BAC9';d['review_lighting']['ambient_color']='B9BAC9'
    d['bench_albedo_multiplier']=[1.0,.95,1.0]
    d['revision']='R2';d['lighting']['background']='#AD9D95';d['review_lighting']['background']='#AD9D95'
    d['pendant_pools']=[
        {'name':'LeftFloorPool','position':[-1.99,2.82,-1.84],'target':[-2.05,.06,.40],'energy':9.0,'angle':15.0},
        {'name':'DisplayTablePool','position':[-1.04,2.66,-1.20],'target':[-.42,1.04,.14],'energy':6.0,'angle':18.0},
        {'name':'RearAislePool','position':[-.44,2.87,-2.04],'target':[1.35,.06,-1.07],'energy':9.0,'angle':15.0}]
    from liubei_r2 import fit_camera
    fit_camera(d,(1544,1544),[(40,946),(818,1452),(1507,991)],footprint=(6.16,5.76),plinth_y=-.255)
    d['review_views']=[{'name':'cargo-detail','position':[4,2.2,1.9],'target':[2.01,.90,-2.20],'size':2.45},{'name':'print-detail','position':[2.0,3.7,3.6],'target':[-.2,1.12,.21],'size':2.9},{'name':'brand-detail','position':[2.5,2.6,2.0],'target':[.13,2.26,-2.46],'size':2.9},{'name':'light-pools-detail','position':[5,6.5,7],'target':[-.30,.4,-.35],'size':6.8}]
