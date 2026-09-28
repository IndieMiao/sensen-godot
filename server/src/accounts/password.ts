/**
 * 密码哈希（SGODOT-135）。用 Node 自带的 scrypt：不引原生模块（argon2 在 alpine 镜像里要编译），
 * 参数写进哈希串本身，将来调参时旧哈希照样能验。
 */
import { randomBytes, scrypt as scryptCb, timingSafeEqual, type ScryptOptions } from 'node:crypto';

const scrypt = (password: string, salt: Buffer, len: number, opts: ScryptOptions) => new Promise<Buffer>((resolve, reject) =>
  scryptCb(password, salt, len, opts, (error, key) => error ? reject(error) : resolve(key)));

const N = 16384, R = 8, P = 1, LEN = 32;
export const PASSWORD_MIN = 8;
export const PASSWORD_MAX = 128;

export const isValidPassword = (v: unknown): v is string =>
  typeof v === 'string' && [...v].length >= PASSWORD_MIN && [...v].length <= PASSWORD_MAX && v.trim().length > 0;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scrypt(password.normalize('NFKC'), salt, LEN, { N, r: R, p: P, maxmem: 64 * 1024 * 1024 });
  return ['scrypt', N, R, P, salt.toString('base64url'), key.toString('base64url')].join('$');
}

export async function verifyPassword(password: string, stored: string | null): Promise<boolean> {
  if (!stored) return false;
  const [kind, n, r, p, salt, hash] = stored.split('$');
  if (kind !== 'scrypt' || !salt || !hash) return false;
  const expected = Buffer.from(hash, 'base64url');
  const key = await scrypt(password.normalize('NFKC'), Buffer.from(salt, 'base64url'), expected.length,
    { N: Number(n), r: Number(r), p: Number(p), maxmem: 64 * 1024 * 1024 });
  return key.length === expected.length && timingSafeEqual(key, expected);
}

/** 用户不存在时也跑一次哈希，登录耗时不泄露"这个邮箱有没有注册"。 */
let dummy: string | null = null;
export async function burnPasswordCheck(password: string): Promise<void> {
  dummy ??= await hashPassword('dummy-password-for-timing');
  await verifyPassword(password, dummy);
}
