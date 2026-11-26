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
import { ageOn, parseProfile } from './profile.js';
import { DELETE_PAGE_HTML } from './delete_page.js';
import { verifyAppleIdToken, type AppleVerifyOptions } from './apple_token.js';
import type { AppleRevoker } from './apple_revoke.js';
import { verifyGoogleIdToken, type GoogleVerifyOptions } from './google_token.js';
import { IdTokenError } from './firebase_token.js';
import { DEFAULT_ACCOUNT_LIMITS, type AccountLimits } from './limits.js';
import { networkKey } from '../http/network.js';
import { createHmac } from 'node:crypto';

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
  /** Sign in with Apple；不配则 /v1/auth/apple 回 503。 */
  apple?: Omit<AppleVerifyOptions, 'now'>;
  /** 配了 .p8 才有：登录时换 refresh token，删号时撤销。 */
  appleRevoker?: AppleRevoker;
  /** Sign in with Google；不配则 /v1/auth/google 回 503。 */
  google?: Omit<GoogleVerifyOptions, 'now'>;
  /**
   * 只用邀请账号（C-96 动态农场正式服）：邮箱注册和 Apple / Google 首登建号都回 403 SIGNUP_CLOSED；
   * 已有账号照常登录。账号由 tools/invite_accounts.ts 直接写库。
   */
  signupClosed?: boolean;
  /** 登录与发信上限（C-132）；见 limits.ts。 */
  limits?: Partial<AccountLimits>;
}

/** 不存在的账号也照样查一次可信网络，免得多一次查询的耗时泄露注册与否。 */
const NO_USER = '00000000-0000-0000-0000-000000000000';

/**
 * ACCOUNT_SIGNUP：不设或 open 照旧开放注册；closed 只用邀请账号（C-96）。
 * 其它值返回 null，由进程入口拒绝启动，免得拼错时悄悄开放注册。
 */
export function signupClosedFromEnv(env: Record<string, string | undefined>): boolean | null {
  const v = env.ACCOUNT_SIGNUP;
  if (v === undefined || v === '' || v === 'open') return false;
  return v === 'closed' ? true : null;
}

