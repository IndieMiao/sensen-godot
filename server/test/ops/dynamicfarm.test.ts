/**
 * 动态农场正式服部署材料（C-96）：冒烟脚本在只用邀请账号的服务上全部通过、在开放注册或开着重选的服务上报错；
 * compose 写死正式配置，只在回环地址发布端口，模板和 ops.sh 的禁写清单与 compose 一致。
 */
import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { hashPassword } from '../../src/accounts/password.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { loadParcelRules } from '../../src/parcels/rules.js';
import { MemoryParcelStore } from '../../src/parcels/store.js';
import { firstInvite, runSmoke } from '../../src/ops/dynamicfarm_smoke.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const DEPLOY = path.join(ROOT, 'server', 'deploy', 'dynamicfarm');
const WRITE = { dataset_version: 'sf-dynamic-farm-20261118-r4', parcel_id: 'p-3512001', center: [-122.4194, 37.7749] as [number, number] };

describe('dynamic farm smoke', () => {
  let app: FastifyInstance | undefined;
  afterEach(async () => { await app?.close(); app = undefined; });

  async function serve(opts: { signupClosed: boolean; reselect: boolean }) {
    const now = () => Date.UTC(2026, 10, 24, 4);
    const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot: plotFor(content), now, contentVersion: CV });
    const created = await store.createEmailUser('df-abcdefgh@invite.example.org', await hashPassword('k3mq-7hxa-pt2d-wz9e'), now());
    if (created.kind !== 'created') throw new Error('seed');
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
      regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-pepper', now, realtimeEnabled: false,
      gitSha: 'a'.repeat(40), signupClosed: opts.signupClosed,
      parcels: { store: new MemoryParcelStore(id => store.displayNameOf(id)), rules: loadParcelRules(DEFAULT_CONTENT_DIR), reselect: opts.reselect } });
    const address = await app.listen({ port: 0, host: '127.0.0.1' });
    return `${address}/v1`;
  }
  const invite = firstInvite('email,password,batch\ndf-abcdefgh@invite.example.org,k3mq-7hxa-pt2d-wz9e,wave-1\n');

  it('passes on the production configuration, including the isolated write path', async () => {
    const base = await serve({ signupClosed: true, reselect: false });
    const lines: string[] = [];
    const result = await runSmoke({ base, gitSha: 'a'.repeat(40), invite, write: WRITE, log: l => { lines.push(l); } });
    expect(result.failures).toEqual([]);
    expect(result.ok).toBe(true);
    expect(result.farm).toMatchObject({ parcel_id: 'p-3512001', farm: { tilled: ['1,1'], house: expect.any(Object) } });
    expect(lines.join('\n')).not.toContain('k3mq-7hxa-pt2d-wz9e');
    // A second run on the same account reads the saved parcel back instead of saving again.
    expect((await runSmoke({ base, invite, write: WRITE })).ok).toBe(true);
  });

  it('fails when sign-up is open, reselect is on or another build is running', async () => {
    const base = await serve({ signupClosed: false, reselect: true });
    const result = await runSmoke({ base, gitSha: 'b'.repeat(40), invite });
    expect(result.ok).toBe(false);
    expect(result.failures).toEqual([`运行的是 ${'b'.repeat(40)}`, '自助注册被拒（只用邀请账号）', '“放弃并重选”关闭']);
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
    ACCOUNT_SIGNUP: 'closed', GUEST_WRITES: '"0"', DYNAMIC_FARM_RESELECT: '"0"', GOOGLE_CLIENT_IDS: '""', APPLE_BUNDLE_IDS: '""',
    QA_EMAIL_DOMAIN: '""', QA_EMAIL_CODE: '""', EMAIL_LOG_CODES: '"0"',
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
