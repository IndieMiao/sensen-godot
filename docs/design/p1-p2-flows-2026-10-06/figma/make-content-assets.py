import json,re,xml.etree.ElementTree as E
from pathlib import Path
p=Path('docs/design/p1-p2-flows-2026-10-06');out=p/'assets';base=json.loads(Path('docs/design/p0-flow-2026-10-05/figma/icons.json').read_text());source=Path('docs/product/gameplay-plan-v2-2026-10-02.md').read_text().splitlines();assets=[]
def svg(x):return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'+x+'</svg>'
def ellipse(x,y,rx,ry,c):return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{c}"/>'
def rect(x,y,w,h,r,c):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{c}"/>'
def path(d,c):return f'<path d="{d}" fill="{c}"/>'
def save(id,name,cat,image,source='new native vector draft',extra=None):
 (out/(id+'.svg')).write_text(image);assets.append(dict(id=id,name=name,category=cat,svg=image,source=source,**(extra or {})))
def leaves():return path('M32 27C12 26 12 11 17 9c10 0 16 6 15 18z','#7FC66A')+path('M32 26c0-13 9-18 20-17 2 12-6 18-20 17z','#5FA85A')+rect(30,16,4,23,2,'#5FA85A')
extra={
'lettuce':ellipse(32,38,23,19,'#94BF6C')+ellipse(23,30,13,13,'#B8D891')+ellipse(39,29,14,14,'#A4CD7D')+ellipse(30,42,15,12,'#C9DDA7'),
'herb':leaves()+path('M32 55V22','none'),
'potato':ellipse(31,36,23,16,'#D5BA8A')+ellipse(20,33,2,1.5,'#B39267')+ellipse(40,30,2,1.5,'#B39267')+ellipse(35,43,2,1.5,'#B39267'),
'chamomile':''.join(ellipse(32+dx,27+dy,7,7,'#FBF8F1') for dx,dy in [(0,-10),(10,-3),(6,9),(-6,9),(-10,-3)])+ellipse(32,27,7,7,'#E3B341')+rect(30,37,4,21,2,'#7FC66A'),
'chili':leaves()+path('M29 26C55 22 54 49 21 58c13-16 3-20 8-32z','#E07A5F'),
 'tomato':ellipse(32,39,22,19,'#E78D70')+path('M32 20l6 8 12-4-7 9-11-3-12 3-6-9 12 4z','#6FAE63'),
 'cabbage':ellipse(32,35,23,22,'#96BDA0')+ellipse(28,34,17,19,'#BDD8AA')+ellipse(35,33,11,16,'#D5E6BE'),
 'corn':ellipse(32,34,11,23,'#EBC665')+path('M20 22C9 39 19 57 34 59L20 22z','#7FB979')+path('M43 22c13 13 2 35-11 37l11-37z','#609B69')+''.join(ellipse(x,y,2.1,2.4,'#F4DA88') for x in [28,34] for y in [18,26,34,42]),
 'cucumber':rect(10,21,44,24,12,'#79AA74')+''.join(ellipse(x,28,1.5,1.5,'#B6D493') for x in [20,30,40]),
 'strawberry':path('M12 27c6-13 33-13 40 0 4 13-13 31-20 32-8-2-25-19-20-32z','#E78D8A')+path('M15 17l12 3 5-8 7 8 12-3-7 10H21z','#7FB979')+''.join(ellipse(x,y,1.2,2,'#F4DCA5') for x,y in [(23,31),(39,31),(31,40),(22,42),(38,43)]),
 'melon':ellipse(32,36,24,20,'#B8C987')+path('M30 17q-5-12 5-13v16z','#7CAA65')+''.join(f'<path d="M{x} 19q-9 18 0 35" fill="none" stroke="#D4DDA6" stroke-width="2"/>' for x in [24,35,43]),
 'pineapple':ellipse(32,40,17,21,'#E6BE64')+path('M32 25L16 9l13 4 3-11 5 12 14-7-13 18z','#75B180')+''.join(f'<path d="M17 {y}l30 12M17 {y+12}l30-12" stroke="#C99E54" fill="none" stroke-width="1.5"/>' for y in [30,40]),
 'pumpkin':ellipse(21,37,12,19,'#E5A45E')+ellipse(43,37,12,19,'#E5A45E')+ellipse(32,37,14,22,'#F0BC70')+rect(29,9,6,12,3,'#91A571'),
 'beet':leaves()+ellipse(31,39,19,17,'#BF8094')+path('M29 51l8 10-3-13z','#BF8094')}
