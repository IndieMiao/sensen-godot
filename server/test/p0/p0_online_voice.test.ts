import Fastify from 'fastify';
import { AccessToken } from 'livekit-server-sdk';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { loadOutposts, pondRoomSpec } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { publicPlayer } from '../../src/p0/online/hub.js';
import { NO_VOICE_ROLES, P0Voice, p0VoiceFromEnv, registerP0Voice, RELEASE_RETRY_MS, VOICE_LEASE_MS } from '../../src/p0/online/voice.js';

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
  // LiveKit's rooms: "room/identity" → the participant's metadata (the lease their token carried)
  const present = new Map<string, string>();
  const media = { fail: 0,
    getParticipant: async (room: string, id: string) => {
      if (media.fail > 0) { media.fail--; throw new Error('livekit down'); }
      const m = present.get(room + '/' + id);
      if (m === undefined) throw Object.assign(new Error('participant not found'), { status: 404, code: 'not_found' });
      return { metadata: m };
    },
    removeParticipant: async (room: string, id: string) => { removed.push([room, id]); present.delete(room + '/' + id); } };
  const voice = new P0Voice(config, rooms, files, () => now, media);
  /** The phone joins LiveKit with its grant's token. */
  const inLiveKit = (grant: Record<string, any>) => present.set(grant.room + '/' + grant.self, jwt(grant.token).metadata);
  const told: [string, any][] = [];
  voice.tell = (player, payload) => told.push([player, payload]);
  const enter = (player: string, place = 'sh_tea_1') => { rooms.join(player, place); voice.joined(rooms.occupant(player)!); return rooms.occupant(player)!; };
  return { rooms, voice, removed, told, files, enter, inLiveKit, media, tick: (ms: number) => { now += ms; } };
}
const jwt = (token: string) => JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());

