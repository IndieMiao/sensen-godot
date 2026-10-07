#!/usr/bin/env python3
"""Bundle reviewed data + source scene art + vector fallback icons; no network."""
from pathlib import Path
import json,base64,io,hashlib,subprocess,tempfile,re
try:
 from PIL import Image
except ImportError:
 Image=None
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
DATA=HERE.parent/'data'
legacy=json.loads((DATA/'legacy-screens.json').read_text())
current=json.loads((DATA/'current-all.json').read_text())
screens=legacy+current
assert len(screens)==288
assert len({s['id'] for s in screens})==288
# Exclude full UI screenshots and giant source copies from the runtime. Preserve provenance only in the ledger.
clean=[]
for s in screens:
 c={k:v for k,v in s.items() if k not in ['original','originalVisibleText','sourceScreenshot','reviewedEvidence']}
 if s.get('original'):
  c['sceneState']={k:v for k,v in s['original'].items() if k in ['quick','stoveStates','stoves','placement','footprint','tag','heat','action','grid','energy','coins','capacity','city','place']}
 if s.get('sourceHtml'):
  html=(ROOT/s['sourceHtml']).read_text()
  names={'i-dish-grilled':'Grilled Crucian','i-dish-herb':'Herb Grilled Fish','i-dish-soup':'Fresh Fish Soup','i-fish':'Pond Crucian','i-worm':'Worm Bait','i-feed-bag':'Orchard Feed','i-salt':'Rock Salt','i-wood':'Timber'}
  def extract_cells(class_name):
   result=[]
   for classes,body in re.findall(r'<div class="('+class_name+r'(?: [^"]*)?)"[^>]*>(.*?)</div>',html,re.S):
    icon=re.search(r'<use[^>]*href="[^"]*#([^"]+)"',body)
    count=re.search(r'<span class="count"[^>]*>(.*?)</span>',body,re.S)
    label=re.search(r'<span class="name"[^>]*>(.*?)</span>',body,re.S)
    key=icon.group(1) if icon else 'i-question'
    title=re.sub(r'<[^>]*>','',label.group(1)).strip() if label else names.get(key,key.removeprefix('i-').replace('-',' ').title())
    empty='is-empty' in classes or 'is-ghost' in classes
    item={'title':'Empty' if empty else title,'icon':key,'selected':'is-selected' in classes}
    if count:item['quantity']={'value':re.sub(r'[^0-9/]','',re.sub(r'<[^>]*>','',count.group(1))),'label':'Owned'}
    selected=s.get('selectedItem') or (s.get('items',[None])[0] if s.get('variant')=='bag' and s.get('items') else None)
    if item['selected'] and selected:item.update(selected);item['icon']=key;item['selected']=True
    result.append(item)
   return result
  cells=extract_cells('cell')
  if cells:c['bagContents']=cells
  quick=extract_cells('slot')
  if quick:c['quickContents']=quick[:5]
 clean.append(c)
