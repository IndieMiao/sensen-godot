from pathlib import Path
import json,hashlib,subprocess,datetime,concurrent.futures
P=Path(__file__).resolve().parent
ROOT=P.parents[4]
data=json.loads((ROOT/'docs/design/ui-refactor-2026-10-06/data/current-all.json').read_text())
NODES={'07':'396:2','08':'430:14','09':'430:16','10':'438:3178','11':'438:3180','12':'438:3182'}
HEIGHT={'07':14080,'08':5120,'09':3200,'10':7040,'11':2240,'12':6080}
rows=[]
for group in NODES:
 screens=[s for s in data if s['sourceGroup']==group]
 grouped={}
 for i,s in enumerate(screens):
  y=s['original']['y'] if group=='07' else 140+(i//6)*960
  grouped.setdefault(y,[]).append(s['id'])
 for r,(y,ids) in enumerate(grouped.items(),1):
  h=950 if group=='07' else 930
  rows.append({'group':group,'row':r,'file':f'{group}-row-{r:02}.png','sourceFile':f'section-{group}.png','crop':{'x':0,'y':y+40,'width':2576,'height':h},'screens':ids,'inspected':False})
def crop(r):
 c=r['crop'];subprocess.run(['sips','--cropOffset',str(c['y']),str(c['x']),'-c',str(c['height']),str(c['width']),str(P/r['sourceFile']),'--out',str(P/r['file'])],check=True,capture_output=True)
 r['sha256']=hashlib.sha256((P/r['file']).read_bytes()).hexdigest()
 return r
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:rows=list(pool.map(crop,rows))
sources=[]
for group,node in NODES.items():
 f=P/f'section-{group}.png';sources.append({'group':group,'nodeId':node,'file':f.name,'width':2576,'height':HEIGHT[group],'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'bytes':f.stat().st_size})
manifest={'capturedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':'Fresh Figma get_screenshot, maxDimension 16000, 2026-10-06','download':'Direct DNS blocked; enableBase64Response used; exact bytes decoded locally','screens':204,'sections':6,'strips':len(rows),'coverage':['07:73','08:30','09:18','10:38','11:12','12:33'],'sources':sources,'rows':rows}
(P/'coverage.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(len(rows),'strips',sum(len(r['screens']) for r in rows),'screens')
