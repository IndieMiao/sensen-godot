/**
 * 造 QA / 演示账号（D8 / B8）：Firebase 邮箱密码账号 → 服务端建映射 → 设 handle / 昵称 → 互相关注。
 * 幂等：账号已存在就直接登录；handle 已是自己的不会报错。
 *
 * 用法：
 *   FIREBASE_WEB_API_KEY=<Web API key> SERVER_BASE=http://127.0.0.1:3101/v1 \
 *   NODE_USE_ENV_PROXY=1 HTTPS_PROXY=http://127.0.0.1:7890 pnpm seed:qa [accounts.json]
 * accounts.json 形如 [{"email":"qa-alice@sensen.test","password":"…","handle":"alice","display_name":"QA alice"}]；
 * 不给就用内置的 alice / bob / carol。Web API key 也可从 ../config/firebase.json 读（api_key）。
 * 密码只在本机环境变量 / 文件里，不要提交。
 */
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

interface Account { email: string; password: string; handle: string; display_name: string }

const DEFAULTS: Account[] = [
  { email: 'qa-alice@sensen.test', password: process.env.QA_PASSWORD ?? 'Sensen-QA-2026', handle: 'alice', display_name: 'QA alice' },
  { email: 'qa-bob@sensen.test', password: process.env.QA_PASSWORD ?? 'Sensen-QA-2026', handle: 'bob', display_name: 'QA bob' },
  { email: 'qa-carol@sensen.test', password: process.env.QA_PASSWORD ?? 'Sensen-QA-2026', handle: 'carol', display_name: 'QA carol' },
];

const apiKey = process.env.FIREBASE_WEB_API_KEY ?? readApiKey();
const base = (process.env.SERVER_BASE ?? 'http://127.0.0.1:3101/v1').replace(/\/$/, '');
if (!apiKey) { console.error('缺 FIREBASE_WEB_API_KEY（或 ../config/firebase.json 的 api_key）'); process.exit(1); }

function readApiKey(): string | undefined {
  const p = path.resolve(process.cwd(), '..', 'config', 'firebase.json');
  if (!existsSync(p)) return undefined;
  try { return (JSON.parse(readFileSync(p, 'utf8')) as { api_key?: string }).api_key; } catch { return undefined; }
}

async function firebase(op: 'signUp' | 'signInWithPassword', email: string, password: string): Promise<{ idToken?: string; error?: string }> {
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:${op}?key=${apiKey}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const j = await r.json() as { idToken?: string; error?: { message?: string } };
  return { idToken: j.idToken, error: j.error?.message };
}

async function api(method: string, url: string, token: string, body?: unknown): Promise<{ status: number; json: Record<string, unknown> }> {
  const r = await fetch(`${base}${url}`, { method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: body === undefined ? '{}' : JSON.stringify(body) });
  let json: Record<string, unknown> = {};
  try { json = await r.json() as Record<string, unknown>; } catch { /* 空体 */ }
  return { status: r.status, json };
}

async function main() {
  const file = process.argv[2];
  const accounts: Account[] = file ? JSON.parse(readFileSync(file, 'utf8')) : DEFAULTS;
  const ids: { handle: string; user_id: string; token: string }[] = [];
  for (const a of accounts) {
    let f = await firebase('signUp', a.email, a.password);
    if (f.error === 'EMAIL_EXISTS') f = await firebase('signInWithPassword', a.email, a.password);
    if (!f.idToken) { console.error(`${a.email}: firebase ${f.error ?? 'no token'}`); process.exit(2); }
    const s = await api('POST', '/auth/firebase', f.idToken);
    if (s.status !== 200 && s.status !== 201) { console.error(`${a.email}: server ${s.status} ${JSON.stringify(s.json)}`); process.exit(3); }
    const p = await api('PUT', '/users/me/profile', f.idToken, { handle: a.handle, display_name: a.display_name });
    if (p.status !== 200 && !(p.status === 409 || p.json.code === 'HANDLE_TAKEN')) { console.error(`${a.email}: profile ${p.status} ${JSON.stringify(p.json)}`); process.exit(4); }
    ids.push({ handle: a.handle, user_id: String(s.json.user_id), token: f.idToken });
    console.log(`${a.email} → ${s.json.user_id} @${a.handle}${p.status === 200 ? '' : ' (handle 未改：' + JSON.stringify(p.json.code) + ')'}`);
  }
  // 互相关注：时间线才不是空的，陌生人打招呼限制也不挡 QA。
  for (const me of ids) for (const other of ids) {
    if (me === other) continue;
    const r = await api('PUT', `/users/${other.user_id}/follow`, me.token);
    if (r.status >= 300) console.warn(`@${me.handle} follow @${other.handle}: ${r.status} ${JSON.stringify(r.json)}`);
  }
  console.log('done');
}

main().catch(e => { console.error(e); process.exit(9); });
