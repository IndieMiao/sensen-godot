import { describe, expect, it, vi } from 'vitest';
import { isSensitiveKey, parseDsn, REDACTED, scrub, scrubText, scrubUrl, sentryReporter, nullReporter } from '../../src/http/telemetry.js';

describe('E2 / E4 服务端脱敏与错误上报', () => {
  it('敏感键整值替换，其余原样保留', () => {
    const got = scrub({ lat: 31.2304, lng: 121.4737, text: '见面聊', conversation_id: 'c1', seq: 7,
      nested: { id_token: 'eyJabc', display_name: '小明' } }) as Record<string, unknown>;
    expect(got.lat).toBe(REDACTED);
    expect(got.lng).toBe(REDACTED);
    expect(got.text).toBe(REDACTED);
    expect(got.conversation_id).toBe('c1');
    expect(got.seq).toBe(7);
    expect((got.nested as Record<string, unknown>).id_token).toBe(REDACTED);
    expect((got.nested as Record<string, unknown>).display_name).toBe(REDACTED);
  });

  it('键名比较忽略大小写与分隔符', () => {
    expect(isSensitiveKey('Lat')).toBe(true);
    expect(isSensitiveKey('ACCESS-TOKEN')).toBe(true);
    expect(isSensitiveKey('user_id')).toBe(false);
  });

  it('自由文本与 URL 打码', () => {
    expect(scrubText('联系 qa@sensen.test')).toBe(`联系 ${REDACTED}`);
    expect(scrubText('at 31.2304,121.4737')).toBe(`at ${REDACTED}`);
    expect(scrubText('Authorization: Bearer abc.def')).toBe(`Authorization: Bearer ${REDACTED}`);
    expect(scrubText('HTTP 404 NOT_FOUND')).toBe('HTTP 404 NOT_FOUND');
    expect(scrubUrl('https://api/v1/feed?cursor=abc')).toBe(`https://api/v1/feed?${REDACTED}`);
  });

  it('深层结构有深度上限', () => {
    let deep: unknown = { lat: 31.2304 };
    for (let i = 0; i < 12; i++) deep = { wrap: deep };
    expect(JSON.stringify(scrub(deep))).not.toContain('31.2304');
  });

  it('DSN 解析；没有 DSN 就是空转', async () => {
    expect(parseDsn('https://abc123@o1.ingest.test/42')).toEqual({ key: 'abc123', url: 'https://o1.ingest.test/api/42/store/' });
    expect(parseDsn('nope')).toBeNull();
    await expect(nullReporter.capture('boom')).resolves.toBeUndefined();
    const fetcher = vi.fn();
    const off = sentryReporter('nope', () => 0, fetcher as never);
    await off.capture('boom');
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('上报的事件已脱敏并带鉴权头', async () => {
    const calls: { url: string; init: { headers: Record<string, string>; body: string } }[] = [];
    const fetcher = (async (url: string, init: never) => { calls.push({ url, init }); }) as never;
    const r = sentryReporter('https://abc123@o1.ingest.test/42', () => 1_700_000_000_000, fetcher, { environment: 'prod' });
    await r.capture('send failed for qa@sensen.test', { code: 'BLOCKED', lat: 31.2 }, 'warning');
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('https://o1.ingest.test/api/42/store/');
    expect(calls[0].init.headers['x-sentry-auth']).toContain('sentry_key=abc123');
    const event = JSON.parse(calls[0].init.body);
    expect(event.message).toBe(`send failed for ${REDACTED}`);
    expect(event.extra.code).toBe('BLOCKED');
    expect(event.extra.lat).toBe(REDACTED);
    expect(event.level).toBe('warning');
    expect(event.environment).toBe('prod');
    expect(event.timestamp).toBe(1_700_000_000);
  });
});
