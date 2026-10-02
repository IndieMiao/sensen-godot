# Homestead ladder + coin absorption sim, v2 energy scale (pool 200, sow 2/3/4/6, cast 5)
# Working assumption: net coins per energy 1.0 (tier1) .. 1.3 (regional crops / coast + carbon rod)
import math
LADDER = {  # level -> (coins, materials dict)
 2: (250, dict(wood=12, stone=8, fiber=6, rock_salt=3)),
 3: (400, dict(wood=16, stone=12, fiber=10, clay=4, rock_salt=4)),
 4: (550, dict(wood=20, stone=16, fiber=10, copper_ore=6, clay=6, rock_salt=4)),
 5: (750, dict(wood=20, stone=16, fiber=12, copper_ore=10, clay=8, quartz=2, rock_salt=4)),
 6: (1000, dict(wood=20, stone=18, fiber=12, copper_ore=10, clay=8, quartz=3, hardwood=3)),
 7: (1300, dict(wood=20, stone=20, fiber=10, copper_ore=12, clay=8, quartz=4, hardwood=4)),
 8: (1650, dict(wood=18, stone=18, fiber=8, copper_ore=12, clay=8, quartz=4, hardwood=6)),
 9: (2050, dict(wood=14, stone=16, fiber=6, copper_ore=12, clay=4, quartz=4, hardwood=7)),
 10:(2600, dict(wood=10, stone=16, fiber=6, copper_ore=13, clay=4, quartz=5, hardwood=8)),
}
GATE = lambda n: 2*n-1  # skills sum needed
FISH_T = [0,70,220,480,850,1300,1850,2500,3300,4300]
FARM_T = [0,50,150,300,500,750,1050,1450,2050,2800]
def lvl(xp, T):
    l=1
    for i,t in enumerate(T):
        if xp>=t: l=i+1
    return l
PERSONAS = {
 'P5':  dict(income=[(7,70),(28,95),(999,105)], fish_xp=30, farm_xp=74,
             mats=dict(wood=4.5,fiber=2.5,stone=4,copper_ore=1.3,rock_salt=0.9,clay_mine=0.3,clay_bank=1.0,quartz=0.3,hardwood=0.5),
             need_daily=[(999,14)], opt_daily=[(999,0)], tea=0),
 'P30': dict(income=[(7,160),(14,230),(28,270),(999,285)], fish_xp=230, farm_xp=135,
             mats=dict(wood=9,fiber=5,stone=16,copper_ore=3.9,rock_salt=2.7,clay_mine=0.9,clay_bank=2.0,quartz=0.9,hardwood=1.0),
             need_daily=[(7,20),(999,50)], opt_daily=[(7,0),(999,12)], tea=20),
 'HV':  dict(income=[(7,420),(14,700),(999,850)], fish_xp=550, farm_xp=233,
             mats=dict(wood=18,fiber=10,stone=44,copper_ore=12,rock_salt=7.5,clay_mine=1.8,clay_bank=4.0,quartz=3.9,hardwood=2.0),
             need_daily=[(7,60),(999,120)], opt_daily=[(7,0),(999,70)], tea=150),
}
# one-offs: (name, coins, mats, condition fn(state), necessary?)
def oneoffs():
    return [
     ('reed_rod',80,{}, lambda s: s['fish']>=3, True),
     ('carbon_rod',350,{}, lambda s: s['fish']>=6, True),
     ('trap1',120,{}, lambda s: s['fish']>=5, False),
     ('trap2',120,{}, lambda s: s['fish']>=8, False),
     ('trap3',120,{}, lambda s: s['fish']>=10, False),
     ('row_tool',0,dict(wood=4,copper_ore=2), lambda s: s['farm']>=4, True),
     ('sprinkler1',0,dict(wood=8,stone=6,copper_ore=3), lambda s: s['farm']>=6, False),
     ('sprinkler2',0,dict(wood=8,stone=6,copper_ore=3), lambda s: s['farm']>=6, False),
     ('compost_bin',0,dict(wood=6,stone=4), lambda s: s['farm']>=7, False),
     ('apple1',40,{}, lambda s: s['farm']>=7, False),
     ('apple2',40,{}, lambda s: s['farm']>=7 and s['hs']>=2, False),
     ('citrus',80,{}, lambda s: s['farm']>=9, False),
     ('grape',60,{}, lambda s: s['farm']>=9, False),
     ('greenhouse',300,dict(wood=20,stone=12,copper_ore=8), lambda s: s['farm']>=8, False),
     ('bag1',150,dict(fiber=10,wood=6), lambda s: s['hs']>=3, False),
     ('bag2',400,dict(hardwood=4,clay=6,copper_ore=4), lambda s: s['hs']>=6, False),
     ('bag3',1000,dict(hardwood=8,quartz=4,copper_ore=8), lambda s: s['hs']>=9, False),
     ('cards_common',60,{}, lambda s: s['day']>=5, False),
     ('cards_fine',160,{}, lambda s: s['day']>=12, False),
     ('card_rare',200,{}, lambda s: s['day']>=20, False),
     ('permit1',100,{}, lambda s: s['day']>=5 and s['p']!='P5', True),
     ('ticket1',150,dict(hardwood=2,quartz=2), lambda s: s['hs']>=4 and s['p']=='HV', True),
     ('permit2',100,{}, lambda s: s['day']>=14 and s['p']=='HV', True),
     ('ticket2',150,dict(hardwood=2,quartz=2), lambda s: s['hs']>=5 and s['p']=='HV', True),
    ]
