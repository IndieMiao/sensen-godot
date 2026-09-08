/**
 * 服务端遥测（E2 数据卫生 + E4 崩溃上报）。
 *
 * 规矩与客户端一致：位置、消息 / UGC 正文、token 一律不进日志与错误上报。
 * Sentry 只用 store 端点，不引 @sentry/node——没有 DSN 时整条链路是空转，
 * 装依赖与配 org 是 SSLAUNCH D7 的事。
 */
export const REDACTED = '[redacted]';

const DROP_KEYS = [
  'lat', 'lng', 'latitude', 'longitude', 'accuracym', 'coords', 'address',
  'text', 'body', 'message', 'comment', 'caption', 'content', 'bio', 'displayname',
  'email', 'phone', 'password', 'idtoken', 'refreshtoken', 'accesstoken', 'token',
  'authorization', 'apikey', 'secret', 'dsn',
];
const norm = (k: string): string => k.toLowerCase().replace(/[_-]/g, '');
export const isSensitiveKey = (k: string): boolean => DROP_KEYS.includes(norm(k));

/** 自由文本里的邮箱 / Bearer / JWT / 经纬度对 / 长数字串打码。 */
export function scrubText(s: string): string {
  return s
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, REDACTED)
    .replace(/bearer\s+[A-Za-z0-9._~+/-]+=*/gi, `Bearer ${REDACTED}`)
    .replace(/eyJ[A-Za-z0-9._-]{20,}/g, REDACTED)
    .replace(/-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}/g, REDACTED)
    .replace(/\d{9,}/g, REDACTED);
}

/** URL 去掉 query（游标 / token 常在里面）。 */
export function scrubUrl(u: string): string {
  const i = u.indexOf('?');
  return i < 0 ? u : `${u.slice(0, i)}?${REDACTED}`;
}

export function scrub(value: unknown, depth = 0): unknown {
  if (depth > 8) return REDACTED;
  if (Array.isArray(value)) return value.map(v => scrub(v, depth + 1));
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>))
      out[k] = isSensitiveKey(k) ? REDACTED : scrub(v, depth + 1);
    return out;
  }
  if (typeof value === 'string') return scrubText(value);
  return value;
}

export interface ErrorReporter {
  capture(message: string, context?: Record<string, unknown>, level?: 'error' | 'warning'): Promise<void>;
}

/** 没配 DSN 时用它：什么都不做，但保留调用点，接上只需换实现。 */
export const nullReporter: ErrorReporter = { async capture() {} };

export function parseDsn(raw: string): { url: string; key: string } | null {
  const m = /^https:\/\/([0-9a-f]+)@([^/]+)\/(\d+)$/i.exec(raw.trim());
  return m ? { key: m[1], url: `https://${m[2]}/api/${m[3]}/store/` } : null;
}

export type Fetcher = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<unknown>;

/** Sentry store 端点上报；内容先过 scrub。fetcher 可注入（测试与离线）。 */
export function sentryReporter(dsn: string, now: () => number, fetcher: Fetcher = globalThis.fetch as unknown as Fetcher,
                               opts: { release?: string; environment?: string } = {}): ErrorReporter {
  const target = parseDsn(dsn);
  if (!target) return nullReporter;
  return {
    async capture(message, context = {}, level = 'error') {
      const event = {
        message: scrubText(message),
        level,
        platform: 'node',
        release: opts.release ?? '',
        environment: opts.environment ?? 'dev',
        extra: scrub(context),
        timestamp: Math.floor(now() / 1000),
      };
      await fetcher(target.url, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-sentry-auth': `Sentry sentry_version=7, sentry_key=${target.key}, sentry_client=sensen-server/1`,
        },
        body: JSON.stringify(event),
      });
    },
  };
}
