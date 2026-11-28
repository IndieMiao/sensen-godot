/**
 * 动态农场正式服部署材料（C-96）：冒烟脚本在正式配置（C-101 起开放邮箱注册和 Google 登录）的服务上全部通过，
 * 在关着注册、关着 Google 或开着重选的服务上报错；冒烟不建号。compose 写死正式配置，只在回环地址发布端口，
 * 模板和 ops.sh 的禁写清单与 compose 一致；开放注册后发信必填。
 * C-146：正式配置关掉游客入口，冒烟核对它关着；ops.sh guests 删游客号前先整库备份、再备份游客数据并核对、加密，才删。
 * C-259：Google 登录按实际配置核对。正式服按所有者 Q-243 把 GOOGLE_CLIENT_IDS 置空，冒烟确认 503 GOOGLE_UNAVAILABLE 即通过；开着时照旧。
 */
import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { execFile, spawnSync } from 'node:child_process';
import { promisify } from 'node:util';
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
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';
import { sha256Hex } from '../../src/accounts/apple_token.js';
import { DEFAULT_GOOGLE_CLIENT_IDS, googleClientIdsFromEnv, verifyGoogleIdToken } from '../../src/accounts/google_token.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const DEPLOY = path.join(ROOT, 'server', 'deploy', 'dynamicfarm');
const WRITE = { dataset_version: 'sf-dynamic-farm-20261118-r4', parcel_id: 'p-3512001', center: [-122.4194, 37.7749] as [number, number] };

