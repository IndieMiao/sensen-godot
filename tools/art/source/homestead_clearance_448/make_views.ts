import {writeFileSync} from 'node:fs';
import {loadP0Content} from './project/server/src/p0/content.ts';
import {freshState,upgradeState} from './project/server/src/p0/state.ts';
import {viewOf} from './project/server/src/p0/view.ts';
const c=loadP0Content();const now=Date.now();
for(const level of [4,5,8,15])for(const look of ['a','b']){
 let s=freshState(c,'zhaoyun-homestead-448-isolated',now,448,{guide:true});s.homestead.level=level;
 s=upgradeState(c,s,now);s.homestead.looks={fence:'a',porch:level===5?look:'a',kitchen_extension:level===8?look:'a',master_farmhouse:look};
 const view=viewOf(c,s,now);writeFileSync(new URL('./project/view-lv'+level+'-'+look+'.json',import.meta.url),JSON.stringify(view));
 console.log(level,look,JSON.stringify(view.homestead),JSON.stringify(view.guide));
}
