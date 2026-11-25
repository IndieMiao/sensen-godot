/**
 * 动态农场正式服部署材料（C-96）：冒烟脚本在正式配置（C-101 起开放邮箱注册和 Google 登录）的服务上全部通过，
 * 在关着注册、关着 Google 或开着重选的服务上报错；冒烟不建号。compose 写死正式配置，只在回环地址发布端口，
 * 模板和 ops.sh 的禁写清单与 compose 一致；开放注册后发信必填。
 */
import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { hashPassword } from '../../src/accounts/password.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { loadParcelRules } from '../../src/parcels/rules.js';
import { MemoryParcelStore } from '../../src/parcels/store.js';
import { firstInvite, runSmoke } from '../../src/ops/dynamicfarm_smoke.js';
import { makeKeys } from '../fixtures/firebase_tokens.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const DEPLOY = path.join(ROOT, 'server', 'deploy', 'dynamicfarm');
const WRITE = { dataset_version: 'sf-dynamic-farm-20261118-r4', parcel_id: 'p-3512001', center: [-122.4194, 37.7749] as [number, number] };

describe('dynamic farm smoke', () => {
  let app: FastifyInstance | undefined;
  afterEach(async () => { await app?.close(); app = undefined; });

  async function serve(opts: { signupClosed: boolean; reselect: boolean; google?: boolean }) {
    const now = () => Date.UTC(2026, 10, 24, 4);
    const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot: plotFor(content), now, contentVersion: CV });
    const created = await store.createEmailUser('df-abcdefgh@invite.example.org', await hashPassword('k3mq-7hxa-pt2d-wz9e'), now());
    if (created.kind !== 'created') throw new Error('seed');
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
      regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-pepper', now, realtimeEnabled: false,
      gitSha: 'a'.repeat(40), signupClosed: opts.signupClosed,
      google: opts.google === false ? undefined : { audiences: ['web-client.apps.googleusercontent.com'], keys: makeKeys('smoke').keys },
      parcels: { store: new MemoryParcelStore(id => store.displayNameOf(id)), rules: loadParcelRules(DEFAULT_CONTENT_DIR), reselect: opts.reselect } });
    const address = await app.listen({ port: 0, host: '127.0.0.1' });
    return { base: `${address}/v1`, store };
  }
  const invite = firstInvite('email,password,batch\ndf-abcdefgh@invite.example.org,k3mq-7hxa-pt2d-wz9e,wave-1\n');

  it('passes on the production configuration, including the isolated write path', async () => {
    const { base, store } = await serve({ signupClosed: false, reselect: false });
    const lines: string[] = [];
    const probes: string[] = [];
    const watched: typeof fetch = async (url, init) => {
      if (String(url).endsWith('/auth/email/register')) probes.push(JSON.parse(String(init?.body)).email);
      return fetch(url, init);
    };
    const result = await runSmoke({ base, gitSha: 'a'.repeat(40), invite, write: WRITE, log: l => { lines.push(l); }, fetch: watched });
    expect(result.failures).toEqual([]);
    expect(result.ok).toBe(true);
    expect(result.farm).toMatchObject({ parcel_id: 'p-3512001', farm: { tilled: ['1,1'], house: expect.any(Object) } });
    expect(lines.join('\n')).not.toContain('k3mq-7hxa-pt2d-wz9e');
    expect(lines).toEqual(expect.arrayContaining(['✓ 邮箱注册已开放', '✓ Google 登录已开启']));
    // The sign-up probe never makes an account.
    expect(probes).toHaveLength(1);
    expect(await store.userByEmail(probes[0])).toBeNull();
    // A second run on the same account reads the saved parcel back instead of saving again.
    expect((await runSmoke({ base, invite, write: WRITE })).ok).toBe(true);
  });

  it('fails when sign-up is closed, Google is off, reselect is on or another build is running', async () => {
    const { base } = await serve({ signupClosed: true, reselect: true, google: false });
    const result = await runSmoke({ base, gitSha: 'b'.repeat(40), invite });
    expect(result.ok).toBe(false);
    expect(result.failures).toEqual([`运行的是 ${'b'.repeat(40)}`, '邮箱注册已开放', 'Google 登录已开启', '“放弃并重选”关闭']);
  });

  it('reads the first account from a CSV and ignores an empty input', () => {
    expect(invite).toEqual({ email: 'df-abcdefgh@invite.example.org', password: 'k3mq-7hxa-pt2d-wz9e' });
    expect(firstInvite('')).toBeUndefined();
    expect(firstInvite('email,password,batch\n')).toBeUndefined();
  });
});