for l in source[1499:1530]:
 a=[x.strip() for x in l.strip('|').split('|')]
 if a and re.fullmatch(r'`crop_\w+`',a[0]):
  id=a[0].strip('`');name=a[2];short=id[5:];key='i-'+short.replace('_','-');im=base.get(key) or svg(extra[short]);save(id,name,'crop',im,'existing '+key if key in base else 'new native vector draft')
for id,name,key in [('crop_apple','Apple','i-apple'),('crop_citrus','Citrus','i-citrus'),('crop_grape','Grapes','i-grape')]:save(id,name,'crop',base[key],'existing '+key)
fish=[]
for l in source[1853:1890]:
 a=[x.strip() for x in l.strip('|').split('|')]
 if a and re.fullmatch(r'fish_\w+',a[0]):fish.append((a[0],a[2],a[3]))
pal=['#A9C5BA','#DFA65E','#A9BCC2','#91B8A2','#9AAE85','#A9C5D4','#94B4C3','#E9C76D','#A4A9B9','#88A9B2','#BFC8CC','#A3B99D','#A1BFB7','#BED0D6','#B3CBA9','#CFB8B2','#A5B995','#C1BA8C','#B9C6B7','#D8B3A5']
for i,(id,name,rar) in enumerate(fish):
 elongated=id in ['fish_mullet','fish_smelt','fish_pike','fish_sturgeon','fish_barramundi'];ry=8 if elongated else 13;col=pal[i]
 if id=='fish_eel':body='<path d="M10 23C39 3 57 23 45 36S21 48 45 54" fill="none" stroke="'+col+'" stroke-width="12" stroke-linecap="round"/>'+ellipse(13,23,7,7,col)+ellipse(10,21,2,2,'#2F3A33')
 else:
  body=path(f'M48 32 61 {32-ry}v{ry*2}z',col)+ellipse(29,32,22,ry,col)+ellipse(29,36,15,ry*.4,'#DDE5DB')+path(f'M24 {32-ry}q9-11 19 1z',col)+ellipse(15,29,3.5,3.5,'#FBF8F1')+ellipse(14,29,1.7,1.7,'#2F3A33')
  if id in ['fish_perch','fish_mackerel','fish_tilapia']:body+=''.join(f'<path d="M{x} 22l2 16" stroke="#6E8C86" stroke-width="2.8" stroke-linecap="round"/>' for x in [26,33,40])
  if id in ['fish_trout','fish_arctic_char','fish_salmon']:body+=''.join(ellipse(x,y,1.4,1.4,'#8B8C99') for x,y in [(25,26),(35,24),(43,30),(30,33),(38,34)])
  if id=='fish_koi':body+=ellipse(28,28,7,6,'#E29170')+ellipse(42,32,5,7,'#FBF8F1')
  if id=='fish_catfish':body+='<path d="M10 34L3 41M12 35l-1 11" stroke="#879399" stroke-width="2" fill="none" stroke-linecap="round"/>'
  if id=='fish_sturgeon':body+=''.join(path(f'M{x} 26l4-5 4 5z','#ECEDDE') for x in [20,28,36])
 save(id,name,'fish',svg(body),extra={'rarity':rar})
