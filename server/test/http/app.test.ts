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
let memoryStore: MemoryStore;

beforeEach(async () => {
  clock = at('2026-09-04T10:00:00+08:00');
  qa = new Set();
  const store = new MemoryStore({
    content, timezone: SH, blueprint: blueprintSets(bp),
    now: () => clock, contentVersion: CV,
  });
  memoryStore = store;
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

describe('journey HTTP commands', () => {
  it('persists a hosted gathering once and rejects another owner or a stale replay', async () => {
    const { token, player_id } = await login();
    const created = (await makeFarm(token)).json();
    const farm = (await memoryStore.farmByOwner(player_id))!;
    farm.state.journey!.facts.push(...content.journey.gatherings.requires);
    farm.state.journey!.workshop = { sequence: 0, stock: { planter: 1 }, displays: {} };
    farm.state.journey!.gathering = { sequence: 1, planned: 'garden', memories: [] };
    farm.state.inventory.dishes.tea = 1;
    const payload = { idempotency_key: 'host-garden', base_version: created.version,
      type: 'host_journey_gathering', payload: { theme: 'garden', sequence: 1 } };
    const request = { method: 'POST' as const, url: '/v1/farms/me/commands', headers: authed(token), payload };
    const first = await app.inject(request);
    expect(first.statusCode).toBe(200);
    expect(first.json().state.journey.gathering).toEqual({ sequence: 2, current: 'garden', memories: ['garden'] });
    expect(first.json().state.inventory.dishes.tea).toBe(0);
    const replay = await app.inject(request);
    expect(replay.json().outcome).toBe('replayed');
    expect(replay.json().state).toEqual(first.json().state);
    const duplicate = await app.inject({ ...request, payload: { ...payload, idempotency_key: 'another-host', base_version: first.json().version } });
    expect(duplicate.statusCode).toBe(422);
    const visitor = await login();
    await makeFarm(visitor.token);
    const forbidden = await app.inject({ ...request, headers: authed(visitor.token) });
    expect(forbidden.statusCode).toBe(422);
    const saved = (await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) })).json();
    expect(saved.state).toEqual(first.json().state);
  });
  it('starts normal farms on the journey and replays an accepted gathering only once', async () => {
    const { token } = await login();
    const farm = (await makeFarm(token)).json();
    expect(farm.state.journey.version).toBe(1);
    const payload = { idempotency_key: 'gather', base_version: farm.version,
      type: 'collect_resource', payload: { node_id: 'nursery_west', round: 0 } };
    const request = { method: 'POST' as const, url: '/v1/farms/me/commands', headers: authed(token), payload };
    const first = await app.inject(request);
    expect(first.statusCode).toBe(200);
    expect(first.json().state.journey.wood).toBe(1);
    const replay = (await app.inject(request)).json();
    expect(replay.outcome).toBe('replayed');
    expect(replay.state).toEqual(first.json().state);
    expect(replay.version).toEqual(first.json().version);
    const duplicate = await app.inject({ ...request, payload: { ...payload, idempotency_key: 'duplicate', base_version: first.json().version } });
    expect(duplicate.statusCode).toBe(422);
    for (const bad of [{ node_id: 'nursery_east', round: -1 }, { node_id: {}, round: 0 }, { node_id: 'nursery_east' }]) {
      const result = await app.inject({ ...request, payload: { ...payload, idempotency_key: JSON.stringify(bad), base_version: first.json().version, payload: bad } });
      expect(result.statusCode).toBe(422);
    }
    const state = (await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) })).json();
    expect(state.state.journey.wood).toBe(1);
  });
});

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
  it('/regions includes placement support and bounds without names or template centers', async () => {
    const r = await app.inject({ method: 'GET', url: '/v1/regions' });
    const body = r.json() as { farm_placement_version: number; regions: Record<string, unknown>[] };
    expect(body.farm_placement_version).toBe(1);
    for (const region of body.regions) {
      expect(Object.keys(region).sort()).toEqual(['candidates', 'id', 'placement_bounds', 'timezone']);
      expect(region.placement_bounds).toHaveLength(4);
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

describe('导演模式端到端', () => {
  const cmd = (token: string, body: object) =>
    app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: authed(token), payload: body });

  it('480 倍下 3 分钟真实时间跨过一个玩家日，且读路径也看得到', async () => {
    // 读路径必须同样过 QA 变换，否则加速后 GET /farms/me 看到的还是没加速的时间。
    const { token, player_id } = await login();
    await makeFarm(token);
    qa.add(player_id);
    const before = await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) });
    expect(before.json().state.clock.player_day_id).toBe('2026-09-04');

    const set = await cmd(token, {
      idempotency_key: 'qa1', base_version: 0, type: 'qa_set_clock', payload: { scale: 480 } });
    expect(set.statusCode).toBe(200);

    clock += 3 * 60_000;                       // 真实过了 3 分钟
    const after = await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) });
    expect(after.json().server_time - before.json().server_time).toBe(24 * 3600_000);
    expect(after.json().derived.player_day_id).toBe('2026-09-05');
  });

  it('qa_skip_days 之后新的一天真的被物化，不只是派生', async () => {
    const { token, player_id } = await login();
    await makeFarm(token);
    qa.add(player_id);
    const skip = await cmd(token, {
      idempotency_key: 'qa2', base_version: 0, type: 'qa_skip_days', payload: { days: 1 } });
    expect(skip.statusCode).toBe(200);
    // 再发一条普通命令，materializeDay 会把换日写进状态。
    const next = await cmd(token, {
      idempotency_key: 'c1', base_version: skip.json().version,
      type: 'clear_cells', payload: { cell_ids: [Object.keys(skip.json().state.cells)[0]] } });
    expect(next.statusCode).toBe(200);
    expect(next.json().state.clock.player_day_id).toBe('2026-09-05');
    expect(next.json().state.clock.weather_day_index).toBe(1);
  });

  it('倍率调回 1 后有效时间不倒退', async () => {
    const { token, player_id } = await login();
    await makeFarm(token);
    qa.add(player_id);
    await cmd(token, { idempotency_key: 'f1', base_version: 0, type: 'qa_set_clock', payload: { scale: 60 } });
    clock += 60_000;
    const fast = await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) });
    const back = await cmd(token, {
      idempotency_key: 'f2', base_version: fast.json().version,
      type: 'qa_set_clock', payload: { scale: 1 } });
    expect(back.statusCode).toBe(200);
    const after = await app.inject({ method: 'GET', url: '/v1/farms/me', headers: authed(token) });
    expect(after.json().server_time).toBeGreaterThanOrEqual(fast.json().server_time);
  });
});


