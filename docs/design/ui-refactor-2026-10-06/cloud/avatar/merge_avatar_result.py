#!/usr/bin/env python3
"""Merge a successful MCP receipt into the local Avatar ledger; no Figma writes."""
from pathlib import Path
from datetime import datetime,timezone
import json,sys,hashlib,fcntl
HERE=Path(__file__).resolve().parent
STATE=HERE/'state.json'
def unwrap(value):
 if isinstance(value,str):
  try:return unwrap(json.loads(value))
  except json.JSONDecodeError:raise ValueError('Receipt text is not JSON')
 if not isinstance(value,dict):raise ValueError('Expected a tool result object')
 if value.get('isError'):raise ValueError('Tool reported an error; inspect the canvas before a retry')
 if value.get('kind','').startswith('avatar-'):return value
 for key in ['structuredContent','result','data','value']:
  if key in value:
   try:return unwrap(value[key])
   except (ValueError,TypeError):pass
 for content in value.get('content',[]):
  if content.get('type')=='text':
   try:return unwrap(content['text'])
   except (ValueError,TypeError):pass
 raise ValueError('No complete successful Avatar result in receipt; truncated output must not advance state')
def ids(result,kind):
 values=list(result.get(kind+'NodeIds',[]))
 for prefix,suffixes in result.get(kind+'InheritedNodeIds',{}).items():
  values.extend(prefix+s for s in (suffixes.split(',')if isinstance(suffixes,str)else suffixes))
 return values
lock=(HERE/'state.lock').open('a');fcntl.flock(lock,fcntl.LOCK_EX)
state=json.loads(STATE.read_text())
for path in map(Path,sys.argv[1:]):
 raw=path.read_bytes();result=unwrap(json.loads(raw))
 if result['kind']=='avatar-asset-upload':
  if state.get('assetFrameId')and state['assetFrameId']!=result['assetFrameId']:raise ValueError('Conflicting source asset frame')
  state['assetFrameId']=result['assetFrameId']
  for image in result['images']:state.setdefault('images',{})[image['key']]=image
 else:
  avatar=state.setdefault('avatar',{});delta=result.get('avatarDelta',{})
  removed=set(ids(result,'removed'))
  for key in ['views','saved','continuations','thumbs','tiles','images']:
   avatar.setdefault(key,{}).update(delta.get(key,{}))
  if delta.get('variantSet'):avatar['variantSet']=delta['variantSet']
  links={x['nodeId']:x for x in avatar.get('links',[])if x['nodeId']not in removed}
  for row in delta.get('linkRows',[]):
   node_id,kind,value,navigation,wired=row;edge={'nodeId':node_id,'navigation':navigation,'wired':wired}
   field={'part':'partId','category':'category','saved':'savedId','continuation':'continuationId','node':'destinationId'}.get(kind)
   if field:edge[field]=value
   links[node_id]=edge
  for edge in delta.get('links',[]):links[edge['nodeId']]=edge
  avatar['links']=list(links.values())
  pending={x['nodeId']:x for x in state.get('pendingLinks',[])if x['nodeId']not in removed}
  for edge in result.get('pendingLinks',[]):pending[edge['nodeId']]=edge
  state['pendingLinks']=list(pending.values())
  if result.get('profileDetailsFrameId'):state['profileDetailsFrameId']=result['profileDetailsFrameId']
  state.setdefault('overlays',{}).update(result.get('overlays',{}))
  state.setdefault('checks',{}).update(result.get('checks',{}))
  state.setdefault('composed',{}).update(result.get('composed',{}))
  state.setdefault('componentSets',{}).update(result.get('componentSets',{}))
 key=result.get('scriptKey')or result.get('batch')or result.get('phase')
 if key and key not in state.setdefault('completed',[]):state['completed'].append(key)
 stamp={'source':str(path),'sha256':hashlib.sha256(raw).hexdigest(),'kind':result['kind'],'key':key,'createdNodes':len(ids(result,'created')),'mutatedNodes':len(ids(result,'mutated')),'removedNodes':len(ids(result,'removed')),'time':datetime.now(timezone.utc).isoformat(timespec='seconds')}
 state.setdefault('receipts',[]).append(stamp)
 state['updatedAt']=stamp['time']
 temp=STATE.with_suffix('.json.tmp');temp.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n');temp.replace(STATE)
 expected={x['key']:x['uploadSHA']for x in json.loads((HERE/'upload-manifest.json').read_text())['images']}
 matched=sum(state.get('images',{}).get(k,{}).get('uploadSHA')==sha for k,sha in expected.items())
 print(json.dumps({'merged':key,'currentImages':matched,'images':len(state.get('images',{})),'variants':len(state.get('avatar',{}).get('views',{})),'saved':len(state.get('avatar',{}).get('saved',{})),'continuations':len(state.get('avatar',{}).get('continuations',{}))},ensure_ascii=False))
