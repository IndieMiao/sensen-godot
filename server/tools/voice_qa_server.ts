import path from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
import { Room, RoomEvent, AudioSource, AudioFrame, AudioStream, LocalAudioTrack, TrackSource, dispose } from '@livekit/rtc-node';
import { buildApp } from '../src/http/app.js';
import { voiceConfig } from '../src/realtime/voice.js';
import { content, cv, blueprintDir, memory, seed } from '../test/realtime/helpers.js';
const store = memory();
const accounts = await Promise.all(Array.from({ length: 9 }, () => seed(store)));
const party = (await store.realtimeDirectory(accounts[0].player, 'create')).party!;
for (const account of accounts.slice(1)) await store.realtimeDirectory(account.player, 'join', party.code);
const config = voiceConfig({ ...process.env, VOICE_NAMESPACE: 'sensen-voice-dev-qa' });
if (!config) throw new Error('Configure server/.env.voice.local first');
const app = await buildApp({ guestWrites: true, store, content, contentVersion: cv, blueprintDir,
  regionsFile: path.join(path.dirname(blueprintDir), 'farm/data/regions.json'), pepper: 'voice-isolated-qa', now: Date.now, voice: config });
const peers: { room: Room; source: AudioSource; running: boolean; frames: number; lease: string; index: number; heartbeat?: ReturnType<typeof setInterval> }[] = [];
async function request(index: number, route: string, body: object) {
  const response = await app.inject({ method: 'POST', url: '/v1/online/' + route,
    headers: { authorization: 'Bearer ' + accounts[index].token }, payload: body });
  if (response.statusCode >= 400) throw new Error(response.json().code);
  return response.json();
}
async function connectPeer(index: number) {
  const grant = await request(index, 'voice/join', { request_id: 'node_peer_' + index });
  const room = new Room(), source = new AudioSource(48000, 1, 20);
  const peer = { room, source, running: true, frames: 0, lease: grant.lease_id as string, index, heartbeat: undefined as ReturnType<typeof setInterval> | undefined };
  peers.push(peer);
  room.on(RoomEvent.TrackSubscribed, track => {
    void (async () => { for await (const _frame of new AudioStream(track)) peer.frames++; })().catch(() => {});
  });
  await room.connect(grant.url, grant.token, { autoSubscribe: true, dynacast: false });
  await room.localParticipant!.publishTrack(LocalAudioTrack.createAudioTrack('qa-tone', source), { source: TrackSource.SOURCE_MICROPHONE });
  peer.heartbeat = setInterval(() => { void request(index, 'voice/heartbeat', { lease_id: peer.lease }).catch(() => {}); }, 5000);
  void (async () => {
    let cursor = 0;
    while (peer.running) {
      const samples = new Int16Array(480);
      for (let i = 0; i < samples.length; i++) samples[i] = Math.round(1800 * Math.sin(2 * Math.PI * (440 + index * 30) * (cursor++) / 48000));
      await source.captureFrame(new AudioFrame(samples, 48000, 1, 480));
    }
  })().catch(() => {});
}
app.get('/qa/status', async () => ({ peers: peers.map(p => ({ index: p.index, frames: p.frames, connected: p.room.isConnected })) }));
app.post('/qa/peers', async req => {
  const count = Number((req.body as { count: number }).count);
  if (!Number.isInteger(count) || count < 1 || count > 7) return { ok: false };
  for (let index = peers.length + 1; index <= count; index++) await connectPeer(index);
  return { ok: true, count: peers.length };
});
app.post('/qa/kick', async () => request(1, 'party', { action: 'kick', value: accounts[0].player }));
await store.realtimeDirectory(accounts[0].player, 'leader', accounts[1].player);
await app.listen({ host: '127.0.0.1', port: 3170 });
await connectPeer(1);
await mkdir('../output/voice-126-2026-09-16/private', { recursive: true });
await writeFile('../output/voice-126-2026-09-16/private/qa-account.json', JSON.stringify(accounts[0]), { mode: 0o600 });
await writeFile('../output/voice-126-2026-09-16/private/qa-ios-account.json', JSON.stringify(accounts[8]), { mode: 0o600 });
console.log('VOICE_QA_READY 3170');
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => {
  void (async () => {
    for (const peer of peers) { peer.running = false; clearInterval(peer.heartbeat); await peer.room.disconnect(); await peer.source.close(); }
    await app.close(); await dispose(); process.exit(0);
  })();
});
