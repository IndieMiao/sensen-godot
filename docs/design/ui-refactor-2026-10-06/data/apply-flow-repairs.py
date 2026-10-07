#!/usr/bin/env python3
"""Scoped UI data repair from the 2026-10-06 row 29/34/35 review; no game state access."""
from pathlib import Path
import json,copy,hashlib
HERE=Path(__file__).resolve().parent
all_path=HERE/'current-all.json'
data=json.loads(all_path.read_text());by={d['id']:d for d in data};changed=[]
def note(d,text):
 d.setdefault('reviewNotes',[])
 if text not in d['reviewNotes']:d['reviewNotes'].append(text)
 d['reviewAmendment']='2026-10-06 row 29/34/35 review'
 return d
def apply(item_id,fn):
 d=by[item_id];before=json.dumps(d,sort_keys=True);fn(d)
 if json.dumps(d,sort_keys=True)!=before:changed.append(item_id)

def mine4(d):
 for action in d['actions']:
  if action.get('label')=='Floor 5':action['target']='MINE-5-ARRIVAL'
 note(d,'Entering Floor 5 leads only to the arrived/elite-not-defeated state. It must not grant the MINE-5 defeated-elite loot.')
apply('MINE-4',mine4)
def mine5(d):
 for f in d['keyFacts']:
  if f['label']=='Quartz':f.update(kind='progress',label='Quartz collected')
 note(d,'Quartz is an already-settled outcome in this fixture, not a reward/cost of Return to entrance. Show once in the content area.')
apply('MINE-5',mine5)

def meal(d,received):
 d['effect']='Added to Bag · Dishes.'if received else"Receive today's meal from Hana."
 d['keyFacts']=[{'kind':'progress','label':'When eaten','value':'Up to 20 Energy'},{'kind':'progress','label':'Resident meal today','value':'1/1'if received else'0/1'},{'kind':'time','label':'Eat before','value':'04:00 · home time'}]
 if not received:d['keyFacts'].insert(2,{'kind':'progress','label':'Destination','value':'Bag · Dishes'})
 d.setdefault('hud',{}).update(energy=142,capacity=200)
 d['disclosure']=["Uneaten Resident meals expire at the next 04:00 reset in your home city.","Energy is restored only when you eat the dish; receiving it does not restore Energy.","Food recovery follows your food allowance and same-dish limits.","One Resident meal per day, shared by all Residents."]
 d['sourceNote']='§3.4.5实物赠餐示例：当前无保温柜且背包有空间，Veggie Plate ×1进入Bag/Dishes；有保温柜的分支按§7.7/7.16处理，不在本卡虚构柜满协议。领取不进食，HUD前后均142/200；吃后才按食物余量/同菜递减回复，下一次家城04:00前未吃失效。'
 note(d,'The displayed +20 is the dish’s maximum eating effect, never a claim reward. The food item, destination and expiry are visible; no duplicate recovery appears above Accept.')
 if received:
  for a in d['actions']:
   if a['label']=='Done':a['target']='RESIDENT-TALK-MEAL-CLAIMED'
apply('RESIDENT-MEAL',lambda d:meal(d,False));apply('RESIDENT-MEAL-DONE',lambda d:meal(d,True))
portraits={'RES-PIP':'res_pip','RES-GRANNY':'res_granny_wu','RES-MIRA':'res_mira','RES-KAI':'res_old_kai','RES-RAFA':'res_rafa','RES-IVO':'res_ivo','RES-HANA':'res_hana','RES-SAM':'res_sam','RES-LENA':'res_lena','RES-TOMO':'res_tomo','RES-THEO':'res_theo','RES-NADIA':'res_nadia'}
for item_id,icon in portraits.items():
 def patch(d,icon=icon):
  d['icon']=icon;note(d,'Uses the existing per-resident portrait master. This is a prototype portrait candidate, not approved final character art.')
 apply(item_id,patch)

