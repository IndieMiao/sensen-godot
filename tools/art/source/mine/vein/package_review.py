"""Sign and package the original-resolution four-band plus guard-floor sheet."""
from pathlib import Path
import hashlib
import json
import argparse
import numpy as np
from PIL import Image,ImageDraw,ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
OUT=ROOT/'output/mine-vein-355'
parser=argparse.ArgumentParser();parser.add_argument('--preview-only',action='store_true');parser.add_argument('--stage',choices=['v0','v1','v1.1','v1.2'],default='v1.2');args=parser.parse_args()
DOC=ROOT/'docs/design/mine-vein-355-2026-11-02'/args.stage;DOC.mkdir(parents=True,exist_ok=True)
prefix='SGODOT-355_mine_vein_'+args.stage+'_'
runtime=ROOT/'output/monsters-355/runtime/assets/mine/types/vein'
glb=json.loads((OUT/'glb-validation.json').read_text())
godot=json.loads((OUT/'captures/godot-validation.json').read_text())
assert glb['passed'] and godot['passed']
assert (OUT/'project/assets/mine/types/vein/backdrop.glb').read_bytes()==(runtime/'backdrop.glb').read_bytes()
assert (OUT/'project/assets/mine/types/vein/palette.json').read_bytes()==(runtime/'palette.json').read_bytes()
for name in ['import.log','render.log']:
    assert 'ERROR:' not in (OUT/name).read_text(),name
fontpath='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
large=ImageFont.truetype(fontpath,30);small=ImageFont.truetype(fontpath,23)
canvas=Image.new('RGB',(3600,1810),'#EBECEE');draw=ImageDraw.Draw(canvas)
draw.text((20,12),'SGODOT-355 / Vein '+args.stage+' / 43 deg / 720 x 1600 per frame',font=large,fill='#26313A')
draw.text((1500,18),'Swatches: ground / wall / backdrop / void',font=small,fill='#26313A')
draw.text((3240,12),'制作：黄忠',font=large,fill='#26313A')
palette=json.loads((runtime/'palette.json').read_text())
comparisons=[];individual=[]
for i,key in enumerate(['band_1','band_2','band_3','band_4','guard_f40']):
    band=palette['bands'][min(i,3)]
    image=Image.open(OUT/'captures'/(key+'.png')).convert('RGB');assert image.size==(720,1600)
    baseline=Image.open(OUT/'captures'/(key+'_without_backdrop.png')).convert('RGB')
    original=np.array(baseline);actual=np.array(image);flat=original.reshape(-1,3)
    colours,counts=np.unique(flat,axis=0,return_counts=True);clear=colours[counts.argmax()]
    foreground=np.any(original!=clear,axis=2)
    diff=np.abs(actual.astype(np.int16)-original.astype(np.int16))
    comparisons.append({'view':key,'clear_rgb':clear.tolist(),'foreground_pixels':int(foreground.sum()),
        'foreground_max_channel_delta':int(diff[foreground].max()),'changed_foreground_pixels':int(np.any(diff[foreground]>0,axis=1).sum())})
    label=f'F{band["from"]}-{band["to"]}' if i<4 else 'F40 / guard arena'
    draw.text((i*720+16,59),label,font=large,fill='#26313A')
    for j,field in enumerate(['ground','wall','backdrop_tint','fog']):
        x=i*720+16+j*176;draw.rectangle((x,106,x+24,130),fill=band[field])
        draw.text((x+32,102),band[field],font=small,fill='#26313A')
    canvas.paste(image,(i*720,146))
    if not args.preview_only and (args.stage=='v1' or (args.stage=='v1.2' and key=='band_4')):
        single=image.copy();stamp=ImageDraw.Draw(single)
        stamp.text((16,1550),label+' / vein '+args.stage,font=small,fill='#D9DDE1')
        stamp.text((584,1550),'【黄忠】',font=small,fill='#D9DDE1')
        filename=(f'band_{band["from"]:02d}_{band["to"]:02d}' if i<4 else 'guard_40')+'.jpg'
        frame=DOC/(prefix+filename);single.save(frame,quality=94,subsampling=0,optimize=True);individual.append(frame)
