/** 开发期本地图片存储：presign → PUT 字节 → GET 读回；token 一次性、类型与大小校验、key 不能越界；发帖引用。 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { MemoryFeedStore } from '../../src/http/memory_feed.js';
import { LocalUploadStore } from '../../src/http/local_uploads.js';
import { socialAccountModule } from '../../src/http/social.js';
import { feedAccountModule } from '../../src/http/feed.js';
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

let app: FastifyInstance;
let dir: string;
let clock = at('2026-09-07T20:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-07T20:00:00+08:00');
  dir = mkdtempSync(path.join(os.tmpdir(), 'sensen-uploads-'));
  const accounts = new MemoryAccountStore();
  const social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  const feed = new MemoryFeedStore(async v => (await social.following(v, null, 1000)).items.map(f => f.followee_id));
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, feed, localUploads: new LocalUploadStore(dir),
    accountModules: [socialAccountModule(social), feedAccountModule(feed)],
  });
});
afterEach(async () => { await app.close(); rmSync(dir, { recursive: true, force: true }); });

const tok = (uid: string) => idToken(k, clock, {}, uid);
const authed = (uid: string) => ({ authorization: `Bearer ${tok(uid)}` });
const signIn = async (uid: string): Promise<string> =>
  (await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: tok(uid) } })).json().user_id as string;

describe('本地直传', () => {
  it('presign → PUT → GET 读回；token 一次性；类型不符 415；空体 413；越界 key 404', async () => {
    const a = await signIn('alice');
    const pre = await app.inject({ method: 'POST', url: '/v1/uploads', headers: authed('alice'), payload: { kind: 'post_image', content_type: 'image/jpeg', size: 3 } });
    expect(pre.statusCode).toBe(201);
    const j = pre.json();
    expect(j.key.startsWith(`u/${a}/20260907/`)).toBe(true);
    expect(j.url).toMatch(/^http:\/\/localhost(:80)?\/v1\/uploads\/local\/[0-9a-f]{32}$/);
    expect(j.public_url).toBe(`http://localhost:80/v1/files/${j.key}`.replace(':80/', j.url.includes(':80') ? ':80/' : '/'));
    const putPath = new URL(j.url).pathname;
    const bytes = Buffer.from([0xff, 0xd8, 0xff]);
    expect((await app.inject({ method: 'PUT', url: putPath, headers: { 'content-type': 'image/png' }, payload: bytes })).statusCode).toBe(415);
    const ok = await app.inject({ method: 'PUT', url: putPath, headers: { 'content-type': 'image/jpeg' }, payload: bytes });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().key).toBe(j.key);
    expect((await app.inject({ method: 'PUT', url: putPath, headers: { 'content-type': 'image/jpeg' }, payload: bytes })).statusCode).toBe(404);
    const got = await app.inject({ method: 'GET', url: `/v1/files/${j.key}` });
    expect(got.statusCode).toBe(200);
    expect(got.headers['content-type']).toContain('image/jpeg');
    expect(Buffer.from(got.rawPayload).equals(bytes)).toBe(true);
    expect((await app.inject({ method: 'GET', url: '/v1/files/u/../../etc/passwd' })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: `/v1/files/u/${a}/20260907/nope.jpg` })).statusCode).toBe(404);
    const post = await app.inject({ method: 'POST', url: '/v1/posts', headers: authed('alice'), payload: { idempotency_key: 'p1', text: 'pic', images: [{ key: j.key, w: 3, h: 1 }] } });
    expect(post.statusCode).toBe(201);
    await signIn('bob');
    const stolen = await app.inject({ method: 'POST', url: '/v1/posts', headers: authed('bob'), payload: { idempotency_key: 'p2', text: 'pic', images: [{ key: j.key }] } });
    expect(stolen.statusCode).toBe(400);
  });

  it('token 过期 410；presign 后 healthz 报 local 模式', async () => {
    await signIn('alice');
    const j = (await app.inject({ method: 'POST', url: '/v1/uploads', headers: authed('alice'), payload: { kind: 'post_image', content_type: 'image/png', size: 1 } })).json();
    clock += 11 * 60 * 1000;
    const late = await app.inject({ method: 'PUT', url: new URL(j.url).pathname, headers: { 'content-type': 'image/png' }, payload: Buffer.from([1]) });
    expect(late.statusCode).toBe(410);
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json()).toMatchObject({ uploads: true, uploads_mode: 'local' });
  });
});
