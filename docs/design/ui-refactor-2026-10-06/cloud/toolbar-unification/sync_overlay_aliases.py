#!/usr/bin/env python3
"""Update only live state pointer values after successful exact-overlay dedup.
No historical receipt or authored source/data is rewritten. Default is dry-run.
"""
from pathlib import Path
import argparse,json,hashlib,datetime
P=Path(__file__).resolve().parent;CLOUD=P.parent
parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');args=parser.parse_args()
aliases={};receipts=[]
for f in sorted(P.glob('overlay-dedup-*-result*.json')):
 raw=json.loads(f.read_text())
 if raw.get('isError'):continue
 result=json.loads(next(c['text']for c in raw['content']if c['type']=='text'))if 'content'in raw else raw
 if result.get('kind')!='exact-information-overlay-dedup':continue
 aliases.update(result.get('aliases',{}));receipts.append(f.name)
def resolve(value):
 seen=set()
 while value in aliases:
  if value in seen:raise ValueError('Alias cycle '+value)
  seen.add(value);value=aliases[value]
 return value
aliases={k:resolve(v)for k,v in aliases.items()}
changes=[]
def visit(value,path):
 if isinstance(value,str)and value in aliases:
  changes.append({'path':path,'before':value,'after':aliases[value]});return aliases[value]
 if isinstance(value,list):return [visit(v,path+'/'+str(i))for i,v in enumerate(value)]
 if isinstance(value,dict):return {k:visit(v,path+'/'+k)for k,v in value.items()}
 return value
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');targets=[]
for rel in ['state.json','avatar/state.json']:
 file=CLOUD/rel;before=file.read_bytes();raw=json.loads(before);at=len(changes);updated=visit(raw,rel)
 if rel=='state.json':updated['overlayAliases']={**updated.get('overlayAliases',{}),**aliases}
 content=(json.dumps(updated,ensure_ascii=False,indent=2)+'\n').encode();changed=content!=before
 if args.apply and changed:
  backup=P/'live-state-backups'/stamp/rel;backup.parent.mkdir(parents=True,exist_ok=True);backup.write_bytes(before);file.write_bytes(content)
 targets.append({'file':rel,'pointerChanges':len(changes)-at,'contentChanged':changed,'beforeSHA256':hashlib.sha256(before).hexdigest(),'afterSHA256':hashlib.sha256(content).hexdigest()})
report={'applied':args.apply,'successfulReceipts':receipts,'resolvedAliases':len(aliases),'liveStateFiles':targets,'pointerChangeCount':len(changes),'changes':changes,'historicalReceiptsChanged':False,'sourceDataChanged':False}
if args.apply:(P/('overlay-alias-sync-'+stamp+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({**report,'changes':changes[:12]},ensure_ascii=False,indent=2))
