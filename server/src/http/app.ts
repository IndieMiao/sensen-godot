/**
 * Fastify 应用。测试用 `app.inject`，不起真实端口。
 *
 * 错误码映射见 spec §7.4；所有响应带 `server_time`，命令响应里的 `server_time` 就是这次
 * 事务采样的 `effectiveNow`（Codex 三审 O-M1）。
 */
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { parseBlueprint, validate } from 'blueprint-core';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { Command, CommandEnvelope } from '../domain/commands.js';
import { isQaCommand } from '../domain/commands.js';
import { contentVersion, loadContent, type Content } from '../domain/content.js';
import { derive } from '../domain/derive.js';
import type { Ctx } from '../domain/reducer.js';
import { createInitialState } from '../domain/state.js';
import { playerDayId } from '../domain/time.js';
import { DOMAIN_VERSION } from '../domain/version.js';
import { installKeyHmac, isValidInstallKey, safeEqualHex, tokenHash } from './auth.js';
import { ownerFarmView, type FarmRow } from './dto.js';
import { payloadHash } from './hash.js';
import type { Store } from './store.js';

export interface AppDeps {
  store: Store;
  content: Content;
  contentVersion: string;
  blueprintDir: string;
  regionsFile: string;
  pepper: string;
  now: () => number;
  gitSha?: string;
  /** 哪些 player 建出来的农场带 qa 标记；客户端不能自设。 */
  qaPlayerIds?: Set<string>;
}

interface Regions {
  regions: { id: string; timezone: string; candidates: { layout_patch_id: string; revision: number }[] }[];
}

