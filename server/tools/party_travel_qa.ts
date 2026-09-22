import { mkdir, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { Client, appFor, memory, seed } from '../test/realtime/helpers.js';
import { onlineGateways } from '../src/realtime/gateway.js';
const store = memory();
const accounts = [await seed(store, { layout: 'sh_b' }), await seed(store, { region: 'los_angeles', layout: 'la_a' })];
for (const account of accounts) (await store.farmByOwner(account.player))!.visit_access = 'only_me';
const app = await appFor(store), gateway = onlineGateways.get(app)!;
const party = await gateway.party(accounts[0].player, 'create');
await gateway.party(accounts[1].player, 'join', party.party!.code);
let leader: Client;
app.post('/qa/phase', async req => {
 const { phase } = req.body as { phase: string };
 if (phase === 'fresh_member') {
  await store.realtimeDirectory(accounts[1].player, 'bind', randomUUID());
 } else if (phase === 'allow' || phase === 'deny') {
  await gateway.party(accounts[0].player, 'farm_access', phase);
 } else {
  if (leader.joined.room) { leader.send({ t: 'leave' }); await leader.next('departed'); leader.messages=[]; }
  const kind = phase === 'mine3' ? 'mine' : phase;
  await leader.join(kind, { channel: kind === 'farm' ? 3 : 7 });
  if (phase === 'mine3') {
   const room = gateway.rooms.get(leader.joined.room)!;
   for (const f of ['1','2']) { room.mine.floors[f].cleared=true; room.mine.floors[f].rocks.forEach(r=>r.broken=true); }
   const member = room.members.get(accounts[0].player)!;
   member.floor=3; member.epoch++; member.grace=room.now+120;
  }
 }
 const status = await gateway.travel.status(accounts[1].player);
 return { ok: true, phase, status };
});
await app.listen({ host: '127.0.0.1', port: 3165 });
leader = new Client('ws://127.0.0.1:3165/v1/online');
await leader.connect(accounts[0].token); await leader.join('farm', { channel: 3 });
const heartbeat = setInterval(()=>leader.send({t:'ping'}),5000);
await mkdir('../output/party-travel-2026-09-16/private',{recursive:true,mode:0o700});
await writeFile('../output/party-travel-2026-09-16/private/account.json', JSON.stringify(accounts[1]), { mode: 0o600 });
console.log('PARTY_TRAVEL_QA_READY 3165');
for (const signal of ['SIGINT','SIGTERM'] as const) process.on(signal,()=>{clearInterval(heartbeat);leader.close();void app.close().then(()=>process.exit(0));});
