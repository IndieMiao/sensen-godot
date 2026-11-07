import { writeFileSync } from 'node:fs';
import { loadP0Content } from '../../../../output/homestead-439/project/server/src/p0/content.ts';
import { freshState, upgradeState } from '../../../../output/homestead-439/project/server/src/p0/state.ts';
import { viewOf } from '../../../../output/homestead-439/project/server/src/p0/view.ts';
const content=loadP0Content(); const now=Date.now();
for (const level of [8,10]) {
 let state=freshState(content, 'zhaoyun-homestead-439-isolated', now, 439, {guide:false});
 state.homestead.level=level;
 state.homestead.plaque=[{level:2,at:now-86400000},{level:5,at:now-3600000}];
 state=upgradeState(content,state,now);
 for (const plot of state.plots) {plot.state='tilled';delete plot.crop;delete plot.ready_at;}
 const view=viewOf(content,state,now);
 writeFileSync(new URL('../../../../output/homestead-439/project/view-lv'+level+'.json',import.meta.url),JSON.stringify(view));
 console.log('QA level',level,'looks',JSON.stringify(view.homestead),'plots',view.garden);
}
