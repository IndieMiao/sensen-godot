import { mkdir, writeFile } from 'node:fs/promises';
import { appFor, memory, seed, Client } from '../test/realtime/helpers.js';
import { onlineGateways } from '../src/realtime/gateway.js';

const store = memory(), app = await appFor(store);
const port = Number(process.env.ONLINE_QA_PORT ?? 3163);
const directory = '../output/online-2026-09-16';
const accounts = [await seed(store), await seed(store)];
const gateway = onlineGateways.get(app)!;
const party = await gateway.party(accounts[0].player, 'create');
await gateway.party(accounts[1].player, 'join', party.party!.code);
await mkdir(directory, { recursive: true });
for (let i = 0; i < accounts.length; i++) await writeFile(directory + '/account-' + i + '.json', JSON.stringify(accounts[i]), { mode: 0o600 });
await app.listen({ port, host: '127.0.0.1' });
console.log('ONLINE_QA_READY port=' + port);
const bots: { client: Client; account: Awaited<ReturnType<typeof seed>>; seq: number }[] = [];
const botCount = Math.min(298, Number(process.env.ONLINE_QA_CROWD ?? 0));
for (let i = 0; i < botCount; i++) {
  const account = await seed(store);
  await gateway.party(account.player, 'join', party.party!.code);
  const client = new Client('ws://127.0.0.1:' + port + '/v1/online');
  await client.connect(account.token);
  bots.push({ client, account, seq: 0 });
}
let updating = false, pulse = 0;
const botTimer = setInterval(async () => {
  if (updating) return;
  updating = true;
  try {
    pulse++;
    const leader = [...gateway.connections].find(c => c.player === accounts[0].player && c.member);
    for (const [index, bot] of bots.entries()) {
      if (pulse % 30 === 0) bot.client.send({ t: 'ping', at: pulse });
      const connection = [...gateway.connections].find(c => c.player === bot.account.player);
      if (!connection) continue;
      if (!leader?.room || !leader.member) {
        if (connection.member) { bot.client.send({ t: 'leave' }); await bot.client.next('departed'); }
        continue;
      }
      if (!connection.member) {
        await bot.client.join(leader.room.kind, leader.room.kind === 'farm' ? { farm_id: accounts[0].farm.id } : {});
      } else if (connection.room?.key !== leader.room.key) {
        bot.client.send({ t: 'leave' }); await bot.client.next('departed');
      } else {
        const member = connection.member;
        bot.client.send({ t: 'input', seq: ++bot.seq, epoch: member.epoch,
          x: leader.room.kind === 'street' ? 17 + index % 8 : 2 + index % 7,
          z: leader.room.kind === 'street' ? -17 - Math.floor(index / 8) % 8 : -.75 - Math.floor(index / 7) % 3 * .7,
          yaw: pulse / 10, action: 'run' });
      }
    }
  } finally { updating = false; }
}, 100);
console.log('ONLINE_QA_CROWD_READY count=' + bots.length);
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => {
  clearInterval(botTimer); bots.forEach(bot => bot.client.close()); void app.close().then(() => process.exit(0));
});
