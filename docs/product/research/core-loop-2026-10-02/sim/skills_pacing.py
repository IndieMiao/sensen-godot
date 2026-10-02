# Pacing model for Farming / Fishing skill tracks (D16). Steady-state daily XP by archetype.
import math

FISH_TH = [0,40,110,220,380,600,880,1250,1700,2250]
FARM_TH = [0,30,80,160,280,450,700,1050,1550,2300]

def level(xp, th):
    lv=1
    for i,t in enumerate(th):
        if xp>=t: lv=i+1
    return lv

# ---------- Fishing ----------
# site weights T1..T4, success 90/80/65/50, xp 4/7/12/20
SUCC=[0.9,0.8,0.65,0.5]; XP=[4,7,12,20]
SITES={'pond':[0.6,0.3,0.09,0.01],'river':[0.35,0.4,0.2,0.05],'coast':[0.2,0.3,0.35,0.15]}
# max tier catchable by fishing level (global fish): T1 Lv1, T2 Lv2, T3 Lv4, T4 Lv7
def max_tier(lv):
    return 1 if lv<2 else 2 if lv<4 else 3 if lv<7 else 4
def cast_stats(site, lv, friend=False):
    w=SITES[site]; mt=max_tier(lv)
    xp=0; fail=0
    for t in range(4):
        if t+1<=mt:
            xp+=w[t]*SUCC[t]*XP[t]; fail+=w[t]*(1-SUCC[t])
        else:
            fail+=w[t]            # escapes
    if friend: xp*=1.2
    energy=2-fail                 # failure refunds 1 (after first 10/day)
    return xp, energy, fail

# species first-catch schedule (home city Shanghai: regional = grass carp T2 Lv3, snakehead T3 Lv5)
# returns bonus available at (level, site) not yet claimed
SPECIES = {  # name: (min level, sites)
 'crucian':(1,{'pond','river'}),'carp':(1,{'pond','river'}),'mullet':(1,{'river','coast'}),
 'perch':(2,{'pond','river'}),'bass':(2,{'pond','river'}),'trout':(2,{'river'}),'mackerel':(2,{'coast'}),
 'grass_carp':(3,{'pond','river'}),
 'koi':(4,{'pond'}),'catfish':(4,{'pond','river'}),'seabass':(5,{'coast'}),'snakehead':(5,{'pond','river'}),
 'sturgeon':(7,{'pond','river','coast'}),'eel':(7,{'pond','river'}),
}

def sim_fish(energy_per_day, site_plan, cap, th=FISH_TH, days=120, free_fail=10, label=''):
    xp=0; caught=set(); out={}; firsts=5+10  # first cast+hook, first city
    day_hit=None
    for d in range(1,days+1):
        lv=level(xp,th)
        site=site_plan(lv)
        c_xp,c_en,c_fail=cast_stats(site,lv)
        # first 10 failures refund 2 -> effective energy lower
        casts=energy_per_day/c_en
        # approximate the 10 free failures bonus casts
        casts += min(free_fail, casts*c_fail)*1/ c_en * 0.5
        day_xp=casts*c_xp
        capped=min(day_xp,cap)
        bonus=firsts; firsts=0
        for sp,(ml,ss) in SPECIES.items():
            if sp not in caught and lv>=ml and site in ss:
                caught.add(sp); bonus+=10
        xp+=capped+bonus
        for L in range(2,11):
            if L not in out and xp>=th[L-1]: out[L]=d
        if 10 in out: break
    return out, caught

def plan_pond(lv): return 'pond'
def plan_regular(lv): return 'pond' if lv<4 else 'river'
def plan_heavy(lv): return 'pond' if lv<4 else 'river' if lv<6 else 'coast'

# ---------- Farming ----------
# xp per energy by chosen tier: tier1-2 = 2.0, tier3 = 1.67, tier4 = 1.5; first-harvest +8 per crop by unlock level
FIRST_BY_LV={1:2,2:2,3:2,4:2,5:3,6:1,7:1,8:1,9:3,10:0}  # crops newly unlocked at each level (home zone only)
def sim_farm(energy_per_day, xp_per_energy, cap, th=FARM_TH, days=200, lag=1):
    xp=0; out={}; claimed=set(); pending=[]
    for d in range(1,days+1):
        lv=level(xp,th)
        # harvest of yesterday's sowing
        day_xp = energy_per_day*xp_per_energy(lv) if d>lag else 0
        capped=min(day_xp,cap)
        bonus=0
        if d>lag:
            for L in range(1,lv+1):
                if L not in claimed:
                    claimed.add(L); bonus+=8*FIRST_BY_LV[L]
        xp+=capped+bonus
        for L in range(2,11):
            if L not in out and xp>=th[L-1]: out[L]=d
        if 10 in out: break
    return out

def fmt(o): return ' '.join(f"L{L}:d{o.get(L,'-')}" for L in range(2,11))

print("=== FISHING (cap 300, thresholds", FISH_TH, ")")
for name,en,plan in [('P5 16en (8 casts) pond',16,plan_pond),('P30 40en (22 casts)',40,plan_regular),
                     ('P30 56en (31 casts)',56,plan_regular),('Heavy balanced 56en',56,plan_heavy),
                     ('Heavy focused 140en',140,plan_heavy),('P30 all-in 96en',96,plan_regular)]:
    o,c=sim_fish(en,plan,300); print(f"{name:28s}", fmt(o), f"species={len(c)}")
print("=== FISHING (cap 250)")
for name,en,plan in [('Heavy focused 140en',140,plan_heavy),('P30 all-in 96en',96,plan_regular),('P30 40en',40,plan_regular)]:
    o,c=sim_fish(en,plan,250); print(f"{name:28s}", fmt(o))
print("=== FISHING cap 300, Lv10=2400 Lv9=1750")
TH2=[0,40,110,220,380,600,880,1250,1750,2400]
for name,en,plan in [('P5 16en',16,plan_pond),('P30 40en',40,plan_regular),('Heavy focused 140en',140,plan_heavy),('P30 all-in 96en',96,plan_regular)]:
    o,c=sim_fish(en,plan,300,th=TH2); print(f"{name:28s}", fmt(o))

print("\n=== FARMING (cap 200, thresholds", FARM_TH, ")")
tier12=lambda lv:2.0
mix=lambda lv:2.0 if lv<5 else 1.8
for name,en,f in [('P5 14en tier1-2',14,tier12),('P30 56en mix',56,mix),('Heavy balanced 84en',84,mix),('Heavy focused 140en',140,tier12),('P30 all-in 96en',96,mix)]:
    o=sim_farm(en,f,200); print(f"{name:28s}", fmt(o))
print("=== FARMING per-cast XP/energy sanity")
for site in SITES:
    for lv in (1,2,4,7):
        x,e,f=cast_stats(site,lv); print(site,lv,f"xp/cast={x:.2f} energy/cast={e:.2f} xp/energy={x/e:.2f} fail={f:.2f}")