describe('dynamic farm deploy files', () => {
  const compose = readFileSync(path.join(DEPLOY, 'compose.yml'), 'utf8');
  const envExample = readFileSync(path.join(DEPLOY, 'env.example'), 'utf8');
  const ops = readFileSync(path.join(DEPLOY, 'ops.sh'), 'utf8');
  const FORCED: Record<string, string> = {
    ACCOUNT_SIGNUP: 'open', GUEST_WRITES: '"0"', PARCEL_GUEST_WRITES: '"0"', DYNAMIC_FARM_RESELECT: '"0"',
    GOOGLE_CLIENT_IDS: '105022638066-s710gs2tsaikbkhbtvstdino7cq661go\\.apps\\.googleusercontent\\.com', APPLE_BUNDLE_IDS: '""',
    QA_EMAIL_DOMAIN: '""', QA_EMAIL_CODE: '""', QA_PLAYER_IDS: '""', EMAIL_LOG_CODES: '"0"',
  };

  it('pins the production switches in compose and keeps them out of the .env template', () => {
    for (const [key, value] of Object.entries(FORCED)) {
      expect(compose).toMatch(new RegExp(`^ {6}${key}: ${value.replace(/"/g, '"')}$`, 'm'));
      expect(envExample).not.toMatch(new RegExp(`^${key}=`, 'm'));
    }
    const forbidden = /for k in (ACCOUNT_SIGNUP[^;]*); do/.exec(ops)?.[1].split(' ') ?? [];
    expect(forbidden.sort()).toEqual(Object.keys(FORCED).filter(k => k !== 'EMAIL_LOG_CODES').sort());
  });

  it('publishes only the app, only on loopback, with its own database volume and no other project network', () => {
    expect(compose.match(/ports:/g)).toHaveLength(1);
    expect(compose).toContain('ports: ["127.0.0.1:${DF_HOST_PORT:-3160}:3000"]');
    expect(compose).toContain('POSTGRES_DB: sensen_dynamicfarm');
    expect(compose).toMatch(/^name: dynamicfarm$/m);
    expect(compose).not.toMatch(/external:|farm_default|p0data|pgdata_farm/);
  });

  it('lists every required setting in the .env template', () => {
    const required = /for k in (POSTGRES_PASSWORD[^;]*); do/.exec(ops)?.[1].split(' ') ?? [];
    expect(required.length).toBeGreaterThan(0);
    for (const key of [...required, 'APP_IMAGE', 'APP_IMAGE_ID', 'GIT_SHA']) expect(envExample).toMatch(new RegExp(`^${key}=$`, 'm'));
  });
});

/**
 * C-104：cron 的 PATH 只有 /usr/bin:/bin，docker 和 age 在 /usr/local/bin 时 ops.sh 要自己找得到。
 * 测试不能往系统目录放替身，所以把 ops.sh 补的每个目录挪到临时根目录下（只改这一行），替身放进 <根>/usr/local/bin。
 */
