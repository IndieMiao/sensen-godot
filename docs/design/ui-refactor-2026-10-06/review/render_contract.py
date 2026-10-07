from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
P=Path(__file__).resolve().parents[1];ROOT=P.parents[2]
S=2; W,H=360*S,800*S
FONT=ROOT/'assets/ui/fonts/Nunito.ttf';CN=ROOT/'assets/ui/fonts/NotoSansSC-Regular.otf'
def font(size,bold=False,cn=False):
 f=ImageFont.truetype(str(CN if cn else FONT),round(size*S))
 if bold and not cn:
  try:f.set_variation_by_name('ExtraBold')
  except Exception:pass
 return f
C={'paper':'#FBF8F1','ink':'#2F3A33','secondary':'#5D6A62','green':'#3E7D43','tint':'#ECF4E7','line':'#E1DAC8','warning':'#FFF0D4','danger':'#9C3F2E'}
def rr(im,box,color,r=14,outline=None):ImageDraw.Draw(im).rounded_rectangle(tuple(int(x*S) for x in box),radius=int(r*S),fill=color,outline=outline,width=S)
def txt(im,xy,value,size=14,color='ink',bold=False,align='left',width=None):
 d=ImageDraw.Draw(im);f=font(size,bold);x,y=xy
 if width:
  words=value.split();lines=[];line=''
  for word in words:
   candidate=(line+' '+word).strip()
   if line and d.textlength(candidate,font=f)>width*S:lines.append(line);line=word
   else:line=candidate
  if line:lines.append(line)
 else:lines=value.split('\n')
 for line in lines:
  xx=x*S
  if align=='right':xx-=d.textlength(line,font=f)
  if align=='center':xx-=d.textlength(line,font=f)/2
  d.text((xx,y*S),line,font=f,fill=C.get(color,color));y+=size*1.35
 return y

def icon(im,name,x,y,size=30):
 f=P/'preview/icons'/(name+'.png')
 if f.exists():
  a=Image.open(f).convert('RGBA');a.thumbnail((size*S,size*S));im.paste(a,(int(x*S),int(y*S)),a)

def base(scene='farm'):
 im=Image.new('RGB',(W,H),'#BFD7C8');b=Image.open(ROOT/'docs/design/ui-anchors-2026-10-03/scenes'/(scene+'.png')).convert('RGB');b=ImageOps.fit(b,(W,H));im.paste(b)
 shade=Image.new('RGBA',im.size,(33,55,33,35));im=Image.alpha_composite(im.convert('RGBA'),shade).convert('RGB')
 rr(im,(12,18,150,60),C['paper'],20);txt(im,(24,24),'142 / 200',15,bold=True);rr(im,(23,49,135,53),'#D8E2D1',2);rr(im,(23,49,103,53),C['green'],2)
 rr(im,(242,18,306,60),C['paper'],20);icon(im,'i-coin',250,27,17);txt(im,(293,26),'230',14,bold=True,align='right')
 rr(im,(314,18,348,60),C['paper'],18);icon(im,'i-home',321,30,20)
 return im

def sheet(im,title,state,qty=None,effect='',y=282):
 rr(im,(0,y,360,850),C['paper'],24);rr(im,(163,y+10,197,y+14),'#D7D7C8',2)
 txt(im,(16,y+30),title,20,bold=True,width=245)
 if qty:txt(im,(344,y+26),qty[0],24,bold=True,align='right');txt(im,(344,y+57),qty[1],12,'secondary',align='right')
 if state:
  rr(im,(16,y+62,95,y+86),C['tint'],12);txt(im,(25,y+65),state,12,'green',True)
 if effect:txt(im,(16,y+105),effect,15,bold=True,width=324)
 return y+160

def nav(im,y,label):
 txt(im,(18,y+13),label,14,bold=True);icon(im,'i-chev-r',324,y+17,14);ImageDraw.Draw(im).line((16*S,(y+48)*S,344*S,(y+48)*S),fill=C['line'],width=S)

def command(im,y,label,danger=False):rr(im,(16,y,344,y+46),C['danger'] if danger else C['green'],23);txt(im,(180,y+12),label,15,'#FFFFFF',True,'center')

a=base('farm-facilities');y=sheet(a,'Sprinkler','Can craft',('2 / 7','placed'),'Automatically waters the eight surrounding plots.',270)
rr(a,(16,y,344,y+64),C['tint']);txt(a,(30,y+10),'OCCUPIES',12,'secondary');txt(a,(30,y+29),'1 plot',18,bold=True);txt(a,(183,y+10),'GROWTH TIME',12,'secondary');txt(a,(183,y+29),'15% faster',18,bold=True)
nav(a,520,'Details & unlock conditions');txt(a,(16,588),'Materials used',12,'secondary',True)
for i,(name,ic,v) in enumerate([('Timber','i-wood','8 / 8'),('Stone','i-stone','6 / 6'),('Copper','i-copper','3 / 3')]):
 x=29+i*111;ImageDraw.Draw(a).ellipse((x*S,615*S,(x+44)*S,659*S),outline=C['green'],width=4*S);icon(a,ic,x+8,623,28);txt(a,(x+22,664),name,12,'secondary',align='center');txt(a,(x+22,681),v,14,bold=True,align='center')
command(a,718,'Craft');a.save(P/'review/sprinkler-concept.png')
b=base('map-tile');y=sheet(b,'Tokyo','In transit',('7:42','remaining'),'Your trip is underway.',330);rr(b,(16,505,344,565),C['tint']);txt(b,(30,515),'WHILE TRAVELLING',12,'secondary');txt(b,(30,535),'Your farm stays open',15,bold=True);nav(b,586,'Travel guide');nav(b,638,'Return to farm');rr(b,(16,710,344,756),C['paper'],23,C['danger']);txt(b,(180,722),'Cancel trip',15,'danger',True,'center');b.save(P/'review/travel-concept.png')
c=base('farm');y=sheet(c,'Mia’s invitation','Waiting',None,'Visit Mia’s room in Tokyo.',298);rr(c,(16,469,344,542),C['warning']);txt(c,(30,479),'YOU PAY',12,'secondary',True);icon(c,'i-energy',30,505,22);txt(c,(62,500),'20 Energy',24,bold=True);txt(c,(16,566),'Invitation expires',13,'secondary');txt(c,(344,562),'28:40',19,bold=True,align='right');nav(c,610,'Invitation details');command(c,686,'Accept invitation');txt(c,(180,745),'Decline',15,'secondary',True,'center');c.save(P/'review/invitation-concept.png')
board=Image.new('RGB',(W*3+S*64,H+S*100),'#E8ECE5');d=ImageDraw.Draw(board);d.text((16*S,14*S),'信息与操作职责 · 重构规范示意',font=font(22,cn=True),fill=C['ink']);d.text((16*S,48*S),'本地设计示意，非云端 Figma 回读；全文页面见离线审阅稿。',font=font(12,cn=True),fill=C['secondary'])
for i,x in enumerate([a,b,c]):board.paste(x,((16+i*376)*S,82*S))
board.save(P/'review/component-direction.png');print('3 visual contract cards and board rendered')
