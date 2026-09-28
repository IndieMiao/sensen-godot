/**
 * 邮箱账户的邮箱规范化与验证码（SGODOT-135，决定 1：大陆可用，自建不经 Firebase）。
 *
 * 验证码只存 HMAC：库被拖走也拿不到可用的码。一个邮箱每种用途同时只有一个有效码，
 * 60 秒内不重发，10 分钟过期，错 5 次作废。
 */
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';

export type CodePurpose = 'verify' | 'reset';
export const CODE_TTL_MS = 10 * 60_000;
export const CODE_RESEND_MS = 60_000;
export const CODE_MAX_ATTEMPTS = 5;

export function normalizeEmail(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const email = v.trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return null;
  return email;
}

export const isCodePurpose = (v: unknown): v is CodePurpose => v === 'verify' || v === 'reset';
export const isValidCode = (v: unknown): v is string => typeof v === 'string' && /^\d{6}$/.test(v);
export const newCode = (): string => String(randomInt(0, 1_000_000)).padStart(6, '0');

export const codeHash = (email: string, purpose: CodePurpose, code: string, pepper: string): string =>
  createHmac('sha256', pepper).update(`email-code:${purpose}:${email}:${code}`, 'utf8').digest('hex');

export function sameHash(a: string, b: string): boolean {
  return a.length === b.length && timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}

/** 邮箱的 HMAC：限流键与日志里用它，不落明文邮箱。 */
export const emailKey = (email: string, pepper: string): string =>
  createHmac('sha256', pepper).update('email:' + email, 'utf8').digest('hex').slice(0, 24);