describe('P0 voice (SGODOT-383)', () => {
  it('does not return a voice grant when the account is removed while JWT signing is pending', async () => {
    const { voice, enter, rooms } = setup();
    voice.setAge('player-delete', true);
    enter('player-delete');
    let signed!: (value: string) => void;
    const signing = new Promise<string>(resolve => { signed = resolve; });
    const jwtSpy = vi.spyOn(AccessToken.prototype, 'toJwt').mockReturnValue(signing);
    try {
      const pending = voice.join('player-delete');
      await voice.removePlayer('player-delete');
      rooms.forget('player-delete');
      signed('fake-signed-token');
      await expect(pending).resolves.toMatchObject({ code: 'LEASE_EXPIRED', status: 410 });
    } finally { jwtSpy.mockRestore(); }
  });

  it('account deletion releases a live lease and age while retaining reports and the other participant', async () => {
    const { voice, enter, files, inLiveKit, removed } = setup();
    for (const p of ['player-delete', 'player-kept']) voice.setAge(p, true);
    enter('player-delete');
    const other = enter('player-kept');
    const grant = await voice.join('player-delete') as Record<string, any>;
    const kept = await voice.join('player-kept') as Record<string, any>;
    inLiveKit(grant); inLiveKit(kept);
    voice.block('player-delete', other.id, true);
    voice.report('player-delete', other.id, 'harassment');
    const reports = readFileSync(files.reports, 'utf8');
    await voice.removePlayer('player-delete');
    expect(removed).toEqual([[grant.room, grant.self]]);
    expect(voice.status('player-delete').age).toBe('unknown');
    expect(voice.status('player-kept').age).toBe('ok');
    expect(voice.heartbeat('player-delete', grant.lease_id)).toMatchObject({ code: 'LEASE_EXPIRED' });
    expect(voice.heartbeat('player-kept', kept.lease_id)).toMatchObject({ ok: true });
    expect(JSON.parse(readFileSync(files.blocks, 'utf8'))).toEqual({});
    expect(readFileSync(files.reports, 'utf8')).toBe(reports);
  });

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
    enter('player-aaaa', 'sh_tea_1');
    NO_VOICE_ROLES.add('tea');   // a role without voice (none on b1 since q(286); poi-rooms keeps 'poi', q(279) ⑧)
    try { await expect(voice.join('player-aaaa')).resolves.toMatchObject({ code: 'VOICE_NOT_HERE' }); }
    finally { NO_VOICE_ROLES.delete('tea'); }
  });

  it("Market Square's layer has voice since q(286): the whole layer of 30 (the user, 11-04)", async () => {
    expect(NO_VOICE_ROLES.has('market')).toBe(false);
    const { voice, enter } = setup();
    voice.setAge('player-aaaa', true);
    enter('player-aaaa', 'sh_market_1');
    await expect(voice.join('player-aaaa')).resolves.toMatchObject({ ok: true, capacity: 30 });
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
    const { voice, enter, rooms, removed, tick, inLiveKit } = setup();
    voice.setAge('player-aaaa', true);
    enter('player-aaaa');
    const grant = await voice.join('player-aaaa') as Record<string, any>;
    inLiveKit(grant);
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

  it('a peer id comes back at once: a removal checks the participant is still that lease\'s, never the newcomer\'s (周瑜 on #647)', async () => {
    const { voice, enter, rooms, removed, inLiveKit } = setup();
    for (const p of ['player-aaaa', 'player-bbbb']) voice.setAge(p, true);
    const a = enter('player-aaaa');
    const ga = await voice.join('player-aaaa') as Record<string, any>;
    inLiveKit(ga);
    expect(jwt(ga.token).metadata).toBe(ga.lease_id);
    // A leaves; before LiveKit is asked, B walks in and takes A's peer id, and joins voice
    const left = rooms.leave('player-aaaa', false)!;
    const b = enter('player-bbbb');
    expect(b.id).toBe(a.id);
    const gb = await voice.join('player-bbbb') as Record<string, any>;
    inLiveKit(gb);
    voice.departed(left);
    await new Promise(r => setTimeout(r, 0));
    expect(removed).toEqual([]);   // that identity is B's lease now: kept
    expect(voice.heartbeat('player-bbbb', gb.lease_id)).toMatchObject({ ok: true });
  });

  it('a removal LiveKit fails is logged and tried again; one already gone is done', async () => {
    vi.useFakeTimers();
    try {
      const { voice, enter, rooms, removed, inLiveKit, media } = setup();
      voice.setAge('player-aaaa', true);
      enter('player-aaaa');
      const g = await voice.join('player-aaaa') as Record<string, any>;
      inLiveKit(g);
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      media.fail = 1;
      voice.departed(rooms.leave('player-aaaa')!);
      await vi.advanceTimersByTimeAsync(0);
      expect(removed).toEqual([]);
      expect(warn).toHaveBeenCalledTimes(1);
      expect(String(warn.mock.calls[0][0])).toContain('release_failed');
      await vi.advanceTimersByTimeAsync(RELEASE_RETRY_MS);
      expect(removed).toEqual([[g.room, g.self]]);   // the second try
      warn.mockRestore();
    } finally { vi.useRealTimers(); }
  });

  it('Block is kept and said to the blocker only — their phone shuts it both ways (SGODOT-384); the one blocked never learns it', async () => {
    const { voice, enter, told, files, rooms } = setup();
    for (const p of ['player-aaaa', 'player-bbbb', 'player-cccc']) voice.setAge(p, true);
    const a = enter('player-aaaa'), b = enter('player-bbbb'), c = enter('player-cccc');
    expect(voice.block('player-aaaa', b.id, true)).toEqual({ ok: true, blocked: [String(b.id)] });
    expect(told).toEqual([['player-aaaa', { t: 'voice_blocks', blocked: [String(b.id)] }]]);   // B is told nothing
    expect(((await voice.join('player-aaaa')) as any).blocked).toEqual([String(b.id)]);
    expect(((await voice.join('player-bbbb')) as any).blocked).toEqual([]);   // B's grant says nothing of A's block
    expect(((await voice.join('player-cccc')) as any).blocked).toEqual([]);
    expect(JSON.parse(readFileSync(files.blocks, 'utf8'))).toEqual({ 'player-aaaa': ['player-bbbb'] });
    expect(voice.block('player-aaaa', 99, true)).toMatchObject({ code: 'NOT_IN_ROOM' });   // nobody there by that id
    // B leaves and comes back (a new peer id): A, who blocks B, is told B's new one; B is told nothing
    rooms.leave('player-bbbb');
    told.length = 0;
    const b2 = enter('player-bbbb');
    expect(told).toEqual([['player-aaaa', { t: 'voice_blocks', blocked: [String(b2.id)] }]]);
    // B leaves: A hears nothing — A's phone keeps refusing B's peer id, never opened to all while B may still be in
    // LiveKit or come back (李元芳 on 384 b5b6a124); the next one to take it is no one A blocked: A hears a list without it
    told.length = 0;
    voice.departed(rooms.leave('player-bbbb')!);
    expect(told).toEqual([]);
    const d = enter('player-dddd');
    expect(d.id).toBe(b2.id);   // B's peer id, taken at once
    expect(told).toEqual([['player-aaaa', { t: 'voice_blocks', blocked: [] }]]);
    expect(voice.blockedPeers('player-aaaa')).toEqual([]);
    told.length = 0;
    enter('player-eeee');   // a peer id A's phone never refused: A hears nothing
    expect(told).toEqual([]);
    rooms.leave('player-eeee');
    rooms.leave('player-dddd');
    const b3 = enter('player-bbbb');
    // A comes into a room where B already is: A is told whom they block there
    rooms.leave('player-aaaa');
    told.length = 0;
    enter('player-aaaa');
    expect(told).toEqual([['player-aaaa', { t: 'voice_blocks', blocked: [String(b3.id)] }]]);
    // unblock
    expect(voice.block('player-aaaa', b3.id, false)).toEqual({ ok: true, blocked: [] });
    expect(JSON.parse(readFileSync(files.blocks, 'utf8'))).toEqual({});
    expect(c.id).toBeGreaterThan(0);
  });

  it('three in a room: B leaves, C takes B\'s peer id, B comes back under a new one — A refuses B\'s new id, never C\'s (李元芳 on 384 d18a76f2)', async () => {
    const { voice, enter, told, rooms } = setup();
    for (const p of ['player-aaaa', 'player-bbbb', 'player-cccc']) voice.setAge(p, true);
    const a = enter('player-aaaa'), b = enter('player-bbbb');
    voice.block('player-aaaa', b.id, true);
    expect(((await voice.join('player-aaaa')) as any).blocked).toEqual([String(b.id)]);
    told.length = 0;
    voice.departed(rooms.leave('player-bbbb')!);
    expect(told).toEqual([]);                       // A's phone keeps refusing B's old id
    const c = enter('player-cccc');
    expect(c.id).toBe(b.id);                        // C takes it at once
    expect(told).toEqual([['player-aaaa', { t: 'voice_blocks', blocked: [] }]]);   // A lets it go: it is C's now
    told.length = 0;
    const b2 = enter('player-bbbb');
    expect(b2.id).not.toBe(c.id);
    expect(told).toEqual([['player-aaaa', { t: 'voice_blocks', blocked: [String(b2.id)] }]]);   // B's new id, not C's; B and C told nothing
    expect(voice.blockedPeers('player-aaaa')).toEqual([String(b2.id)]);
    told.length = 0;
    voice.departed(rooms.leave('player-cccc')!);    // C goes: A's phone never refused C's id, nothing to say
    expect(told).toEqual([]);
    expect(voice.blockedPeers('player-aaaa')).toEqual([String(b2.id)]);
    expect(a.id).toBeGreaterThan(0);
  });

  it('the Blocked list, by handle (the blocked are out of sight): Unblock from it wherever the two are; Block and Unblock tell the hub (seen)', async () => {
    const { voice, enter, rooms } = setup();
    const seen: string[][] = [];
    voice.seen = (a, b) => seen.push([a, b]);
    enter('player-aaaa');
    const b = enter('player-bbbb');
    voice.block('player-aaaa', b.id, true);
    expect(seen).toEqual([['player-aaaa', 'player-bbbb']]);
    expect(voice.hides('player-aaaa', 'player-bbbb')).toBe(true);
    expect(voice.hides('player-bbbb', 'player-aaaa')).toBe(true);   // either way
    expect(voice.blockedList('player-aaaa')).toEqual([{ handle: publicPlayer('player-bbbb') }]);
    expect(voice.blockedList('player-bbbb')).toEqual([]);   // the blocked one's own list says nothing of it
    rooms.leave('player-bbbb');   // apart now: still unblocked from the list
    expect(voice.unblock('player-aaaa', 'ffffffffffffffff')).toMatchObject({ code: 'NOT_BLOCKED', status: 404 });
    expect(voice.unblock('player-aaaa', publicPlayer('player-bbbb'))).toEqual({ ok: true, blocked: [] });
    expect(voice.hides('player-aaaa', 'player-bbbb')).toBe(false);
    expect(seen).toEqual([['player-aaaa', 'player-bbbb'], ['player-aaaa', 'player-bbbb']]);
  });

  it('Report writes one line — who, whom, when, where — and nothing else happens', () => {
    const { voice, enter, files } = setup();
    enter('player-aaaa');
    const b = enter('player-bbbb');
    expect(voice.report('player-aaaa', b.id, 'shouting')).toEqual({ ok: true, already: false });
    expect(voice.report('player-aaaa', b.id, '')).toEqual({ ok: true, already: true });   // You already reported this: no second line
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
    // a peer id as the grant writes it (a string) or as a number: the same person (蒙恬 on #647)
    enter('player-bbbb');
    expect((await post('/v1/p0/voice/block', { peer: '2', on: true })).json()).toEqual({ ok: true, blocked: ['2'] });
    expect((await post('/v1/p0/voice/block', { peer: 2, on: false })).json()).toEqual({ ok: true, blocked: [] });
    expect((await post('/v1/p0/voice/report', { peer: '2' })).json()).toEqual({ ok: true, already: false });
    expect((await post('/v1/p0/voice/report', { peer: '2.5' })).statusCode).toBe(400);
    expect((await post('/v1/p0/voice/leave', { lease_id: r.json().lease_id })).json()).toEqual({ ok: true });
    await app.close();
  });
});
