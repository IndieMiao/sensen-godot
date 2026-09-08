import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { createHmac } from 'node:crypto';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { MemoryVoiceStore } from '../../src/http/memory_voice.js';
import { socialAccountModule } from '../../src/http/social.js';
import { canPublishFor, liveKitFromEnv, signAccessToken, stageFull, validateRoom, voiceAccountModule,
  ROOM_TITLE_MAX, STAGE_MAX, type RoomMemberRow } from '../../src/http/voice.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { at, SH } from '../domain/helpers.js';
import { PROJECT, idToken, makeKeys } from '../fixtures/firebase_tokens.js';

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const BLUEPRINTS = path.join(ROOT, 'assets', 'blueprints');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const bp = loadBlueprint(BLUEPRINTS, 'sh_a', 2)!;
const k = makeKeys();
const LK = { url: 'wss://lk.test', apiKey: 'API123', apiSecret: 'secret-xyz' };

let app: FastifyInstance;
let voice: MemoryVoiceStore;
let accounts: MemoryAccountStore;
let clock = at('2026-09-08T10:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-08T10:00:00+08:00');
  accounts = new MemoryAccountStore();
  const social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  voice = new MemoryVoiceStore();
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, voice, livekit: LK,
    accountModules: [socialAccountModule(social), voiceAccountModule(voice)],
  });
});
afterEach(async () => { await app.close(); });

const tok = (uid: string) => idToken(k, clock, {}, uid);
const authed = (uid: string) => ({ authorization: `Bearer ${tok(uid)}` });
const signIn = async (uid: string): Promise<string> =>
  (await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: tok(uid) } })).json().user_id as string;
const get = (uid: string, url: string) => app.inject({ method: 'GET', url, headers: authed(uid) });
const post = (uid: string, url: string, payload?: object) => app.inject({ method: 'POST', url, headers: authed(uid), payload });

const claims = (jwt: string) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString());

