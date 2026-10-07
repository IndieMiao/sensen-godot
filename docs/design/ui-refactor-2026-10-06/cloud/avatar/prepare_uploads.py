#!/usr/bin/env python3
"""Make display copies and bounded Figma image-upload scripts; retain original PNGs."""
from pathlib import Path
import json,base64,hashlib,sys,io
try:
 from PIL import Image,ImageChops,ImageStat
except ImportError as exc:
 raise SystemExit('Pillow is required. Install it with: python3 -m pip install Pillow') from exc
HERE=Path(__file__).resolve().parent
DESIGN=HERE.parents[1]
ASSETS=DESIGN/'avatar-assets'
main=json.loads((HERE.parent/'state.json').read_text())
manifest=json.loads((ASSETS/'manifest.json').read_text())
state_path=HERE/'state.json'
state=json.loads(state_path.read_text()) if state_path.exists() else {'version':1,'pageId':main['pageId'],'assetFrameId':None,'images':{},'avatar':{},'pendingLinks':[],'completed':[],'scripts':{},'receipts':[]}
(HERE/'optimized/thumbs').mkdir(parents=True,exist_ok=True)
(HERE/'optimized/previews').mkdir(parents=True,exist_ok=True)
(HERE/'uploads').mkdir(exist_ok=True)
order=sorted(k for k in manifest['images'] if k.startswith('thumbs/'))+['background','previews/base','previews/defaults']+sorted(k for k in manifest['images'] if k.startswith('previews/')and k not in ['previews/base','previews/defaults'])
records=[]
for index,key in enumerate(order):
 original=DESIGN.parents[2]/manifest['images'][key]['file']
 if key=='background':
  image=Image.open(original).convert('RGB');image.thumbnail((360,540),Image.Resampling.LANCZOS);out=HERE/'optimized/background.jpg';image.save(out,'JPEG',quality=76,optimize=True);format_name='jpg';error=None
 else:
  original_image=Image.open(original).convert('RGBA');out=HERE/'optimized'/f'{key}.png'
  sizes=[360,336,312,288,264,240,216]if key.startswith('previews/')else[160]
  for width in sizes:
   image=original_image.copy();image.thumbnail((width,width*7//6)if key.startswith('previews/')else(width,width),Image.Resampling.LANCZOS)
   encoded=io.BytesIO();image.save(encoded,'PNG',optimize=True,compress_level=9)
   if len(encoded.getvalue())<=32500:break
  if len(encoded.getvalue())>32500:raise ValueError('Cannot fit lossless RGBA display copy: '+key)
  out.write_bytes(encoded.getvalue());error=[0.0,0.0,0.0,0.0];format_name='png'
 data=out.read_bytes();records.append({'key':key,'index':index,'file':str(out.relative_to(HERE)),'width':image.width,'height':image.height,'format':format_name,'bytes':len(data),'sourceSHA':manifest['images'][key]['sha256'],'uploadSHA':hashlib.sha256(data).hexdigest(),'quantizationMeanAbsoluteRGBA':error,'alphaPreservedAtDisplaySize':key!='background','displayCopyMethod':'JPEG'if key=='background'else'RGBA resize + lossless PNG (no color/alpha quantization)','base64':base64.b64encode(data).decode()})
def script(batch,batch_name):
 supplied=[{k:v for k,v in r.items() if k not in ['file','bytes','quantizationMeanAbsoluteRGBA','alphaPreservedAtDisplaySize','displayCopyMethod']}for r in batch]
 return '''const INPUT='''+json.dumps(supplied,separators=(',',':'))+''';
const page=await figma.getNodeByIdAsync('''+json.dumps(main['pageId'])+''');if(!page||page.type!=='PAGE')throw Error('Avatar page missing');await figma.setCurrentPageAsync(page);
const created=[],mutated=[],name='Avatar · source assets · 2026-10-06';let zone=page.children.find(n=>n.name===name&&n.type==='FRAME');if(!zone){zone=figma.createFrame();zone.name=name;zone.resize(1680,1920);zone.x=20000;zone.y=0;zone.fills=[];zone.clipsContent=false;page.appendChild(zone);created.push(zone.id);mutated.push(page.id);}
function bytes(s){const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',out=[];let bits=0,value=0;for(const char of s){if(char==='=')break;const n=alphabet.indexOf(char);if(n<0)continue;value=(value<<6)|n;bits+=6;if(bits>=8){bits-=8;out.push((value>>bits)&255)}}return new Uint8Array(out)}
const images=[];for(const item of INPUT){const hash=figma.createImage(bytes(item.base64)).hash;let node=zone.children.find(n=>n.name==='Avatar source · '+item.key&&n.type==='RECTANGLE');if(!node){node=figma.createRectangle();node.name='Avatar source · '+item.key;zone.appendChild(node);created.push(node.id);mutated.push(zone.id);}else if(node.fills[0]?.imageHash!==hash)mutated.push(node.id);node.resize(160,190);node.x=16+(item.index%8)*208;node.y=16+Math.floor(item.index/8)*232;node.fills=[{type:'IMAGE',imageHash:hash,scaleMode:'FIT'}];images.push({key:item.key,hash,nodeId:node.id,width:item.width,height:item.height,format:item.format,sourceSHA:item.sourceSHA,uploadSHA:item.uploadSHA});}
return {kind:'avatar-asset-upload',batch:'''+json.dumps(batch_name)+''',assetFrameId:zone.id,createdNodeIds:created,mutatedNodeIds:[...new Set(mutated)],images};'''
batches=[];batch=[]
for record in records:
 candidate=batch+[record]
 if len(script(candidate,'upload-999'))>=47000:
  assert batch, f'Asset too large for one call: {record["key"]}'
  batches.append(batch);batch=[record]
 else:batch=candidate
if batch:batches.append(batch)
for index,batch in enumerate(batches):
 name=f'upload-{index:03}';code=script(batch,name);assert len(code)<48000;path=HERE/'uploads'/f'{name}.js';path.write_text(code)
metadata={'sourceImages':len(records),'batches':len(batches),'maxScriptCharacters':max(len((HERE/'uploads'/f'upload-{i:03}.js').read_text())for i in range(len(batches))),'originalsRetained':True,'images':[{k:v for k,v in r.items()if k!='base64'}for r in records]}
(HERE/'upload-manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
if not state_path.exists():state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in metadata.items()if k!='images'},ensure_ascii=False))
