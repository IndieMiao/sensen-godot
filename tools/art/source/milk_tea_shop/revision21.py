"""R2.1: a readable upholstered banquette with a table and two facing chairs."""
import math
import kit as k
import series_revision as r
from kit import cube,tube

def revise():
    r.clear('pastel_bench');r.move('pastel_bench',(-1.86,.07,2.31))
    for x in (-.88,.88):
        for z in (-.22,.22):cube('Banquette short timber foot',(x,.19,z),(.075,.30,.075),'B38F76',.014,'wood')
    cube('Continuous banquette upholstered base',(0,.425,0),(2.05,.25,.67),'BA94C5',.035,'cloth')
    for j in range(4):
        x=-.765+j*.51
        cube('Divided thick lavender seating cushion',(x,.565,-.01),(.499,.18,.66),'BC92CC',.035,'cloth')
        o=tube('Banquette front cushion piping',[(x-.232,.598,-.341),(x+.232,.598,-.341)],.006,'E2B9E7',5);o['atlas_constant_colour']=True
    cube('Low upholstered banquette back',(0,.665,.268),(2.05,.12,.12),'C8A2D3',.035,'cloth')
    for x,color in [(-.62,'E3A8B9'),(.13,'A9CDBA')]:
        o=cube('Upright loose pillow leaning against back',(x,.825,.157),(.42,.46,.145),color,.056,'cloth');o.rotation_euler.x=math.radians(-9)
    k.KITS['pastel_bench']['collision']=[{'at':[0,.46,0],'size':[2.05,.92,.68]}]
    r.move('cafe_table',(-1.80,.06,1.15));r.move('table_flower_vase',(-1.80,1.104,1.15))
    r.move('chair',(-2.22,.06,.28));k.KITS['chair']['yaw']=0;k.KITS['chair']['root'].rotation_euler.z=0
    for p in k.INSTANCES:
        if p['name']=='chair_2':p['position']=[-1.36,.06,.28];p['yaw_degrees']=0
    r.sync_instances()

def manifest(d):
    d['revision']='R2.1'
    for p in d['bench']['route']:
        if p['name']=='bench_approach':p['position']=[0,.06,1.95]
        if p['name']=='bench_front':p['position']=[-.46,.06,2.18]
    for p in d['bench']['blocked']:
        if p['name']=='bench':p.update({'from':[-.5,.06,2.31],'to':[-1.8,.06,2.31]})
        if p['name']=='table':p.update({'from':[-.8,.06,1.15],'to':[-1.8,.06,1.15]})
    for p in d['bench']['gaps']:
        if p['name']=='chairs_center':p.update({'measure':[[-1.25,.7,.90],[.385,.7,.90]],'width':1.635})
        if p['name']=='tables_counter':p.update({'measure':[[-1.4,.7,-1.19],[-1.4,.7,-.02]],'width':1.17})
    d['review_views']=[{'name':'banquette-detail','position':[3.8,3.0,-.2],'target':[-1.8,.68,1.95],'size':3.3}]