export async function buildApp(deps: AppDeps): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(rateLimit, { global: false });
  const regions = JSON.parse(readFileSync(deps.regionsFile, 'utf8')) as Regions;

  const auth = async (req: FastifyRequest): Promise<{ id: string } | null> => {
    const raw = req.headers.authorization;
    if (!raw?.startsWith('Bearer ')) return null;
    return deps.store.playerByToken(tokenHash(raw.slice(7)), deps.now());
  };

  app.post('/v1/auth/anonymous', {
    config: { rateLimit: { max: 10, timeWindow: '1 hour' } },
  }, async (req, reply) => {
    const body = req.body as { install_key?: unknown };
    if (!isValidInstallKey(body?.install_key))
      return reply.code(400).send({ code: 'SCHEMA', message: 'install_key 需为 32 位十六进制' });
    const { player, token } = await deps.store.authAnonymous(installKeyHmac(body.install_key, deps.pepper));
    return reply.send({ player_id: player.id, token, server_time: deps.now() });
  });

  app.delete('/v1/auth/token', async (req, reply) => {
    const raw = req.headers.authorization;
    if (!raw?.startsWith('Bearer ')) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    await deps.store.revokeToken(tokenHash(raw.slice(7)));
    return reply.send({ ok: true, server_time: deps.now() });
  });

  app.delete('/v1/auth/tokens', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    await deps.store.revokeAllTokens(p.id);
    return reply.send({ ok: true, server_time: deps.now() });
  });

  /**
   * 换绑安装密钥。**同时需要有效 token 与当前 install_key**：只要 token 的话，拿到
   * install_key 的人可以先登录再抢先换绑，把真正的用户锁在外面（Codex 三审 V3-C2）。
   * 成功后撤销包含调用者在内的全部会话。
   */
  app.post('/v1/auth/rotate-install-key', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const body = req.body as { current_install_key?: unknown; new_install_key?: unknown };
    if (!isValidInstallKey(body?.current_install_key) || !isValidInstallKey(body?.new_install_key))
      return reply.code(400).send({ code: 'SCHEMA' });
    const stored = await deps.store.playerHmac(p.id);
    if (!stored || !safeEqualHex(stored, installKeyHmac(body.current_install_key, deps.pepper)))
      return reply.code(401).send({ code: 'UNAUTHENTICATED', message: 'current_install_key 不匹配' });
    await deps.store.rotateInstallKey(p.id, installKeyHmac(body.new_install_key, deps.pepper));
    await deps.store.revokeAllTokens(p.id);
    return reply.send({ ok: true, server_time: deps.now() });
  });

  /** 只给 id / timezone / candidates——名字、中心点由客户端从本地 regions.json 取（决策②）。 */
  app.get('/v1/regions', async (_req, reply) => reply.send({
    regions: regions.regions.map(r => ({
      id: r.id, timezone: r.timezone,
      candidates: r.candidates.map(c => ({ layout_patch_id: c.layout_patch_id, revision: c.revision })),
    })),
    server_time: deps.now(),
  }));

  app.post('/v1/farms', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const b = req.body as { idempotency_key?: string; region_id?: string; layout_patch_id?: string; blueprint_revision?: number };
    if (!b?.idempotency_key || !b.region_id || !b.layout_patch_id || !Number.isInteger(b.blueprint_revision))
      return reply.code(400).send({ code: 'SCHEMA' });
    const region = regions.regions.find(r => r.id === b.region_id);
    const cand = region?.candidates.find(c => c.layout_patch_id === b.layout_patch_id);
    if (!region || !cand) return reply.code(400).send({ code: 'SCHEMA', message: '未知候选' });
    // 只接受 regions.json 当前 revision：旧 revision 用的是当时的 canonical 文法（V3-I2）。
    if (cand.revision !== b.blueprint_revision)
      return reply.code(422).send({ code: 'STALE_REVISION', message: `当前 revision 为 ${cand.revision}` });

    const bp = loadBlueprint(deps.blueprintDir, b.layout_patch_id, b.blueprint_revision);
    if (!bp) return reply.code(422).send({ code: 'BLUEPRINT_MISMATCH' });

    const now = deps.now();
    const hash = payloadHash({
      idempotency_key: b.idempotency_key, base_version: 0, type: 'create_farm',
      payload: { region_id: b.region_id, layout_patch_id: b.layout_patch_id, blueprint_revision: b.blueprint_revision },
    });
    const res = await deps.store.createFarm({
      ownerId: p.id, idempotencyKey: b.idempotency_key, payloadHash: hash,
      regionId: b.region_id, layoutPatchId: b.layout_patch_id, blueprintRevision: b.blueprint_revision,
      build: () => buildFarmRow(p.id, region.id, region.timezone, bp, deps, now),
    });
    if (res.kind === 'idempotency_mismatch')
      return reply.code(409).send({ code: 'IDEMPOTENCY_MISMATCH' });
    const d = derive(res.farm.state, now, region.timezone, deps.content);
    return reply.code(res.kind === 'created' ? 201 : 200).send(ownerFarmView(res.farm, d, now));
  });

  app.get('/v1/farms/me', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const farm = await deps.store.farmByOwner(p.id);
    if (!farm) return reply.code(404).send({ code: 'NO_FARM' });
    const tz = timezoneOf(regions, farm.region_id);
    // 读路径同样先 clamp 成 max(采样, last) 再 derive，但**不写回**：时钟回拨时读取结果
    // 不会倒退（Codex 三审 O-I3）。
    const now = Math.max(deps.now(), farm.state.clock.last_effective_now);
    return reply.send(ownerFarmView(farm, derive(farm.state, now, tz, deps.content), now));
  });

  app.post('/v1/farms/me/commands', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const env = req.body as CommandEnvelope;
    if (!env?.idempotency_key || typeof env.type !== 'string' || !Number.isInteger(env.base_version))
      return reply.code(400).send({ code: 'SCHEMA' });
    const farm = await deps.store.farmByOwner(p.id);
    if (!farm) return reply.code(404).send({ code: 'NO_FARM' });
    if (isQaCommand(env.type) && !deps.qaPlayerIds?.has(p.id))
      return reply.code(403).send({ code: 'QA_ONLY' });

    const cmd = { type: env.type, ...(env.payload ?? {}) } as Command;
    const out = await deps.store.applyCommand(p.id, env, cmd);
    switch (out.kind) {
      case 'applied':
        return reply.send({ outcome: 'applied', ...(out.body as object) });
      case 'replayed':
        return reply.send({ outcome: 'replayed', replayed_outcome: out.record.outcome,
          ...(out.record.result as object ?? {}), server_time: deps.now() });
      case 'rejected':
        return reply.code(422).send({ outcome: 'rejected', code: out.code, detail: out.detail, server_time: deps.now() });
      case 'idempotency_mismatch':
        return reply.code(409).send({ code: 'IDEMPOTENCY_MISMATCH', server_time: deps.now() });
      case 'version_conflict': {
        const tz = timezoneOf(regions, out.farm.region_id);
        const now = deps.now();
        return reply.code(409).send({ code: 'VERSION_CONFLICT',
          ...ownerFarmView(out.farm, derive(out.farm.state, now, tz, deps.content), now) });
      }
      case 'version_mismatch':
        return reply.code(503).send({ code: 'VERSION_MISMATCH', server_time: deps.now() });
      default:
        return reply.code(404).send({ code: 'NO_FARM' });
    }
  });

  app.get('/v1/healthz', async (_req, reply) => reply.send({
    ok: true, db: true, git_sha: deps.gitSha ?? 'dev',
    content_version: deps.contentVersion, domain_version: DOMAIN_VERSION,
    server_time: deps.now(),
  }));

  return app;
}

