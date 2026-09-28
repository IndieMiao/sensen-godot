/**
 * 邮箱账户接口（SGODOT-135）。
 *
 * 决定 1：大陆开发阶段必须可用，所以邮箱账户自建，不经 Firebase；会话仍是本服务签发的
 * opaque token，与游客 token 同一张表、同一套上限与闲置过期。账号登录拿到的是"账号玩家"
 * 的 token，农场、联机、队伍照旧按 player id 走。
 *
 * 防枚举：发码接口对不存在的邮箱也回 200；登录失败统一 INVALID_CREDENTIALS，且用户不存在时
 * 照样跑一次 scrypt，耗时不泄露注册与否。
 */
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { PlayerRow, Store, UserRow } from '../http/store.js';
import { burnPasswordCheck, hashPassword, isValidPassword, verifyPassword } from './password.js';
import { CODE_MAX_ATTEMPTS, CODE_RESEND_MS, CODE_TTL_MS, codeHash, emailKey, isCodePurpose, isValidCode, newCode,
  normalizeEmail, type CodePurpose } from './email.js';
import type { Mailer } from './mailer.js';

export interface AccountRouteDeps {
  store: Store;
  pepper: string;
  now: () => number;
  mailer: Mailer;
  /** 这个域名下的邮箱固定用 qaEmailCode、不发信（自动化与 QA 账号）。 */
  qaEmailDomain?: string;
  qaEmailCode?: string;
  /** 撤销会话后断开该玩家的联机连接。 */
  closeSessions?: (playerId: string) => Promise<void>;
  /** 删号前清理该玩家的联机状态（离队、离房）。 */
  beforeDelete?: (playerId: string) => Promise<void>;
  log?: (line: string) => void;
}

export function userView(u: UserRow, player?: PlayerRow) {
  return {
    user_id: u.id, email: u.email, email_verified: u.email_verified, created_at: u.created_at,
    ...(player ? { player_id: player.id } : {}),
  };
}

const bearer = (req: FastifyRequest) => {
  const raw = req.headers.authorization;
  return raw?.startsWith('Bearer ') ? raw.slice(7) : '';
};

