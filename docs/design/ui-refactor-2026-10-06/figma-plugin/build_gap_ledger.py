#!/usr/bin/env python3
"""Classify remaining prototype gaps without inventing outcomes or rule values."""
from pathlib import Path
import json,hashlib
p=Path(__file__).resolve().parent
validation=json.loads((p/'local-validation.json').read_text())
assert hashlib.sha256((p/'code.js').read_bytes()).hexdigest()==validation['bundleSha256'],'Run final validation before classifying gaps'
raw=json.loads((p/'local-destination-warnings.json').read_text())
groups={key:[] for key in ['authored-state-not-simulated','gameplay-result-not-authored','account-action-not-simulated','informational-navigation','already-open-entry']}
unique={}
for warning in raw:
 if not isinstance(warning,dict):continue
 key=(warning.get('screen'),warning.get('action'),warning.get('kind'),warning.get('target'))
 row=unique.setdefault(key,{**warning,'occurrences':0,'reasons':[]});row['occurrences']+=1
 if warning.get('reason')not in row['reasons']:row['reasons'].append(warning.get('reason'))
for row in unique.values():
 screen,action,kind,target=[row.get(k)for k in ['screen','action','kind','target']]
 if kind=='navigate':
  if target==screen and action in ['Today','Inbox','Energy','Location']:
   group='already-open-entry';note='The current page is already the requested destination. No self-navigation or resource change is needed.'
  else:group='informational-navigation';note='Information entry is shown, but this exact explanatory overlay or destination has not been authored; no execution outcome is substituted.'
 elif screen=='SETTINGS-1':group='account-action-not-simulated';note='Settings/account action is illustrated; the static design does not toggle live preferences, sign out or delete accounts.'
 elif action in ['Remove','Stop tracking','Sit','Rest']:
  group='authored-state-not-simulated';note='Local control/state change remains an illustrated specimen for this screen; a generic toast or an unrelated page is not treated as the completed state.'
 else:
  group='gameplay-result-not-authored';note='Exact same-item resulting resources/state are not authored for this legacy/example action. The control is not linked to a false success or unrelated reward.'
 row['classification']=group;row['handoff']=note;row.pop('reason',None);groups[group].append(row)
out={'schemaVersion':1,'bundleSha256':validation['bundleSha256'],'warningOccurrences':len(raw),'uniqueScreenActionKindTarget':len(unique),'classificationSource':'Local build destination warnings;not a cloud click run. Gameplay may be defined even when its illustrative result frame is missing.','simulationRequiredForDesignReview':False,'noFakeResultPolicy':'Do not wire to different items, repeat rewards, infer unknown inventory or reset resource snapshots.','groupCounts':{k:len(v)for k,v in groups.items()},'groups':groups}
(p/'prototype-gap-ledger.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'file':str(p/'prototype-gap-ledger.json'),'unique':len(unique),'groupCounts':out['groupCounts']}))
