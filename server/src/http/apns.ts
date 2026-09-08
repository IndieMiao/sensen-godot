/**
 * APNs 直连发送端（iOS）。
 *
 * 为什么不走 FCM 代投：那样 iOS 客户端就得引 Firebase iOS SDK 才能拿到 FCM token，
 * 为了一条推送通道把整套 Google SDK 装进 App——包体、隐私清单、审核问答都要多担一份。
 * 直连只要一个 p8 密钥：ES256 签个 JWT，HTTP/2 POST 到 APNs，二十行的事。
 * 所以分工是：iOS token = APNs device token 走这里，Android token = FCM token 走 fcm.ts。
 *
 * 失效 token（410 Unregistered / 400 BadDeviceToken）回给调用方删表。
 * 内容规矩同 push.ts：通知正文里不放消息内容。
 */
import { createSign } from 'node:crypto';
import type { DeviceRow, Notification, PushSender } from './push.js';

export interface ApnsConfig {
  /** Apple Developer 后台下载的 .p8 私钥内容（-----BEGIN PRIVATE KEY-----…）。 */
  key: string;
  /** 密钥 ID（10 位）。 */
  keyId: string;
  /** 团队 ID（10 位）。 */
  teamId: string;
  /** 应用 bundle id，作为 apns-topic。 */
  topic: string;
  /** 沙箱（开发构建 / TestFlight 之外的真机调试）还是生产。 */
  sandbox: boolean;
}

export const APNS_HOST_PROD = 'https://api.push.apple.com';
export const APNS_HOST_SANDBOX = 'https://api.sandbox.push.apple.com';

/** 注入点：一次 APNs 请求。分出来是为了测试不真开 HTTP/2。 */
export type ApnsPost = (url: string, headers: Record<string, string>, body: string)
  => Promise<{ status: number; reason: string }>;

export function apnsHost(cfg: ApnsConfig): string {
  return cfg.sandbox ? APNS_HOST_SANDBOX : APNS_HOST_PROD;
}

export function parseApnsConfig(env: Record<string, string | undefined>): ApnsConfig | null {
  const key = env.APNS_KEY ?? '';
  const keyId = env.APNS_KEY_ID ?? '';
  const teamId = env.APNS_TEAM_ID ?? '';
  const topic = env.APNS_TOPIC ?? '';
  if (!key || !keyId || !teamId || !topic) return null;
  return { key: key.replace(/\\n/g, '\n'), keyId, teamId, topic, sandbox: env.APNS_SANDBOX === '1' };
}

const b64url = (b: Buffer): string => b.toString('base64url');

/** APNs provider token（ES256）。Apple 要求至少 20 分钟换一次、最多一小时，取 50 分钟。 */
export function signProviderToken(cfg: ApnsConfig, nowMs: number): string {
  const iat = Math.floor(nowMs / 1000);
  const header = b64url(Buffer.from(JSON.stringify({ alg: 'ES256', kid: cfg.keyId, typ: 'JWT' })));
  const claims = b64url(Buffer.from(JSON.stringify({ iss: cfg.teamId, iat })));
  const signer = createSign('SHA256');
  signer.update(`${header}.${claims}`);
  // APNs 要 JOSE 格式（r||s 定长 64 字节），不是 DER。
  const sig = signer.sign({ key: cfg.key, dsaEncoding: 'ieee-p1363' });
  return `${header}.${claims}.${b64url(sig)}`;
}

export const TOKEN_TTL_MS = 50 * 60 * 1000;

/** APNs 认为这个 token 已经没用了：从表里删掉，别再发。 */
export function isDeadToken(status: number, reason: string): boolean {
  if (status === 410) return true;
  return status === 400 && (reason === 'BadDeviceToken' || reason === 'DeviceTokenNotForTopic');
}

export function apnsSender(cfg: ApnsConfig, now: () => number, post: ApnsPost): PushSender {
  let token = '';
  let signedAt = 0;

  const providerToken = (): string => {
    if (!token || now() - signedAt >= TOKEN_TTL_MS) {
      token = signProviderToken(cfg, now());
      signedAt = now();
    }
    return token;
  };

  return {
    async send(devices: DeviceRow[], n: Notification) {
      const ios = devices.filter(d => d.platform === 'ios');
      if (ios.length === 0) return { sent: 0, invalid: [] };
      const at = providerToken();
      const body = JSON.stringify({
        aps: { alert: { title: n.title, body: n.body }, sound: 'default' },
        ...n.data,
      });
      let sent = 0;
      const invalid: string[] = [];
      for (const d of ios) {
        const r = await post(`${apnsHost(cfg)}/3/device/${d.token}`, {
          ':method': 'POST',
          'authorization': `bearer ${at}`,
          'apns-topic': cfg.topic,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'content-type': 'application/json',
        }, body);
        if (r.status === 200) { sent += 1; continue; }
        if (isDeadToken(r.status, r.reason)) invalid.push(d.token);
      }
      return { sent, invalid };
    },
  };
}

/** 两条通道各管各的平台，对外还是一个 PushSender。缺哪条就只发另一条。 */
export function platformSender(ios: PushSender | null, android: PushSender | null): PushSender {
  return {
    async send(devices: DeviceRow[], n: Notification) {
      const iosDevices = devices.filter(d => d.platform === 'ios');
      const androidDevices = devices.filter(d => d.platform === 'android');
      let sent = 0;
      const invalid: string[] = [];
      if (ios && iosDevices.length > 0) {
        const r = await ios.send(iosDevices, n);
        sent += r.sent;
        invalid.push(...r.invalid);
      }
      if (android && androidDevices.length > 0) {
        const r = await android.send(androidDevices, n);
        sent += r.sent;
        invalid.push(...r.invalid);
      }
      return { sent, invalid };
    },
  };
}

/**
 * 真的 HTTP/2 发送（生产用；测试注入替身，不走这里）。
 * APNs 只认 HTTP/2，Node 的 fetch 走不了，用内建的 node:http2。每次一条连接开销不小，
 * 但离线推送本来就稀疏；真到量大了再加连接池。
 */
export function http2Post(): ApnsPost {
  return async (url, headers, body) => {
    const { connect } = await import('node:http2');
    const target = new URL(url);
    const session = connect(target.origin);
    try {
      return await new Promise<{ status: number; reason: string }>((resolve, reject) => {
        const req = session.request({ ...headers, ':path': target.pathname });
        let raw = '';
        req.setEncoding('utf8');
        let status = 0;
        req.on('response', h => { status = Number(h[':status'] ?? 0); });
        req.on('data', chunk => { raw += chunk; });
        req.on('error', reject);
        req.on('end', () => {
          let reason = '';
          try { reason = String((JSON.parse(raw || '{}') as { reason?: string }).reason ?? ''); } catch { reason = ''; }
          resolve({ status, reason });
        });
        req.end(body);
      });
    } finally {
      session.close();
    }
  };
}