styles={}
for l in source[2879:2980]:
 a=[x.strip() for x in l.strip('|').split('|')]
 if len(a)>8 and a[0].isdigit() and a[1].startswith('dish_'):
  id,name=a[1],a[3];style=a[8];ix=int(a[0]);basekey='i-dish-soup' if style=='Soup' else 'i-dish-stew' if style=='Stew' else 'i-dish-salad' if style=='Salad' else 'i-dish-cake' if style=='Dessert' else 'i-tea' if style=='Tea' else 'i-dish-grilled'
  basekey=next((k for word,k in [('Skewers','i-dish-skewer'),('Cakes','i-dish-cakes'),('Biscuits','i-dish-biscuit'),('Pie','i-dish-pie'),('Plate','i-dish-plate'),('Platter','i-dish-plate')] if word in name),basekey)
  original=base[basekey];garnish=''
  for j,c in enumerate(['#7FB979','#E8BD65','#DB997F'][ix%3:]+['#7FB979','#E8BD65','#DB997F'][:ix%3]):garnish+=ellipse(24+j*8,33+(ix%2)*3,2+(ix+j)%2,2,c)
  if 'chili' in l or 'Spicy' in name:garnish+=path('M30 27q14-3 9 9l-10 3q8-7 1-12z','#D98170')
  if 'salt' in l:garnish+=''.join(ellipse(x,28,1,1,'#FBF8F1') for x in [26,32,38])
  im=original.replace('</svg>',garnish+'</svg>');save(id,name,'dish',im,'existing '+basekey+' with recipe garnish variant',{'style':style,'recipe':a[5],'page':ix})
res=[]
for l in source[3954:3970]:
 a=[x.strip() for x in l.strip('|').split('|')]
 if a and re.fullmatch(r'`res_\w+`',a[0]):res.append((a[0].strip('`'),a[1].split(' / ')[-1]))
for i,(id,name) in enumerate(res):
 skin=['#F6D7BC','#EAC6A3','#DDB390'][i%3];hair=['#846C55','#C2BAB0','#694F43','#B28F62'][i%4];cloth=['#E3B341','#A6B9A1','#AF9EC2','#779DA9','#C49577'][i%5]
 body=path('M7 64v-5c0-15 50-15 50 0v5z',cloth)+ellipse(32,34,22,24,hair)+ellipse(32,37,19,20,skin)+path('M13 29c0-24 39-25 39 0L39 16l-8 9-8-6-10 10z',hair)+ellipse(24,37,2.4,2.8,'#2F3A33')+ellipse(40,37,2.4,2.8,'#2F3A33')+'<path d="M27 47q5 4 10 0" fill="none" stroke="#A67761" stroke-width="2" stroke-linecap="round"/>'
 if id in ['res_pip','res_sam','res_ivo','res_old_kai']:body=body+path('M10 23c2-24 42-24 44 0z',cloth)+rect(7,22,50,6,3,cloth)
 if id in ['res_granny_wu','res_tomo']:body+='<circle cx="24" cy="37" r="7" fill="none" stroke="#8D9287" stroke-width="2"/><circle cx="40" cy="37" r="7" fill="none" stroke="#8D9287" stroke-width="2"/><path d="M31 37h2" stroke="#8D9287" stroke-width="2"/>'
 if id=='res_ivo':body+=ellipse(32,18,5,5,'#F4D27A')
 if id=='res_nadia':body+=ellipse(20,14,9,9,'#FBF8F1')+ellipse(32,10,12,11,'#FBF8F1')+ellipse(44,14,9,9,'#FBF8F1')
 save(id,name,'resident',svg(body),'new native portrait draft; not a 3D character model')
assert {c:sum(a['category']==c for a in assets) for c in ['crop','fish','dish','resident']}=={'crop':20,'fish':20,'dish':48,'resident':12}
(p/'figma/content-assets.json').write_text(json.dumps(assets,ensure_ascii=False,indent=2));print('Native content assets',len(assets))
