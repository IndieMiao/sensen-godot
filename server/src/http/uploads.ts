/**
 * 图片直传（D4-c）：客户端向服务端要一个 **预签名 PUT URL**，自己把字节直接放到 Cloudflare R2
 * （S3 兼容），服务端不经手图片流量。签名是 AWS SigV4 查询串形式，用 Node crypto 手写——
 * 一个 presign 不值得引 AWS SDK（Demo 期依赖越少越好，且 R2 只用到这一个动作）。
 *
 * 对象 key 一律 `u/<user_id>/<yyyymmdd>/<random>.<ext>`：发帖时校验前缀，用户只能引用自己上传的图。
 * 公网读取走 R2 自定义域（PUBLIC_BASE），没有配就退回 R2 端点（仅开发）。
 */
import { createHash, createHmac, randomBytes } from 'node:crypto';

export interface S3Config {
  endpoint: string;        // https://<account>.r2.cloudflarestorage.com
  region: string;          // R2 用 'auto'
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
  /** 公网读地址前缀，如 https://img.example.com；空则用 endpoint/bucket。 */
  publicBase?: string;
}

export const UPLOAD_CONTENT_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif', 'image/heic': 'heic',
};
export const UPLOAD_MAX_BYTES = 15 * 1024 * 1024;
export const UPLOAD_EXPIRES_S = 600;
export const UPLOAD_KINDS = new Set(['post_image', 'avatar']);

const sha256Hex = (s: string | Buffer): string => createHash('sha256').update(s).digest('hex');
const hmac = (key: string | Buffer, s: string): Buffer => createHmac('sha256', key).update(s, 'utf8').digest();

/** RFC 3986 编码，S3 要求 `~` 不编、空格编成 %20。 */
export const uriEncode = (s: string, encodeSlash = true): string => {
  let out = '';
  for (const ch of s) {
    if (/[A-Za-z0-9\-_.~]/.test(ch) || (ch === '/' && !encodeSlash)) out += ch;
    else out += Array.from(Buffer.from(ch, 'utf8')).map(b => '%' + b.toString(16).toUpperCase().padStart(2, '0')).join('');
  }
  return out;
};

export const amzDate = (ms: number): string => new Date(ms).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');

export interface PresignArgs {
  method: 'GET' | 'PUT';
  host: string;
  /** 以 / 开头的路径，如 /bucket/key。 */
  path: string;
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
  nowMs: number;
  expiresS: number;
  /** 除 host 外要一起签的头（小写名 → 值）；客户端必须原样带上。 */
  signedHeaders?: Record<string, string>;
  scheme?: 'https' | 'http';
}