describe('D5 语音房', () => {
  it('token 是 HS256 且带房间与发布权限；签名可验', () => {
    const jwt = signAccessToken(LK, { identity: 'u1', name: 'A', room: 'r1', canPublish: true, nowMs: 1_700_000_000_000 });
    const [h, p, sig] = jwt.split('.');
    expect(JSON.parse(Buffer.from(h, 'base64url').toString())).toEqual({ alg: 'HS256', typ: 'JWT' });
    expect(createHmac('sha256', LK.apiSecret).update(`${h}.${p}`).digest('base64url')).toBe(sig);
    const c = claims(jwt);
    expect(c.iss).toBe('API123');
    expect(c.sub).toBe('u1');
    expect(c.video).toMatchObject({ room: 'r1', roomJoin: true, canPublish: true, canSubscribe: true });
    expect(c.exp - c.iat).toBe(3600);
    expect(canPublishFor('host', false)).toBe(true);
    expect(canPublishFor('speaker', false)).toBe(true);
    expect(canPublishFor('listener', false)).toBe(false);
    expect(canPublishFor('speaker', true)).toBe(false); // 被静音的人签不出发布权限
    expect(liveKitFromEnv({})).toBeUndefined();
    expect(liveKitFromEnv({ LIVEKIT_URL: 'u', LIVEKIT_API_KEY: 'k', LIVEKIT_API_SECRET: 's' })).toEqual({ url: 'u', apiKey: 'k', apiSecret: 's' });
  });

  it('建房 / 列表 / 进房：房主可发布，听众不可；进房不自动上麦', async () => {
    await signIn('alice'); const b = await signIn('bob');
    expect((await post('alice', '/v1/voice/rooms', { title: '' })).statusCode).toBe(400);
    expect((await post('alice', '/v1/voice/rooms', { title: 'x'.repeat(ROOM_TITLE_MAX + 1) })).statusCode).toBe(400);
    const created = await post('alice', '/v1/voice/rooms', { title: '午后闲聊' });
    expect(created.statusCode).toBe(201);
    const room = created.json();
    expect(room).toMatchObject({ title: '午后闲聊', member_count: 1, speaker_count: 1, closed: false });
    expect(room.livekit_url).toBe('wss://lk.test');
    expect(claims(room.token).video).toMatchObject({ room: room.id, canPublish: true });

    const list = (await get('bob', '/v1/voice/rooms')).json().items;
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({ id: room.id, host_name: 'alice' });

    const joined = (await post('bob', `/v1/voice/rooms/${room.id}/join`)).json();
    expect(joined.me).toMatchObject({ user_id: b, role: 'listener', muted: false });
    expect(claims(joined.token).video.canPublish).toBe(false); // 听众不能发布
    expect(joined.member_count).toBe(2);
    expect(joined.speaker_count).toBe(1);
  });

  it('上麦换到可发布的 token；下麦收回；房主可请人下麦，别人不行', async () => {
    await signIn('alice'); const b = await signIn('bob'); await signIn('carol');
    const room = (await post('alice', '/v1/voice/rooms', { title: 'T' })).json();
    await post('bob', `/v1/voice/rooms/${room.id}/join`);
    await post('carol', `/v1/voice/rooms/${room.id}/join`);

    const up = (await post('bob', `/v1/voice/rooms/${room.id}/stage`, { on: true })).json();
    expect(up.me.role).toBe('speaker');
    expect(claims(up.token).video.canPublish).toBe(true);

    const down = (await post('bob', `/v1/voice/rooms/${room.id}/stage`, { on: false })).json();
    expect(down.me.role).toBe('listener');
    expect(claims(down.token).video.canPublish).toBe(false);

    await post('bob', `/v1/voice/rooms/${room.id}/stage`, { on: true });
    // carol 不是房主：请不动别人
    expect((await post('carol', `/v1/voice/rooms/${room.id}/stage`, { on: false, user_id: b })).statusCode).toBe(403);
    // 房主可以
    const kicked = (await post('alice', `/v1/voice/rooms/${room.id}/stage`, { on: false, user_id: b })).json();
    expect((kicked.members as { user_id: string; role: string }[]).find(m => m.user_id === b)!.role).toBe('listener');
    // 房主永远在麦上，不能被下
    expect((await post('alice', `/v1/voice/rooms/${room.id}/stage`, { on: false })).statusCode).toBe(409);
  });

  it('房主静音某人：立刻下麦且上不去；解除后可以再上', async () => {
    await signIn('alice'); const b = await signIn('bob');
    const room = (await post('alice', '/v1/voice/rooms', { title: 'T' })).json();
    await post('bob', `/v1/voice/rooms/${room.id}/join`);
    await post('bob', `/v1/voice/rooms/${room.id}/stage`, { on: true });
    expect((await post('bob', `/v1/voice/rooms/${room.id}/mute`, { user_id: b, muted: true })).statusCode).toBe(403);
    const muted = (await post('alice', `/v1/voice/rooms/${room.id}/mute`, { user_id: b, muted: true })).json();
    expect((muted.members as { user_id: string; muted: boolean; role: string }[]).find(m => m.user_id === b))
      .toMatchObject({ muted: true, role: 'listener' });
    expect((await post('bob', `/v1/voice/rooms/${room.id}/stage`, { on: true })).statusCode).toBe(403);
    // 被静音的人续 token 也拿不到发布权限
    const bobToken = (await post('bob', `/v1/voice/rooms/${room.id}/token`)).json().token;
    expect(claims(bobToken).video.canPublish).toBe(false);
    await post('alice', `/v1/voice/rooms/${room.id}/mute`, { user_id: b, muted: false });
    expect((await post('bob', `/v1/voice/rooms/${room.id}/stage`, { on: true })).json().me.role).toBe('speaker');
  });

  it('房主离开即关房；关掉的房不在列表里、进不去；麦位上限', async () => {
    await signIn('alice'); await signIn('bob');
    const room = (await post('alice', '/v1/voice/rooms', { title: 'T' })).json();
    await post('bob', `/v1/voice/rooms/${room.id}/join`);
    expect((await post('alice', `/v1/voice/rooms/${room.id}/leave`)).json()).toMatchObject({ closed: true });
    expect((await get('bob', '/v1/voice/rooms')).json().items).toEqual([]);
    expect((await post('bob', `/v1/voice/rooms/${room.id}/join`)).statusCode).toBe(404);

    const full: RoomMemberRow[] = Array.from({ length: STAGE_MAX }, (_, i) =>
      ({ room_id: 'r', user_id: `u${i}`, role: i === 0 ? 'host' : 'speaker', muted: false, joined_at: 0 }));
    expect(stageFull(full)).toBe(true);
    expect(stageFull(full.slice(1))).toBe(false);
    expect(validateRoom({ title: '  ok  ' })).toEqual({ ok: true, title: 'ok' });
    expect(validateRoom({ title: 'bad\nline' })).toMatchObject({ ok: false });
  });

  it('删号：本人建的房关掉、从别人的房里退出；未配置 LiveKit 时 503', async () => {
    const a = await signIn('alice'); await signIn('bob');
    const mine = (await post('alice', '/v1/voice/rooms', { title: 'mine' })).json();
    const theirs = (await post('bob', '/v1/voice/rooms', { title: 'theirs' })).json();
    await post('alice', `/v1/voice/rooms/${theirs.id}/join`);
    const mod = voiceAccountModule(voice);
    expect((await mod.export!(a) as { room_id: string }[]).map(r => r.room_id).sort()).toEqual([mine.id, theirs.id].sort());
    await mod.del!(a);
    expect((await voice.room(mine.id))!.closed_at).not.toBeNull();
    expect(await voice.member(theirs.id, a)).toBeNull();

    const bare = await buildApp({
      store: new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV }),
      content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
      accounts, firebase: { projectId: PROJECT, keys: k.keys },
    });
    expect((await bare.inject({ method: 'GET', url: '/v1/voice/rooms', headers: authed('alice') })).statusCode).toBe(503);
    await bare.close();
  });
});
