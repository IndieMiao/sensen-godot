import {afterEach,describe,expect,it} from 'vitest';
import type {FastifyInstance} from 'fastify';
import {Client,appFor,memory,seed,content} from './helpers.js';
import {onlineGateways} from '../../src/realtime/gateway.js';
import {generateFarmTerrain} from '../../src/geography/farm_terrain.js';
import {CENTER,fixtureGeography} from '../geography/fixtures.js';
import {walkable} from '../../src/realtime/model.js';
let app:FastifyInstance;const peers:Client[]=[];
afterEach(async()=>{peers.splice(0).forEach(c=>c.close());await app?.close();});
describe('private generated realtime farms',()=>{
 it('isolates same-coordinate farms and prevents legacy street joins from bypassing permission',async()=>{
  const store=memory(),a=await seed(store),b=await seed(store);
  const terrain=generateFarmTerrain(CENTER,fixtureGeography(),content.farm_plot.layouts[content.farm_plot.default_layout]);
  for(const who of [a,b])Object.assign((await store.farmByOwner(who.player))!,{farm_terrain:terrain,layout_patch_id:terrain.layout_id,blueprint_revision:1,visit_access:'only_me'});
  app=await appFor(store);const url=(await app.listen({host:'127.0.0.1',port:0})).replace('http:','ws:')+'/v1/online';
  const connect=async(token:string)=>{const c=new Client(url);peers.push(c);await c.connect(token);return c;};
  const ca=await connect(a.token),cb=await connect(b.token),ra=await ca.join('street'),rb=await cb.join('street');
  expect(ra.kind).toBe('farm');expect(ra.room).not.toBe(rb.room);
  const gateway=onlineGateways.get(app)!,nav=gateway.rooms.get(ra.room)!.nav(0);
  expect(nav.spawn).toEqual([21.375,-26.625]);expect(walkable(nav,[42.5*.75,-45.5*.75])).toBe(false);
  cb.send({t:'leave'});await cb.next('departed');cb.send({t:'join',kind:'street',farm_id:a.farm.id});expect((await cb.next('error')).code).toBe('NOT_FOUND');
  const group=await gateway.party(a.player,'create');await gateway.party(b.player,'join',group.party!.code);
  cb.send({t:'join',kind:'street',farm_id:a.farm.id});expect((await cb.next('error')).code).toBe('NOT_FOUND');
  await gateway.party(a.player,'farm_access','allow');expect((await cb.join('street',{farm_id:a.farm.id})).room).toBe(ra.room);
  const snapshot=(await app.inject({method:'GET',url:'/v1/farms/'+a.farm.id+'/snapshot',headers:{authorization:'Bearer '+b.token}})).json();
  expect(snapshot.farm_terrain.plot.checksum).toBe(terrain.plot.checksum);expect(snapshot.farm_terrain.source).toBeUndefined();
 });
});
