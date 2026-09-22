import { performance, monitorEventLoopDelay } from 'node:perf_hooks';
import { mkdir, writeFile } from 'node:fs/promises';
import { Client, appFor, memory, seed } from '../test/realtime/helpers.js';
import { onlineGateways } from '../src/realtime/gateway.js';

const store = memory(), app = await appFor(store);
const base = await app.listen({ port: 0, host: '127.0.0.1' });
const gateway = onlineGateways.get(app)!;
const clients: Client[] = [], accounts = [];
const reports: object[] = [];
const seconds = Number(process.env.ONLINE_LOAD_SECONDS ?? 20);
try {
  for (let i = 0; i < 301; i++) accounts.push(await seed(store));
  for (let start = 0; start < 301; start += 12) await Promise.all(accounts.slice(start, start + 12).map(async account => {
    const client = new Client(base.replace('http:', 'ws:') + '/v1/online');
    await client.connect(account.token);
    clients[accounts.indexOf(account)] = client;
  }));
  const party = await gateway.party(accounts[0].player, 'create');
  for (const account of accounts.slice(1, 300)) await gateway.party(account.player, 'join', party.party!.code);
  for (const kind of ['street', 'farm', 'mine']) {
    const args = kind === 'farm' ? { farm_id: accounts[0].farm.id } : {};
    await clients[0].join(kind, args);
    for (let start = 1; start < 300; start += 12) await Promise.all(clients.slice(start, start + 12).filter((_, i) => start + i < 300).map(client => client.join(kind, args)));
    const room = gateway.rooms.get(clients[0].joined.room)!;
    if (room.members.size !== 300) throw new Error('Expected exactly 300 actual room connections');
    if (kind !== 'mine') {
      clients[300].send({ t: 'join', kind, ...args });
      if ((await clients[300].next('error')).code !== 'ROOM_FULL') throw new Error('301st entry not rejected');
    }
    const delay = monitorEventLoopDelay({ resolution: 10 }); delay.enable();
    const beforeBytes = clients.slice(0, 300).map(c => c.bytes), beforeFrames = clients.slice(0, 300).map(c => c.binaryCount);
    const beforeTicks = room.metrics.ticks, beforeSkipped = room.metrics.skipped;
    const latency: number[] = [], sent = clients.slice(0, 300).map(() => new Map<number, number>());
    const handlers = clients.slice(0, 300).map((c, index) => {
      const handler = (data: Buffer, binary: boolean) => {
        if (!binary) return;
        for (let offset = 12; offset < data.length; offset += 26) if (data.readUInt16LE(offset) === c.joined.self) {
          const seq = data.readUInt32LE(offset + 20), at = sent[index].get(seq);
          if (at !== undefined) { latency.push(performance.now() - at); sent[index].delete(seq); }
          break;
        }
      };
      c.ws.on('message', handler); return handler;
    });
    let seq = 0;
    const start = performance.now();
    const sender = setInterval(() => {
      seq++;
      clients.slice(0, 300).forEach((c, index) => {
        sent[index].set(seq, performance.now()); sent[index].delete(seq - 40);
        const m = room.members.get(accounts[index].player)!;
        c.send({ t: 'input', seq, epoch: m.epoch,
          x: kind === 'street' ? 19.2 + Math.sin(seq / 12 + index) * 3 : kind === 'farm' ? 4.2 + Math.sin(seq / 12 + index) : 4.75 + Math.sin(seq / 12 + index) * 2,
          z: kind === 'street' ? -19.2 + Math.cos(index) * 2 : -.75, yaw: index % 6,
          action: seq % 20 < 3 ? 'emote_wave' : 'run' });
      });
    }, 50);
    await new Promise(resolve => setTimeout(resolve, seconds * 1000));
    clearInterval(sender); delay.disable();
    clients.slice(0, 300).forEach((c, i) => c.ws.off('message', handlers[i]));
    const elapsed = (performance.now() - start) / 1000;
    const bytes = clients.slice(0, 300).reduce((n, c, i) => n + c.bytes - beforeBytes[i], 0);
    const frames = clients.slice(0, 300).map((c, i) => c.binaryCount - beforeFrames[i]);
    latency.sort((a, b) => a - b);
    const report = { kind, clients: room.members.size, elapsed_s: elapsed, tick_hz: (room.metrics.ticks - beforeTicks) / elapsed,
      ack_p95_ms: latency[Math.floor(latency.length * .95)], ack_p99_ms: latency[Math.floor(latency.length * .99)],
      loop_p99_ms: delay.percentile(99) / 1e6, skipped: room.metrics.skipped - beforeSkipped,
      max_tick_ms: room.metrics.maxTickMs, min_snapshot_hz: Math.min(...frames) / elapsed,
      outbound_MB_s: bytes / elapsed / 1e6, average_client_KB_s: bytes / elapsed / 300 / 1000,
      rss_MB: process.memoryUsage().rss / 1e6, slow_closes: room.metrics.slowCloses, failed: room.failed };
    reports.push(report);
    console.log(JSON.stringify(report));
    if (room.failed || room.members.size !== 300 || report.tick_hz < 18 || report.min_snapshot_hz < 8 || report.ack_p95_ms > 250) throw new Error('300-client capacity gate failed');
    await Promise.all(clients.slice(0, 300).map(async c => { c.send({ t: 'leave' }); await c.next('departed'); }));
  }
  await mkdir('../output/online-2026-09-16', { recursive: true });
  await writeFile('../output/online-2026-09-16/load.json', JSON.stringify({ transport: 'real loopback WebSocket', storage: 'MemoryStore', reports }, null, 2));
} finally {
  clients.forEach(c => c.close());
  await app.close();
}