/** SigV4 查询串预签名（UNSIGNED-PAYLOAD）。 */
export function presign(a: PresignArgs): string {
  const date = amzDate(a.nowMs);
  const day = date.slice(0, 8);
  const scope = `${day}/${a.region}/s3/aws4_request`;
  const headers: Record<string, string> = { host: a.host, ...(a.signedHeaders ?? {}) };
  const headerNames = Object.keys(headers).map(h => h.toLowerCase()).sort();
  const signedHeaders = headerNames.join(';');
  const query: [string, string][] = [
    ['X-Amz-Algorithm', 'AWS4-HMAC-SHA256'],
    ['X-Amz-Credential', `${a.accessKeyId}/${scope}`],
    ['X-Amz-Date', date],
    ['X-Amz-Expires', String(a.expiresS)],
    ['X-Amz-SignedHeaders', signedHeaders],
  ];
  const canonicalQuery = query
    .map(([k, v]) => [uriEncode(k), uriEncode(v)] as [string, string])
    .sort((x, y) => (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`).join('&');
  const canonicalHeaders = headerNames.map(h => `${h}:${headers[h].trim().replace(/\s+/g, ' ')}\n`).join('');
  const canonicalRequest = [a.method, uriEncode(a.path, false), canonicalQuery, canonicalHeaders, signedHeaders, 'UNSIGNED-PAYLOAD'].join('\n');
  const stringToSign = ['AWS4-HMAC-SHA256', date, scope, sha256Hex(canonicalRequest)].join('\n');
  const kDate = hmac(`AWS4${a.secretAccessKey}`, day);
  const kRegion = hmac(kDate, a.region);
  const kService = hmac(kRegion, 's3');
  const kSigning = hmac(kService, 'aws4_request');
  const signature = createHmac('sha256', kSigning).update(stringToSign, 'utf8').digest('hex');
  return `${a.scheme ?? 'https'}://${a.host}${uriEncode(a.path, false)}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

export type UploadRequest = { ok: true; kind: string; contentType: string; ext: string; size: number } | { ok: false; field: string; reason: string };

export function validateUploadRequest(body: unknown): UploadRequest {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body', reason: 'OBJECT' };
  const b = body as Record<string, unknown>;
  if (typeof b.kind !== 'string' || !UPLOAD_KINDS.has(b.kind)) return { ok: false, field: 'kind', reason: 'UNKNOWN' };
  if (typeof b.content_type !== 'string' || !(b.content_type in UPLOAD_CONTENT_TYPES)) return { ok: false, field: 'content_type', reason: 'UNSUPPORTED' };
  if (!Number.isInteger(b.size) || (b.size as number) <= 0 || (b.size as number) > UPLOAD_MAX_BYTES) return { ok: false, field: 'size', reason: 'SIZE' };
  return { ok: true, kind: b.kind, contentType: b.content_type, ext: UPLOAD_CONTENT_TYPES[b.content_type], size: b.size as number };
}

/** 对象 key：用户前缀 + 日期 + 随机；发帖校验 `ownsKey`。 */
export const newObjectKey = (userId: string, ext: string, nowMs: number, rand = randomBytes(12).toString('hex')): string =>
  `u/${userId}/${amzDate(nowMs).slice(0, 8)}/${rand}.${ext}`;

export const ownsKey = (key: string, userId: string): boolean => key.startsWith(`u/${userId}/`);

export interface PresignedUpload {
  key: string;
  url: string;
  method: 'PUT';
  headers: Record<string, string>;
  expires_at: number;
  public_url: string;
}

export function presignUpload(cfg: S3Config, userId: string, r: Extract<UploadRequest, { ok: true }>, nowMs: number, rand?: string): PresignedUpload {
  const key = newObjectKey(userId, r.ext, nowMs, rand);
  const u = new URL(cfg.endpoint);
  const url = presign({
    method: 'PUT', host: u.host, path: `/${cfg.bucket}/${key}`, region: cfg.region,
    accessKeyId: cfg.accessKeyId, secretAccessKey: cfg.secretAccessKey, nowMs, expiresS: UPLOAD_EXPIRES_S,
    signedHeaders: { 'content-type': r.contentType }, scheme: u.protocol === 'http:' ? 'http' : 'https',
  });
  return {
    key, url, method: 'PUT',
    headers: { 'content-type': r.contentType },
    expires_at: nowMs + UPLOAD_EXPIRES_S * 1000,
    public_url: publicUrl(cfg, key),
  };
}

export const publicUrl = (cfg: S3Config, key: string): string =>
  `${(cfg.publicBase ?? `${cfg.endpoint.replace(/\/$/, '')}/${cfg.bucket}`).replace(/\/$/, '')}/${uriEncode(key, false)}`;

/** 从环境变量装配；缺任一项返回 undefined（上传路由 503）。 */
export function s3ConfigFromEnv(env: NodeJS.ProcessEnv): S3Config | undefined {
  const { R2_ENDPOINT, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY } = env;
  if (!R2_ENDPOINT || !R2_BUCKET || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY) return undefined;
  return { endpoint: R2_ENDPOINT, bucket: R2_BUCKET, accessKeyId: R2_ACCESS_KEY_ID, secretAccessKey: R2_SECRET_ACCESS_KEY,
    region: env.R2_REGION ?? 'auto', publicBase: env.R2_PUBLIC_BASE || undefined };
}