describe('dynamic farm smoke', () => {
  let app: FastifyInstance | undefined;
  afterEach(async () => { await app?.close(); app = undefined; });

  async function serve(opts: { signupClosed: boolean; reselect: boolean; google?: boolean; guestsOpen?: boolean }) {
    const now = () => Date.UTC(2026, 10, 24, 4);
    const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot: plotFor(content), now, contentVersion: CV });
    const created = await store.createEmailUser('df-abcdefgh@invite.example.org', await hashPassword('k3mq-7hxa-pt2d-wz9e'), now());
    if (created.kind !== 'created') throw new Error('seed');
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
      regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-pepper', now, realtimeEnabled: false,
      gitSha: 'a'.repeat(40), signupClosed: opts.signupClosed, guestAccountsClosed: !opts.guestsOpen,
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
    expect(lines).toEqual(expect.arrayContaining(['✓ 邮箱注册已开放', '✓ Google 登录已开启', '✓ 游客入口已关', '✓ 不登录不能认领']));
    // The guest probe never makes a player (C-146).
    expect(await store.installationKnown('0'.repeat(64))).toBe(false);
    // The sign-up probe never makes an account.
    expect(probes).toHaveLength(1);
    expect(await store.userByEmail(probes[0])).toBeNull();
    // A second run on the same account reads the saved parcel back instead of saving again.
    expect((await runSmoke({ base, invite, write: WRITE })).ok).toBe(true);
  });

  it('fails when sign-up is closed, Google is off, guests can sign in, reselect is on or another build is running', async () => {
    const { base } = await serve({ signupClosed: true, reselect: true, google: false, guestsOpen: true });
    const result = await runSmoke({ base, gitSha: 'b'.repeat(40), invite });
    expect(result.ok).toBe(false);
    expect(result.failures).toEqual([`运行的是 ${'b'.repeat(40)}`, '邮箱注册已开放', 'Google 登录已开启', '游客入口已关', '“放弃并重选”关闭']);
  });

  // C-259：正式服按 Q-243 只开邮箱注册，Google 登录关着；按配置判断时这一项通过，其余各项照旧核对。
  it('passes with Google sign-in off when the configuration has it off, and still checks everything else', async () => {
    const { base } = await serve({ signupClosed: false, reselect: false, google: false });
    const lines: string[] = [];
    const result = await runSmoke({ base, gitSha: 'a'.repeat(40), invite, google: false, log: l => { lines.push(l); } });
    expect(result.failures).toEqual([]);
    expect(lines).toEqual(['✓ 健康检查', `✓ 运行的是 ${'a'.repeat(40)}`, '✓ 邮箱注册已开放', '✓ Google 登录已关闭（按配置）',
      '✓ 游客入口已关', '✓ 不登录不能认领', '✓ 不登录不能存档', '✓ 邀请账号登录', '✓ “放弃并重选”关闭']);
    // Without the configuration the default still expects Google on, as before (C-101).
    expect((await runSmoke({ base })).failures).toEqual(['Google 登录已开启']);
  });

  it('fails when the configuration says Google is off but the server still accepts Google sign-in', async () => {
    const { base } = await serve({ signupClosed: false, reselect: false });
    const lines: string[] = [];
    const result = await runSmoke({ base, google: false, log: l => { lines.push(l); } });
    expect(result.failures).toEqual(['Google 登录已关闭（按配置）']);
    expect(lines).toContain('✗ Google 登录已关闭（按配置）（HTTP 401 GOOGLE_TOKEN_MALFORMED）');
  });

  it('reads Google on or off from GOOGLE_CLIENT_IDS the same way the server does', () => {
    expect(googleClientIdsFromEnv({})).toEqual([DEFAULT_GOOGLE_CLIENT_IDS]);
    expect(googleClientIdsFromEnv({ GOOGLE_CLIENT_IDS: '' })).toEqual([]);
    expect(googleClientIdsFromEnv({ GOOGLE_CLIENT_IDS: ' , ' })).toEqual([]);
    expect(googleClientIdsFromEnv({ GOOGLE_CLIENT_IDS: ' a.apps.googleusercontent.com , b ' })).toEqual(['a.apps.googleusercontent.com', 'b']);
  });

  // ops.sh runs the tool inside the app container; by default it judges Google by that container's GOOGLE_CLIENT_IDS.
  it('the smoke tool judges Google by GOOGLE_CLIENT_IDS unless told otherwise', async () => {
    const { base } = await serve({ signupClosed: false, reselect: false, google: false });
    const run = async (env: Record<string, string>, ...extra: string[]) => {
      try {
        const { stderr } = await promisify(execFile)(path.join(ROOT, 'server', 'node_modules', '.bin', 'tsx'),
          ['tools/dynamicfarm_smoke.ts', '--base', base, ...extra], { cwd: path.join(ROOT, 'server'), env: { PATH: process.env.PATH ?? '', ...env } });
        return { code: 0, stderr };
      } catch (error) { const e = error as { code: number; stderr: string }; return { code: e.code, stderr: e.stderr }; }
    };
    const off = await run({ GOOGLE_CLIENT_IDS: '' });
    expect(off.stderr).toContain('Google 登录按配置判断：关着（GOOGLE_CLIENT_IDS 为空）');
    expect(off.stderr).toContain('✓ Google 登录已关闭（按配置）');
    expect(off.stderr).toContain('冒烟通过');
    expect(off.code).toBe(0);
    const on = await run({ GOOGLE_CLIENT_IDS: 'web-client.apps.googleusercontent.com' });
    expect(on.stderr).toContain('Google 登录按配置判断：开着');
    expect(on.stderr).toContain('✗ Google 登录已开启（HTTP 503 GOOGLE_UNAVAILABLE）');
    expect(on.code).toBe(1);
    // Unset means the server's default client, so Google is expected on, as the rehearsal runs it from the host.
    expect((await run({})).stderr).toContain('✗ Google 登录已开启（HTTP 503 GOOGLE_UNAVAILABLE）');
    const forced = await run({ GOOGLE_CLIENT_IDS: 'web-client.apps.googleusercontent.com' }, '--google', 'off');
    expect(forced.stderr).not.toContain('按配置判断');
    expect(forced.code).toBe(0);
    const bad = await run({}, '--google', 'maybe');
    expect(bad.stderr).toContain('--google 只能是 on、off 或 env');
    expect(bad.code).toBe(2);
  }, 30_000);

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
    ACCOUNT_SIGNUP: 'open', GUEST_ACCOUNTS: 'closed', GUEST_WRITES: '"0"', PARCEL_GUEST_WRITES: '"0"', DYNAMIC_FARM_RESELECT: '"0"',
    GOOGLE_CLIENT_IDS: '870347303349-bkbtvblhsj7epud9cm2ma2ia9r0blj5i\\.apps\\.googleusercontent\\.com', APPLE_BUNDLE_IDS: '""',
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

  it('accepts the Google web client id the release package asks tokens for (V-315)', async () => {
    // The package requests ID tokens for sensen/auth/google_web_client_id, so that is the token's aud.
    const project = readFileSync(path.join(ROOT, 'project.godot'), 'utf8');
    const sensen = /^\[sensen\]$([\s\S]*?)(?=^\[|(?![\s\S]))/m.exec(project)?.[1] ?? '';
    expect(sensen).not.toMatch(/^auth\/google_web_client_id\./m);
    const webClient = /^auth\/google_web_client_id="([^"]+)"$/m.exec(sensen)?.[1];
    expect(webClient).toMatch(/\.apps\.googleusercontent\.com$/);
    const audiences = /^ {6}GOOGLE_CLIENT_IDS: (.+)$/m.exec(compose)?.[1].split(',').map(s => s.trim()) ?? [];
    expect(audiences).toContain(webClient);
    // A token issued to the package's web client verifies under the production audiences.
    const keys = makeKeys('v315'), nonce = 'n'.repeat(32), now = Date.UTC(2026, 10, 25, 2), s = Math.floor(now / 1000);
    const token = signToken(keys, { iss: 'https://accounts.google.com', aud: webClient, sub: '1', iat: s - 5, exp: s + 3600,
      nonce: sha256Hex(nonce), email: 'ada@gmail.com', email_verified: true });
    await expect(verifyGoogleIdToken(token, nonce, { audiences, keys: keys.keys, now: () => now })).resolves.toMatchObject({ aud: webClient });
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
  function stage(script: (root: string) => string, cmd: string | string[] = 'backup', extraEnv: string[] = [], runEnv: string[] = []) {
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
      ./node_modules/.bin/tsx) shift
        [ "$1" != tools/dynamicfarm_smoke.ts ] || exit 0
        [ "$1" = tools/guest_purge.ts ] || exit 2; shift
        case "$1" in
          plan) echo 'plan players=2' ;;
          backup) [ -z "\${FAIL_GUEST_BACKUP:-}" ] || exit 1; printf 'GUEST-BACKUP\\nplayers\\t[]\\n' ;;
          verify|purge|restore) cat > "$(dirname "$0")/stdin.$1" ;;
          *) exit 2 ;;
        esac ;;
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
    const run = spawnSync('/usr/bin/env', ['-i', 'PATH=/usr/bin:/bin', ...runEnv, path.join(deploy, 'ops.sh'), ...[cmd].flat()], { encoding: 'utf8' });
    const calls = existsSync(path.join(bin, 'calls.log')) ? readFileSync(path.join(bin, 'calls.log'), 'utf8') : '';
    return { run, calls, deploy, bin };
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

  // C-146：删游客号之前先整库备份，再在主机上落盘、核对、加密游客备份，最后把同一份备份交给工具删；任何一步失败都不删。
  it.skipIf(realTools)('guests purge backs up the database and the guests, verifies and encrypts, then deletes with that backup', () => {
    const plain = (root: string) => { const m = PATH_LINE.exec(ops)!; return ops.replace(m[0], () => `PATH="\${PATH:+$PATH:}${m[1].split(':').map(d => root + d).join(':')}"; export PATH`); };
    const release = [`GIT_SHA=${'c'.repeat(40)}`, `APP_IMAGE=dynamicfarm-server:${'c'.repeat(40)}`, `APP_IMAGE_ID=sha256:${'d'.repeat(64)}`];
    // docker image inspect is the release check; the stand-in answers it with the recorded image ID.
    const withInspect = (root: string) => plain(root).replace('docker image inspect --format \'{{.Id}}\' "$(envget APP_IMAGE)"', `echo sha256:${'d'.repeat(64)}`);
    const unconfirmed = stage(withInspect, ['guests', 'purge'], release);
    expect(unconfirmed.run.status).not.toBe(0);
    expect(unconfirmed.run.stderr).toContain('--confirm-delete');
    expect(unconfirmed.calls).toBe('');
    rmSync(tmp!, { recursive: true, force: true });
    const done = stage(withInspect, ['guests', 'purge', '--confirm-delete'], release);
    expect(done.run.status, done.run.stderr).toBe(0);
    const steps = done.calls.split('\n').filter(Boolean);
    const at = (re: RegExp) => steps.findIndex(s => re.test(s));
    expect(at(/pg_dump/)).toBeGreaterThanOrEqual(0);
    expect(at(/pg_dump/)).toBeLessThan(at(/guest_purge\.ts backup --out -/));
    expect(at(/guest_purge\.ts backup/)).toBeLessThan(at(/guest_purge\.ts verify --backup -/));
    expect(at(/guest_purge\.ts verify/)).toBeLessThan(at(/^age -r age1stub -o \S+dynamicfarm-guests-\S+\.txt\.age/));
    expect(at(/dynamicfarm-guests-\S+\.txt\.age/)).toBeLessThan(at(/guest_purge\.ts purge --backup - --confirm-database sensen_dynamicfarm/));
    // The tool deleted with exactly the backup that was encrypted; the plaintext is gone, the .age stays.
    expect(readFileSync(path.join(done.bin, 'stdin.purge'), 'utf8')).toBe('GUEST-BACKUP\nplayers\t[]\n');
    const kept = readdirSync(path.join(done.deploy, 'backups'));
    expect(kept.filter(f => /^dynamicfarm-guests-\d{8}T\d{6}Z\.txt\.age$/.test(f))).toHaveLength(1);
    expect(kept.filter(f => f.includes('.part'))).toEqual([]);
    expect(kept.some(f => /pre-guest-purge\.dump\.age$/.test(f))).toBe(true);
    rmSync(tmp!, { recursive: true, force: true });
    const failed = stage(withInspect, ['guests', 'purge', '--confirm-delete'], release, ['FAIL_GUEST_BACKUP=1']);
    expect(failed.run.status).not.toBe(0);
    expect(failed.run.stderr).toContain('什么都没删');
    expect(failed.calls).not.toMatch(/guest_purge\.ts purge/);
    expect(readdirSync(path.join(failed.deploy, 'backups')).filter(f => f.includes('guests'))).toEqual([]);
  });

  // C-259：smoke 在 app 容器里跑冒烟工具，工具按容器的 GOOGLE_CLIENT_IDS 判断 Google 登录；命令行不加新参数，回滚到旧镜像也能跑；--invite 和入口地址照旧。
  it.skipIf(realTools)('smoke runs the tool in the app container with the same arguments as before', () => {
    const plain = (root: string) => { const m = PATH_LINE.exec(ops)!; return ops.replace(m[0], () => `PATH="\${PATH:+$PATH:}${m[1].split(':').map(d => root + d).join(':')}"; export PATH`); };
    const release = [`GIT_SHA=${'c'.repeat(40)}`, `APP_IMAGE=dynamicfarm-server:${'c'.repeat(40)}`, `APP_IMAGE_ID=sha256:${'d'.repeat(64)}`];
    const withInspect = (root: string) => plain(root).replace('docker image inspect --format \'{{.Id}}\' "$(envget APP_IMAGE)"', `echo sha256:${'d'.repeat(64)}`);
    const local = stage(withInspect, 'smoke', release);
    expect(local.run.status, local.run.stderr).toBe(0);
    expect(local.calls).toMatch(new RegExp(`^docker compose .* exec -T app \\./node_modules/\\.bin/tsx tools/dynamicfarm_smoke\\.ts --base http://127\\.0\\.0\\.1:3000/v1 --git-sha ${'c'.repeat(40)}$`, 'm'));
    rmSync(tmp!, { recursive: true, force: true });
    const entry = stage(withInspect, ['smoke', '--invite', 'https://farm.example.org/dynamicfarm/v1'], release);
    expect(entry.run.status, entry.run.stderr).toBe(0);
    expect(entry.calls).toMatch(new RegExp(`tools/dynamicfarm_smoke\\.ts --base https://farm\\.example\\.org/dynamicfarm/v1 --git-sha ${'c'.repeat(40)} --invite-stdin$`, 'm'));
  });

  it.skipIf(realTools)('fails to find docker without the PATH line (the cron failure this guards against)', () => {
    const { run, calls } = stage(() => ops.replace(PATH_LINE, ''));
    expect(run.status).not.toBe(0);
    expect(run.stderr).toMatch(/docker: (command )?not found/);
    expect(calls).toBe('');
  });
});
