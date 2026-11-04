import { writeFileSync } from 'node:fs';
import { loadP0Content } from '../../../../output/hardwood-408/project/server/src/p0/content.ts';
import { freshState } from '../../../../output/hardwood-408/project/server/src/p0/state.ts';
import { viewOf } from '../../../../output/hardwood-408/project/server/src/p0/view.ts';
const content = loadP0Content();
const now = Date.now();
const state = freshState(content, 'zhaoyun-hardwood-408-isolated', now, 408, { guide: false });
writeFileSync(new URL('../../../../output/hardwood-408/project/view.json', import.meta.url), JSON.stringify(viewOf(content, state, now)));
console.log('Isolated pond art view; no production state');
