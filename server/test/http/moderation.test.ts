import { describe, expect, it } from 'vitest';
import { NullModerator, OpenAiModerator, decide, validateReport } from '../../src/http/moderation.js';

const fetchWith = (status: number, body: unknown): typeof fetch =>
  (async () => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })) as unknown as typeof fetch;

describe('OpenAiModerator', () => {
  it('命中时给出排序后的分类；未命中 flagged=false', async () => {
    let seen: { url: string; init?: RequestInit } | null = null;
    const f: typeof fetch = (async (url: string | URL | Request, init?: RequestInit) => {
      seen = { url: String(url), init };
      return new Response(JSON.stringify({ results: [{ flagged: true, categories: { violence: true, harassment: false, 'sexual/minors': true } }] }), { status: 200 });
    }) as unknown as typeof fetch;
    const m = new OpenAiModerator('sk-test', f);
    expect(await m.check('bad text')).toEqual({ flagged: true, categories: ['sexual/minors', 'violence'] });
    expect(seen!.url).toBe('https://api.openai.com/v1/moderations');
    expect(JSON.parse(String(seen!.init!.body))).toEqual({ model: 'omni-moderation-latest', input: 'bad text' });
    expect((seen!.init!.headers as Record<string, string>).authorization).toBe('Bearer sk-test');
    expect(await new OpenAiModerator('k', fetchWith(200, { results: [{ flagged: false, categories: {} }] })).check('ok')).toEqual({ flagged: false, categories: [] });
  });

  it('HTTP 错误 / 空结果 / 抛异常都当服务出错，不当命中也不当放行', async () => {
    expect((await new OpenAiModerator('k', fetchWith(429, {})).check('x')).error).toBe('HTTP_429');
    expect((await new OpenAiModerator('k', fetchWith(200, { results: [] })).check('x')).error).toBe('EMPTY');
    const boom: typeof fetch = (async () => { throw new Error('ECONNRESET'); }) as unknown as typeof fetch;
    expect((await new OpenAiModerator('k', boom).check('x')).error).toBe('ECONNRESET');
    expect((await new NullModerator().check()).error).toBe('NOT_CONFIGURED');
  });

  it('decide：命中拒发、出错进队列、干净放行', () => {
    expect(decide({ flagged: true, categories: ['hate'] })).toEqual({ status: 'rejected', categories: ['hate'] });
    expect(decide({ flagged: false, categories: [], error: 'HTTP_500' })).toEqual({ status: 'pending', categories: [] });
    expect(decide({ flagged: false, categories: [] })).toEqual({ status: 'approved', categories: [] });
  });
});

describe('validateReport', () => {
  it('目标类型 / uuid / 原因枚举 / 说明长度', () => {
    const id = '11111111-2222-4333-8444-555555555555';
    expect(validateReport({ target_type: 'post', target_id: id, reason: 'spam' })).toMatchObject({ ok: true, targetType: 'post', detail: '' });
    expect(validateReport({ target_type: 'room', target_id: id, reason: 'spam' })).toMatchObject({ ok: false, field: 'target_type' });
    expect(validateReport({ target_type: 'user', target_id: 'nope', reason: 'spam' })).toMatchObject({ ok: false, field: 'target_id' });
    expect(validateReport({ target_type: 'user', target_id: id, reason: 'ugly' })).toMatchObject({ ok: false, field: 'reason' });
    expect(validateReport({ target_type: 'user', target_id: id, reason: 'other', detail: 'x'.repeat(501) })).toMatchObject({ ok: false, field: 'detail' });
    expect(validateReport(null)).toMatchObject({ ok: false, field: 'body' });
  });
});
