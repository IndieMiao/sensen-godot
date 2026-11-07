"""Preserve binary FBX geometry/rig properties; repoint only unused/source material image links.
The actual clothing material is supplied by recipes_gabriel.json at extraction.
"""
from pathlib import Path
import struct,subprocess,hashlib,json
R=Path(__file__).resolve().parents[4]
REF='8493a5c4258db3e59b2b845c83d3ee5b34724156'
raw=subprocess.check_output(['git','show',REF+':assets/avatar/source/cloth36_npc_sigrid/SK_dt_skin36.fbx'],cwd=R)
assert struct.unpack_from('<I',raw,23)[0]==7500
changes=[]
def node(pos,outpos):
 end,count,plen,nlen=struct.unpack_from('<QQQB',raw,pos)
 if end==0:return b'\0'*25,pos+25
 name=raw[pos+25:pos+25+nlen];p0=pos+25+nlen;props=raw[p0:p0+plen];cursor=p0+plen
 if name in [b'FileName',b'RelativeFilename',b'Filename']:
  assert count==1 and props[:1]==b'S'
  old=props[5:];new=b'T_gabriel_cloth_D.png'
  changes.append({'field':name.decode(),'before':old.decode(),'after':new.decode()})
  props=b'S'+struct.pack('<I',len(new))+new
 children=b''
 while cursor<end:
  child,cursor=node(cursor,outpos+25+nlen+len(props)+len(children));children+=child
 assert cursor==end
 size=25+nlen+len(props)+len(children)
 return struct.pack('<QQQB',outpos+size,count,len(props),nlen)+name+props+children,end
out=raw[:27];pos=27
while True:
 item,pos=node(pos,len(out));out+=item
 if item==b'\0'*25:break
out+=raw[pos:]
dst=R/'assets/avatar/source/cloth36_npc_gabriel/SK_dt_skin36.fbx';dst.write_bytes(out)
report={'donor_ref':REF,'donor_sha256':hashlib.sha256(raw).hexdigest(),'delivered_sha256':hashlib.sha256(out).hexdigest(),'changes':changes,'non_image_properties_byte_preserved':True,'note':'Only FBX filename string properties plus enclosing byte offsets changed; no mesh, UV, bones, skin or transforms edited. Ancillary donor body/eyes/shoes are never extracted.'}
(R/'tools/art/source/gabriel_423/fbx-provenance.json').write_text(json.dumps(report,indent=2)+'\n');print(len(changes),'image paths repointed',report['delivered_sha256'])
