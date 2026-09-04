/**
 * 匿名鉴权（Codex 二审 Important 1 / 三审 V3-C2）。
 *
 * 客户端首装生成 128 位随机 `install_key` 存本地，不是设备 ID——可猜的设备标识会让
 * 未认证的人直接登进别人的账号。服务端只存 HMAC。
 *
 * token 是 opaque 随机串而不是 JSON Web Token：可即时撤销、无时钟偏差、不需要密钥轮换
 * 设计。方案 D4 原本写的是签 JWT，这里显式改掉并记下理由。
 */
import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

export const MAX_ACTIVE_TOKENS = 5;
export const TOKEN_IDLE_MS = 90 * 24 * 3600_000;
export const INSTALL_KEY_BYTES = 16;

export const newInstallKey = (): string => randomBytes(INSTALL_KEY_BYTES).toString('hex');
export const newToken = (): string => randomBytes(32).toString('hex');

export const installKeyHmac = (key: string, pepper: string): string =>
  createHmac('sha256', pepper).update(key, 'utf8').digest('hex');

export const tokenHash = (token: string): string =>
  createHash('sha256').update(token, 'utf8').digest('hex');

export function safeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}

/** `install_key` 必须是 32 位十六进制（128 bit）；短的、可猜的一律拒。 */
export const isValidInstallKey = (v: unknown): v is string =>
  typeof v === 'string' && /^[0-9a-f]{32}$/.test(v);
