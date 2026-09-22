import { describe, expect, it } from 'vitest';
import { addBagItem, allBagStacks, ensureBag } from '../../src/domain/bag.js';
import { mainHandStats, characterStats, gatherSeconds } from '../../src/domain/character.js';
import { startJourney } from '../../src/domain/journey.js';
import { EQUIPMENT_SLOTS } from '../../src/domain/content.js';
import { apply, makeCtx } from '../../src/domain/reducer.js';
import { content, freshFarm, plot, SH, T0 } from './helpers.js';
import type { FarmState, BagStack } from '../../src/domain/state.js';
import type { Command } from '../../src/domain/commands.js';
const item=(id:number,item_id:string):BagStack=>({id:`bag_${id}`,instance_id:`item_${id}`,item_id,quantity:1,quality:'gold',attributes:{serial:'preserved'}});
function fresh(){const s=freshFarm();ensureBag(s,content);return s;}
function command(s:FarmState,c:Command,now=T0){return apply(s,c,makeCtx(s,now,SH,content,plot,now,'owner'));}
function equip(s:FarmState,id:string,slot?:any){const stack=s.bag!.slots.find(v=>v.item_id===id)!;const out=command(s,{type:'equip_bag_item',sequence:s.bag!.sequence,stack_id:stack.id,slot});if(!out.ok)throw Error(out.code);return out.state;}
describe('six-slot equipment contract',()=>{
 it('migrates old weapon/tool/accessory without losing instances, full-bag overflow or growing crops',()=>{
  const s=freshFarm(), tool=item(1,'copper_pickaxe'),weapon=item(2,'copper_sword'),accessory=item(3,'artisan_apron');
  s.bag={version:1,sequence:9,capacity:1,next_id:5,slots:[item(4,'foraging_gloves')],overflow:[],equipped:{tool,weapon,accessory}};
  const cells=structuredClone(s.cells), old=allBagStacks(s.bag).map(v=>structuredClone(v));
  ensureBag(s,content);
  expect(s.bag.version).toBe(2);expect(Object.keys(s.bag.equipped).sort()).toEqual([...EQUIPMENT_SLOTS].sort());
  expect(s.bag.equipped.main_hand).toEqual(weapon);expect(s.bag.equipped.gloves).toEqual(accessory);expect(s.bag.overflow).toContainEqual(tool);
  expect(allBagStacks(s.bag).filter(v=>v.item_id!=='starter_fishing_rod').sort((a,b)=>a.id.localeCompare(b.id))).toEqual(old.sort((a,b)=>a.id.localeCompare(b.id)));
  expect(s.cells).toEqual(cells);const snapshot=structuredClone(s);ensureBag(s,content);expect(s).toEqual(snapshot);
 });
 it('grants and equips a starter rod once; unequipping never mints or auto-equips another',()=>{
  let s=fresh();expect(s.bag!.equipped.fishing_rod?.item_id).toBe('starter_fishing_rod');
  const out=command(s,{type:'unequip_bag_item',sequence:s.bag!.sequence,slot:'fishing_rod'});expect(out.ok).toBe(true);if(!out.ok)return;s=out.state;
  ensureBag(s,content);expect(s.bag!.equipped.fishing_rod).toBeNull();expect(allBagStacks(s.bag!).filter(v=>v.item_id==='starter_fishing_rod')).toHaveLength(1);
  const ctx=makeCtx(s,T0,SH,content,plot,T0,'owner');ctx.fishingPresence={space:'farm',home:'owner',nonce:'one',x:9.375,z:-27.375};
  expect(apply(s,{type:'cast_fishing',sequence:0,site_id:'farm_pond'},ctx)).toMatchObject({ok:false,code:'FISHING_ROD_REQUIRED'});
  s=equip(s,'starter_fishing_rod','fishing_rod');const ready={...ctx};
  expect(apply(s,{type:'cast_fishing',sequence:0,site_id:'farm_pond'},ready).ok).toBe(true);
  const future=structuredClone(content);future.character.auto_grant_starter_rod=false;const freshFuture=freshFarm();ensureBag(freshFuture,future);expect(freshFuture.bag!.equipped.fishing_rod).toBeNull();
 });
 it('two ring slots are independent, contribute once each, and reject foreign item slots',()=>{
  let s=fresh();for(const id of ['copper_ring','wooden_ring','copper_necklace','copper_axe'])addBagItem(s.bag!,{item_id:id,quantity:1},content);
  s=equip(s,'copper_ring','ring_1');s=equip(s,'wooden_ring','ring_2');s=equip(s,'copper_necklace','necklace');
  expect(characterStats(s,content)).toMatchObject({max_hp:120,defense:2});
  const axe=s.bag!.slots.find(v=>v.item_id==='copper_axe')!;const before=structuredClone(s);
  expect(command(s,{type:'equip_bag_item',sequence:s.bag!.sequence,stack_id:axe.id,slot:'ring_2'})).toMatchObject({ok:false,code:'INVALID_BAG_ACTION'});expect(s).toEqual(before);
 });
 it('all main hands have positive defaults, exchange one slot, and specialize real gather duration',()=>{
  let s=fresh();const rod=structuredClone(s.bag!.equipped.fishing_rod);for(const id of ['rusty_sword','copper_pickaxe','copper_axe','row_tool'])addBagItem(s.bag!,{item_id:id,quantity:1},content);
  s=equip(s,'rusty_sword');const sword=mainHandStats(s,content);expect(sword.damage).toBe(14);
  s=equip(s,'copper_pickaxe');const pick=mainHandStats(s,content);expect(pick.damage).toBe(7);expect(gatherSeconds(s,content,'ore',1)).toBe(.5);expect(s.bag!.slots.some(v=>v.item_id==='rusty_sword')).toBe(true);
  s=equip(s,'copper_axe');expect(gatherSeconds(s,content,'wood',.9)).toBe(.45);
  s=equip(s,'row_tool');expect(characterStats(s,content).tool_scope).toBe(3);expect(gatherSeconds(s,content,'crop',.45)).toBeCloseTo(.28125);
  expect(s.bag!.equipped.fishing_rod).toEqual(rod);
  for(const value of Object.values(mainHandStats(s,content)))expect(value).toBeGreaterThan(0);
 });
});

