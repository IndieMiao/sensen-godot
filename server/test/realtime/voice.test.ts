import { afterEach, describe, expect, it } from 'vitest';
import { TokenVerifier, TrackSource } from 'livekit-server-sdk';
import { PartyVoice, VOICE_LEASE_MS, voiceConfig, type VoiceConfig, type VoiceMedia } from '../../src/realtime/voice.js';
import { tokenHash } from '../../src/http/auth.js';
import { buildApp } from '../../src/http/app.js';
import { content, cv, blueprintDir, memory, seed } from './helpers.js';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';

const config: VoiceConfig = { url: 'ws://127.0.0.1:7880', apiKey: 'test-api', apiSecret: 'test-secret-at-least-32-characters',
  namespace: 'voice-test', mode: 'self-hosted', maxParticipants: 8 };
class Media implements VoiceMedia {
  rooms = new Map<string, number>(); deleted: string[] = []; fail = false;
  async listRooms() { return [...this.rooms.keys()].map(name => ({ name })); }
  async createRoom(r: { name: string; maxParticipants: number }) { this.rooms.set(r.name, r.maxParticipants); }
  async deleteRoom(name: string) { if (this.fail) throw new Error('network unavailable'); this.deleted.push(name); this.rooms.delete(name); }
}
async function fixture(n = 3) {
  const store = memory(), accounts = await Promise.all(Array.from({ length: n }, () => seed(store)));
  const party = (await store.realtimeDirectory(accounts[0].player, 'create')).party!;
  for (const a of accounts.slice(1)) await store.realtimeDirectory(a.player, 'join', party.code);
  const media = new Media(), changes: string[][] = [];
  let now = Date.now();
  const voice = new PartyVoice(config, store, () => now, users => changes.push(users), media);
  const join = (i: number, request = 'request_' + i) => voice.join(accounts[i].player, tokenHash(accounts[i].token), request);
  return { store, accounts, party, media, voice, join, changes, advance: (ms: number) => now += ms };
}
let app: FastifyInstance | undefined;
afterEach(async () => { await app?.close(); app = undefined; });

