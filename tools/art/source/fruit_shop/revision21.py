"""R2.1 moves the right olive into the front wall corner, clearing produce bins."""
import kit as k
import series_revision as r
POSITION=[2.32,.07,2.03]
def revise():
    for p in k.INSTANCES:
        if p['name']=='right_olive_crown_leaves':p['position']=POSITION[:]
    r.sync_instances()
def manifest(d):
    d['revision']='R2.1'
    next(p for p in d['shared_plants'] if p['name']=='RightOlive')['position']=POSITION[:]
    route=d['bench']['route']
    for p in route:
        if p['name']=='right_crate':p['position']=[1.65,.06,.35]
        if p['name']=='front_return':p['position']=[.15,.06,.35]
    route[:]=[p for p in route if p['name']!='right_return']
    for p in d['bench']['blocked']:
        if p['name']=='side_wall':p.update({'from':[2.5,.06,.4],'to':[3.6,.06,.4]})
    d['bench']['gaps']=[p for p in d['bench']['gaps'] if p['name']!='entry_to_produce']
    d['bench']['gaps'].append({'name':'entry_to_produce','from':[.10,.06,1.70],'to':[.10,.06,.25],'measure':[[-.91,.32,1.10],[.40,.32,1.10]],'width':1.31,'minimum':.8})
    d['review_views']=[p for p in d['review_views'] if p['name']!='clear-produce-detail']
    d['review_views'].append({'name':'clear-produce-detail','position':[5,4.6,7],'target':[.15,1.25,-1.1],'size':5.8})