def rate(table, day):
    for lim,v in table:
        if day<=lim: return v
    return table[-1][1]
def run(p, greedy, days=200, report=28):
    P=PERSONAS[p]
    wallet=180.0; mats={k:0.0 for k in ['wood','stone','fiber','copper_ore','rock_salt','clay','quartz','hardwood']}
    hs=1; fxp=0; farmxp=0; bought=set(); arrivals={}
    spent=dict(need=0.0,opt=0.0,upg=0.0,growth=0.0); income_total=0.0
    snap=None
    for day in range(1,days+1):
        inc=rate(P['income'],day); wallet+=inc; income_total+=inc
        fxp+=P['fish_xp']; farmxp+=P['farm_xp']
        st=dict(fish=lvl(fxp,FISH_T),farm=lvl(farmxp,FARM_T),hs=hs,day=day,p=p)
        m=P['mats']
        for k in ['wood','fiber','stone','copper_ore','rock_salt','quartz']: mats[k]+=m[k]
        mats['clay']+=m['clay_mine']+(m['clay_bank'] if hs>=2 else 0)
        if hs>=3: mats['hardwood']+=m['hardwood']
        nd=rate(P['need_daily'],day); wallet-=nd; spent['need']+=nd
        if greedy:
            od=rate(P['opt_daily'],day)+P['tea']; od=min(od,max(0,wallet-40)); wallet-=od; spent['opt']+=od
        for name,c,mm,cond,nec in oneoffs():
            if name in bought or not cond(st): continue
            if not nec and not greedy: continue
            if p=='P5' and name in ('card_rare','trap2','trap3','citrus','cards_fine'): continue
            if p=='P5' and name=='greenhouse' and day<35: continue
            if wallet-c<40: continue
            if any(mats[k]<v for k,v in mm.items()): continue
            wallet-=c; spent['need' if nec else 'growth']+=c
            for k,v in mm.items(): mats[k]-=v
            bought.add(name)
        # upgrade
        while hs<10:
            n=hs+1; c,mm=LADDER[n]
            if st['fish']+st['farm']<GATE(n): break
            if wallet-c<40: break
            if any(mats[k]<v for k,v in mm.items()): break
            wallet-=c; spent['upg']+=c
            for k,v in mm.items(): mats[k]-=v
            hs=n; arrivals[n]=day; st['hs']=hs
        if day==report:
            snap=dict(income=income_total+180, need=spent['need'], growth=spent['growth'], daily_opt=spent['opt'], upg=spent['upg'], low=(spent['need']+spent['upg'])/(income_total+180), mid=(spent['need']+spent['growth']+spent['upg'])/(income_total+180), high=(spent['need']+spent['growth']+spent['opt']+spent['upg'])/(income_total+180), wallet=wallet, hs=hs, fish=st['fish'], farm=st['farm'])
    return arrivals, snap
import sys
for p in ['P5','P30','HV']:
    a,s=run(p,True)
    print(p,'balanced arrivals', a)
    print('   d28:', {k:(round(v,2) if isinstance(v,float) else v) for k,v in s.items()})
    a,s=run(p,False)
    print(p,'sprint(no optional) arrivals', a)
