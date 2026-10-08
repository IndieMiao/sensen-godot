/**
 * Scripted players for outpost-room hand tests (SGODOT-227), over the same /v1/p0/online protocol as the client.
 *   node --import tsx tools/p0_outpost_bots.ts fill [outpost=sh_tackle_1] [n=12]   idle players: the next one in lands in Room 2
 *   node --import tsx tools/p0_outpost_bots.ts tea                                 one walking a loop, one seated on the bench
 * P0_ONLINE_URL (default ws://127.0.0.1:3110/v1/p0/online) picks the server; P0_BOTS_MINUTES (default 15) when to quit.
 * Stop early with Ctrl+C or by the PID this prints.
 */
import { WebSocket } from 'ws';

const url = process.env.P0_ONLINE_URL ?? 'ws://127.0.0.1:3110/v1/p0/online';
const [mode = 'fill', ...rest] = process.argv.slice(2);

interface Plan { outpost: string; at: [number, number]; slots?: Record<string, string>; move?: (t: number) => [number, number]; seat?: { node: string; at: [number, number] } }

function bot(player: string, plan: Plan) {
  const ws = new WebSocket(url, { headers: { 'x-p0-player': player } });
  let epoch = 0;
  let seq = 0;
  let t = 0;
  ws.on('open', () => ws.send(JSON.stringify({ t: 'join', outpost: plan.outpost, at: plan.at, ...(plan.slots ? { appearance: { version: 1, slots: plan.slots } } : {}) })));
  ws.on('message', (data, binary) => {
    if (binary) return;
    const m = JSON.parse(String(data));
    if (m.t !== 'joined') return;
    epoch = m.epoch;
    console.log(`${player}: ${plan.outpost} Room ${m.room}`);
    if (plan.seat) ws.send(JSON.stringify({ t: 'act', seq: 1, epoch, action: 'sit', node: plan.seat.node, at: plan.seat.at }));
  });
  ws.on('close', (code) => console.log(`${player}: closed ${code}`));
  setInterval(() => {
    if (ws.readyState !== WebSocket.OPEN || !epoch) return;
    if (!plan.move) return void ws.send(JSON.stringify({ t: 'ping', at: Date.now() }));
    t += 0.1;
    const [x, z] = plan.move(t);
    ws.send(JSON.stringify({ t: 'input', seq: ++seq, epoch, x, z, yaw: t, action: 'walk' }));
  }, plan.move ? 100 : 10_000);
}

if (mode === 'fill') {
  const [outpost = 'sh_tackle_1', n = '12'] = rest;
  for (let i = 0; i < Number(n); i++) bot(`fill-bot-${String(i).padStart(4, '0')}`, { outpost, at: [-2 + (i % 4), -1 + Math.floor(i / 4)] });
} else if (mode === 'tea') {
  // Coffee Shop kit (SGODOT-227 scene integration): the walker loops the open floor between the tables and the
  // counter; the sitter takes the far chair of the second table (chair_4).
  bot('tea-walker-001', { outpost: 'sh_tea_1', at: [0.2, -0.6], slots: { hairHat: 'hairhat43', cloth: 'cloth11' },
    move: t => [0.2 + Math.cos(t * 0.6) * 1.4, -0.6 + Math.sin(t * 0.6) * 0.3] });
  bot('tea-sitter-002', { outpost: 'sh_tea_1', at: [2.3, 1.8], slots: { hairHat: 'hairhat51', cloth: 'cloth1_1' },
    seat: { node: 'seat_table2_2', at: [2.24, 1.0] } });
} else {
  console.error('usage: p0_outpost_bots.ts fill [outpost] [n] | tea');
  process.exit(2);
}
console.log(`pid ${process.pid} → ${url}`);
setTimeout(() => process.exit(0), Number(process.env.P0_BOTS_MINUTES ?? 15) * 60_000);