export function registerAccounts(app: FastifyInstance, deps: AccountRouteDeps,
  auth: (req: FastifyRequest) => Promise<PlayerRow | null>) {
  const log = deps.log ?? (line => console.log(line));
  const isQa = (email: string) => Boolean(deps.qaEmailDomain && deps.qaEmailCode && email.endsWith('@' + deps.qaEmailDomain));
  const bodyEmail = (req: FastifyRequest) => normalizeEmail((req.body as { email?: unknown } | undefined)?.email);

  const loginLimit = app.createRateLimit({ max: 10, timeWindow: '15 minutes', keyGenerator: req => {
    const email = bodyEmail(req);
    return email ? 'login:' + emailKey(email, deps.pepper) : 'login-invalid:' + req.ip;
  } });
  const codeLimit = app.createRateLimit({ max: 8, timeWindow: '1 hour', keyGenerator: req => {
    const email = bodyEmail(req);
    return email ? 'code:' + emailKey(email, deps.pepper) : 'code-invalid:' + req.ip;
  } });
  const limited = async (limit: typeof loginLimit, req: FastifyRequest, reply: FastifyReply) => {
    const quota = await limit(req);
    if (!quota.isAllowed && quota.isExceeded) {
      await reply.code(429).header('retry-after', quota.ttlInSeconds).send({ code: 'RATE_LIMITED', server_time: deps.now() });
      return true;
    }
    return false;
  };

  const sendCode = async (email: string, purpose: CodePurpose): Promise<{ ok: true } | { ok: false; retry_after_ms: number }> => {
    const code = isQa(email) ? deps.qaEmailCode! : newCode();
    const saved = await deps.store.saveEmailCode(email, purpose, codeHash(email, purpose, code, deps.pepper), deps.now(), CODE_TTL_MS, CODE_RESEND_MS);
    if (saved.kind === 'cooldown') return { ok: false, retry_after_ms: saved.retry_after_ms };
    if (!isQa(email)) {
      try { await deps.mailer.sendCode(email, code, purpose); }
      catch (error) { log(`[mail] send failed for ${emailKey(email, deps.pepper)}: ${(error as Error).message}`); }
    }
    return { ok: true };
  };
  const consume = (email: string, purpose: CodePurpose, code: string) =>
    deps.store.consumeEmailCode(email, purpose, codeHash(email, purpose, code, deps.pepper), deps.now(), CODE_MAX_ATTEMPTS);
  const codeError = (outcome: string) => outcome === 'expired' ? 'CODE_EXPIRED' : outcome === 'locked' ? 'CODE_LOCKED' : 'CODE_INVALID';

  /** 当前请求的账号；游客 token 返回 LOGIN_REQUIRED。 */
  const account = async (req: FastifyRequest, reply: FastifyReply): Promise<{ player: PlayerRow; user: UserRow } | null> => {
    const player = await auth(req);
    if (!player) { await reply.code(401).send({ code: 'UNAUTHENTICATED', server_time: deps.now() }); return null; }
    const user = player.user_id ? await deps.store.userById(player.user_id) : null;
    if (!user) { await reply.code(401).send({ code: 'LOGIN_REQUIRED', server_time: deps.now() }); return null; }
    return { player, user };
  };

  app.post('/v1/auth/email/register', { config: { rateLimit: { max: 20, timeWindow: '1 hour' } } }, async (req, reply) => {
    const body = req.body as { email?: unknown; password?: unknown } | undefined;
    const email = normalizeEmail(body?.email);
    if (!email) return reply.code(400).send({ code: 'INVALID_EMAIL', server_time: deps.now() });
    if (!isValidPassword(body?.password)) return reply.code(400).send({ code: 'WEAK_PASSWORD', server_time: deps.now() });
    const created = await deps.store.createEmailUser(email, await hashPassword(body.password), deps.now());
    if (created.kind === 'email_taken') return reply.code(409).send({ code: 'EMAIL_TAKEN', server_time: deps.now() });
    const session = await deps.store.authUser(created.user.id, deps.now());
    const sent = await sendCode(email, 'verify');
    return reply.code(201).send({ token: session.token, ...userView(created.user, session.player), verification_sent: sent.ok, server_time: deps.now() });
  });

  app.post('/v1/auth/email/login', { config: { rateLimit: { max: 120, timeWindow: '1 hour' } } }, async (req, reply) => {
    if (await limited(loginLimit, req, reply)) return;
    const body = req.body as { email?: unknown; password?: unknown } | undefined;
    const email = normalizeEmail(body?.email);
    if (!email || typeof body?.password !== 'string' || body.password.length > 256)
      return reply.code(400).send({ code: 'SCHEMA', server_time: deps.now() });
    const user = await deps.store.userByEmail(email);
    if (!user) { await burnPasswordCheck(body.password); return reply.code(401).send({ code: 'INVALID_CREDENTIALS', server_time: deps.now() }); }
    if (!await verifyPassword(body.password, user.password_hash)) return reply.code(401).send({ code: 'INVALID_CREDENTIALS', server_time: deps.now() });
    const session = await deps.store.authUser(user.id, deps.now());
    return reply.send({ token: session.token, ...userView(user, session.player), server_time: deps.now() });
  });

  /** 发码：verify（已登录账号验证邮箱）或 reset（找回密码）。邮箱不存在也回 200。 */
  app.post('/v1/auth/email/code', { config: { rateLimit: { max: 60, timeWindow: '1 hour' } } }, async (req, reply) => {
    if (await limited(codeLimit, req, reply)) return;
    const body = req.body as { email?: unknown; purpose?: unknown } | undefined;
    const email = normalizeEmail(body?.email);
    if (!email || !isCodePurpose(body?.purpose)) return reply.code(400).send({ code: 'SCHEMA', server_time: deps.now() });
    const user = await deps.store.userByEmail(email);
    if (user && !(body.purpose === 'verify' && user.email_verified)) {
      const sent = await sendCode(email, body.purpose);
      if (!sent.ok) return reply.code(429).header('retry-after', Math.ceil(sent.retry_after_ms / 1000))
        .send({ code: 'CODE_COOLDOWN', retry_after_s: Math.ceil(sent.retry_after_ms / 1000), server_time: deps.now() });
    }
    return reply.send({ ok: true, server_time: deps.now() });
  });

  app.post('/v1/auth/email/verify', async (req, reply) => {
    const me = await account(req, reply);
    if (!me) return;
    const code = (req.body as { code?: unknown } | undefined)?.code;
    if (!isValidCode(code)) return reply.code(400).send({ code: 'SCHEMA', server_time: deps.now() });
    if (me.user.email_verified) return reply.send({ ...userView(me.user, me.player), server_time: deps.now() });
    const outcome = await consume(me.user.email ?? '', 'verify', code);
    if (outcome !== 'ok') return reply.code(422).send({ code: codeError(outcome), server_time: deps.now() });
    await deps.store.markEmailVerified(me.user.id);
    return reply.send({ ...userView({ ...me.user, email_verified: true }, me.player), server_time: deps.now() });
  });

  /** 找回密码：码对了就改密、撤销该账号全部会话（含其它设备）并签发新会话。 */
  app.post('/v1/auth/email/reset', { config: { rateLimit: { max: 30, timeWindow: '1 hour' } } }, async (req, reply) => {
    const body = req.body as { email?: unknown; code?: unknown; password?: unknown } | undefined;
    const email = normalizeEmail(body?.email);
    if (!email || !isValidCode(body?.code)) return reply.code(400).send({ code: 'SCHEMA', server_time: deps.now() });
    if (!isValidPassword(body?.password)) return reply.code(400).send({ code: 'WEAK_PASSWORD', server_time: deps.now() });
    const user = await deps.store.userByEmail(email);
    const outcome = user ? await consume(email, 'reset', body.code) : 'invalid';
    if (!user || outcome !== 'ok') return reply.code(422).send({ code: codeError(outcome), server_time: deps.now() });
    await deps.store.setUserPassword(user.id, await hashPassword(body.password));
    // A reset code proves mailbox ownership, which is the same proof verification asks for.
    if (!user.email_verified) await deps.store.markEmailVerified(user.id);
    await deps.store.revokeUserTokens(user.id);
    const session = await deps.store.authUser(user.id, deps.now());
    await deps.closeSessions?.(session.player.id);
    return reply.send({ token: session.token, ...userView({ ...user, email_verified: true }, session.player), server_time: deps.now() });
  });

  app.get('/v1/users/me', async (req, reply) => {
    const me = await account(req, reply);
    if (!me) return;
    const farm = await deps.store.farmByOwner(me.player.id);
    return reply.send({ ...userView(me.user, me.player), has_farm: Boolean(farm), server_time: deps.now() });
  });

  /** 数据访问请求：账号 + 农场存档，一份 JSON 附件。不含 token 与密码哈希。 */
  app.get('/v1/users/me/export', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (req, reply) => {
    const me = await account(req, reply);
    if (!me) return;
    const farm = await deps.store.farmByOwner(me.player.id);
    reply.header('content-disposition', `attachment; filename="sensen-account-${me.user.id}.json"`);
    return reply.send({ exported_at: deps.now(), account: userView(me.user, me.player),
      farm: farm ? { id: farm.id, city_id: farm.region_id, location: farm.location ?? null, visit_access: farm.visit_access,
        location_visible: farm.location_visible, version: farm.version, state: farm.state } : null });
  });

  /**
   * 应用内删号（Apple 5.1.1(v)）：删除而非停用。有密码的账号要再输一次密码，防止借来的
   * 手机一键删号。账号玩家的农场、命令、快照、联机状态随之级联删除。
   */
  app.delete('/v1/users/me', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (req, reply) => {
    const me = await account(req, reply);
    if (!me) return;
    const password = (req.body as { password?: unknown } | undefined)?.password;
    if (me.user.password_hash && (typeof password !== 'string' || !await verifyPassword(password, me.user.password_hash)))
      return reply.code(401).send({ code: 'INVALID_CREDENTIALS', server_time: deps.now() });
    await deps.beforeDelete?.(me.player.id);
    await deps.closeSessions?.(me.player.id);
    const deleted = await deps.store.deleteUser(me.user.id, {
      user_id: me.user.id, provider_uid: me.user.email ? 'email:' + emailKey(me.user.email, deps.pepper) : 'none',
      requested_at: deps.now(), source: 'app', apple_revocation: 'n/a',
    });
    return reply.send({ ok: true, deleted, server_time: deps.now() });
  });

  return { bearer };
}
