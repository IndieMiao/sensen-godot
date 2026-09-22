import { mkdir, writeFile } from 'node:fs/promises';
import { Client, appFor, memory, seed } from '../test/realtime/helpers.js';
import { onlineGateways } from '../src/realtime/gateway.js';
import { defaultAppearance } from '../src/realtime/appearance.js';
const store = memory(), app = await appFor(store), gateway = onlineGateways.get(app)!;
const accounts = [await seed(store, { layout: 'sh_b' }), await seed(store, { region: 'los_angeles', layout: 'la_a' }), await seed(store)];
const looks = [
  { version: 1, slots: { ...defaultAppearance().slots, cloth: 'cloth1', hairHat: 'hairhat20', shoes: 'shoes1', glass: 'glass1', messengerBag: 'messengerbag1' } },
  { version: 1, slots: { ...defaultAppearance().slots, cloth: 'cloth42', hairHat: 'hairhat70', shoes: 'shoes5', glass: 'glass5' } },
];
const party = await gateway.party(accounts[0].player, 'create');
for (const a of accounts.slice(1)) await gateway.party(a.player, 'join', party.party!.code);
await gateway.party(accounts[0].player, 'farm_access', 'allow');
const bots: Client[] = []; let look = looks[0];
app.post('/qa/phase', async req => {
  const { phase } = req.body as { phase: string };
  const leader = bots[0];
  if (phase === 'change') {
    look = looks[1]; leader.send({ t: 'appearance', appearance: look });
    if (!(await leader.next('appearance_result')).ok) throw new Error('Outfit change failed');
  } else if (phase === 'newcomer') {
    const room = [...gateway.rooms.values()].find(r => r.members.has(accounts[0].player))!;
    await bots[1].join(room.kind, { appearance: looks[0], ...(room.kind === 'farm' ? { farm_id: accounts[0].farm.id } : {}) });
  } else {
    look = looks[0];
    for (const bot of bots) if (bot.joined.room) { bot.send({ t: 'leave' }); await bot.next('departed'); bot.joined = {}; bot.messages = []; }
    const kind = phase === 'mine3' ? 'mine' : phase;
    await leader.join(kind, { appearance: look, channel: kind === 'farm' ? 3 : 7 });
    if (phase === 'mine3') {
      const room = gateway.rooms.get(leader.joined.room)!;
      for (const id of ['1', '2']) { room.mine.floors[id].cleared = true; room.mine.floors[id].rocks.forEach(r => r.broken = true); }
      const member = room.members.get(accounts[0].player)!;
      member.floor = 3; member.epoch++; member.grace = room.now + 120;
    }
  }
  return { ok: true, look };
});
app.get('/qa/status', async () => ({ appearance: [...gateway.rooms.values()].flatMap(r => [...r.members.values()]).find(m => m.player === accounts[1].player)?.appearance }));
await app.listen({ host: '127.0.0.1', port: 3166 });
for (const account of [accounts[0], accounts[2]]) { const client = new Client('ws://127.0.0.1:3166/v1/online'); await client.connect(account.token); bots.push(client); }
const heartbeat = setInterval(() => bots.forEach(c => c.send({ t: 'ping' })), 5000);
await mkdir('../output/appearance-2026-09-16/private', { recursive: true, mode: 0o700 });
await writeFile('../output/appearance-2026-09-16/private/account.json', JSON.stringify({ ...accounts[1], leader: accounts[0].player, newcomer: accounts[2].player, looks }), { mode: 0o600 });
console.log('APPEARANCE_QA_READY 3166');
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { clearInterval(heartbeat); bots.forEach(c => c.close()); void app.close().then(() => process.exit(0)); });
