import Fastify from 'fastify';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { loadOutposts, pondRoomSpec } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { NO_VOICE_ROLES, P0Voice, p0VoiceFromEnv, registerP0Voice, VOICE_LEASE_MS } from '../../src/p0/online/voice.js';

// Voice in the online rooms (SGODOT-383; the user, 11-02 via 奕星, q(274)): the voice room is the hub's room; LiveKit sees
// the peer id, never the player id; Market Square has none; Block is both ways and kept; Report is a log line; no 13+
// yes, no grant.

const CONFIG = { url: 'ws://livekit.test:7880', apiKey: 'devkey', apiSecret: 'a-secret-of-at-least-32-characters-long', namespace: 'p0-test' };
let dir = '';
afterEach(() => { if (dir) rmSync(dir, { recursive: true, force: true }); dir = ''; });

function setup(config: typeof CONFIG | null = CONFIG) {
  dir = mkdtempSync(path.join(tmpdir(), 'p0-voice-'));
  let now = 1_000_000;
  const rooms = new OutpostRooms(loadOutposts(), () => now, pondRoomSpec(id => id === 'pond_san_francisco_03'));
  const removed: [string, string][] = [];
  const files = { blocks: path.join(dir, 'blocks.json'), ages: path.join(dir, 'ages.json'), reports: path.join(dir, 'reports.jsonl') };
  const voice = new P0Voice(config, rooms, files, () => now, { removeParticipant: async (room, id) => { removed.push([room, id]); } });
  const told: [string, any][] = [];
  voice.tell = (player, payload) => told.push([player, payload]);
  const enter = (player: string, place = 'sh_tea_1') => { rooms.join(player, place); voice.joined(rooms.occupant(player)!); return rooms.occupant(player)!; };
  return { rooms, voice, removed, told, files, enter, tick: (ms: number) => { now += ms; } };
}
const jwt = (token: string) => JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());