describe('party voice grants and membership', () => {
  it('issues only microphone and subscription grants bound to the authenticated player and party', async () => {
    const f = await fixture(); const grant = await f.join(0);
    const claims = await new TokenVerifier(config.apiKey, config.apiSecret).verify(grant.token);
    expect(claims.sub).toBe(f.accounts[0].player);
    expect(claims.video).toMatchObject({ room: grant.room, roomJoin: true, canPublish: true, canPublishData: false, canSubscribe: true });
    expect(claims.video?.canPublishSources).toEqual(['microphone']);
    expect(claims.video?.roomAdmin).toBeUndefined();
    expect(claims.video?.roomCreate).toBeUndefined();
    expect(grant).not.toHaveProperty('apiSecret');
    expect(grant.capacity).toBe(8);
  });
  it('reserves the eight seats atomically including clients still connecting', async () => {
    const f = await fixture(9);
    const r = await Promise.allSettled(f.accounts.map((_, i) => f.join(i)));
    expect(r.filter(x => x.status === 'fulfilled')).toHaveLength(8);
    expect(r.filter(x => x.status === 'rejected')).toHaveLength(1);
    expect((r[8] as PromiseRejectedResult).reason.message).toBe('VOICE_FULL');
    expect([...f.media.rooms.values()]).toEqual([8]);
  });
  it('bounds total admissions across parties and reclaims expired rooms independently', async () => {
    const f = await fixture();
    const v = new PartyVoice({ ...config, maxTotalParticipants: 2 }, f.store, Date.now, () => {}, f.media);
    const join = (i: number) => v.join(f.accounts[i].player, tokenHash(f.accounts[i].token), 'global_' + i);
    await f.store.realtimeDirectory(f.accounts[2].player, 'leave');
    await f.store.realtimeDirectory(f.accounts[2].player, 'create');
    const a = await join(0); await join(1);
    await expect(join(2)).rejects.toThrow('VOICE_BUSY');
    await v.leave(f.accounts[0].player, a.lease_id);
    await expect(join(2)).resolves.toMatchObject({ capacity: 8 });
    await v.close();
    expect(f.media.rooms.size).toBe(0);
    const expired = await f.join(0);
    f.advance(VOICE_LEASE_MS + 1); await f.voice.sweep();
    expect(f.media.rooms.has(expired.room)).toBe(false);
    expect((await f.join(0)).room).not.toBe(expired.room);
  });
  it('retrying the same join reuses the lease without rotating or occupying another seat', async () => {
    const f = await fixture(); const a = await f.join(0), b = await f.join(0);
    expect(b.lease_id).toBe(a.lease_id); expect(b.room).toBe(a.room); expect(b.participants).toHaveLength(1);
  });
  it('different parties get different rooms and nonmembers cannot join', async () => {
    const f = await fixture(); const a = await f.join(0);
    await f.store.realtimeDirectory(f.accounts[2].player, 'leave');
    await expect(f.join(2)).rejects.toThrow('VOICE_NO_PARTY');
    await f.store.realtimeDirectory(f.accounts[2].player, 'create');
    expect((await f.join(2)).room).not.toBe(a.room);
  });
  it('kicking a speaker rotates the room so cached tokens never grant the remaining room', async () => {
    const f = await fixture(); const a = await f.join(0), b = await f.join(1);
    await f.store.realtimeDirectory(f.accounts[0].player, 'kick', f.accounts[1].player);
    await f.voice.membershipChanged(f.party.members);
    expect(f.media.deleted).toContain(a.room);
    const next = await f.join(0);
    expect(next.room).not.toBe(b.room);
    const stale = await new TokenVerifier(config.apiKey, config.apiSecret).verify(b.token);
    expect(stale.video?.room).not.toBe(next.room);
    await expect(f.join(1)).rejects.toThrow('VOICE_NO_PARTY');
    expect(f.changes.flat()).toContain(f.accounts[0].player);
  });
  it('leader transfer leaves the ongoing voice room and lease intact', async () => {
    const f = await fixture(); const a = await f.join(0);
    await f.store.realtimeDirectory(f.accounts[0].player, 'leader', f.accounts[1].player);
    await f.voice.membershipChanged(f.party.members);
    expect((await f.join(0)).room).toBe(a.room); expect(f.media.deleted).toEqual([]);
  });
  it('voice leave preserves game party and stale delayed leave cannot remove a later join', async () => {
    const f = await fixture(); const a = await f.join(0);
    await f.voice.leave(f.accounts[0].player, a.lease_id);
    expect((await f.store.realtimeDirectory(f.accounts[0].player)).party?.id).toBe(f.party.id);
    const b = await f.join(0, 'next_request');
    await f.voice.leave(f.accounts[0].player, a.lease_id);
    expect((await f.voice.heartbeat(f.accounts[0].player, tokenHash(f.accounts[0].token), b.lease_id)).joined).toBe(true);
  });
  it('expired leases are removed and cannot be resurrected by a heartbeat', async () => {
    const f = await fixture(); const a = await f.join(0); f.advance(VOICE_LEASE_MS + 1);
    await f.voice.sweep();
    expect(f.media.deleted).toContain(a.room);
    await expect(f.voice.heartbeat(f.accounts[0].player, tokenHash(f.accounts[0].token), a.lease_id)).rejects.toThrow('VOICE_EXPIRED');
  });
  it('auth token revocation retires voice grants', async () => {
    const f = await fixture(); const a = await f.join(0);
    await f.store.revokeToken(tokenHash(f.accounts[0].token)); await f.voice.sweep();
    expect(f.media.deleted).toContain(a.room);
    await expect(f.join(0)).rejects.toThrow('VOICE_NO_PARTY');
  });
  it('failed retirement denies new grants until media cleanup succeeds', async () => {
    const f = await fixture(); const a = await f.join(0); await f.join(1); f.media.fail = true;
    await expect(f.voice.leave(f.accounts[1].player, (await f.join(1)).lease_id)).rejects.toThrow('VOICE_UNAVAILABLE');
    await expect(f.join(0)).rejects.toThrow('VOICE_UNAVAILABLE');
    f.media.fail = false; const next = await f.join(0);
    expect(next.room).not.toBe(a.room); expect(f.media.deleted).toContain(a.room);
  });
  it('reclaims earlier process rooms only for its own namespace and party', async () => {
    const f = await fixture(); const orphan = `${config.namespace}-${f.party.id}-old`;
    f.media.rooms.set(orphan, 8); f.media.rooms.set(`other-env-${f.party.id}-old`, 8);
    await f.join(0); expect(f.media.deleted).toContain(orphan); expect(f.media.rooms.has(`other-env-${f.party.id}-old`)).toBe(true);
  });
  it('rechecks membership after a slow SFU request', async () => {
    const f = await fixture(); const original = f.media.createRoom.bind(f.media);
    f.media.createRoom = async options => { await original(options); await f.store.realtimeDirectory(f.accounts[1].player, 'leave'); };
    await expect(f.join(1)).rejects.toThrow('VOICE_NO_PARTY');
  });
  it('requires explicit environment isolation and rejects unsafe or incomplete settings', () => {
    expect(voiceConfig({})).toBeUndefined();
    expect(() => voiceConfig({ LIVEKIT_URL: config.url })).toThrow('Incomplete');
    const env = { LIVEKIT_URL: config.url, LIVEKIT_API_KEY: config.apiKey, LIVEKIT_API_SECRET: config.apiSecret,
      LIVEKIT_MODE: 'self-hosted', VOICE_NAMESPACE: 'voice-dev' };
    expect(voiceConfig(env)?.namespace).toBe('voice-dev');
    expect(voiceConfig({ ...env, LIVEKIT_ADMIN_URL: 'http://172.18.0.1:7880' })?.adminUrl).toBe('http://172.18.0.1:7880');
    expect(() => voiceConfig({ ...env, LIVEKIT_ADMIN_URL: 'file:///etc/config' })).toThrow('Invalid');
    expect(() => voiceConfig({ ...env, LIVEKIT_MODE: 'cloud' })).toThrow('Invalid');
    expect(() => voiceConfig({ ...env, VOICE_NAMESPACE: '' })).toThrow('isolated');
    expect(() => voiceConfig({ ...env, VOICE_MAX_PARTICIPANTS: '300' })).toThrow('2–8');
  });
  it('HTTP requires auth and accepts no caller-supplied room, identity or grants', async () => {
    const f = await fixture();
    app = await buildApp({ guestWrites: true, store: f.store, content, contentVersion: cv, blueprintDir,
      regionsFile: path.join(path.dirname(blueprintDir), 'farm/data/regions.json'), pepper: 'test', now: Date.now, voice: config, voiceMedia: f.media });
    const invoke = (payload: object, authenticated = true) => app!.inject({ method: 'POST', url: '/v1/online/voice/join',
      headers: authenticated ? { authorization: 'Bearer ' + f.accounts[0].token } : {}, payload });
    expect((await invoke({ request_id: 'request_0' }, false)).statusCode).toBe(401);
    expect((await invoke({ request_id: 'request_0', room: 'other-party' })).statusCode).toBe(400);
    const joined = await invoke({ request_id: 'request_0' });
    expect(joined.statusCode).toBe(200); expect(joined.headers['cache-control']).toBe('no-store');
    const voice = joined.json();
    await app.inject({ method: 'POST', url: '/v1/online/party', headers: { authorization: 'Bearer ' + f.accounts[0].token }, payload: { action: 'disband' } });
    expect(f.media.deleted).toContain(voice.room);
  });
});