draw.text((20,1758),'All four bands: player + slime + bat + shroomling + beetle + iron / quartz / coal / copper.  Backdrop: '+str(glb['geometry']['triangles'])+' tris / 1 surface / 0 textures.',font=small,fill='#26313A')
path=(OUT/'review-preview.jpg') if args.preview_only else DOC/(prefix+'bands.jpg')
canvas.save(path,quality=91,subsampling=0,optimize=True)
assert path.stat().st_size<8*1024*1024
assert all(row['foreground_max_channel_delta']<=1 for row in comparisons),comparisons
if args.preview_only:
    (OUT/'foreground-validation.json').write_text(json.dumps(comparisons,indent=2)+'\n')
    print(path,json.dumps(comparisons));raise SystemExit(0)
colour_audit=None;inherited=None
if args.stage in ['v1.1','v1.2']:
    accepted=json.loads((DOC.parent/'v1/SGODOT-355_mine_vein_v1_validation.json').read_text())
    colour_audit=json.loads((OUT/'quartz-colour-validation.json').read_text())
    assert colour_audit['passed'] and colour_audit['baseline_sha256']==accepted['glb']['geometry']['sha256']
    assert colour_audit['sha256']==hashlib.sha256((runtime/'backdrop.glb').read_bytes()).hexdigest()
    depth=accepted['depth'];outline=accepted['outline_raster_comparison']
    inherited={'stage':'v1','glb_sha256':colour_audit['baseline_sha256'],
        'reason':'Only quartz RGB bytes change; all geometry, UV, normals, indices, materials and other colours are identical.'}
else:
    depth_name='depth-validation-v1.json' if args.stage=='v1' else 'depth-validation.json'
    depth=json.loads((OUT/depth_name).read_text())
assert len(depth['cases'])==10 and all(case['worst']['far_margin']>=.05 and case['near_margin']>0 for case in depth['cases'])
assert depth['zoom_step']==.01 and depth['across_step']==.05 and depth['down_step']==.1
if args.stage not in ['v1.1','v1.2']:assert 'ERROR:' not in (OUT/('depth-v1.log' if args.stage=='v1' else 'depth.log')).read_text()
uv2=json.loads((OUT/'uv2-empty/uv2-report.json').read_text())
assert uv2['backdrop.glb']['mask_0_vertices']>0 and uv2['backdrop.glb']['mask_1_vertices']>0
assert uv2['backdrop.glb']['other_vertices']==0 and uv2['backdrop.glb']['non_gray_mask_0_vertices']==0
assert (OUT/'uv2-empty/backdrop.glb').read_bytes()==(runtime/'backdrop.glb').read_bytes()
if args.stage not in ['v1.1','v1.2']:outline=json.loads((OUT/'outline-validation.json').read_text()) if args.stage=='v1' else None
assert args.stage=='v0' or outline['passed']
contrast=None
if args.stage=='v1.2':
    contrast=json.loads((OUT/'ore-contrast-validation.json').read_text());assert contrast['passed']
    for row in contrast['bands']:
        for name,digest in row['images'].items():assert hashlib.sha256((OUT/'captures'/(name+'.png')).read_bytes()).hexdigest()==digest
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','stage':args.stage,
    'glb':glb,'godot':godot,'depth':depth,'foreground_comparisons':comparisons,
    'gltf_document_uv2':uv2,'vein_mask':1,'outline_raster_comparison':outline,
    'colour_byte_audit':colour_audit,'inherited_geometry_validation':inherited,'rendered_ore_contrast':contrast,
    'review_shader_formula':'mix(mix(COLOR.rgb * floor_tint, COLOR.rgb, UV2.y * vein_mask), void_tint, UV2.x)',
    'palette':palette,'provenance':json.loads((SRC/'reuse_provenance.json').read_text()),
    'dependencies':json.loads((OUT/'dependencies.json').read_text())}
validation=DOC/(prefix+'validation.json');validation.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
media=[{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
    'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in [path,*individual,validation]]
(DOC/'media-manifest.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'sheet':str(path),'bytes':path.stat().st_size,'far_margin_min':min(c['worst']['far_margin'] for c in depth['cases']),
    'full_depth_views':sum(c['views'] for c in depth['cases']),'foreground_comparisons':comparisons},indent=2))
