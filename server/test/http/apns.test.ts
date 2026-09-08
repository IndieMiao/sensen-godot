/** D7 iOS 直连 APNs：provider token 签名与复用、失效 token 回报、按平台分流。 */
import { describe, expect, it } from 'vitest';
import { generateKeyPairSync } from 'node:crypto';
import {
  apnsHost, apnsSender, isDeadToken, parseApnsConfig, platformSender, signProviderToken, TOKEN_TTL_MS,
  type ApnsConfig, type ApnsPost,
} from '../../src/http/apns.js';
import type { DeviceRow, Notification, PushSender } from '../../src/http/push.js';

const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256', privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });

const cfg: ApnsConfig = { key: privateKey, keyId: 'ABCDE12345', teamId: 'TEAM123456', topic: 'app.sensen.ios', sandbox: true };
const device = (token: string, platform: 'ios' | 'android' = 'ios'): DeviceRow =>
  ({ user_id: 'u1', token, platform, updated_at: 0 });
const note: Notification = { title: '阿甲', body: 'Sent you a message', data: { type: 'im_message', conversation_id: 'c1' } };

function recorder(results: { status: number; reason: string }[]) {
  const calls: { url: string; headers: Record<string, string>; body: string }[] = [];
  const post: ApnsPost = async (url, headers, body) => {
    calls.push({ url, headers, body });
    return results[calls.length - 1] ?? { status: 200, reason: '' };
  };
  return { calls, post };
}

describe('apns config', () => {
  it('四项缺一就当没配', () => {
    expect(parseApnsConfig({ APNS_KEY: 'k', APNS_KEY_ID: 'i', APNS_TEAM_ID: 't' })).toBeNull();
    const ok = parseApnsConfig({ APNS_KEY: 'a\\nb', APNS_KEY_ID: 'i', APNS_TEAM_ID: 't', APNS_TOPIC: 'x', APNS_SANDBOX: '1' });
    expect(ok?.sandbox).toBe(true);
    expect(ok?.key).toBe('a\nb'); // 环境变量里的 \n 要还原成真换行
  });

  it('沙箱与生产是两个主机', () => {
    expect(apnsHost(cfg)).toContain('sandbox');
    expect(apnsHost({ ...cfg, sandbox: false })).not.toContain('sandbox');
  });
});

describe('provider token', () => {
  it('ES256 三段，签名是 JOSE 定长 64 字节', () => {
    const jwt = signProviderToken(cfg, 1_700_000_000_000);
    const [h, c, sig] = jwt.split('.');
    expect(JSON.parse(Buffer.from(h, 'base64url').toString())).toMatchObject({ alg: 'ES256', kid: cfg.keyId });
    expect(JSON.parse(Buffer.from(c, 'base64url').toString())).toMatchObject({ iss: cfg.teamId });
    expect(Buffer.from(sig, 'base64url').length).toBe(64);
  });

  it('50 分钟内复用同一个，过期才重签', async () => {
    let now = 1_000_000;
    const { calls, post } = recorder([]);
    const sender = apnsSender(cfg, () => now, post);
    await sender.send([device('t1')], note);
    await sender.send([device('t2')], note);
    expect(calls[0].headers.authorization).toBe(calls[1].headers.authorization);
    now += TOKEN_TTL_MS + 1;
    await sender.send([device('t3')], note);
    expect(calls[2].headers.authorization).not.toBe(calls[0].headers.authorization);
  });
});

describe('send', () => {
  it('每台一条，路径带 token，topic 与推送类型齐全', async () => {
    const { calls, post } = recorder([]);
    const sender = apnsSender(cfg, () => 1, post);
    const r = await sender.send([device('aa'), device('bb')], note);
    expect(r.sent).toBe(2);
    expect(calls[0].url).toContain('/3/device/aa');
    expect(calls[0].headers['apns-topic']).toBe(cfg.topic);
    expect(calls[0].headers['apns-push-type']).toBe('alert');
    const body = JSON.parse(calls[0].body);
    expect(body.aps.alert).toEqual({ title: note.title, body: note.body });
    expect(body.conversation_id).toBe('c1'); // 路由 id 平铺在 aps 之外
  });

  it('410 与 BadDeviceToken 回报为失效，其他失败只是没发出去', async () => {
    expect(isDeadToken(410, 'Unregistered')).toBe(true);
    expect(isDeadToken(400, 'BadDeviceToken')).toBe(true);
    expect(isDeadToken(400, 'PayloadTooLarge')).toBe(false);
    expect(isDeadToken(503, '')).toBe(false);
    const { post } = recorder([{ status: 410, reason: 'Unregistered' }, { status: 503, reason: '' }, { status: 200, reason: '' }]);
    const sender = apnsSender(cfg, () => 1, post);
    const r = await sender.send([device('dead'), device('flaky'), device('good')], note);
    expect(r.sent).toBe(1);
    expect(r.invalid).toEqual(['dead']);
  });

  it('安卓 token 不进 APNs', async () => {
    const { calls, post } = recorder([]);
    const sender = apnsSender(cfg, () => 1, post);
    const r = await sender.send([device('android-token', 'android')], note);
    expect(calls).toHaveLength(0);
    expect(r.sent).toBe(0);
  });
});

describe('platformSender', () => {
  const stub = (name: string, seen: string[]): PushSender => ({
    async send(devices) { seen.push(`${name}:${devices.map(d => d.token).join(',')}`); return { sent: devices.length, invalid: [] }; },
  });

  it('按平台分流，两边的失效 token 汇到一起', async () => {
    const seen: string[] = [];
    const s = platformSender(stub('ios', seen), stub('android', seen));
    const r = await s.send([device('a'), device('b', 'android')], note);
    expect(seen).toEqual(['ios:a', 'android:b']);
    expect(r.sent).toBe(2);
  });

  it('只配了一条通道时另一边静默跳过', async () => {
    const seen: string[] = [];
    const s = platformSender(null, stub('android', seen));
    const r = await s.send([device('a'), device('b', 'android')], note);
    expect(seen).toEqual(['android:b']);
    expect(r.sent).toBe(1);
  });
});