kit=json.loads((ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/approved-kit-state.json').read_text())
icons=json.loads((ROOT/'docs/design/p0-flow-2026-10-05/figma/icons.json').read_text())
assets=json.loads((ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/content-assets.json').read_text())
assetComponents=json.loads((ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/all-asset-components.json').read_text())
for a in assets:icons[a['id']]=a['svg']
iconNodes=dict(kit['icons'])
for a in assetComponents:iconNodes[a['id']]=a['componentId']
sceneHashes=json.loads((ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/scenes.json').read_text())
sceneHashes.update(json.loads((DATA/'legacy-scene-hashes.json').read_text())['hashes'])
sceneFiles={k:ROOT/'docs/design/ui-anchors-2026-10-03/scenes'/f'{k}.png' for k in sceneHashes}
sceneFiles['mine']=ROOT/'docs/design/ui-anchors-2026-10-03/scenes/mine-floor1.png'
sceneFiles['map']=ROOT/'docs/design/ui-anchors-2026-10-03/scenes/map-tile.png'
for s in legacy:
 if s.get('sceneName') and s.get('scene'):sceneFiles[s['sceneName']]=ROOT/s['scene']
sceneBytes={}
for key,p in sceneFiles.items():
 if not p.exists():continue
 assert '/scenes/' in str(p), 'Only source scene art is permitted'
 if Image:
  im=Image.open(p).convert('RGB');im.thumbnail((800,1000))
  b=io.BytesIO();im.save(b,'JPEG',quality=85,optimize=True);raw=b.getvalue()
 else:
  with tempfile.TemporaryDirectory(prefix='gensen-scene-') as td:
   dest=Path(td)/'scene.jpg'
   subprocess.run(['sips','-s','format','jpeg','-Z','1000',str(p),'--out',str(dest)],check=True,capture_output=True)
   raw=dest.read_bytes()
 sceneBytes[key]=base64.b64encode(raw).decode()
avatar_assets=json.loads((HERE.parent/'avatar-assets/figma-payload.json').read_text())
flow_repair_states=[{k:v for k,v in s.items() if k!='original'} for s in json.loads((DATA/'flow-repair-states.json').read_text())]
payload={'schemaVersion':1,'runName':'14 · UI semantic refactor · 2026-10-06','screens':clean,'tokens':json.loads((DATA/'tokens.json').read_text()),'iconNodeIds':iconNodes,'iconSvgs':icons,'assetNames':{a['name'].lower():a['id'] for a in assets},'sceneHashes':sceneHashes,'sceneBytes':sceneBytes,'avatarAssets':avatar_assets,'avatarControlIcons':json.loads((DATA/'avatar-control-icons.json').read_text()),'flowRepairStates':flow_repair_states}
payload['npcFlowStates']=[{k:v for k,v in state.items() if k!='original'} for state in json.loads((DATA/'legacy-npc-flow-states.json').read_text())] if (DATA/'legacy-npc-flow-states.json').exists() else []
payload['freeTravelStates']=json.loads((DATA/'free-travel-flow-states.json').read_text())
payload['freeTravelPassport']=json.loads((DATA/'free-travel-passport.json').read_text())
payload['cropDexData']=json.loads((DATA/'crop-dex.json').read_text())
(HERE/'source-grid-evidence.json').write_text(json.dumps({s['id']:{k:s[k] for k in ['bagContents','quickContents'] if k in s} for s in clean if s.get('bagContents') or s.get('quickContents')},ensure_ascii=False,indent=2)+'\n')
source_files=['src.js','legacy-icon-fixes.js','current-fixes.js','legacy-fixes.js','legacy-scene-fixes.js','legacy-reference-fixes.js','legacy-pin-fixes.js','kitchen-scene-fixes.js','kitchen-selection-fixes.js','action-picker-fixes.js','hud-navigation-fixes.js','legacy-qa-fixes.js','current-qa-fixes.js','camera-highlight-fixes.js','responsive-component-fixes.js','avatar-fixes.js','avatar-integration.js','avatar-polish-fixes.js','visual-polish-fixes.js','hud-lightweight-fixes.js','visual-container-fixes.js','visual-current-containers.js','visual-fishing-fixes.js','visual-kitchen-fixes.js','kitchen-selection-state-fixes.js','current-kitchen-focus-fixes.js','unknown-requirement-fixes.js','p2p3-visual-fixes.js','current-visual-fixes.js','visual-legacy-surfaces.js','flow-repair-fixes.js','legacy-npc-flow-fixes.js','visual-legacy-shops.js','crop-dex-fixes.js','free-travel-flow-fixes.js','avatar-recovery-fixes.js','overlay-cleanup-fixes.js','component-family-fixes.js']
for name in source_files:assert (HERE/name).is_file(),'Missing required source '+name
source='\n'.join((HERE/name).read_text() for name in source_files)
code='// Generated by build.py. Source: src.js. Never edit code.js directly.\nconst BUNDLE = '+json.dumps(payload,ensure_ascii=False,separators=(',',':'))+';\n'+source
(HERE/'code.js.tmp').write_text(code)
(HERE/'code.js.tmp').replace(HERE/'code.js')
summary={'screens':len(screens),'legacy':len(legacy),'current':len(current),'stateExamples':sum(len(s.get('stateExamples',[])) for s in screens),'legacyScreensWithSourceGrid':sum(bool(s.get('bagContents')) for s in clean),'legacySourceCells':sum(len(s.get('bagContents',[])) for s in clean),'sourceIconReferences':len(iconNodes),'vectorFallbacks':len(icons),'sceneHashes':len(sceneHashes),'sceneFallbackImages':len(sceneBytes),'noFullUiScreenshots':True,'sha256':hashlib.sha256(code.encode()).hexdigest(),'bytes':len(code.encode()),'cloudExecuted':False,'avatarRealPartAssets':len(avatar_assets['parts']),'avatarWardrobeVariants':30,'avatarRenderedLookProfiles':29,'avatarDedicatedLayout':True,'flowRepairStateCount':len(flow_repair_states),'npcFlowStateCount':len(payload['npcFlowStates']),'freeTravelStateCount':len(payload['freeTravelStates']),'cropDexEntryCount':len(payload['cropDexData']['entries']),'sourceModuleCount':len(source_files)}
(HERE/'bundle-report.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
dependencies=[HERE/name for name in source_files]+[HERE/'build.py',HERE/'validate.cjs',HERE/'package.py',HERE/'build_gap_ledger.py',HERE/'manifest.json',HERE/'ui.html']
dependencies += [DATA/name for name in ['legacy-screens.json','current-all.json','tokens.json','flow-repair-states.json','legacy-npc-flow-states.json','free-travel-flow-states.json','free-travel-passport.json','crop-dex.json','avatar-control-icons.json','legacy-scene-hashes.json','toolbar-fixture-provenance.json']]
dependencies += [HERE.parent/'avatar-assets/figma-payload.json',ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/approved-kit-state.json',ROOT/'docs/design/p0-flow-2026-10-05/figma/icons.json',ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/content-assets.json',ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/all-asset-components.json',ROOT/'docs/design/p1-p2-flows-2026-10-06/figma/scenes.json']
dependencies += [ROOT/s['sourceHtml'] for s in legacy if s.get('sourceHtml')]
dependencies += [p for p in sceneFiles.values() if p.exists()]
entries=[{'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(set(dependencies))]
manifest={'schemaVersion':1,'bundleSha256':summary['sha256'],'sourceModules':source_files,'sourceModuleCount':len(source_files),'files':entries,'scope':'Exact local build inputs;code.js contains native UI plus source scene and Avatar artwork only. This manifest is not cloud visual acceptance.'}
(HERE/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,indent=2))
