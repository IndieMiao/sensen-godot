import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { newInstallKey } from '../../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { at, SH } from '../domain/helpers.js';
import { ownerFarmView, visitorSnapshot, nearbyEntry, snapshotSlot } from '../../src/http/dto.js';
import { derive } from '../../src/domain/derive.js';

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const BLUEPRINTS = path.join(ROOT, 'assets', 'blueprints');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const bp = loadBlueprint(BLUEPRINTS, 'sh_a', 2)!;

let app: FastifyInstance;
let clock = at('2026-09-04T10:00:00+08:00');
let qa: Set<string>;

beforeEach(async () => {
  clock = at('2026-09-04T10:00:00+08:00');
  qa = new Set();
  const store = new MemoryStore({
    content, timezone: SH, blueprint: blueprintSets(bp),
    now: () => clock, contentVersion: CV,
  });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS,
    pepper: 'test-pepper', now: () => clock, qaPlayerIds: qa,
  });
});
afterEach(async () => { await app.close(); });

async function login() {
  const key = newInstallKey();
  const r = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: key } });
  return { key, ...r.json() as { player_id: string; token: string } };
}
const authed = (token: string) => ({ authorization: `Bearer ${token}` });

async function makeFarm(token: string, key = 'k1') {
  return app.inject({
    method: 'POST', url: '/v1/farms', headers: authed(token),
    payload: { idempotency_key: key, region_id: 'shanghai', layout_patch_id: 'sh_a', blueprint_revision: 2 },
  });
}

describe('鉴权', () => {
  it('同一 install_key 返回同一 player，但每次签发新 token', async () => {
    const key = newInstallKey();
    const a = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: key } });
    const b = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: key } });
    expect(a.json().player_id).toBe(b.json().player_id);
    expect(a.json().token).not.toBe(b.json().token);
  });

  it('install_key 必须是 32 位十六进制——可猜的设备标识会让人登进别人账号', async () => {
    for (const bad of ['device-1', '', 'ABCDEF', null])
      expect((await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: bad } })).statusCode)
        .toBe(400);
  });

  it('活跃 token 至多 5 个，超出淘汰最久未用的', async () => {
    const key = newInstallKey();
    const tokens: string[] = [];
    for (let i = 0; i < 6; i++) {
      clock += 1000;
      const r = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: key } });
      tokens.push(r.json().token);
    }
    const oldest = await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(tokens[0]) });
    const newest = await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(tokens[5]) });
    expect(oldest.statusCode).toBe(401);
    expect(newest.statusCode).toBe(404); // 认证通过，只是还没农场
  });

  it('token 闲置 90 天过期', async () => {
    const { token } = await login();
    clock += 91 * 24 * 3600_000;
    expect((await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) })).statusCode).toBe(401);
  });

  it('撤销全部会话后所有 token 失效', async () => {
    const { token } = await login();
    await app.inject({ method: 'DELETE', url: '/v1/auth/tokens', headers: authed(token) });
    expect((await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) })).statusCode).toBe(401);
  });

  it('换绑 install_key 需要同时持有 token 与旧 key——否则泄露者能抢先接管', async () => {
    const { key, token } = await login();
    const wrong = await app.inject({
      method: 'POST', url: '/v1/auth/rotate-install-key', headers: authed(token),
      payload: { current_install_key: newInstallKey(), new_install_key: newInstallKey() },
    });
    expect(wrong.statusCode).toBe(401);
    const nk = newInstallKey();
    const good = await app.inject({
      method: 'POST', url: '/v1/auth/rotate-install-key', headers: authed(token),
      payload: { current_install_key: key, new_install_key: nk },
    });
    expect(good.statusCode).toBe(200);
    // 换绑后连调用者自己的 token 也失效
    expect((await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) })).statusCode).toBe(401);
    // 旧 key 再也登不进原账号
    const relog = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: key } });
    const nlog = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: nk } });
    expect(relog.json().player_id).not.toBe(nlog.json().player_id);
  });
});

describe('regions 与建场', () => {
  it('/regions 只给 id / timezone / candidates，不含名字与中心点', async () => {
    const r = await app.inject({ method: 'GET', url: '/v1/regions' });
    const body = r.json() as { regions: Record<string, unknown>[] };
    for (const region of body.regions) {
      expect(Object.keys(region).sort()).toEqual(['candidates', 'id', 'timezone']);
      for (const c of region.candidates as Record<string, unknown>[])
        expect(Object.keys(c).sort()).toEqual(['blueprint_revision', 'layout_patch_id'].includes('blueprint_revision')
          ? ['layout_patch_id', 'revision'] : ['layout_patch_id', 'revision']);
    }
  });

  it('建场返回 201，同 key 重放返回 200 且是同一农场', async () => {
    const { token } = await login();
    const a = await makeFarm(token);
    expect(a.statusCode).toBe(201);
    const b = await makeFarm(token);
    expect(b.statusCode).toBe(200);
    expect(b.json().farm_id).toBe(a.json().farm_id);
  });

  it('同 key 换地区返回 409——建场也要比对 payload hash', async () => {
    const { token } = await login();
    await makeFarm(token);
    const r = await app.inject({
      method: 'POST', url: '/v1/farms', headers: authed(token),
      payload: { idempotency_key: 'k1', region_id: 'los_angeles', layout_patch_id: 'la_a', blueprint_revision: 2 },
    });
    expect(r.statusCode).toBe(409);
    expect(r.json().code).toBe('IDEMPOTENCY_MISMATCH');
  });

  it('旧 revision 被拒——r1 用的是当时的 canonical 文法', async () => {
    const { token } = await login();
    const r = await app.inject({
      method: 'POST', url: '/v1/farms', headers: authed(token),
      payload: { idempotency_key: 'k9', region_id: 'shanghai', layout_patch_id: 'sh_a', blueprint_revision: 1 },
    });
    expect(r.statusCode).toBe(422);
    expect(r.json().code).toBe('STALE_REVISION');
  });

  it('新农场是 12 格荒地、钱包 180、已发第 0 章 Grant', async () => {
    const { token } = await login();
    const body = (await makeFarm(token)).json();
    expect(Object.keys(body.state.cells)).toHaveLength(12);
    expect(body.state.wallet).toBe(180);
    expect(body.state.inventory.seeds.R.bound).toBe(6);
    expect(body.state.inventory.seeds.L.bound).toBe(3);
    expect(body.visit_access).toBe('only_me'); // 默认不可访问（PRD L659）
    expect(body.location_visible).toBe(true);
  });
});

