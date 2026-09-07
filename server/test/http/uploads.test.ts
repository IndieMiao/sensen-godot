import { describe, expect, it } from 'vitest';
import { amzDate, newObjectKey, ownsKey, presign, presignUpload, publicUrl, s3ConfigFromEnv, uriEncode, validateUploadRequest, UPLOAD_EXPIRES_S } from '../../src/http/uploads.js';

describe('SigV4 预签名', () => {
  it('与 AWS 文档「Using Query Parameters」示例逐字节一致', () => {
    // https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html 的 GET 示例
    const url = presign({
      method: 'GET', host: 'examplebucket.s3.amazonaws.com', path: '/test.txt', region: 'us-east-1',
      accessKeyId: 'AKIAIOSFODNN7EXAMPLE', secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      nowMs: Date.UTC(2013, 4, 24, 0, 0, 0), expiresS: 86400,
    });
    expect(url).toBe(
      'https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256'
      + '&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request'
      + '&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host'
      + '&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404');
  });

  it('编码与日期：~ 不编、空格 %20、路径里的 / 保留；amzDate 无毫秒', () => {
    expect(uriEncode('a b~c/d')).toBe('a%20b~c%2Fd');
    expect(uriEncode('a b~c/d', false)).toBe('a%20b~c/d');
    expect(uriEncode('中')).toBe('%E4%B8%AD');
    expect(amzDate(Date.UTC(2026, 8, 7, 9, 5, 3, 456))).toBe('20260907T090503Z');
  });

  it('PUT 预签名把 content-type 签进去，客户端必须原样带上', () => {
    const cfg = { endpoint: 'https://acct.r2.cloudflarestorage.com', region: 'auto', bucket: 'ugc', accessKeyId: 'AK', secretAccessKey: 'SK', publicBase: 'https://img.example.test' };
    const now = Date.UTC(2026, 8, 7, 9, 0, 0);
    const u = presignUpload(cfg, 'user-1', { ok: true, kind: 'post_image', contentType: 'image/png', ext: 'png', size: 10 }, now, 'abc123');
    expect(u.key).toBe('u/user-1/20260907/abc123.png');
    expect(u.method).toBe('PUT');
    expect(u.headers).toEqual({ 'content-type': 'image/png' });
    expect(u.expires_at).toBe(now + UPLOAD_EXPIRES_S * 1000);
    expect(u.public_url).toBe('https://img.example.test/u/user-1/20260907/abc123.png');
    expect(u.url.startsWith('https://acct.r2.cloudflarestorage.com/ugc/u/user-1/20260907/abc123.png?')).toBe(true);
    expect(u.url).toContain('X-Amz-SignedHeaders=content-type%3Bhost');
    expect(u.url).toContain('X-Amz-Expires=600');
    // 同参数确定性；换 content-type 签名就变
    expect(presignUpload(cfg, 'user-1', { ok: true, kind: 'post_image', contentType: 'image/png', ext: 'png', size: 10 }, now, 'abc123').url).toBe(u.url);
    expect(presignUpload(cfg, 'user-1', { ok: true, kind: 'post_image', contentType: 'image/jpeg', ext: 'jpg', size: 10 }, now, 'abc123').url).not.toBe(u.url);
    expect(publicUrl({ ...cfg, publicBase: undefined }, 'u/x/1.png')).toBe('https://acct.r2.cloudflarestorage.com/ugc/u/x/1.png');
  });

  it('请求校验与 key 归属', () => {
    expect(validateUploadRequest({ kind: 'post_image', content_type: 'image/jpeg', size: 1000 })).toMatchObject({ ok: true, ext: 'jpg' });
    expect(validateUploadRequest({ kind: 'video', content_type: 'image/jpeg', size: 1 })).toMatchObject({ ok: false, field: 'kind' });
    expect(validateUploadRequest({ kind: 'avatar', content_type: 'image/svg+xml', size: 1 })).toMatchObject({ ok: false, field: 'content_type' });
    expect(validateUploadRequest({ kind: 'avatar', content_type: 'image/png', size: 16 * 1024 * 1024 })).toMatchObject({ ok: false, field: 'size' });
    expect(validateUploadRequest({ kind: 'avatar', content_type: 'image/png', size: 0 })).toMatchObject({ ok: false, field: 'size' });
    const key = newObjectKey('u-1', 'png', Date.UTC(2026, 8, 7));
    expect(key).toMatch(/^u\/u-1\/20260907\/[0-9a-f]{24}\.png$/);
    expect(ownsKey(key, 'u-1')).toBe(true);
    expect(ownsKey(key, 'u-10')).toBe(false);
    expect(ownsKey('u/u-10/x.png', 'u-1')).toBe(false);
    expect(s3ConfigFromEnv({ R2_ENDPOINT: 'https://a.r2.cloudflarestorage.com', R2_BUCKET: 'b', R2_ACCESS_KEY_ID: 'k' })).toBeUndefined();
    expect(s3ConfigFromEnv({ R2_ENDPOINT: 'https://a.r2.cloudflarestorage.com', R2_BUCKET: 'b', R2_ACCESS_KEY_ID: 'k', R2_SECRET_ACCESS_KEY: 's', R2_PUBLIC_BASE: '' }))
      .toEqual({ endpoint: 'https://a.r2.cloudflarestorage.com', bucket: 'b', accessKeyId: 'k', secretAccessKey: 's', region: 'auto', publicBase: undefined });
  });
});
