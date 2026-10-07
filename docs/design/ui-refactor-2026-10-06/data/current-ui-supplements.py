from pathlib import Path
import json
P=Path(__file__).resolve().parent
ROOT=P.parents[3]
f=P/'current-all.json';screens=json.loads(f.read_text());by={s['id']:s for s in screens}
controls=json.loads((ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/control-data-final.json').read_text())
names={'i-radish-seeds':'Radish Seeds','i-carrot-seeds':'Carrot Seeds','i-sprout':'Lettuce Seeds','i-torch':'Torch','i-trap':'Fish Trap','i-worm':'Worm Bait','i-lure':'Lure','i-compost':'Compost','i-feed-bag':'Orchard Feed'}
for s in screens:
 hud=s.setdefault('hud',{});energy=float(hud.get('energy',142));cap=float(hud.get('capacity',200))
 hud['recoveryState']='bonus' if energy>cap else 'full' if energy==cap else 'recovering'
 hud['recoveryText']='Bonus +'+str(int(energy-cap)) if energy>cap else 'Full' if energy==cap else '+1 in '+('2:40' if s['sourceGroup']=='07' else '3:59')
 s.setdefault('presentation',{})['close']=s['layout'] not in ['scene','states'] and not s.get('reviewOnly',False)
for c in controls:
 s=by[c['id']];a=next((a for a in s['actions'] if a['kind']=='commit'),{})
 label=s['original'].get('action',a.get('label',c['mode'])).split('\n')[0].split(' · ')[0]
 cost=s['original'].get('action','').split('\n')[1:] or [next((q['value'] for q in s['keyFacts'] if q['kind']=='cost'),'Free')]
 quick=[]
 for q in c['quick']:
  key=q['icon'];title='Healing Potion' if c['mode']=='Combat' else names.get(key,key.removeprefix('i-').replace('-',' ').title())
  quick.append({'title':title,'icon':key,'quantity':{'value':q['count'].removeprefix('×'),'label':'Owned'}})
 s['sceneControls']={'label':label,'cost':cost[0],'icon':{'Farming':'i-hoe','Fishing':'i-rod','Mining':'i-pickaxe','Combat':'i-sword','SetTrap':'i-trap'}[c['mode']],'quick':quick,'target':a.get('target'),'mode':c['mode']}
for id,title,remaining,mode,icon in [('BUFF-ACTIVE','Harvest Focus','2h 59m','time','i-sprout'),('BUFF-CASTS','Steady Hands','1 cast','casts','i-rod')]:
 by[id]['hud']['buff']={'title':title,'remaining':remaining,'mode':mode,'icon':icon}
by['BUFF-LAST']['sceneControls']={'label':'Cast','cost':'5 Energy','icon':'i-rod','quick':[{'title':names[k],'icon':k} for k in ['i-worm','i-lure','i-trap']],'target':'LOCAL-CATCH','mode':'Fishing'}
by['BUFF-TIMEOUT']['sceneControls']={'label':'Sow','cost':'2 Energy','icon':'i-hoe','quick':[{'title':names[k],'icon':k} for k in ['i-radish-seeds','i-carrot-seeds','i-compost','i-feed-bag']],'target':None,'mode':'Farming'}
for id in ['BUFF-LAST','BUFF-TIMEOUT']:
 by[id]['presentation'].update({'feedback':'nonmodal-toast','close':False,'suppressDecisionArea':True})
recipe_ids=['TUT-3-07B','COOK-P0-2','COOK-P0-7','COOK-P0-8','COOK-P1-2','COOK-P1-6','COOK-P1-7','EXPAND-4','EXPAND-5']
for id in recipe_ids:
 s=by[id];slots=4 if id=='EXPAND-4' else 5 if id=='EXPAND-5' else 3 if 'P1' in id else 2
 selected=[{'title':q['title'],'icon':q.get('icon','i-question'),'quantity':{'value':str(q['need']),'label':'In pot'}} for q in s['requirements'] if q['title'] not in ['Coins']]
 if id=='COOK-P0-2':selected=[{'title':'Pond Crucian','icon':'i-fish','quantity':{'value':'1','label':'In pot'}}]
 s['kitchen']={'mode':'experiment' if id=='COOK-P0-2' else 'recipe','ingredientSlots':slots,'selectedIngredients':selected,'heat':None,'stoves':[],'previewOnly':id.startswith('EXPAND-')}
for id,remaining,target in [('COOK-P0-3','0:03','TUT-3-07C'),('COOK-HERB-HEAT','0:15','COOK-P0-9')]:
 s=by[id];s['kitchen']={'mode':'heat','ingredientSlots':2,'selectedIngredients':[],'heat':{'instruction':'Tap when the needle reaches gold.','remaining':remaining,'target':target,'stove':1},'stoves':[]}
 s['actions']=[a for a in s['actions'] if a['label']!='Tap the pot'];s['presentation']['close']=True
for id in ['COOK-P0-1','COOK-P1-1','COOK-P1-3','COOK-P1-4','COOK-P1-5','COOK-EMPTY']:
 s=by[id];s['kitchen']={'mode':'stoves','ingredientSlots':2 if id=='COOK-P0-1' else 3,'selectedIngredients':[],'heat':None,'stoves':[{'title':f'Stove {i+1}','state':state} for i,state in enumerate(s['original'].get('stoveStates',['Empty']))]}
by['GUESTBOOK']['selection']={'kind':'single','selected':'Nice farm!','options':['Nice farm!','Thanks for the fish!','Come visit mine!']}
by['GUESTBOOK']['supporting']='Selected note: Nice farm!'
by['GUESTBOOK']['actions']=[{'label':'Post note','kind':'commit','target':None,'feedback':'Note posted.','context':{'operation':'post-note','selectionFrom':'GUESTBOOK','resultOnly':True}}]
for id,label in [('SOC-2','Send invitation'),('SOC-3','Invite helper'),('HELPER-INBOX','Accept')]:
 s=by[id]
 for a in s['actions']:
  if a['label']==label:
   old=a.get('target');a['target']=None;a['context']={'operation':'send-invitation' if id=='SOC-2' else 'invite-helper' if id=='SOC-3' else 'accept-helper','resultOnly':True}
   a['feedback']='Invitation sent.' if id!='HELPER-INBOX' else 'Helper invitation accepted.'

   if old and not any(r.get('target')==old and r.get('label')=='Review other role / later state' for r in s.get('reviewActions',[])):s.setdefault('reviewActions',[]).append({'label':'Review other role / later state','target':old,'reason':'Different role or later offline settlement; not an immediate player action result.'})
 s.setdefault('reviewNotes',[]).append('Sender/recipient/offline settlement are separate review entry points; no player-facing jump changes the acting identity.')
# Live screenshot row action added after old JSON authoring: preserve the concrete Perch branch.
by['PARCEL-1']['rows'][0]['actions']=[{'label':'Claim','kind':'commit','target':'PARCEL-ONE'}]
for id in ['PARCEL-1','PARCEL-ONE']:
 for r in by[id]['rows']:
  if r.get('actions'):continue
  r['actions']=[{'label':'Claim','kind':'commit','target':None,'context':{'operation':'claim-parcel','item':r['title'],'quantity':r.get('quantity'),'resultOnly':True},'feedback':r['title']+' claimed.'}]
by['TRAVEL-RECONNECT']['hud'].update({'city':'Tokyo','place':'Map'})
for id in ['FAC-2','FAC-3','FAC-GH-PLACE']:
 s=by[id];s['presentation']['coverage']={'kind':'greenhouse' if 'GH' in id else 'sprinkler','columns':4 if 'GH' in id else 3,'schematic':True,'occupiedCenter':False if 'GH' in id else True,'blocked':id=='FAC-3'}
 s.setdefault('reviewNotes',[]).append('Coverage is a labelled schematic. Runtime world anchors, terrain registration and collision placement remain unverified.')
for id,label,cost,target,mode,icon in [('BUFF-ACTIVE','Sow','2 Energy',None,'Farming','i-hoe'),('BUFF-CASTS','Cast','5 Energy','BUFF-LAST','Fishing','i-rod')]:
 by[id]['layout']='scene';by[id]['sceneControls']={'label':label,'cost':cost,'icon':icon,'quick':[],'target':target,'mode':mode};by[id]['presentation'].update({'close':False,'suppressDecisionArea':True})
for group in ['07','08','09','10','11','12']:(P/f'current-{group}.json').write_text(json.dumps([s for s in screens if s['sourceGroup']==group],ensure_ascii=False,indent=2)+'\n')
f.write_text(json.dumps(screens,ensure_ascii=False,indent=2)+'\n')
print('Updated UI structure fields on',len(screens),'cards')
