/**
 * 邀请账号（C-96）：动态农场正式服只用邀请账号登录（ACCOUNT_SIGNUP=closed）。邀请账号就是普通的邮箱 + 密码账号，
 * 客户端照常走 /v1/auth/email/login；邮箱在运营方自己的域名下，不收信。写库时标 email_verified=true，
 * 身份行 provider='email'、sign_in_provider='invite:<批次>'，以便按批次列出、重置或停用。
 * 密码只出现在 createInvites / resetInvite 的返回值里，库里只存 scrypt 哈希。命令行入口是 tools/invite_accounts.ts。
 */
import { randomInt, randomUUID } from 'node:crypto';
import type pg from 'pg';
import { normalizeEmail } from './email.js';
import { hashPassword } from './password.js';

/** 去掉 0/o、1/l/i 这些容易看错的字符，玩家要在手机上手输。 */
const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';
const pick = (n: number) => Array.from({ length: n }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');

export const INVITE_PROVIDER_PREFIX = 'invite:';
export const BATCH_RE = /^[a-z0-9][a-z0-9-]{0,31}$/;
export const PREFIX_RE = /^[a-z][a-z0-9]{0,11}$/;
export const MAX_INVITES_PER_RUN = 500;

/** 4 组各 4 个字符（约 79 位熵），例如 k3mq-7hxa-pt2d-wz9e。 */
export const newInvitePassword = (): string => [pick(4), pick(4), pick(4), pick(4)].join('-');

export const newInviteEmail = (prefix: string, domain: string): string => `${prefix}-${pick(8)}@${domain}`;

/** 邮箱域名要能通过登录接口的邮箱校验。 */
export const isInviteDomain = (domain: string): boolean => /^[a-z0-9.-]+$/.test(domain) && normalizeEmail(`a@${domain}`) === `a@${domain}`;

export interface InviteCredential { email: string; password: string; batch: string }
export interface InviteRow { email: string; batch: string; created_at: number; last_seen_at: number; disabled: boolean; has_parcel: boolean }

export interface CreateInvitesOptions { count: number; domain: string; batch: string; prefix?: string }

function checkCreate(o: CreateInvitesOptions): void {
  if (!Number.isInteger(o.count) || o.count < 1 || o.count > MAX_INVITES_PER_RUN) throw new Error(`count 要在 1..${MAX_INVITES_PER_RUN}`);
  if (!isInviteDomain(o.domain)) throw new Error('domain 不是合法的邮箱域名');
  if (!BATCH_RE.test(o.batch)) throw new Error('batch 只能用小写字母、数字和 -，最长 32');
  if (o.prefix !== undefined && !PREFIX_RE.test(o.prefix)) throw new Error('prefix 只能用小写字母和数字，字母开头，最长 12');
}

/** 一次建 count 个账号，整批在一个事务里：中途失败一个都不留。 */
export async function createInvites(pool: pg.Pool, o: CreateInvitesOptions, now: number): Promise<InviteCredential[]> {
  checkCreate(o);
  const prefix = o.prefix ?? 'df';
  const out: InviteCredential[] = [];
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    while (out.length < o.count) {
      const email = newInviteEmail(prefix, o.domain);
      const password = newInvitePassword();
      const id = randomUUID();
      const inserted = await client.query(
        `INSERT INTO users (id, email, email_verified, password_hash, created_at, last_seen_at) VALUES ($1,$2,true,$3,$4,$4)
           ON CONFLICT (email) DO NOTHING RETURNING id`, [id, email, await hashPassword(password), now]);
      if (!inserted.rowCount) continue; // 8 位随机后缀撞上已有邮箱，换一个
      await client.query(`INSERT INTO user_identities (provider, provider_uid, user_id, sign_in_provider, created_at)
        VALUES ('email', $1, $2, $3, $4)`, [email, id, INVITE_PROVIDER_PREFIX + o.batch, now]);
      out.push({ email, password, batch: o.batch });
    }
    await client.query('COMMIT');
    return out;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

/** 只列邀请账号，不含密码；batch 给了就只列这一批。 */
export async function listInvites(pool: pg.Pool, batch?: string): Promise<InviteRow[]> {
  const r = await pool.query(
    `SELECT u.email, i.sign_in_provider, u.created_at, u.last_seen_at, u.password_hash IS NULL AS disabled,
            EXISTS (SELECT 1 FROM players p JOIN parcel_claims c ON c.player_id = p.id WHERE p.user_id = u.id) AS has_parcel
       FROM user_identities i JOIN users u ON u.id = i.user_id
      WHERE i.provider = 'email' AND i.sign_in_provider ${batch === undefined ? "LIKE 'invite:%'" : '= $1'}
      ORDER BY u.created_at, u.email`, batch === undefined ? [] : [INVITE_PROVIDER_PREFIX + batch]);
  return r.rows.map(row => ({
    email: row.email, batch: String(row.sign_in_provider).slice(INVITE_PROVIDER_PREFIX.length),
    created_at: Number(row.created_at), last_seen_at: Number(row.last_seen_at), disabled: row.disabled, has_parcel: row.has_parcel,
  }));
}

async function inviteUser(client: pg.PoolClient, email: string): Promise<{ id: string; batch: string } | null> {
  const r = await client.query(
    `SELECT u.id, i.sign_in_provider FROM user_identities i JOIN users u ON u.id = i.user_id
      WHERE i.provider = 'email' AND i.provider_uid = $1 AND i.sign_in_provider LIKE 'invite:%' FOR UPDATE OF u`, [email]);
  return r.rowCount ? { id: r.rows[0].id, batch: String(r.rows[0].sign_in_provider).slice(INVITE_PROVIDER_PREFIX.length) } : null;
}

/**
 * 重置（忘记密码时）或停用（password=null：登录一律失败）一个邀请账号，同时撤销它的全部会话。
 * 地块和存档不动。不是邀请账号的邮箱一律拒绝，返回 null。
 */
async function setInvitePassword(pool: pg.Pool, email: string, password: string | null): Promise<{ batch: string } | null> {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const user = await inviteUser(client, normalized);
    if (!user) { await client.query('ROLLBACK'); return null; }
    await client.query('UPDATE users SET password_hash = $2 WHERE id = $1', [user.id, password === null ? null : await hashPassword(password)]);
    await client.query('DELETE FROM tokens WHERE player_id IN (SELECT id FROM players WHERE user_id = $1)', [user.id]);
    await client.query('COMMIT');
    return { batch: user.batch };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

export async function resetInvite(pool: pg.Pool, email: string): Promise<InviteCredential | null> {
  const password = newInvitePassword();
  const done = await setInvitePassword(pool, email, password);
  return done ? { email: normalizeEmail(email)!, password, batch: done.batch } : null;
}

export async function disableInvite(pool: pg.Pool, email: string): Promise<boolean> {
  return (await setInvitePassword(pool, email, null)) !== null;
}