const timezoneOf = (r: Regions, id: string): string =>
  r.regions.find(x => x.id === id)?.timezone ?? 'UTC';

export function loadBlueprint(dir: string, id: string, rev: number) {
  try {
    const file = path.join(dir, id, `r${rev}`, 'farm_blueprint.json');
    const bp = parseBlueprint(JSON.parse(readFileSync(file, 'utf8')));
    // 校验先于 checksum：checksum 只证明没被改过，不证明合法。
    if (validate(bp).length > 0) return null;
    return bp;
  } catch {
    return null;
  }
}

function buildFarmRow(
  ownerId: string, regionId: string, timezone: string,
  bp: ReturnType<typeof parseBlueprint>, deps: AppDeps, now: number,
): FarmRow {
  const { cultivable, reserved } = blueprintSets(bp);
  const d0 = deps.content.weather.script[0];
  const state = createInitialState({
    player_day_id: playerDayId(now, timezone), field_condition: d0, now,
    wallet: deps.content.economy.initial_wallet,
    bed_cells: [...cultivable].filter(x => !reserved.has(x)),
    reserved_cells: [...reserved],
  });
  // 第 0 章 Grant 在建场时发（不经过换日路径）。
  for (const [crop, n] of Object.entries(deps.content.chapters.chapters[0].grants))
    if (!crop.startsWith('_')) state.inventory.seeds[crop as 'R'].bound += n ?? 0;
  state.chapters[0].grants_issued = true;
  return {
    id: cryptoRandomId(), owner_id: ownerId, region_id: regionId,
    layout_patch_id: bp.layout_patch_id, blueprint_revision: bp.revision,
    version: 0, location_visible: true, visit_access: 'only_me', state,
  };
}

export function blueprintSets(bp: ReturnType<typeof parseBlueprint>): Ctx['blueprint'] {
  const cultivable = new Set<string>();
  bp.masks.cultivable.forEach((row, j) => {
    for (let i = 0; i < row.length; i++) if (row[i] === '1') cultivable.add(`${i},${j}`);
  });
  const reserved = new Set(bp.anchors.reserved_bed.cells.map(c => `${c[0]},${c[1]}`));
  return { cultivable, reserved };
}

const cryptoRandomId = (): string => randomUUID();

export { contentVersion, loadContent };
