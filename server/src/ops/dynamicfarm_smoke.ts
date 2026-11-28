/**
 * 动态农场正式服冒烟（C-96），入口 tools/dynamicfarm_smoke.ts，由 server/deploy/dynamicfarm/ops.sh smoke 调用。
 * 默认只读、不建号：健康检查、邮箱注册和 Google 登录已开放（C-101）、游客入口已关（C-146）、不登录不能认领。
 * Google 登录按实际配置核对（C-259）：google=false 时确认它关着（503 GOOGLE_UNAVAILABLE），不当成失败。
 * 给了邀请账号再核对登录和“放弃并重选”被拒。
 * 只有隔离环境（演练）才给 write：用这个账号认领一块地、首次进入、放房开垦播种，再读回存档。正式服不要用，地块会被永久占用。
 */
import { randomBytes } from 'node:crypto';

export interface SmokeOptions {
  base: string;
  gitSha?: string;
  invite?: { email: string; password: string };
  /** 服务端是否开着 Google 登录；默认开着（C-101）。正式服按所有者 Q-243 关着，ops.sh 按 app 容器的 GOOGLE_CLIENT_IDS 传入。 */
  google?: boolean;
  write?: { dataset_version: string; parcel_id: string; center: [number, number] };
  fetch?: typeof fetch;
  log?: (line: string) => void;
}
export interface SmokeResult { ok: boolean; failures: string[]; farm?: unknown }

/** 读 CSV（email,password[,batch]）的第一条账号；表头和空行跳过。 */
export function firstInvite(text: string): { email: string; password: string } | undefined {
  for (const line of text.split(/\r?\n/)) {
    const [email, password] = line.split(',').map(v => v?.trim());
    if (email && password && email !== 'email') return { email, password };
  }
  return undefined;
}

export async function runSmoke(o: SmokeOptions): Promise<SmokeResult> {
  const http = o.fetch ?? fetch;
  const log = o.log ?? (() => {});
  const base = o.base.replace(/\/+$/, '');
  const failures: string[] = [];
  const check = (ok: boolean, what: string, detail = '') => {
    log(`${ok ? '✓' : '✗'} ${what}${ok || !detail ? '' : `（${detail}）`}`);
    if (!ok) failures.push(what);
    return ok;
  };
  const call = async (method: string, path: string, body?: unknown, token?: string) => {
    const res = await http(base + path, { method, headers: {
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    let json: Record<string, unknown> = {};
    try { json = JSON.parse(text) as Record<string, unknown>; } catch { /* 非 JSON 时只看状态码 */ }
    return { status: res.status, json };
  };
  const said = (r: { status: number; json: Record<string, unknown> }) => `HTTP ${r.status} ${String(r.json.code ?? '')}`.trim();

  const health = await call('GET', '/healthz');
  check(health.status === 200 && health.json.ok === true, '健康检查', said(health));
  if (o.gitSha) check(health.json.git_sha === o.gitSha, `运行的是 ${o.gitSha}`, `实际 ${String(health.json.git_sha)}`);

  // 邮箱注册已开放（C-101）：故意给一个太短的密码，开放的服务器回 400 WEAK_PASSWORD，不会建号也不发信；关着时回 403 SIGNUP_CLOSED。
  const signup = await call('POST', '/auth/email/register', { email: `smoke-${randomBytes(6).toString('hex')}@example.invalid`, password: 'short' });
  check(signup.status === 400 && signup.json.code === 'WEAK_PASSWORD', '邮箱注册已开放', said(signup));
  // Google 登录开着：一个不成形的令牌在验签前就被拒（401 GOOGLE_TOKEN_*），不去 Google 取公钥；关着时回 503 GOOGLE_UNAVAILABLE。
  // 按配置核对（C-259）：配置关着时，回 503 GOOGLE_UNAVAILABLE 才算通过。
  const google = await call('POST', '/auth/google', { id_token: 'smoke', nonce: randomBytes(12).toString('hex') });
  if (o.google === false) check(google.status === 503 && google.json.code === 'GOOGLE_UNAVAILABLE', 'Google 登录已关闭（按配置）', said(google));
  else check(google.status === 401 && String(google.json.code ?? '').startsWith('GOOGLE_TOKEN_'), 'Google 登录已开启', said(google));

  // 游客入口已关（C-146）：一个从没见过的安装密钥也拿不到 token，服务器不建号；开着时这里会建出一个游客。
  const anon = await call('POST', '/auth/anonymous', { install_key: randomBytes(16).toString('hex') });
  check(anon.status === 403 && anon.json.code === 'GUEST_CLOSED' && anon.json.token === undefined, '游客入口已关', said(anon));
  const claim = await call('POST', '/parcels/claim', { dataset_version: o.write?.dataset_version ?? 'smoke', parcel_id: 'p-smoke', center: [0, 0] });
  check(claim.status === 401 && claim.json.code === 'UNAUTHENTICATED', '不登录不能认领', said(claim));
  const cmd = await call('POST', '/parcels/mine/commands', { base_version: 0, commands: [{ type: 'till', cell: '1,1' }] });
  check(cmd.status === 401 && cmd.json.code === 'UNAUTHENTICATED', '不登录不能存档', said(cmd));

  let farm: unknown;
  if (o.invite) {
    const login = await call('POST', '/auth/email/login', { email: o.invite.email, password: o.invite.password });
    const token = typeof login.json.token === 'string' ? login.json.token : '';
    if (check(login.status === 200 && Boolean(token), '邀请账号登录', said(login))) {
      const abandon = await call('POST', '/parcels/mine/abandon', {}, token);
      check(abandon.status === 403 && abandon.json.code === 'RESELECT_DISABLED', '“放弃并重选”关闭', said(abandon));
      if (o.write) {
        const claim = await call('POST', '/parcels/claim', o.write, token);
        check(claim.status === 201 || claim.status === 200, '邀请账号认领地块', said(claim));
        const enter = await call('POST', '/parcels/mine/enter', {}, token);
        check(enter.status === 200, '首次进入地块', said(enter));
        const parcel = enter.json.parcel as { farm_version: number; farm: { house?: unknown } } | undefined;
        if (parcel && !parcel.farm.house) {
          const saved = await call('POST', '/parcels/mine/commands', { base_version: parcel.farm_version, commands: [
            { type: 'place_house', x: 9, y: 9 }, { type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }] }, token);
          check(saved.status === 200, '存档（放房、开垦、播种）', said(saved));
        }
        const again = await call('GET', '/parcels/mine', undefined, token);
        const back = again.json.parcel as { parcel_id: string; farm: { house?: unknown; tilled?: string[] } } | null;
        check(Boolean(back && back.parcel_id === o.write.parcel_id && back.farm.house && back.farm.tilled?.includes('1,1')), '读回存档', said(again));
        farm = back;
      }
    }
  }
  return { ok: failures.length === 0, failures, farm };
}