describe('authoritative collection and rod lifetime',()=>{
 it('uses the current hand to rate-limit real collections without consuming a rejected reward',()=>{
  let s=startJourney(fresh(),content);
  addBagItem(s.bag!,{item_id:'copper_axe',quantity:1},content);
  const first=command(s,{type:'collect_resource',node_id:'nursery_west',round:0},T0);expect(first.ok).toBe(true);if(!first.ok)return;s=first.state;
  const before=structuredClone(s);
  expect(command(s,{type:'collect_resource',node_id:'nursery_east',round:0},T0+500)).toMatchObject({ok:false,code:'WORK_COOLDOWN'});
  expect(s).toEqual(before);
  s=equip(s,'copper_axe');
  const faster=command(s,{type:'collect_resource',node_id:'nursery_east',round:0},T0+500);
  expect(faster.ok).toBe(true);if(!faster.ok)return;
  expect(faster.state.journey!.wood).toBeGreaterThan(s.journey!.wood);
  expect(faster.state.journey!.exploration.collected.filter(id=>id==='nursery_east')).toHaveLength(1);
 });
 it('removing the rod after casting prevents hooking, while cancellation remains available',()=>{
  let s=fresh();const ctx=makeCtx(s,T0,SH,content,plot,T0,'owner');ctx.fishingPresence={space:'farm',home:'owner',nonce:'one',x:9.375,z:-27.375};
  const cast=apply(s,{type:'cast_fishing',sequence:0,site_id:'farm_pond'},ctx);expect(cast.ok).toBe(true);if(!cast.ok)return;s=cast.state;
  const unequip=command(s,{type:'unequip_bag_item',sequence:s.bag!.sequence,slot:'fishing_rod'});if(!unequip.ok)throw Error(unequip.code);s=unequip.state;
  const now=s.fishing!.active!.bite_at;
  expect(apply(s,{type:'hook_fishing',sequence:1},{...ctx,realNow:now,now})).toMatchObject({ok:false,code:'FISHING_ROD_REQUIRED'});
  expect(apply(s,{type:'cancel_fishing',sequence:1},{...ctx,realNow:now,now})).toMatchObject({ok:true,state:{fishing:{active:null}}});
 });
});