describe('dynamic farm ops.sh under a cron PATH', () => {
  const ops = readFileSync(path.join(DEPLOY, 'ops.sh'), 'utf8');
  const PATH_LINE = /^PATH="\$\{PATH:\+\$PATH:\}([^"]+)"; export PATH$/m;
  // 系统目录里有真的 docker 或 age 时，会先于替身被找到，不能在这台机器上跑。
  const realTools = ['/usr/bin/docker', '/bin/docker', '/usr/bin/age', '/bin/age'].some(p => existsSync(p));
  let tmp: string | undefined;
  afterEach(() => { if (tmp) rmSync(tmp, { recursive: true, force: true }); tmp = undefined; });

  it('appends the usual tool directories after the caller PATH', () => {
    const dirs = PATH_LINE.exec(ops)?.[1].split(':') ?? [];
    expect(dirs).toEqual(expect.arrayContaining(['/usr/local/bin', '/usr/local/sbin', '/usr/sbin', '/sbin', '/snap/bin']));
    // 放在 set -euo pipefail 之后、第一次调用外部命令之前。
    expect(ops.indexOf('set -euo pipefail')).toBeLessThan(ops.search(PATH_LINE));
    expect(ops.search(PATH_LINE)).toBeLessThan(ops.indexOf('DIR="$(cd'));
  });

  /** 在临时目录摆好部署目录和替身，用 env -i PATH=/usr/bin:/bin 跑 ops.sh（默认 backup）；script 拿到临时根目录，返回要运行的脚本。 */
  function stage(script: (root: string) => string, cmd = 'backup', extraEnv: string[] = []) {
    tmp = mkdtempSync(path.join(os.tmpdir(), 'df-cron-'));
    const root = path.join(tmp, 'root');
    const deploy = path.join(tmp, 'opt', 'dynamicfarm');
    const bin = path.join(root, 'usr', 'local', 'bin');
    mkdirSync(deploy, { recursive: true }); mkdirSync(bin, { recursive: true });
    writeFileSync(path.join(deploy, 'ops.sh'), script(root), { mode: 0o755 });
    writeFileSync(path.join(deploy, '.env'), [
      `POSTGRES_PASSWORD=${'a'.repeat(24)}`, `TOKEN_PEPPER=${'p'.repeat(32)}`, 'TRUSTED_PROXIES=172.30.96.1',
      'INVITE_EMAIL_DOMAIN=invite.example.org', `PG_IMAGE=postgres:16@sha256:${'0'.repeat(64)}`, 'AGE_RECIPIENT=age1stub', ...extraEnv, '',
    ].join('\n'), { mode: 0o600 });
    // docker 替身只认 ops.sh backup 用到的 compose 调用，每次调用记进 calls.log。
    writeFileSync(path.join(bin, 'docker'), `#!/bin/bash
echo "docker $*" >> "$(dirname "$0")/calls.log"
[ "$1" = compose ] || exit 2; shift
while [ $# -gt 0 ]; do case "$1" in -f|--env-file) shift 2 ;; *) break ;; esac; done
sub=$1; shift
case "$sub" in
  up) ;;
  exec) [ "$1" = -T ] && shift; shift
    case "$1" in
      pg_isready) ;;
      pg_dump) printf 'PGDMP-stub' ;;
      pg_restore) cat > /dev/null ;;
      psql) case "$*" in *parcel_claims_md5*) printf 'users 0\\nplayers 0\\n' ;; esac ;;
      *) exit 2 ;;
    esac ;;
  *) exit 2 ;;
esac
`, { mode: 0o755 });
    writeFileSync(path.join(bin, 'age'), `#!/bin/bash
echo "age $*" >> "$(dirname "$0")/calls.log"
while [ $# -gt 1 ]; do case "$1" in -o) out=$2; shift 2 ;; *) shift ;; esac; done
cp "$1" "$out"
`, { mode: 0o755 });
    const run = spawnSync('/usr/bin/env', ['-i', 'PATH=/usr/bin:/bin', path.join(deploy, 'ops.sh'), cmd], { encoding: 'utf8' });
    const calls = existsSync(path.join(bin, 'calls.log')) ? readFileSync(path.join(bin, 'calls.log'), 'utf8') : '';
    return { run, calls, deploy };
  }

  it.skipIf(realTools)('backs up with only /usr/bin:/bin when docker and age live in /usr/local/bin', () => {
    const m = PATH_LINE.exec(ops);
    if (!m) throw new Error('ops.sh has no PATH line');
    const { run, calls, deploy } = stage(root =>
      ops.replace(m[0], () => `PATH="\${PATH:+$PATH:}${m[1].split(':').map(d => root + d).join(':')}"; export PATH`));
    expect(run.stderr).not.toContain('not found');
    expect(run.status, run.stderr).toBe(0);
    expect(run.stdout.trim()).toMatch(/\/backups\/dynamicfarm-\d{8}T\d{6}Z\.dump\.age$/);
    expect(existsSync(run.stdout.trim())).toBe(true);
    expect(readdirSync(path.join(deploy, 'backups')).sort()).toHaveLength(2);
    expect(calls).toMatch(/^docker compose .* exec -T postgres pg_dump /m);
    expect(calls).toMatch(/^age -r age1stub -o /m);
  });

  // C-101：开放注册后 check 和 deploy 要求发信配置；上面的备份用例的 .env 没有发信配置，仍然通过（cron 备份不受影响）。
  it.skipIf(realTools)('check refuses a deployment without mail settings, before touching docker', () => {
    const plain = (root: string) => { const m = PATH_LINE.exec(ops)!; return ops.replace(m[0], () => `PATH="\${PATH:+$PATH:}${m[1].split(':').map(d => root + d).join(':')}"; export PATH`); };
    const none = stage(plain, 'check');
    expect(none.run.status).not.toBe(0);
    expect(none.run.stderr).toContain('.env 缺少 SMTP_URL');
    expect(none.calls).toBe('');
    rmSync(tmp!, { recursive: true, force: true });
    const http = stage(plain, 'check', ['SMTP_URL=http://mail.example.org', 'MAIL_FROM=Sensen <no-reply@example.org>']);
    expect(http.run.status).not.toBe(0);
    expect(http.run.stderr).toContain('SMTP_URL 要以 smtp:// 或 smtps:// 开头');
    expect(http.run.stderr).not.toContain('mail.example.org');
    expect(http.calls).toBe('');
    rmSync(tmp!, { recursive: true, force: true });
    const good = stage(plain, 'check', ['SMTP_URL=smtps://user:secret-pass@mail.example.org:465', 'MAIL_FROM=Sensen <no-reply@example.org>']);
    // Mail passes; the docker stand-in then refuses `compose config`, which proves check got past the mail step.
    expect(good.calls).toMatch(/^docker compose .* config -q$/m);
    expect(good.run.stderr + good.run.stdout).not.toContain('secret-pass');
  });

  it.skipIf(realTools)('fails to find docker without the PATH line (the cron failure this guards against)', () => {
    const { run, calls } = stage(() => ops.replace(PATH_LINE, ''));
    expect(run.status).not.toBe(0);
    expect(run.stderr).toMatch(/docker: (command )?not found/);
    expect(calls).toBe('');
  });
});