describe('P0 voice (SGODOT-383)', () => {
  it('is off without P0_VOICE=on, and on needs the LiveKit keys', () => {
    expect(p0VoiceFromEnv({})).toBeNull();
    expect(p0VoiceFromEnv({ P0_VOICE: 'off', LIVEKIT_URL: 'ws://x', LIVEKIT_API_KEY: 'k', LIVEKIT_API_SECRET: 's' })).toBeNull();
    expect(() => p0VoiceFromEnv({ P0_VOICE: 'on' })).toThrow();
    expect(p0VoiceFromEnv({ P0_VOICE: 'on', LIVEKIT_URL: 'ws://lk:7880', LIVEKIT_API_KEY: 'k', LIVEKIT_API_SECRET: 's' }))
      .toEqual({ url: 'ws://lk:7880', apiKey: 'k', apiSecret: 's', namespace: 'p0-dev' });
  });

  it('refuses in order: off, the 13+ gate, not in a room, a room without voice', async () => {
    const off = setup(null);
    off.enter('player-aaaa');
    await expect(off.voice.join('player-aaaa')).resolves.toMatchObject({ code: 'VOICE_OFF' });
    rmSync(dir, { recursive: true, force: true });
    const { voice, enter } = setup();
    await expect(voice.join('player-aaaa')).resolves.toMatchObject({ code: 'AGE_GATE', status: 403 });
    voice.setAge('player-aaaa', true);
    await expect(voice.join('player-aaaa')).resolves.toMatchObject({ code: 'NOT_IN_ROOM' });
    expect(NO_VOICE_ROLES.has('market')).toBe(true);
    enter('player-aaaa', 'sh_market_1');
    await expect(voice.join('player-aaaa')).resolves.toMatchObject({ code: 'VOICE_NOT_HERE' });
  });

  it('a 13+ no stays a no; the answer is kept beside the save, and no birthday', () => {
    const { voice, files } = setup();
    expect(voice.status('player-aaaa').age).toBe('unknown');
    expect(voice.setAge('player-aaaa', false)).toBeNull();
    expect(voice.setAge('player-aaaa', true)).toMatchObject({ code: 'AGE_GATE' });
    expect(voice.status('player-aaaa')).toEqual({ ok: true, available: true, age: 'no' });
    expect(JSON.parse(readFileSync(files.ages, 'utf8'))).toEqual({ 'player-aaaa': false });
  });

  it('grants the hub room as a LiveKit room: the peer id as identity, never the player id; a name with no `:` or `~`', async () => {
    const { voice, enter } = setup();
    for (const p of ['player-aaaa', 'player-bbbb']) voice.setAge(p, true);
    enter('player-aaaa', 'pond:pond_san_francisco_03');
    const b = enter('player-bbbb', 'pond:pond_san_francisco_03');
    const grant = await voice.join('player-bbbb') as Record<string, any>;
    expect(grant).toMatchObject({ ok: true, url: CONFIG.url, capacity: 8, lease_ms: VOICE_LEASE_MS, self: String(b.id), blocked: [] });
    expect(grant.room).toMatch(/^p0-test-[0-9a-f]{12}-1$/);
    const claims = jwt(grant.token);
    expect(claims.sub).toBe(String(b.id));
    expect(claims.video).toMatchObject({ room: grant.room, roomJoin: true, canPublish: true, canPublishData: false });
    expect(JSON.stringify(grant)).not.toContain('player-bbbb');
    const a = await voice.join('player-aaaa') as Record<string, any>;
    expect(a.room).toBe(grant.room);   // the same room, the same voice
  });

  it('a heartbeat keeps the lease while the player stays; leaving the room ends it and LiveKit lets them go', async () => {
    const { voice, enter, rooms, removed, tick } = setup();
    voice.setAge('player-aaaa', true);
    enter('player-aaaa');
    const grant = await voice.join('player-aaaa') as Record<string, any>;
    tick(VOICE_LEASE_MS - 1000);
    expect(voice.heartbeat('player-aaaa', grant.lease_id)).toMatchObject({ ok: true, room: grant.room });
    expect(voice.heartbeat('player-aaaa', 'another-lease')).toMatchObject({ code: 'LEASE_EXPIRED', status: 410 });
    const left = rooms.leave('player-aaaa')!;
    voice.departed(left);
    await new Promise(r => setTimeout(r, 0));
    expect(removed).toEqual([[grant.room, String(left.id)]]);
    expect(voice.heartbeat('player-aaaa', grant.lease_id)).toMatchObject({ code: 'LEASE_EXPIRED' });
    // a lease not kept alive runs out
    enter('player-aaaa');
    const again = await voice.join('player-aaaa') as Record<string, any>;
    tick(VOICE_LEASE_MS + 1);
    expect(voice.heartbeat('player-aaaa', again.lease_id)).toMatchObject({ code: 'LEASE_EXPIRED' });
  });

  it('Block is both ways and kept: both hear their lists at once, a grant carries them, and one coming in later is told', async () => {
    const { voice, enter, told, files, rooms } = setup();
    for (const p of ['player-aaaa', 'player-bbbb', 'player-cccc']) voice.setAge(p, true);
    const a = enter('player-aaaa'), b = enter('player-bbbb'), c = enter('player-cccc');
    expect(voice.block('player-aaaa', b.id, true)).toEqual({ ok: true, blocked: [String(b.id)] });
    expect(told).toEqual([['player-aaaa', { t: 'voice_blocks', blocked: [String(b.id)] }], ['player-bbbb', { t: 'voice_blocks', blocked: [String(a.id)] }]]);
    expect(((await voice.join('player-bbbb')) as any).blocked).toEqual([String(a.id)]);   // the blocked one does not hear the blocker either
    expect(((await voice.join('player-cccc')) as any).blocked).toEqual([]);
    expect(JSON.parse(readFileSync(files.blocks, 'utf8'))).toEqual({ 'player-aaaa': ['player-bbbb'] });
    expect(voice.block('player-aaaa', 99, true)).toMatchObject({ code: 'NOT_IN_ROOM' });   // nobody there by that id
    // B leaves and comes back (a new peer id): both are told again
    rooms.leave('player-bbbb');
    told.length = 0;
    const b2 = enter('player-bbbb');
    expect(told).toContainEqual(['player-aaaa', { t: 'voice_blocks', blocked: [String(b2.id)] }]);
    expect(told).toContainEqual(['player-bbbb', { t: 'voice_blocks', blocked: [String(a.id)] }]);
    // unblock
    expect(voice.block('player-aaaa', b2.id, false)).toEqual({ ok: true, blocked: [] });
    expect(JSON.parse(readFileSync(files.blocks, 'utf8'))).toEqual({});
    expect(c.id).toBeGreaterThan(0);
  });

  it('Report writes one line — who, whom, when, where — and nothing else happens', () => {
    const { voice, enter, files } = setup();
    enter('player-aaaa');
    const b = enter('player-bbbb');
    expect(voice.report('player-aaaa', b.id, 'shouting')).toEqual({ ok: true });
    const line = JSON.parse(readFileSync(files.reports, 'utf8').trim());
    expect(line).toMatchObject({ kind: 'voice_report', reporter: 'player-aaaa', reported: 'player-bbbb', place: 'sh_tea_1', room: 1, reason: 'shouting' });
    expect(voice.blockedPeers('player-aaaa')).toEqual([]);
  });

  it('routes: a refusal is an HTTP error with its code (PartyVoiceSession reads non-2xx as one); the grant is a 200', async () => {
    const { voice, enter } = setup();
    const app = Fastify({ logger: false });
    registerP0Voice(app, voice);
    const post = (url: string, payload: object, player = 'player-aaaa') => app.inject({ method: 'POST', url, payload, headers: { 'x-p0-player': player } });
    expect((await app.inject({ method: 'POST', url: '/v1/p0/voice/join', payload: {} })).statusCode).toBe(401);
    expect((await app.inject({ method: 'GET', url: '/v1/p0/voice/status', headers: { 'x-p0-player': 'player-aaaa' } })).json())
      .toEqual({ ok: true, available: true, age: 'unknown' });
    let r = await post('/v1/p0/voice/join', {});
    expect([r.statusCode, r.json()]).toEqual([403, { ok: false, code: 'AGE_GATE' }]);
    expect((await post('/v1/p0/voice/age', { ok: true })).json()).toMatchObject({ age: 'ok' });
    enter('player-aaaa');
    r = await post('/v1/p0/voice/join', { request_id: 'x' });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ ok: true, self: '1' });
    expect((await post('/v1/p0/voice/heartbeat', { lease_id: r.json().lease_id })).statusCode).toBe(200);
    expect((await post('/v1/p0/voice/heartbeat', { lease_id: 'nope' })).statusCode).toBe(410);
    expect((await post('/v1/p0/voice/block', { peer: 'x', on: true })).statusCode).toBe(400);
    expect((await post('/v1/p0/voice/leave', { lease_id: r.json().lease_id })).json()).toEqual({ ok: true });
    await app.close();
  });
});
