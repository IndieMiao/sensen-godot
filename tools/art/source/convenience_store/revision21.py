"""R2.1: hollow, illuminated drinks fridge with clear glass and front-facing stock."""
import kit as k
import series_revision as r
from kit import begin,cube
from revision2 import package

def revise():
    r.clear('drink_cabinet')
    cube('Insulated rear wall',(0,1.13,-.12),(.70,2.26,.12),'698E84',.025)
    for x in (-.34,.34):
        cube('Insulated side wall',(x,1.13,.08),(.065,2.26,.50),'89B5A8',.018)
    cube('Insulated roof',(0,2.235,.08),(.70,.05,.50),'89B5A8',.018)
    for row in range(5):
        cube('Thin metal shelf',(0,.27+row*.37,.13),(.635,.018,.34),'789C9E',.005)
    for x in (-.306,.306):
        cube('Narrow door frame',(x,1.23,.329),(.026,1.98,.038),'A6C8BC',.008)
    for y in (.245,2.21):
        cube('Narrow door frame',(0,y,.329),(.64,.026,.038),'A6C8BC',.008)
    cube('Door handle',(.258,1.2,.38),(.024,.38,.035),'B1C5BA',.008)
    cube('Refrigerator plinth',(0,.13,.12),(.70,.23,.48),'89B5A8',.020)
    for j in range(4):
        cube('Vent slit',(0,.055+j*.041,.369),(.54,.017,.006),'496F60',.004)
    for name in ('chilled_drinks_stock','chilled_back_liner'):
        if name in k.KITS:r.remove(name)
    begin('chilled_drinks_stock',at=(-2.68,.065,-.72),yaw=90)
    for row in range(5):
        for col in range(4):
            package((-.231+col*.154,.28+row*.37,.215),col+row*4,
                    'can' if row%2 else 'drink')
    k.instance('chilled_drinks_stock','chilled_drinks_stock_second',(-2.68,.065,-1.48),90)
    begin('chilled_back_liner',at=(-2.68,.065,-.72),yaw=90)
    cube('Cool luminous back liner',(0,1.23,-.052),(.635,1.90,.012),'B6CFD6',0)
    k.instance('chilled_back_liner','chilled_back_liner_second',(-2.68,.065,-1.48),90)
    r.sync_instances()

def manifest(d):
    d['revision']='R2.1'
    # Keep glass separate: the shared glass batch intentionally has a fixed material.
    d['material_overrides']['chiller_glass']={'alpha':.025,'unshaded':True}
    d['material_overrides']['chilled_back_liner']={'emission':'D4EEFF','emission_energy':.65}
    d['material_overrides']['chilled_drinks_stock']={'emission':'FFFFFF','emission_use_atlas':True,'emission_energy':.38}
    d['review_views']=[v for v in d['review_views'] if v['name']!='fridge-detail']
    d['review_views'].append({'name':'fridge-detail','position':[3.2,2.9,3.5],'target':[-2.48,1.28,-1.04],'size':3.0})
