#!/usr/bin/env python3
"""Bundle real Avatar design renders. Does not render, upload or modify game state."""
from pathlib import Path
import json,re,hashlib,base64,struct
OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
source=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())['parts']
labels=dict(re.findall(r'"((?:hairhat|cloth|shoes|messengerbag|glass)[^"]*)": "([^"]+)"',(ROOT/'scenes/dressing_room/parts_panel.gd').read_text()))
slots=[('hairHat','Hair','hairhat43'),('cloth','Outfits','cloth28'),('shoes','Shoes','shoes0'),('messengerBag','Bags','none'),('glass','Glasses','none')]
parts=[];images={};meta={}
for part in source:
 if part['slot'] not in {s[0] for s in slots}:continue
 part_id=part['id'];parts.append({'id':part_id,'slot':part['slot'],'label':labels[part_id],'thumb':f'thumbs/{part_id}.png','preview':f'previews/{part_id}.png'})
for part in parts:
 for kind in ['thumb','preview']:assert (OUT/part[kind]).is_file(),part[kind]
assert (OUT/'previews/base.png').is_file()
files={str(p.relative_to(OUT)).removesuffix('.png'):p for p in sorted([*OUT.joinpath('thumbs').glob('*.png'),*OUT.joinpath('previews').glob('*.png')])}
files['background']=ROOT/'assets/ui/backgrounds/dressing-room.png'
for key,p in files.items():
 data=p.read_bytes();width,height=struct.unpack('>II',data[16:24]);images[key]={'bytes':base64.b64encode(data).decode(),'width':width,'height':height};meta[key]={'file':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(data).hexdigest(),'width':width,'height':height,'bytes':len(data)}
current=json.loads((OUT.parent/'data/current-all.json').read_text());profile=next(s for s in current if s['id']=='PROFILE-1-P0');profile={k:v for k,v in profile.items()if k not in ['original']}
spec={'version':2,'categories':[{'slot':slot,'label':label,'defaultPart':part,'optional':slot in ['messengerBag','glass']}for slot,label,part in slots],'parts':parts,'base':{'hairHat':'hairhat43','cloth':'cloth28','shoes':'shoes0','messengerBag':'','glass':''},'profile':profile,'profileSource':'data/current-all.json#PROFILE-1-P0','noneIconSvg':(ROOT/'assets/ui/icons/none.svg').read_text(),'images':images,'prototypeBoundary':'Each variant is an actual one-part try-on relative to the declared base outfit. Reset uses the actual slot_table.default_config. Free multi-slot combinations, drag rotation and category close-up remain the existing Godot runtime capabilities.'}
(OUT/'figma-payload.json').write_text(json.dumps(spec,ensure_ascii=False,separators=(',',':')))
(OUT/'manifest.json').write_text(json.dumps({**{k:v for k,v in spec.items()if k not in ['images','noneIconSvg']},'images':meta,'engineRenders':len(list(OUT.glob('previews/*.png'))),'partThumbnails':len(list(OUT.glob('thumbs/*.png'))),'resetRenderAvailable':'previews/defaults' in images},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'parts':len(parts),'images':len(images),'resetRenderAvailable':'previews/defaults' in images,'profileRows':len(profile.get('rows',[]))+len(profile.get('items',[])),'payloadBytes':(OUT/'figma-payload.json').stat().st_size}))