arrival={'id':'MINE-5-ARRIVAL','sourceGroup':'12','title':'The mine','state':'Floor 5 · Arrived','effect':'The elite is still here. Switch to Combat to face it.','keyFacts':[{'kind':'progress','label':'Elite','value':'Not defeated'},{'kind':'progress','label':'Run','value':'In progress'}],'requirements':[],'supporting':'','disclosure':['Express arrival is free and does not defeat the elite.','Combat uses your equipped weapon; entering the floor does not award loot.','Leaving the mine preserves this run until the daily reset.'],'actions':[{'label':'Return to entrance','target':'HOME-RETURN','kind':'commit'}],'rows':[],'items':[],'scene':'mine','layout':'sheet','hud':{**by['MINE-4'].get('hud',{}),'energy':142,'capacity':200,'coins':230,'place':'Mine · Floor 5'},'navigation':{'tabs':[],'selectedTab':0,'place':'Mine · Floor 5','placeExplicit':True},'presentation':{**by['MINE-4'].get('presentation',{}),'close':False},'sourceRef':{'file':'docs/product/gameplay-plan-v2-2026-10-02.md','section':'13.3.8–13.3.9','designLabel':'Express到达5层 · 精英未击败'},'sourceNote':'§13.3.9已解锁Express可局内0体力到第5层；本卡仅到达，不虚构攻击次数、敌方HP、概率或战利品。战斗结果的真实条件转移尚未定义，MINE-5仅作为独立击败结果审阅，不绑定在Floor 5导航上。','reviewNotes':['ARRIVAL-ONLY PROTOTYPE STATE. Combat outcome transition remains undefined; do not wire this arrival directly to the elite-defeated reward.'],'reviewActions':[{'label':'Inspect elite-defeated outcome (separate condition)','target':'MINE-5'}],'reviewOnly':False,'unresolvedRules':[]}
after=copy.deepcopy(by['RESIDENT-TALK']);after.update(id='RESIDENT-TALK-MEAL-CLAIMED',effect="Chat with Hana. Today's Resident meal has been claimed.",sourceNote='领取赠餐后的Hana面板；今日赠餐1/1，Today’s meal只查看已领取状态，不再回到可领取0/1。保留原对话/教学入口；本次领取没有自动进食或加体力。')
after['keyFacts']=[f for f in after.get('keyFacts',[])if f.get('label')!='Resident meal today']+[{'kind':'progress','label':'Resident meal today','value':'1/1'}]
after.setdefault('hud',{}).update(energy=142,capacity=200)
for action in after.get('actions',[]):
 if action.get('label')in ["Today’s meal","Today's meal"]:action['target']='RESIDENT-MEAL-DONE'
after['sourceRef']={'file':'docs/product/gameplay-plan-v2-2026-10-02.md','section':'3.4.5','designLabel':'Hana · 今日赠餐已领'}
repairs=[arrival,after]
assert len(data)==204 and len({d['id']for d in data})==204
assert all(f.get('kind')!='reward'for item_id in ['MINE-5','RESIDENT-MEAL','RESIDENT-MEAL-DONE']for f in by[item_id].get('keyFacts',[]))
assert by['RESIDENT-MEAL']['hud']['energy']==by['RESIDENT-MEAL-DONE']['hud']['energy']==142
assert len(portraits)==12

def atomic(path,value):
 temp=path.with_suffix(path.suffix+'.tmp');temp.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n');temp.replace(path)
# Apply only these IDs to the freshest all/section files so other approved repairs survive.
patched={item_id:by[item_id]for item_id in changed}
fresh=json.loads(all_path.read_text());atomic(all_path,[patched.get(d['id'],d)for d in fresh])
for group in ['07','08','09','10','11','12']:
 path=HERE/f'current-{group}.json';section=json.loads(path.read_text())
 if any(d['id']in patched for d in section):atomic(path,[patched.get(d['id'],d)for d in section])
atomic(HERE/'flow-repair-states.json',repairs)
report={'mainScreensChanged':changed,'additionalStates':[d['id']for d in repairs],'mainLegacyCount':84,'mainCurrentCount':204,'mainTotalUnchanged':288,'newStatesSeparate':True,'foodEnergyBefore':142,'foodEnergyAfter':142,'residentPortraits':portraits,'figmaExecution':'Not performed by this data script.'}
atomic(HERE/'flow-repair-report.json',report)
print(json.dumps(report,ensure_ascii=False))