export function userView(u: UserRow, player?: PlayerRow, now = Date.now()) {
  return {
    user_id: u.id, email: u.email, email_verified: u.email_verified, created_at: u.created_at,
    display_name: u.display_name ?? null, gender: u.gender ?? null, gender_custom: u.gender_custom ?? null,
    birth_date: u.birth_date ?? null, age: u.birth_date ? ageOn(u.birth_date, now) : null,
    // A nickname is the only required profile field; the client asks for it before the first farm.
    profile_complete: Boolean(u.display_name),
    // Apple-only accounts have no password: the app hides password steps for them.
    has_password: Boolean(u.password_hash),
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

  const limits = { ...DEFAULT_ACCOUNT_LIMITS, ...deps.limits };
  const trustMs = limits.trustedNetworkDays * 86_400_000;
  const networkHash = (req: FastifyRequest) =>
    createHmac('sha256', deps.pepper).update('login-network:' + networkKey(req.ip), 'utf8').digest('hex').slice(0, 32);

  // C-132: password attempts per email *and* network, so a stranger's wrong passwords only use up their own network's
  // budget. The per-email budget below covers networks the account never signed in from, which keeps brute force at
  // the old per-email rate while the owner's known networks stay usable.
  const loginLimit = app.createRateLimit({ max: limits.loginPerNetwork, timeWindow: '15 minutes', keyGenerator: req => {
    const email = bodyEmail(req);
    return email ? 'login:' + emailKey(email, deps.pepper) + ':' + networkKey(req.ip) : 'login-invalid:' + networkKey(req.ip);
  } });
  const loginAccountLimit = app.createRateLimit({ max: limits.loginPerAccount, timeWindow: '15 minutes',
    keyGenerator: req => 'login-account:' + emailKey(bodyEmail(req) ?? '', deps.pepper) });
  // C-132: every verification email counts against its recipient and the whole server.
  const mailLimits = [
    app.createRateLimit({ max: limits.mailPerRecipientHour, timeWindow: '1 hour', keyGenerator: req => 'mail-to-h:' + emailKey(bodyEmail(req) ?? '', deps.pepper) }),
    app.createRateLimit({ max: limits.mailPerRecipientDay, timeWindow: '1 day', keyGenerator: req => 'mail-to-d:' + emailKey(bodyEmail(req) ?? '', deps.pepper) }),
    app.createRateLimit({ max: limits.mailPerHour, timeWindow: '1 hour', keyGenerator: () => 'mail-all-h' }),
    app.createRateLimit({ max: limits.mailPerDay, timeWindow: '1 day', keyGenerator: () => 'mail-all-d' }),
  ];
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

  /** 来自该账号没成功登录过的网络时扣按邮箱的额度；用尽回 429。 */
  const accountLimited = async (user: UserRow | null, req: FastifyRequest, reply: FastifyReply) => {
    if (await deps.store.loginNetworkTrusted(user?.id ?? NO_USER, networkHash(req), deps.now() - trustMs) && user) return false;
    return limited(loginAccountLimit, req, reply);
  };
  /** 签发会话的地方都调：这个网络从此算该账号登录过的网络。 */
  const trustNetwork = (userId: string, req: FastifyRequest) => deps.store.trustLoginNetwork(userId, networkHash(req), deps.now());
  /**
   * 扣一封验证信的额度（请求体里的收件邮箱 + 全局）。超限返回需等待的秒数，否则 null。
   * QA 域名不发信，不扣。
   */
  const mailQuotaWait = async (email: string, req: FastifyRequest): Promise<number | null> => {
    if (isQa(email)) return null;
    for (const limit of mailLimits) {
      const quota = await limit(req);
      if (!quota.isAllowed && quota.isExceeded) return quota.ttlInSeconds;
    }
    return null;
  };
  const mailLimited = (reply: FastifyReply, waitS: number) => reply.code(429).header('retry-after', waitS)
    .send({ code: 'RATE_LIMITED', reason: 'MAIL_LIMIT', retry_after_s: waitS, server_time: deps.now() });

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
    if (deps.signupClosed) return reply.code(403).send({ code: 'SIGNUP_CLOSED', server_time: deps.now() });
    const body = req.body as { email?: unknown; password?: unknown } | undefined;
    const email = normalizeEmail(body?.email);
    if (!email) return reply.code(400).send({ code: 'INVALID_EMAIL', server_time: deps.now() });
    if (!isValidPassword(body?.password)) return reply.code(400).send({ code: 'WEAK_PASSWORD', server_time: deps.now() });
    const created = await deps.store.createEmailUser(email, await hashPassword(body.password), deps.now());
    if (created.kind === 'email_taken') return reply.code(409).send({ code: 'EMAIL_TAKEN', server_time: deps.now() });
    // A nickname given at sign-up is saved right away; an invalid one is simply asked for again later.
    const nickname = (req.body as { display_name?: unknown }).display_name;
    if (nickname !== undefined) {
      const parsed = parseProfile({ display_name: nickname }, deps.now());
      if (parsed.ok) { await deps.store.updateUserProfile(created.user.id, parsed.profile); created.user.display_name = parsed.profile.display_name; }
    }
    const session = await deps.store.authUser(created.user.id, deps.now());
    await trustNetwork(created.user.id, req);
    // Over the mail limit the account still exists; the code can be asked for again later.
    const mailWait = await mailQuotaWait(email, req);
    const sent = mailWait === null ? await sendCode(email, 'verify') : { ok: false };
    return reply.code(201).send({ token: session.token, ...userView(created.user, session.player, deps.now()), verification_sent: sent.ok,
      ...(mailWait === null ? {} : { verification_error: 'MAIL_LIMIT', retry_after_s: mailWait }), server_time: deps.now() });
  });

  app.post('/v1/auth/email/login', { config: { rateLimit: { max: 120, timeWindow: '1 hour' } } }, async (req, reply) => {
    if (await limited(loginLimit, req, reply)) return;
    const body = req.body as { email?: unknown; password?: unknown } | undefined;
    const email = normalizeEmail(body?.email);
    if (!email || typeof body?.password !== 'string' || body.password.length > 256)
      return reply.code(400).send({ code: 'SCHEMA', server_time: deps.now() });
    const user = await deps.store.userByEmail(email);
    if (await accountLimited(user, req, reply)) return;
    if (!user) { await burnPasswordCheck(body.password); return reply.code(401).send({ code: 'INVALID_CREDENTIALS', server_time: deps.now() }); }
    if (!await verifyPassword(body.password, user.password_hash)) return reply.code(401).send({ code: 'INVALID_CREDENTIALS', server_time: deps.now() });
    const session = await deps.store.authUser(user.id, deps.now());
    await trustNetwork(user.id, req);
    return reply.send({ token: session.token, ...userView(user, session.player, deps.now()), server_time: deps.now() });
  });

  /**
   * 第三方身份登录的共用落号：先按 (provider, sub) 找号；没有就按提供方验证过的邮箱挂到**已验证**的邮箱账号上；
   * 再没有就建无密码账号。邮箱被未验证账号占着返回 null（EMAIL_IN_USE，防抢注劫持）。
   * 提供方给的名字只在账号还没有昵称时用作默认昵称。只用邀请账号时不建号，返回 'closed'。
   */
  const resolveIdentityUser = async (provider: string, sub: string, verifiedEmail: string | undefined, givenName: string | undefined):
    Promise<{ user: UserRow; created: boolean } | 'closed' | null> => {
    const email = verifiedEmail ? normalizeEmail(verifiedEmail) : null;
    let user = await deps.store.userByIdentity(provider, sub);
    let created = false;
    if (!user && email) {
      const existing = await deps.store.userByEmail(email);
      if (existing) {
        if (!existing.email_verified) return null;
        await deps.store.linkIdentity(provider, sub, existing.id, deps.now());
        user = await deps.store.userByIdentity(provider, sub);
      }
    }
    if (!user && deps.signupClosed) return 'closed';
    if (!user) {
      const made = await deps.store.createIdentityUser(provider, sub, email, deps.now());
      if (made.kind === 'created') { user = made.user; created = true; }
      else if (made.kind === 'identity_taken') user = await deps.store.userByIdentity(provider, sub);
      else return null;
      if (!user) return null;
    }
    if (!user.display_name && givenName) {
      const parsed = parseProfile({ display_name: givenName.trim() }, deps.now());
      if (parsed.ok) {
        await deps.store.updateUserProfile(user.id, { ...parsed.profile, gender: user.gender ?? null,
          gender_custom: user.gender_custom ?? null, birth_date: user.birth_date ?? null });
        user = { ...user, display_name: parsed.profile.display_name };
      }
    }
    return { user, created };
  };

  /** Sign in with Google（Android Credential Manager）。与 Apple 同一套落号规则；Google 不要求删号撤销。 */
  app.post('/v1/auth/google', { config: { rateLimit: { max: 60, timeWindow: '1 hour' } } }, async (req, reply) => {
    if (!deps.google) return reply.code(503).send({ code: 'GOOGLE_UNAVAILABLE', server_time: deps.now() });
    const body = req.body as { id_token?: unknown; nonce?: unknown } | undefined;
    let identity;
    try { identity = await verifyGoogleIdToken(body?.id_token, body?.nonce, { ...deps.google, now: deps.now }); }
    catch (error) {
      if (error instanceof IdTokenError) return reply.code(401).send({ code: 'GOOGLE_TOKEN_' + error.code, server_time: deps.now() });
      log(`[google] verify failed: ${(error as Error).message}`);
      return reply.code(503).send({ code: 'GOOGLE_UNAVAILABLE', server_time: deps.now() });
    }
    // C-132: each nonce signs in once. A captured id_token and nonce sent again is refused, also when both race.
    if (!await deps.store.claimIdTokenNonce('google', identity.nonceHash, identity.usableUntil, deps.now()))
      return reply.code(401).send({ code: 'GOOGLE_TOKEN_REPLAYED', server_time: deps.now() });
    const resolved = await resolveIdentityUser('google', identity.sub, identity.emailVerified ? identity.email : undefined, identity.givenName);
    if (resolved === 'closed') return reply.code(403).send({ code: 'SIGNUP_CLOSED', server_time: deps.now() });
    if (!resolved) return reply.code(409).send({ code: 'EMAIL_IN_USE', server_time: deps.now() });
    const session = await deps.store.authUser(resolved.user.id, deps.now());
    await trustNetwork(resolved.user.id, req);
    return reply.code(resolved.created ? 201 : 200).send({ token: session.token, ...userView(resolved.user, session.player, deps.now()),
      created: resolved.created, server_time: deps.now() });
  });

  /**
   * Sign in with Apple。按 Apple sub 找号；没有就按 Apple 验证过的邮箱挂到已验证的邮箱账号上，
   * 再没有就建一个无密码账号。邮箱被一个**未验证**的账号占着时不挂：那个账号可能是别人抢注的。
   * Apple 只在首次授权时给名字，客户端顺带发来，用作默认昵称。
   */
  app.post('/v1/auth/apple', { config: { rateLimit: { max: 60, timeWindow: '1 hour' } } }, async (req, reply) => {
    if (!deps.apple) return reply.code(503).send({ code: 'APPLE_UNAVAILABLE', server_time: deps.now() });
    const body = req.body as { identity_token?: unknown; nonce?: unknown; given_name?: unknown; family_name?: unknown; authorization_code?: unknown } | undefined;
    let identity;
    try { identity = await verifyAppleIdToken(body?.identity_token, body?.nonce, { ...deps.apple, now: deps.now }); }
    catch (error) {
      if (error instanceof IdTokenError) return reply.code(401).send({ code: 'APPLE_TOKEN_' + error.code, server_time: deps.now() });
      log(`[apple] verify failed: ${(error as Error).message}`);
      return reply.code(503).send({ code: 'APPLE_UNAVAILABLE', server_time: deps.now() });
    }
    const resolved = await resolveIdentityUser('apple', identity.sub, identity.emailVerified ? identity.email : undefined,
      typeof body?.given_name === 'string' ? body.given_name : undefined);
    if (resolved === 'closed') return reply.code(403).send({ code: 'SIGNUP_CLOSED', server_time: deps.now() });
    if (!resolved) return reply.code(409).send({ code: 'EMAIL_IN_USE', server_time: deps.now() });
    const { user, created } = resolved;
    // A fresh authorization code yields a refresh token for revocation on deletion; failures never block sign-in.
    const code = body?.authorization_code;
    if (deps.appleRevoker && typeof code === 'string' && code.length > 0 && code.length <= 512) {
      try {
        const refresh = await deps.appleRevoker.exchange(code, identity.aud);
        if (refresh) await deps.store.setIdentityToken('apple', identity.sub, refresh, identity.aud);
        else log('[apple] authorization code exchange returned no refresh token');
      } catch (error) { log(`[apple] code exchange failed: ${(error as Error).message}`); }
    }
    const session = await deps.store.authUser(user.id, deps.now());
    await trustNetwork(user.id, req);
    return reply.code(created ? 201 : 200).send({ token: session.token, ...userView(user, session.player, deps.now()),
      created, server_time: deps.now() });
  });

  /** 发码：verify（已登录账号验证邮箱）或 reset（找回密码）。邮箱不存在也回 200。 */
  app.post('/v1/auth/email/code', { config: { rateLimit: { max: 60, timeWindow: '1 hour' } } }, async (req, reply) => {
    if (await limited(codeLimit, req, reply)) return;
    const body = req.body as { email?: unknown; purpose?: unknown } | undefined;
    const email = normalizeEmail(body?.email);
    if (!email || !isCodePurpose(body?.purpose)) return reply.code(400).send({ code: 'SCHEMA', server_time: deps.now() });
    // Counted before looking the address up, so the limit answers the same whether or not it has an account.
    const mailWait = await mailQuotaWait(email, req);
    if (mailWait !== null) return mailLimited(reply, mailWait);
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
    if (me.user.email_verified) return reply.send({ ...userView(me.user, me.player, deps.now()), server_time: deps.now() });
    const outcome = await consume(me.user.email ?? '', 'verify', code);
    if (outcome !== 'ok') return reply.code(422).send({ code: codeError(outcome), server_time: deps.now() });
    await deps.store.markEmailVerified(me.user.id);
    return reply.send({ ...userView({ ...me.user, email_verified: true }, me.player, deps.now()), server_time: deps.now() });
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
    await trustNetwork(user.id, req);
    await deps.closeSessions?.(session.player.id);
    return reply.send({ token: session.token, ...userView({ ...user, email_verified: true }, session.player, deps.now()), server_time: deps.now() });
  });

  /** 应用内与站外删号共用：先清联机状态、断开会话，再级联删除并写墓碑。 */
  const deleteUserEverywhere = async (user: UserRow, source: 'app' | 'web') => {
    const players = await deps.store.authUser(user.id, deps.now()).then(s => [s.player.id]).catch(() => [] as string[]);
    for (const id of players) { await deps.beforeDelete?.(id); await deps.closeSessions?.(id); }
    // Apple asks apps to revoke the user's Apple authorization on deletion. Without a stored token it stays pending.
    const apple = (await deps.store.identitiesOf(user.id)).find(i => i.provider === 'apple');
    let revocation: 'pending' | 'n/a' | 'revoked' | 'failed' = apple ? 'pending' : 'n/a';
    if (apple?.refresh_token && apple.client_id && deps.appleRevoker) {
      revocation = await deps.appleRevoker.revoke(apple.refresh_token, apple.client_id)
        .then(ok => ok ? 'revoked' : 'failed', error => { log(`[apple] revoke failed: ${(error as Error).message}`); return 'failed'; });
    }
    return deps.store.deleteUser(user.id, {
      user_id: user.id,
      provider_uid: apple ? 'apple:' + apple.provider_uid : user.email ? 'email:' + emailKey(user.email, deps.pepper) : 'none',
      requested_at: deps.now(), source, apple_revocation: revocation,
    });
  };

  /** 资料：昵称必填，性别与生日选填；生日不足 13 岁拒绝且不保存。 */
  app.put('/v1/users/me/profile', { config: { rateLimit: { max: 60, timeWindow: '1 hour' } } }, async (req, reply) => {
    const me = await account(req, reply);
    if (!me) return;
    const parsed = parseProfile(req.body, deps.now());
    if (!parsed.ok) return reply.code(400).send({ code: parsed.code, server_time: deps.now() });
    await deps.store.updateUserProfile(me.user.id, parsed.profile);
    return reply.send({ ...userView({ ...me.user, ...parsed.profile }, me.player, deps.now()), server_time: deps.now() });
  });

  /** 登录状态下改密码：要当前密码；改完撤销该账号全部会话（含其它设备），本设备拿新 token。 */
  app.post('/v1/auth/email/password', { config: { rateLimit: { max: 20, timeWindow: '1 hour' } } }, async (req, reply) => {
    const me = await account(req, reply);
    if (!me) return;
    const body = req.body as { current_password?: unknown; new_password?: unknown } | undefined;
    if (typeof body?.current_password !== 'string' || !await verifyPassword(body.current_password, me.user.password_hash))
      return reply.code(401).send({ code: 'INVALID_CREDENTIALS', server_time: deps.now() });
    if (!isValidPassword(body.new_password)) return reply.code(400).send({ code: 'WEAK_PASSWORD', server_time: deps.now() });
    if (body.new_password === body.current_password) return reply.code(400).send({ code: 'SAME_PASSWORD', server_time: deps.now() });
    await deps.store.setUserPassword(me.user.id, await hashPassword(body.new_password));
    await deps.store.revokeUserTokens(me.user.id);
    await deps.closeSessions?.(me.player.id);
    const session = await deps.store.authUser(me.user.id, deps.now());
    return reply.send({ token: session.token, ...userView(me.user, session.player, deps.now()), server_time: deps.now() });
  });

  // —— 站外删号（Google Play 要求可在应用外删除账号） ——
  app.get('/v1/account/delete', async (_req, reply) => reply
    .header('content-type', 'text/html; charset=utf-8')
    .header('content-security-policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
    .header('cache-control', 'no-store')
    .send(DELETE_PAGE_HTML));

  app.post('/v1/account/delete/code', { config: { rateLimit: { max: 30, timeWindow: '1 hour' } } }, async (req, reply) => {
    if (await limited(codeLimit, req, reply)) return;
    const email = bodyEmail(req);
    if (!email) return reply.code(400).send({ code: 'INVALID_EMAIL', server_time: deps.now() });
    const mailWait = await mailQuotaWait(email, req);
    if (mailWait !== null) return mailLimited(reply, mailWait);
    const user = await deps.store.userByEmail(email);
    if (user) {
      const sent = await sendCode(email, 'delete');
      if (!sent.ok) return reply.code(429).send({ code: 'CODE_COOLDOWN', retry_after_s: Math.ceil(sent.retry_after_ms / 1000), server_time: deps.now() });
    }
    return reply.send({ ok: true, server_time: deps.now() });
  });

  /** 站外删号：邮箱 + 密码，或邮箱 + 删号验证码（忘了密码也能删）。失败一律不区分邮箱是否存在。 */
  app.post('/v1/account/delete', { config: { rateLimit: { max: 30, timeWindow: '1 hour' } } }, async (req, reply) => {
    if (await limited(loginLimit, req, reply)) return;
    const body = req.body as { email?: unknown; password?: unknown; code?: unknown } | undefined;
    const email = normalizeEmail(body?.email);
    if (!email || (typeof body?.password !== 'string' && !isValidCode(body?.code)))
      return reply.code(400).send({ code: 'SCHEMA', server_time: deps.now() });
    const user = await deps.store.userByEmail(email);
    if (await accountLimited(user, req, reply)) return;
    if (typeof body.password === 'string') {
      if (!user) { await burnPasswordCheck(body.password); return reply.code(401).send({ code: 'INVALID_CREDENTIALS', server_time: deps.now() }); }
      if (!await verifyPassword(body.password, user.password_hash)) return reply.code(401).send({ code: 'INVALID_CREDENTIALS', server_time: deps.now() });
    } else {
      const outcome = user ? await consume(email, 'delete', body.code as string) : 'invalid';
      if (!user || outcome !== 'ok') return reply.code(422).send({ code: codeError(outcome), server_time: deps.now() });
    }
    const deleted = await deleteUserEverywhere(user!, 'web');
    return reply.send({ ok: true, deleted, server_time: deps.now() });
  });

  app.get('/v1/users/me', async (req, reply) => {
    const me = await account(req, reply);
    if (!me) return;
    const farm = await deps.store.farmByOwner(me.player.id);
    return reply.send({ ...userView(me.user, me.player, deps.now()), has_farm: Boolean(farm), server_time: deps.now() });
  });

  /** 数据访问请求：账号 + 农场存档，一份 JSON 附件。不含 token 与密码哈希。 */
  app.get('/v1/users/me/export', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (req, reply) => {
    const me = await account(req, reply);
    if (!me) return;
    const farm = await deps.store.farmByOwner(me.player.id);
    reply.header('content-disposition', `attachment; filename="sensen-account-${me.user.id}.json"`);
    return reply.send({ exported_at: deps.now(), account: userView(me.user, me.player, deps.now()),
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
    const deleted = await deleteUserEverywhere(me.user, 'app');
    return reply.send({ ok: true, deleted, server_time: deps.now() });
  });

  return { bearer };
}
