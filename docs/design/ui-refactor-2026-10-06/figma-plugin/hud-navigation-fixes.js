/* Compact second HUD row: Today + Location. Append after the existing HUD wrappers.
 * Optional counters are hidden unless explicit unread/task counts are provided.
 */
const HUD_NAVIGATION_BASE={library};
async function ensureHudNavigation(main){
 if(!main||main.type!=='COMPONENT')throw Error('Shared HUD master is required.');
 const created=new Set(),mutated=new Set([main.id]);
 const fonts=new Map();for(const n of main.findAllWithCriteria({types:['TEXT']}))for(const seg of n.getStyledTextSegments(['fontName']))fonts.set(seg.fontName.family+'|'+seg.fontName.style,seg.fontName);for(const f of fonts.values())await figma.loadFontAsync(f);
 const status=main.children.find(n=>n.name==='Status');const location=main.findOne(n=>n.type==='TEXT'&&n.name==='Location');if(!status||!location)throw Error('Existing HUD Status and Location are required.');
 let row=main.children.find(n=>n.name==='HUD second row');
 if(!row){row=horizontal(main,'HUD second row',328,8);created.add(row.id);row.resize(328,20);row.primaryAxisSizingMode='FIXED';row.counterAxisSizingMode='FIXED';
  const today=horizontal(row,'Today navigation',88,4);created.add(today.id);today.resize(88,20);today.primaryAxisSizingMode='FIXED';today.counterAxisSizingMode='FIXED';
  const title=ctext(main,today,'Today label','Today',40,'body','text','Bold');created.add(title.id);
  const badge=frame(today,'Today count badge',24,18,'primaryTint');created.add(badge.id);radius(badge,9);const count=ctext(main,badge,'Today count','',24,'caption','primary','ExtraBold');created.add(count.id);count.textAlignHorizontal='CENTER';absolute(count,0,0);cvisible(main,badge,'Show Today badge',false);
  const caret=ctext(main,today,'Today chevron','⌄',8,'caption','secondary','Bold');created.add(caret.id);
  const place=horizontal(row,'Location navigation',232,4);created.add(place.id);place.resize(232,20);place.primaryAxisSizingMode='FIXED';place.counterAxisSizingMode='FIXED';place.appendChild(location);mutated.add(location.id);location.resize(216,18);location.textAutoResize='HEIGHT';location.textTruncation='ENDING';location.maxLines=1;
  const arrow=ctext(main,place,'Location chevron','›',12,'body','secondary','Bold');created.add(arrow.id);
  main.insertChild(main.children.indexOf(status)+1,row);
 }
 let inboxBadge=main.findOne(n=>n.name==='Inbox unread badge');
 if(!inboxBadge){inboxBadge=frame(status,'Inbox unread badge',24,18,'primary');created.add(inboxBadge.id);radius(inboxBadge,9);absolute(inboxBadge,302,-2);const count=ctext(main,inboxBadge,'Inbox unread count','',24,'caption','surface','ExtraBold');created.add(count.id);count.textAlignHorizontal='CENTER';absolute(count,0,0);cvisible(main,inboxBadge,'Show Inbox badge',false);}
 main.primaryAxisSizingMode='AUTO';main.counterAxisSizingMode='FIXED';mutated.add(row.id);
 return {createdNodeIds:[...created],mutatedNodeIds:[...mutated],hudId:main.id,secondRowId:row.id,visualRowHeight:20,todayWidth:88,locationWidth:232,touchHeight:44,countersDefault:'hidden'};
}
library=async function(){await HUD_NAVIGATION_BASE.library();await ensureHudNavigation(KIT.HUD);LIBRARY.resize(1260,Math.max(libraryY+40,LIBRARY.height));};
function knownHudCounter(value){if(typeof value==='number'&&Number.isInteger(value)&&value>=0)return value;if(typeof value==='string'&&/^\d+$/.test(value))return Number(value);return null;}
hud=function(p,s){
 const d={...(s.sceneState||{}),...(s.hud||{})},energy=Number(d.energy??142),cap=Number(d.capacity??200),buff=d.buff;
 const recovery=energy>cap?'Bonus +'+(energy-cap):energy===cap?'Full':d.recoveryText||'+1 in 2:40';
 const today=knownHudCounter(d.todayCount??s.navigation?.todayCount),unread=knownHudCounter(d.inboxUnreadCount??d.unreadCount);
 const props={Energy:energy+'/'+cap,Recovery:recovery,Coins:String(d.coins??230),Location:[d.city||s.identity?.city||'Shanghai',worldPlace(s,d)].join(' · '),'Today label':'Today','Today count':today===null?'':today>99?'99+':String(today),'Show Today badge':today!==null&&today>0,'Inbox unread count':unread===null?'':unread>99?'99+':String(unread),'Show Inbox badge':unread!==null&&unread>0,'Show Buff':Boolean(buff),'Buff title':buff?.title||'','Buff remaining':buff?.remaining||'','Buff icon':(ICON[buff?.icon]||ICON['i-sprout']).id};
 const n=inst(p,'HUD',props);absolute(n,8,16);
 const meter=n.findOne(x=>x.name==='Energy fill');if(meter)meter.resize(Math.max(1,112*Math.min(1,energy/cap)),4);
 // Separate, non-overlapping second-row hit regions; retain the existing first-row destinations.
 const hits=[['Profile',16,24,44,'PROFILE-1-P0'],['Energy',68,24,142,'ENERGY-P0-1'],['Inbox',296,24,44,'PARCEL-1'],['Today',16,70,88,'TODAY-1'],['Location',112,70,232,'MAP-2-FREE']];
 for(const [label,x,y,w,target]of hits){const hit=frame(p,'HUD touch · '+label,w,44);absolute(hit,x,y);PENDING_LINKS.push({node:hit,ownerId:s.id,action:{label,target,kind:'navigate'}});}
 if(buff){const hit=frame(p,'Buff touch · '+buff.title,328,44);absolute(hit,16,118);PENDING_LINKS.push({node:hit,ownerId:s.id,detail:{title:buff.title,state:'Active',effect:s.effect,keyFacts:[{label:buff.mode==='casts'?'Casts remaining':'Time remaining',value:buff.remaining,kind:buff.mode==='casts'?'progress':'time'}],actions:[{label:'Close',kind:'dismiss'}]}});}
 return n;
};