describe('访问骨架（G2）', () => {
  const cmd = (token: string, body: object) =>
    app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: authed(token), payload: body });
  async function farmOf(token: string) {
    const r = await makeFarm(token);
    return { farm_id: r.json().farm_id as string, version: r.json().version as number,
      cells: Object.keys(r.json().state.cells) as string[] };
  }

  it('nearby 需要登录，且 region_id 必须是已知地区', async () => {
    const anon = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai' });
    expect(anon.statusCode).toBe(401);
    const { token } = await login();
    const bad = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=mars', headers: authed(token) });
    expect(bad.statusCode).toBe(400);
    const none = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: authed(token) });
    expect(none.statusCode).toBe(200);
    expect(none.json()).toMatchObject({ region_id: 'shanghai', count: 0, entries: [] });
  });

  it('NearbyEntry 字段集精确：farm_id / avatar_ref / nursery_stage (+region_id)', async () => {
    const a = await login();
    const fa = await farmOf(a.token);
    await cmd(a.token, { idempotency_key: 'v1', base_version: fa.version, type: 'set_visit_access', payload: { access: 'anyone' } });
    const b = await login();
    const seen = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: authed(b.token) });
    const entry = seen.json().entries[0];
    expect(Object.keys(entry).sort()).toEqual(['avatar_ref', 'farm_id', 'nursery_stage', 'region_id']);
    expect(entry.avatar_ref).toMatch(/^seed:[0-9a-f]{8}$/);
    expect(entry.farm_id).toBe(fa.farm_id);
    // 关掉位置可见：region_id 消失，条目仍在
    await cmd(a.token, { idempotency_key: 'l1', base_version: fa.version + 1, type: 'set_location_visible', payload: { visible: false } });
    const hidden = await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: authed(b.token) });
    expect(Object.keys(hidden.json().entries[0]).sort()).toEqual(['avatar_ref', 'farm_id', 'nursery_stage']);
  });

  it('快照四种组合：only_me 一律 404，anyone 200 且 location_visible 决定 region_id', async () => {
    const a = await login();
    const fa = await farmOf(a.token);
    const b = await login();
    const url = `/v1/farms/${fa.farm_id}/snapshot`;
    let v = fa.version;
    for (const combo of [
      { access: 'only_me', visible: true, status: 404 },
      { access: 'only_me', visible: false, status: 404 },
      { access: 'anyone', visible: true, status: 200, region: true },
      { access: 'anyone', visible: false, status: 200, region: false },
    ]) {
      await cmd(a.token, { idempotency_key: `a${v}`, base_version: v++, type: 'set_visit_access', payload: { access: combo.access } });
      await cmd(a.token, { idempotency_key: `l${v}`, base_version: v++, type: 'set_location_visible', payload: { visible: combo.visible } });
      clock += 15 * 60_000; // 每个组合换一个槽，避免上一组合的快照被复用
      const r = await app.inject({ method: 'GET', url, headers: authed(b.token) });
      expect(r.statusCode, JSON.stringify(combo)).toBe(combo.status);
      if (combo.status === 200) expect('region_id' in r.json()).toBe(combo.region);
    }
    const missing = await app.inject({ method: 'GET', url: '/v1/farms/00000000-0000-4000-8000-000000000000/snapshot', headers: authed(b.token) });
    expect(missing.statusCode).toBe(404);
  });

  it('快照不含任何主人私有字段', async () => {
    const a = await login();
    const fa = await farmOf(a.token);
    await cmd(a.token, { idempotency_key: 'v1', base_version: fa.version, type: 'set_visit_access', payload: { access: 'anyone' } });
    const b = await login();
    const r = await app.inject({ method: 'GET', url: `/v1/farms/${fa.farm_id}/snapshot`, headers: authed(b.token) });
    expect(Object.keys(r.json()).sort()).toEqual([
      'avatar_ref', 'beds_unlocked', 'blueprint_revision', 'cells', 'farm_id', 'layout_patch_id', 'nursery',
      'props', 'region_id', 'server_time', 'snapshot_revision', 'snapshot_taken_at', 'weather_snapshot',
    ]);
    const text = JSON.stringify(r.json());
    for (const bad of ['wallet', 'owner_id', 'inventory', 'residents', 'xp', 'lat', 'lng', 'ready_at'])
      expect(text, bad).not.toContain(`"${bad}"`);
  });
});
