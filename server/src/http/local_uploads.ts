/**
 * 开发期本地图片存储（D4-c 的"没有 R2"分支）：presign 给回**本服务**的 PUT 地址，字节落磁盘，
 * `GET /v1/files/<key>` 读回。接口形状与 R2 预签名完全一样，客户端不区分；R2 真桶（SSLAUNCH D4）
 * 到手后换环境变量即可。只用于 dev / QA，生产不会配 UPLOAD_LOCAL_DIR。
 */
import { randomBytes } from 'node:crypto';
import { mkdirSync, promises as fs } from 'node:fs';
import path from 'node:path';
import { UPLOAD_EXPIRES_S, UPLOAD_MAX_BYTES, newObjectKey, type PresignedUpload, type UploadRequest } from './uploads.js';

interface PendingToken { key: string; contentType: string; expiresAt: number }

export type LocalPutResult = { ok: true; key: string } | { ok: false; code: 'NOT_FOUND' | 'EXPIRED' | 'CONTENT_TYPE' | 'SIZE' };

/** key 只认 `u/<uuid>/<yyyymmdd>/<rand>.<ext>`，天然挡住 `..` 与绝对路径。 */
export const LOCAL_KEY_RE = /^u\/[0-9a-f-]{36}\/\d{8}\/[A-Za-z0-9]+\.[a-z0-9]+$/i;

export class LocalUploadStore {
  private tokens = new Map<string, PendingToken>();

  constructor(readonly dir: string) {
    mkdirSync(dir, { recursive: true });
  }

  presign(userId: string, r: Extract<UploadRequest, { ok: true }>, nowMs: number, baseUrl: string): PresignedUpload {
    const key = newObjectKey(userId, r.ext, nowMs);
    const token = randomBytes(16).toString('hex');
    const expiresAt = nowMs + UPLOAD_EXPIRES_S * 1000;
    this.tokens.set(token, { key, contentType: r.contentType, expiresAt });
    return {
      key, url: `${baseUrl}/v1/uploads/local/${token}`, method: 'PUT',
      headers: { 'content-type': r.contentType }, expires_at: expiresAt, public_url: `${baseUrl}/v1/files/${key}`,
    };
  }

  /** 一个 token 只能用一次；content-type 要和 presign 时一致（R2 也是这么签的）。 */
  async put(token: string, body: Buffer, contentType: string, nowMs: number): Promise<LocalPutResult> {
    const t = this.tokens.get(token);
    if (!t) return { ok: false, code: 'NOT_FOUND' };
    if (nowMs > t.expiresAt) { this.tokens.delete(token); return { ok: false, code: 'EXPIRED' }; }
    if (contentType.split(';')[0].trim().toLowerCase() !== t.contentType) return { ok: false, code: 'CONTENT_TYPE' };
    if (body.length === 0 || body.length > UPLOAD_MAX_BYTES) return { ok: false, code: 'SIZE' };
    const file = this.fileFor(t.key)!;
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, body);
    await fs.writeFile(`${file}.type`, t.contentType);
    this.tokens.delete(token);
    return { ok: true, key: t.key };
  }

  async read(key: string): Promise<{ bytes: Buffer; contentType: string } | null> {
    const file = this.fileFor(key);
    if (!file) return null;
    try {
      const [bytes, type] = await Promise.all([fs.readFile(file), fs.readFile(`${file}.type`, 'utf8')]);
      return { bytes, contentType: type.trim() || 'application/octet-stream' };
    } catch {
      return null;
    }
  }

  fileFor(key: string): string | null {
    if (!LOCAL_KEY_RE.test(key)) return null;
    return path.join(this.dir, ...key.split('/'));
  }
}