describe('命令端点', () => {
  const cmd = (token: string, body: object) =>
    app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: authed(token), payload: body });

  it('版本递增，base_version 过期返回 409 并带最新状态', async () => {
    const { token } = await login();
    await makeFarm(token);
    const a = await cmd(token, { idempotency_key: 'c1', base_version: 0, type: 'clear_cells', payload: { cell_ids: ['26,42'] } });
    expect(a.statusCode).toBe(200);
    expect(a.json().version).toBe(1);
    const stale = await cmd(token, { idempotency_key: 'c2', base_version: 0, type: 'clear_cells', payload: { cell_ids: ['27,42'] } });
    expect(stale.statusCode).toBe(409);
    expect(stale.json().code).toBe('VERSION_CONFLICT');
    expect(stale.json().version).toBe(1);
  });

  it('同 key 同 payload 重放拿回原结果，applied 与 rejected 都能重放', async () => {
    const { token } = await login();
    await makeFarm(token);
    const env = { idempotency_key: 'c1', base_version: 0, type: 'clear_cells', payload: { cell_ids: ['26,42'] } };
    const a = await cmd(token, env);
    const b = await cmd(token, env);
    expect(b.json().outcome).toBe('replayed');
    expect(b.json().version).toBe(a.json().version);

    const bad = { idempotency_key: 'c2', base_version: 1, type: 'till_cells', payload: { cell_ids: ['27,42'] } };
    const r1 = await cmd(token, bad);
    expect(r1.statusCode).toBe(422);
    const r2 = await cmd(token, bad);
    expect(r2.json().outcome).toBe('replayed');
    expect(r2.json().replayed_outcome).toBe('rejected');
  });

  it('同 key 不同 payload 返回 409 IDEMPOTENCY_MISMATCH', async () => {
    const { token } = await login();
    await makeFarm(token);
    await cmd(token, { idempotency_key: 'c1', base_version: 0, type: 'clear_cells', payload: { cell_ids: ['26,42'] } });
    const r = await cmd(token, { idempotency_key: 'c1', base_version: 0, type: 'clear_cells', payload: { cell_ids: ['27,42'] } });
    expect(r.statusCode).toBe(409);
    expect(r.json().code).toBe('IDEMPOTENCY_MISMATCH');
  });

  it('领域错误返回 422 且版本不变', async () => {
    const { token } = await login();
    await makeFarm(token);
    const r = await cmd(token, { idempotency_key: 'x', base_version: 0, type: 'till_cells', payload: { cell_ids: ['26,42'] } });
    expect(r.statusCode).toBe(422);
    expect(r.json().code).toBe('WRONG_STATE');
    const me = await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) });
    expect(me.json().version).toBe(0);
  });

  it('QA 命令对非白名单玩家返回 403', async () => {
    const { token, player_id } = await login();
    await makeFarm(token);
    const denied = await cmd(token, { idempotency_key: 'q1', base_version: 0, type: 'qa_skip_days', payload: { days: 1 } });
    expect(denied.statusCode).toBe(403);
    expect(denied.json().code).toBe('QA_ONLY');
    qa.add(player_id);
    const allowed = await cmd(token, { idempotency_key: 'q2', base_version: 0, type: 'qa_skip_days', payload: { days: 1 } });
    expect(allowed.statusCode).not.toBe(403);
  });

  it('响应的 server_time 就是本次采样的时间', async () => {
    const { token } = await login();
    await makeFarm(token);
    const r = await cmd(token, { idempotency_key: 'c1', base_version: 0, type: 'clear_cells', payload: { cell_ids: ['26,42'] } });
    expect(r.json().server_time).toBe(clock);
  });

  it('读路径不因时钟回拨而倒退', async () => {
    const { token } = await login();
    await makeFarm(token);
    await cmd(token, { idempotency_key: 'c1', base_version: 0, type: 'clear_cells', payload: { cell_ids: ['26,42'] } });
    const before = (await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) })).json();
    clock -= 3600_000;
    const after = (await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) })).json();
    expect(after.derived.player_day_id).toBe(before.derived.player_day_id);
    expect(after.server_time).toBeGreaterThanOrEqual(before.server_time);
  });
});

describe('健康检查', () => {
  it('带内容版本与领域版本', async () => {
    const r = await app.inject({ method: 'GET', url: '/v1/healthz' });
    expect(r.json()).toMatchObject({ ok: true, db: true, content_version: CV });
  });
});
