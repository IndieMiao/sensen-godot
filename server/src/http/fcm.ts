/**
 * FCM HTTP v1 发送端（不引 firebase-admin）。三步：服务账号私钥签一个 JWT →
 * 换 OAuth2 access token（缓存到过期前 60 秒）→ 逐 token POST /messages:send。
 * APNs 由 FCM 代投，所以 iOS 不需要另一条通道，只要在 Firebase 控制台挂上 APNs key（SSLAUNCH A9）。
 *
 * 失效 token（UNREGISTERED / INVALID_ARGUMENT）回给调用方删表——不删的话每次都白发一遍。
 */
import { createSign } from 'node:crypto';
import type { DeviceRow, Notification, PushSender } from './push.js';

export interface ServiceAccount { project_id: string; client_email: string; private_key: string }

export type HttpJson = (url: string, init: { method: string; headers: Record<string, string>; body: string })
  => Promise<{ status: number; json: unknown }>;

export function parseServiceAccount(raw: string): ServiceAccount | null {
  try {
    const j = JSON.parse(raw) as Partial<ServiceAccount>;
    if (!j.project_id || !j.client_email || !j.private_key) return null;
    return { project_id: j.project_id, client_email: j.client_email, private_key: j.private_key.replace(/\\n/g, '\n') };
  } catch { return null; }
}

const b64url = (b: Buffer): string => b.toString('base64url');

/** 服务账号 JWT（RS256），scope 只要 firebase.messaging。 */
export function signAssertion(sa: ServiceAccount, nowMs: number): string {
  const iat = Math.floor(nowMs / 1000);
  const header = b64url(Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = b64url(Buffer.from(JSON.stringify({
    iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', iat, exp: iat + 3600,
  })));
  const signer = createSign('RSA-SHA256');
  signer.update(`${header}.${claims}`);
  return `${header}.${claims}.${b64url(signer.sign(sa.private_key))}`;
}

export function fcmSender(sa: ServiceAccount, now: () => number, http: HttpJson): PushSender {
  let token = '';
  let expiresAt = 0;

  const accessToken = async (): Promise<string> => {
    if (token && now() < expiresAt) return token;
    const body = new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: signAssertion(sa, now()),
    }).toString();
    const r = await http('https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body,
    });
    const j = r.json as { access_token?: string; expires_in?: number };
    if (r.status !== 200 || !j.access_token) throw new Error(`fcm oauth ${r.status}`);
    token = j.access_token;
    expiresAt = now() + Math.max(0, (j.expires_in ?? 3600) - 60) * 1000;
    return token;
  };

  return {
    async send(devices: DeviceRow[], n: Notification) {
      if (devices.length === 0) return { sent: 0, invalid: [] };
      const at = await accessToken();
      const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
      let sent = 0;
      const invalid: string[] = [];
      for (const d of devices) {
        const message = {
          token: d.token,
          notification: { title: n.title, body: n.body },
          data: n.data,
          apns: { payload: { aps: { sound: 'default' } } },
          android: { priority: 'HIGH' },
        };
        const r = await http(url, {
          method: 'POST',
          headers: { 'content-type': 'application/json', authorization: `Bearer ${at}` },
          body: JSON.stringify({ message }),
        });
        if (r.status === 200) { sent += 1; continue; }
        const err = (r.json as { error?: { status?: string } })?.error?.status ?? '';
        if (r.status === 404 || err === 'UNREGISTERED' || err === 'INVALID_ARGUMENT') invalid.push(d.token);
      }
      return { sent, invalid };
    },
  };
}
