"""Orchard R2: wood-framed legible sign, denser olive crowns and flowering arch."""
import math,importlib.util,json
from pathlib import Path
from mathutils import Matrix
import kit as k
import series_revision as r
from kit import begin,cube,cylinder,tube,mesh

def revise():
    r.move('floor_fig_crate',(.85,.064,1.30))
    r.move('orchard_market_sign',(-2.82,1.83,1.75));r.clear('orchard_market_sign')
    cube('Wood framed orchard sign',(0,0,0),(1.24,1.16,.09),'B57B4E',.028,'wood')
    cube('Cream orchard sign face',(0,0,.051),(1.12,1.04,.025),'F4E4C3',.012)
    k.text_label('ORCHARD',(0,.27,.080),.205,'4B663C')
    k.text_label('MARKET',(0,.025,.080),.218,'4B663C')
    for radius,z,tone in [(.155,.092,'DC8427'),(.135,.105,'F7E5B7'),(.119,.113,'EB9A32')]:
        o=cylinder('Painted cut-orange illustration',(0,-.29,z),radius,.007,tone,vertices=32);o.rotation_euler.x=math.pi/2;o['atlas_constant_colour']=True
    for j in range(7):
        a=j*math.tau/7;tube('Orange segment line',[(0,-.29,.121),(.113*math.cos(a),-.29+.113*math.sin(a),.121)],.0045,'F8E4AD',4)
    for side in (-1,1):
        tube('Painted orange branch',[(side*.13,-.31,.097),(side*.33,-.23,.097),(side*.45,-.10,.097)],.008,'607244',5)
        for j in range(3):
            x=side*(.22+j*.09);y=-.26+j*.055
            mesh('Orange botanical sign leaf',[(x,y,.104),(x+side*.085,y+.065,.104),(x+side*.095,y-.008,.104)],[(0,1,2),(2,1,0)],'687D43')
    tube('Iron sign lamp arm',[(-.44,.63,0),(-.44,.83,.055),(.29,.83,.18),(.29,.67,.18)],.025,'494943',7)
    k.lathe('Dark rounded sign lampshade',(.29,.60,.18),[(0,.16),(.04,.17),(.11,.07),(.14,.04)],'4F5047',20)
    # Extra canopy reuses the authored shared olive leaves. It has no duplicate pot/trunk.
    src=k.ROOT/'assets/rooms/_shared/plants/source/build_plants.py';spec=importlib.util.spec_from_file_location('olive_shared_shapes',src);lib=importlib.util.module_from_spec(spec);spec.loader.exec_module(lib)
    begin('olive_crown_leaves',at=(-2.43,.07,.78),yaw=65);lib.olive()
    rec=k.CURRENT
    for o in list(rec['objects']):
        if 'Silver olive leaf' not in o.name:rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
        else:
            o['atlas_constant_colour']=True
            for v in o.data.vertices:
                v.co.x*=1.07;v.co.y*=1.07;v.co.z=1.50+(v.co.z-1.50)*1.04
    k.instance('olive_crown_leaves','right_olive_crown_leaves',(2.55,.07,-.12),150)
    k.INSTANCES[-1]['scale']=[1.12]*3;k.bpy.data.objects['right_olive_crown_leaves'].scale=(1.12,1.12,1.12)
    for col,z in enumerate((-1.29,-1.09,-.89)):
        for row,y in enumerate((2.95,1.76)):
            name='arch_foliage_%d%d'%(col,row)
            if col==0 and row==0:
                begin('arch_vine_leaves',at=(-2.76,y,z),yaw=90);lib.vine(1.4,13,flowers=False)
                for o in k.CURRENT['objects']:o['atlas_constant_colour']=True
            else:k.instance('arch_vine_leaves',name,(-2.76,y,z),90)
    import revision21
    revision21.revise()
    r.sync_instances()

def manifest(d):
    d['revision']='R2';d['botanical_assets']=['olive_crown_leaves','hanging_herbs_leaves','arch_vine_leaves']
    left,right=d['shared_plants'][:2];left['position']=[-2.43,.07,.78];right['position']=[2.55,.07,-.12];right['scale']=[1.12]*3
    # Closely spaced strands retain the required envelope and white-flower density.
    plants=d['shared_plants']
    for i,z in enumerate((-2.18,-1.52)):
        plants.append(r.plant('LeftWallCrown'+str(i),'ivy_medium',(-2.78,3.00,z),.90,90))
    plants.append(r.plant('BackCornerFlowering','ivy_long',(-2.35,2.99,-2.52),.95,0))
    from liubei_r2 import fit_camera
    fit_camera(d,(1544,1544),[(90,998),(809,1405),(1452,995)])
    # The right pot is now on the front side of the display. Route stays inside it.
    for point in d['bench']['route']:
        if point['name']=='right_olive':point['position']=[1.70,.06,-.22]
    for block in d['bench']['blocked']:
        if block['name']=='side_wall':block.update({'from':[2.5,.06,1.40],'to':[3.6,.06,1.40]})
    d['bench']['scale']['chair']={'applicable':False,'reason':'N/A: no chair in the reference or delivered scene; no placeholder measurement.'}
    d['review_views']=[{'name':'olive-sign-detail','position':[3.8,3.9,6.2],'target':[-2.30,1.45,1.1],'size':3.35},{'name':'vine-detail','position':[3.4,4.0,5.2],'target':[-2.57,2.1,-1.0],'size':3.6}]

    import revision21
    revision21.manifest(d)
