import { it, expect } from 'vitest';
import { randomUUID } from 'node:crypto';
import { appFor, memory } from '../realtime/helpers.js';
it('persists the initial rod at farm creation and cannot mint another on creation replay', async()=>{
 const store=memory(), app=await appFor(store), auth=await store.authAnonymous(randomUUID());
 const payload={idempotency_key:randomUUID(),region_id:'shanghai',layout_patch_id:'sh_a',blueprint_revision:2};
 try {
  const response=await app.inject({method:'POST',url:'/v1/farms',headers:{authorization:'Bearer '+auth.token},payload});
  expect(response.statusCode).toBe(201);
  const stored=structuredClone(await store.farmByOwner(auth.player.id));
  expect(stored!.state.bag).toMatchObject({version:2,starter_rod_granted:true,equipped:{fishing_rod:{item_id:'starter_fishing_rod'}}});
  const replay=await app.inject({method:'POST',url:'/v1/farms',headers:{authorization:'Bearer '+auth.token},payload});
  expect(replay.statusCode).toBeLessThan(300);
  expect(await store.farmByOwner(auth.player.id)).toEqual(stored);
 }finally{await app.close();}
});
