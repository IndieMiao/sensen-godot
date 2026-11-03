"""Build approved B atlases without changing any A texture or model."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image,ImageDraw

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/skin-325-v1'
OUT.mkdir(parents=True,exist_ok=True)
SLOTS=json.loads((ROOT/'assets/rooms/_shared/shell_hall/hall_palette.json').read_text())['slots']
report={'stage':'B v1 from approved palette v0.1','author':'黄忠','rooms':{},'adjustments':[]}
def rgb(value):return np.array(list(bytes.fromhex(value)),dtype=float)
def replace(atlas,slot,old,new):
    x,y,w,h=SLOTS[slot]['rect_px_top_left'];patch=atlas[y:y+h,x:x+w,:3]
    modulation=np.median(patch.astype(float)/rgb(old),axis=2)
    atlas[y:y+h,x:x+w,:3]=np.clip(modulation[:,:,None]*rgb(new),0,255).astype('uint8')

for room in ['poi_hotel_lobby','poi_service_hall']:
    n1=room=='poi_hotel_lobby';filename='room_albedo_ao.png' if n1 else 'hall_albedo_ao_n2.png'
    source=ROOT/'assets/rooms'/room/filename
    atlas=np.array(Image.open(source).convert('RGBA'));original=atlas.copy();changes=[]
    if n1:
        known={key:slot['hex_srgb'] for key,slot in SLOTS.items()};known.update(wood_dark='783B22',stone='8C8376')
        colors={'plaster':'F3ECE2','plaster_solid':'F3ECE2','parquet':'D7B48A','floor_solid':'D7B48A',
            **{key:'A97B52' for key in ['panel','cornice','skirting','window','wainscot_solid','cornice_solid','window_solid','wood_dark','wood_mid','oak','oak_light','oak_edge']},
            'brass':'C9A04E'}
        for key,new in colors.items():replace(atlas,key,known[key],new);changes.append({'slot':key,'from':known[key],'to':new})
        x,y,w,h=SLOTS['cloth_green']['rect_px_top_left'];patch=original[y:y+h,x:x+w,:3]
        border=(patch[:,:,0]>patch[:,:,1])&(patch[:,:,0]>120)
        target=np.clip(np.median(patch.astype(float)/rgb('567E4A'),axis=2)[:,:,None]*rgb('8DBDB6'),0,255).astype('uint8')
        target[border]=rgb('C9A04E');target[h//2-12:h//2+13,w//2-12:w//2+13]=rgb('5E9AA0')
        atlas[y:y+h,x:x+w,:3]=target
        changes += [{'slot':'cloth_green:center','from':'42683A','to':'5E9AA0'},
            {'slot':'cloth_green:rug','from':'567E4A','to':'8DBDB6'}]
        for key in ['linen','porcelain','print_portrait','print_landscape','sky','leaf','leaf_light','leaf_dark']:
            x,y,w,h=SLOTS[key]['rect_px_top_left'];assert np.array_equal(atlas[y:y+h,x:x+w],original[y:y+h,x:x+w]),key
    else:
        skin=json.loads((ROOT/'assets/rooms'/room/'room_skin.json').read_text())
        known={key:slot['hex_srgb'] for key,slot in SLOTS.items()};known.update(skin['overrides'])
        colors={'plaster':'EEF3EE','plaster_solid':'CFB48C','panel':'DCE7DF','wainscot_solid':'DCE7DF',
            'skirting':'CFB48C','window':'CFB48C','window_solid':'CFB48C','cornice':'CFB48C','cornice_solid':'CFB48C',
            'floor_solid':'E4E2DA','cloth_green':'5F9680','print_landscape':'3E9E6A',
            **{key:'CFB48C' for key in ['wood_mid','oak','oak_light','oak_edge']}}
        for key,new in colors.items():
            assert key not in skin['plant_reserved_slots']
            replace(atlas,key,known[key],new);changes.append({'slot':key,'from':known[key],'to':new})
        patch=original[:1024,:1024,:3];path=np.all(patch==rgb('6180A3'),axis=2)
        target=np.clip(np.median(patch.astype(float)/rgb('DFD1B4'),axis=2)[:,:,None]*rgb('E4E2DA'),0,255).astype('uint8')
        target[path]=rgb('7FB59C');atlas[:1024,:1024,:3]=target
        changes += [{'slot':'parquet:tiles','from':'DFD1B4','to':'E4E2DA'}, {'slot':'parquet:cross-and-ring','from':'6180A3','to':'7FB59C'}]
        for item in skin['plant_tiles']:
            x,y=item['target_px'];assert np.array_equal(atlas[y:y+128,x:x+128],original[y:y+128,x:x+128]),item
    dest=ROOT/'assets/rooms'/room;dest.mkdir(parents=True,exist_ok=True)
    path=dest/'room_albedo_ao_b.png';Image.fromarray(atlas).save(path)
    report['rooms'][room]={'source':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'b_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'changes':changes,'texture_dimensions':[2048,2048]}

sign=Image.new('RGBA',(1024,192),'#F3ECE2')
sign.save(ROOT/'assets/rooms/poi_hotel_lobby/sign_b.png')
sign=Image.new('RGBA',(880,230),'#F7FBF7');draw=ImageDraw.Draw(sign)
draw.rectangle((35,91,175,139),fill='#3E9E6A');draw.rectangle((81,45,129,185),fill='#3E9E6A')
sign.save(ROOT/'assets/rooms/poi_service_hall/sign_b.png')
(OUT/'palette-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('Two approved 2048px B atlases and blank sign patches ready')
