import { mkdir, writeFile } from 'node:fs/promises';
import { appFor, memory, seed, content } from '../test/realtime/helpers.js';
import { addBagItem, projectBagAggregates } from '../src/domain/bag.js';
const store=memory();const account=await seed(store,{layout:'sh_b'});
const farm=(await store.farmByOwner(account.player))!;
for(const item of ['copper_sword','trail_boots','copper_pickaxe']) {
  addBagItem(farm.state.bag!,{item_id:item,quantity:1},content,true);
  const at=farm.state.bag!.slots.findIndex(s=>s.item_id===item);
  const [stack]=farm.state.bag!.slots.splice(at,1);
  const slot=item==='copper_sword'?'weapon':item==='trail_boots'?'accessory':'tool';
  const previous=farm.state.bag!.equipped[slot];if(previous)farm.state.bag!.slots.push(previous);
  farm.state.bag!.equipped[slot]=stack;
}
for(const item of ['vegetable_soup','salad'])addBagItem(farm.state.bag!,{item_id:item,quantity:3},content,true);
projectBagAggregates(farm.state,content);farm.state.character!.hp=120;
const app=await appFor(store);
const output='../output/mine-art-video-2026-09-16/private';await mkdir(output,{recursive:true});
await writeFile(output+'/account.json',JSON.stringify({token:account.token,player:account.player}),{mode:0o600});
app.get('/qa/summary',async()=>{const f=(await store.farmByOwner(account.player))!;return{version:f.version,hp:f.state.character?.hp,mine:f.state.mine,bag:f.state.bag}});
await app.listen({host:'127.0.0.1',port:3172});console.log('MINE_ART_READY 3172');
for(const signal of ['SIGTERM','SIGINT'] as const)process.on(signal,()=>void app.close().then(()=>process.exit(0)));
