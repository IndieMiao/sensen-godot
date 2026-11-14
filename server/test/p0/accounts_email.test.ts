/** Sign in with an emailed code (SGODOT-497; contract-accounts v1.5 / v1.6.4; 亚瑟's plan §1; 周瑜): session/email/start,
 *  session/email, claim with {email, code}, hello's `email`, and that neither the address nor a code is kept or logged. */
import Fastify from 'fastify';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { EMAIL_LIMITS, EmailCodes, emailReady, emailVerifier, normalizeEmail, registerEmailRoutes, signInMail,
  type Mailer, type SignInMail } from '../../src/p0/accounts/email.js';
import { PendingSignIns } from '../../src/p0/accounts/link.js';
import { registerAccountRoutes } from '../../src/p0/accounts/routes.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 14, 4);
const V = { terms: '2026-11-13', privacy: '2026-11-13' };
const KEY = Buffer.alloc(32, 7);
const T = (n: number) => n.toString(16).padStart(64, '0');
const MIA = 'Mia.Rose+farm@Example.com';

const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });

function setup(over: { on?: boolean; key?: boolean; mailer?: 'ok' | 'none' | 'fail'; limits?: Partial<typeof EMAIL_LIMITS> } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'p0-email-'));
  dirs.push(dir);
  const file = path.join(dir, 'accounts.json');
  const clock = { t: T0 };
  const now = () => clock.t;
  const store = new P0Store(c), accounts = new P0Accounts(file, over.key === false ? null : KEY, now);
  const pending = new PendingSignIns(now);
  const codes = new EmailCodes(now, { ...EMAIL_LIMITS, ...over.limits });
  const mails: { to: string; mail: SignInMail }[] = [], warned: string[] = [], alerts: { subject: string; text: string }[] = [], kicked: string[] = [];
  const mailer: Mailer | null = over.mailer === 'none' ? null : {
    async send(to, mail) {
      if (over.mailer === 'fail') throw Object.assign(new Error(`550 mailbox ${to} unavailable`), { code: 'EENVELOPE', responseCode: 550 });
      mails.push({ to, mail });
    } };
  const deps = { store, accounts, now, pending, on: over.on ?? true, codes, mailer, kick: (p: string) => { kicked.push(p); },
    alert: (subject: string, text: string) => { alerts.push({ subject, text }); }, warn: (l: string) => { warned.push(l); } };
  const app = Fastify();
  registerEmailRoutes(app, deps);
  const verifyEmail = emailVerifier(deps);
  registerAccountRoutes(app, { store, accounts, identify: { accounts, legacyId: false, warn: () => {} }, now, versions: V,
    pending, kick: deps.kick, email: emailReady(deps),
    verify: async (provider, b) => {
      if (provider !== 'email') return undefined;
      const v = await verifyEmail(b);
      return 'status' in v ? v : { link: v };
    } });
  const post = (url: string, payload: unknown, ip = '10.0.0.1', headers: Record<string, string> = {}) =>
    app.inject({ method: 'POST', url, payload: payload as object, remoteAddress: ip, headers });
  const start = (email = MIA, extra: Record<string, unknown> = {}, ip?: string) => post('/v1/p0/session/email/start', { email, ...extra }, ip);
  const lastCode = () => /\n(\d{6})\n/.exec(mails[mails.length - 1].mail.text)![1];
  const signIn = (code: string, token = T(1), email = MIA, ip?: string) => post('/v1/p0/session/email', { email, code, token }, ip);
  const guest = (pend: string, token = T(1)) => post('/v1/p0/session/guest', { age_ok: true, ...V, name: 'Mia', token, request_id: T(9), pending: pend });
  return { app, file, clock, store, accounts, pending, codes, mails, warned, alerts, kicked, post, start, lastCode, signIn, guest };
}

describe('the address', () => {
  it('is trimmed and read in lower case, Gmail\'s dots and + kept; one emailId for each way of typing it', () => {
    expect(normalizeEmail('  Mia.Rose+farm@Example.COM ')).toBe('mia.rose+farm@example.com');
    for (const bad of ['', 'mia', 'mia@', '@example.com', 'mia@example', 'a b@example.com', 42, null, `${'a'.repeat(250)}@example.com`])
      expect(normalizeEmail(bad)).toBeNull();
    const a = new P0Accounts(undefined, KEY);
    expect(a.emailId(normalizeEmail(MIA)!)).toBe(a.emailId(normalizeEmail(' mia.rose+farm@example.com')!));
    expect(a.emailId('mia.rose+farm@example.com')).not.toBe(a.emailId('miarose+farm@example.com'));
    expect(a.emailId('x@example.com')).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe('session/email/start (contract v1.5)', () => {
  it('mails a 6-digit code in the app\'s language (q(323) ⑦ and note 1) and answers every address alike', async () => {
    const { start, mails } = setup();
    const r = await start();
    expect(r.statusCode).toBe(200);
    expect(r.json()).toEqual({ ok: true, resend_in: 60 });
    expect(mails[0].to).toBe('mia.rose+farm@example.com');
    const code = /\n(\d{6})\n/.exec(mails[0].mail.text)![1];
    expect(mails[0].mail).toEqual(signInMail(code, 'en'));
    expect(mails[0].mail.subject).toBe('Your Gensen sign-in code');
    expect(mails[0].mail.text).toBe(`Your Gensen sign-in code is\n\n${code}\n\nIt expires in 10 minutes.\n\n`
      + 'If you didn\'t ask for this code, you can ignore this email. No one can sign in without it.\n\nGensen · gensen.app/support\n');
    expect(await (await start('zh@example.com', { lang: 'zh' })).json()).toEqual({ ok: true, resend_in: 60 });
    const zh = /\n(\d{6})\n/.exec(mails[1].mail.text)![1];
    expect(mails[1].mail).toEqual({ subject: '你的 Gensen 登录验证码', text: `你的 Gensen 登录验证码是\n\n${zh}\n\n10 分钟内有效。\n\n`
      + '如果不是你本人申请的，忽略这封邮件即可。没有这个验证码，别人无法登录。\n\nGensen · gensen.app/support\n' });
    await start('fr@example.com', { lang: 'fr' });
    expect(mails[2].mail.subject).toBe('Your Gensen sign-in code');   // an unknown lang: English
    for (const m of mails) { expect(m.mail.subject).not.toMatch(/\d{6}/); expect(m.mail.text).not.toMatch(/https?:|www\./); }
  });

  it('a malformed address is schema; the code is never in the answer', async () => {
    const { start } = setup();
    expect([(await start('nope')).statusCode, (await start('nope')).json().code]).toEqual([400, 'schema']);
    expect((await start()).body).not.toMatch(/\d{6}/);
  });
});

describe('session/email (contract v1.5)', () => {
  it('no farm: no_farm with a pending sign-in that guest makes the farm with, linked to the address\'s emailId alone', async () => {
    const { start, lastCode, signIn, guest, accounts, pending, file } = setup();
    await start();
    const code = lastCode();
    const r = await signIn(code);
    expect(r.statusCode).toBe(404);
    expect(r.json()).toEqual({ ok: false, code: 'no_farm', pending: expect.stringMatching(/^[0-9a-f]{64}$/) });
    expect(pending.peek(r.json().pending)).toMatchObject({ provider: 'email', link: { sub: accounts.emailId('mia.rose+farm@example.com') } });
    const g = await guest(r.json().pending);
    expect(g.json()).toMatchObject({ ok: true, linked: 'email' });
    expect(accounts.linked(g.json().player)).toEqual(['email']);
    expect(accounts.isClaimed(g.json().player)).toBe(true);
    accounts.revoke(T(1));   // signed out: the email link alone keeps it claimed (its id alone must not open it)
    expect(accounts.isClaimed(g.json().player)).toBe(true);
    const disk = readFileSync(file, 'utf8');
    expect(disk).not.toMatch(/mia|example\.com/i);
    expect(disk).not.toContain(code);
  });

  it('the address\'s farm signed in on this phone, its other phones out; the code is taken once', async () => {
    const { start, lastCode, signIn, guest, accounts, kicked, clock } = setup();
    await start();
    const player = (await guest((await signIn(lastCode())).json().pending, T(1))).json().player;
    clock.t += 61_000;
    await start();
    const code = lastCode();
    const r = await signIn(code, T(2));
    expect(r.statusCode).toBe(200);
    expect(r.json()).toEqual({ ok: true, player, linked: ['email'] });
    expect(accounts.byToken(T(1))).toBeUndefined();   // the other phone's token revoked
    expect(accounts.byToken(T(2))?.player).toBe(player);
    expect(kicked).toEqual([player]);
    expect([(await signIn(code, T(3))).statusCode, (await signIn(code, T(3))).json().code]).toEqual([410, 'code_expired']);
  });

  it('five wrong tries void the code; ten minutes and it is gone; a new one voids the one before', async () => {
    const { start, lastCode, signIn, clock } = setup();
    await start();
    const code = lastCode(), wrong = code === '000000' ? '111111' : '000000';
    for (const left of [4, 3, 2, 1]) expect((await signIn(wrong)).json()).toEqual({ ok: false, code: 'bad_code', attempts_left: left });
    const fifth = await signIn(wrong);
    expect([fifth.statusCode, fifth.json()]).toEqual([401, { ok: false, code: 'bad_code', attempts_left: 0 }]);
    expect((await signIn(code)).json().code).toBe('code_expired');   // voided by the fifth
    clock.t += 61_000;
    await start();
    const late = lastCode();
    clock.t += 9.5 * 60_000;
    await signIn('123456', T(1), 'sweep@example.com');   // the sweep runs now, while the code is in date
    clock.t += 31_000;   // 10 minutes and a second: past it, with no sweep since
    expect((await signIn(late)).json().code).toBe('code_expired');
    clock.t += 61_000;
    await start();
    const first = lastCode();
    clock.t += 61_000;
    await start();
    const second = lastCode();
    if (first !== second) expect((await signIn(first)).json().code).toBe('bad_code');   // the one before is void
    expect((await signIn(second)).statusCode).toBe(404);
  });

  it('a token another player holds is refused and the code kept for the right one', async () => {
    const { start, lastCode, signIn, guest, store, accounts, clock } = setup();
    await start();
    await guest((await signIn(lastCode())).json().pending, T(1));
    store.get('p0-other0001', T0); accounts.ensure('p0-other0001'); accounts.issue('p0-other0001', T(5));
    clock.t += 61_000;
    await start();
    const code = lastCode();
    expect([(await signIn(code, T(5))).statusCode, (await signIn(code, T(5))).json().code]).toEqual([400, 'schema']);
    expect((await signIn(code, T(6))).statusCode).toBe(200);
  });

  it('refuses a short token and a malformed code or address', async () => {
    const { post } = setup();
    expect((await post('/v1/p0/session/email', { email: MIA, code: '123456', token: 'ab' })).json().code).toBe('token_too_short');
    for (const b of [{ email: MIA, code: '12345' }, { email: MIA, code: 'abcdef' }, { email: 'nope', code: '123456' }])
      expect((await post('/v1/p0/session/email', { ...b, token: T(1) })).json().code).toBe('schema');
  });
});

describe('limits (亚瑟\'s plan §1)', () => {
  it('an address: a minute between codes, 5 an hour, 10 a day — rate_limited with the seconds to wait', async () => {
    const { start, clock } = setup();
    await start();
    clock.t += 20_000;
    expect([(await start()).statusCode, (await start()).json()]).toEqual([429, { ok: false, code: 'rate_limited', retry_in: 40 }]);
    for (let i = 0; i < 4; i++) { clock.t += 61_000; expect((await start()).statusCode).toBe(200); }   // 5 this hour
    clock.t += 61_000;
    const sixth = await start();
    expect(sixth.statusCode).toBe(429);
    expect(sixth.json().retry_in).toBe(3600 - (20 + 5 * 61));   // the hour's first send leaves
    for (let h = 1; h <= 2; h++) {   // two more hours, 5 each: the day's 10
      clock.t = T0 + h * 3_600_000 + 1000;
      for (let i = 0; i < 5; i++) { clock.t += 61_000; await start(); }
    }
    clock.t += 3_600_000;
    const r = await start();
    expect(r.statusCode).toBe(429);
    expect(r.json().retry_in).toBeGreaterThan(3600);   // the day's first leaves after more than an hour
    expect((await start('other@example.com')).statusCode).toBe(200);   // another address is not held
  });

  it('an IP: 20 sends an hour and 30 checks an hour', async () => {
    const { start, post } = setup();
    for (let i = 0; i < 20; i++) expect((await start(`p${i}@example.com`, {}, '10.0.0.9')).statusCode).toBe(200);
    expect((await start('p20@example.com', {}, '10.0.0.9')).json().code).toBe('rate_limited');
    expect((await start('p20@example.com', {}, '10.0.0.8')).statusCode).toBe(200);   // another IP
    for (let i = 0; i < 30; i++) await post('/v1/p0/session/email', { email: `p${i}@example.com`, code: '000000', token: T(1) }, '10.0.0.7');
    const r = await post('/v1/p0/session/email', { email: 'p1@example.com', code: '000000', token: T(1) }, '10.0.0.7');
    expect([r.statusCode, r.json().code]).toEqual([429, 'rate_limited']);
  });

  it('every address together: the hour\'s and the day\'s caps answer email_unavailable, one alert a day without an address', async () => {
    const { start, alerts, warned, clock } = setup({ limits: { allHour: 3, allDay: 5 } });
    for (let i = 0; i < 3; i++) expect((await start(`a${i}@example.com`)).statusCode).toBe(200);
    const r = await start('a3@example.com');
    expect([r.statusCode, r.json()]).toEqual([503, { ok: false, code: 'email_unavailable' }]);
    await start('a4@example.com');
    expect(alerts).toHaveLength(1);
    expect(alerts[0].subject).toBe('Gensen sign-in codes: the cap is reached');
    clock.t += 3_600_000;
    for (let i = 5; i < 7; i++) expect((await start(`a${i}@example.com`)).statusCode).toBe(200);   // the day's 5
    expect((await start('a7@example.com')).json().code).toBe('email_unavailable');
    expect(alerts).toHaveLength(1);   // once a day
    clock.t = Date.UTC(2026, 10, 15, 3, 30);   // the next UTC day, still within 24 h of the first sends
    await start('a8@example.com');
    expect(alerts).toHaveLength(2);
    for (const line of [...alerts.map(a => a.subject + a.text), ...warned]) expect(line).not.toMatch(/@|example/);
  });

  it('a mail that fails takes nothing: email_unavailable, no code, the minute not spent; the log has no address', async () => {
    const { start, signIn, warned } = setup({ mailer: 'fail' });
    const r = await start();
    expect([r.statusCode, r.json()]).toEqual([503, { ok: false, code: 'email_unavailable' }]);
    expect((await start()).json().code).toBe('email_unavailable');   // not rate_limited: the failed one gave its place back
    expect((await signIn('123456')).json().code).toBe('code_expired');
    expect(warned[0]).toMatch(/"email_signin":"send_failed".*"error":"EENVELOPE".*"smtp":550/);
    for (const l of warned) expect(l).not.toMatch(/mia|example|unavailable/i);
  });
});

describe('switches (contract v1.5 / v1.6 ③)', () => {
  it('off, or no P0_ACCOUNTS_KEY: provider_unavailable on both routes; no mail: start is email_unavailable', async () => {
    for (const s of [setup({ on: false }), setup({ key: false })]) {
      for (const url of ['/v1/p0/session/email/start', '/v1/p0/session/email']) {
        const r = await s.post(url, { email: MIA, code: '123456', token: T(1) });
        expect([r.statusCode, r.json().code]).toEqual([503, 'provider_unavailable']);
      }
    }
    const { start } = setup({ mailer: 'none' });
    expect([(await start()).statusCode, (await start()).json().code]).toEqual([503, 'email_unavailable']);
  });

  it('hello says email only when it can run: on, a key and a mail', async () => {
    const hello = async (s: ReturnType<typeof setup>) => (await s.app.inject({ method: 'GET', url: '/v1/p0/hello' })).json().email;
    expect(await hello(setup())).toBe(true);
    expect(await hello(setup({ on: false }))).toBe(false);
    expect(await hello(setup({ key: false }))).toBe(false);
    expect(await hello(setup({ mailer: 'none' }))).toBe(false);
  });
});

describe('claim with an email sign-in (contract v1.5)', () => {
  it('the old farm claimed and linked to the address in one step; the code used up', async () => {
    const { start, lastCode, post, store, accounts } = setup();
    store.get('p0-old000001', T0);
    await start();
    const code = lastCode();
    const r = await post('/v1/p0/session/claim', { provider: 'email', email: MIA, code, token: T(3) }, undefined, { 'x-p0-player': 'p0-old000001' });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ ok: true, player: 'p0-old000001', linked: ['email'] });
    expect(accounts.byIdentity('email', accounts.emailId('mia.rose+farm@example.com'))).toBe('p0-old000001');
    const again = await post('/v1/p0/session/claim', { provider: 'email', email: MIA, code, token: T(4) }, undefined, { 'x-p0-player': 'p0-old000002' });
    expect([again.statusCode, again.json().code]).toEqual([410, 'code_expired']);
  });

  it('the address with another farm still there: conflict with the pending sign-in and has_farm', async () => {
    const { start, lastCode, signIn, guest, post, store, clock } = setup();
    await start();
    await guest((await signIn(lastCode())).json().pending, T(1));
    store.get('p0-old000001', T0);
    clock.t += 61_000;
    await start();
    const r = await post('/v1/p0/session/claim', { provider: 'email', email: MIA, code: lastCode(), token: T(3) }, undefined, { 'x-p0-player': 'p0-old000001' });
    expect(r.statusCode).toBe(409);
    expect(r.json()).toMatchObject({ code: 'conflict', has_farm: true, pending: expect.any(String) });
  });

  it('a wrong code is bad_code with its tries left; email off is provider_unavailable', async () => {
    const { start, lastCode, post, store } = setup();
    store.get('p0-old000001', T0);
    await start();
    const wrong = lastCode() === '000000' ? '111111' : '000000';
    const r = await post('/v1/p0/session/claim', { provider: 'email', email: MIA, code: wrong, token: T(3) }, undefined, { 'x-p0-player': 'p0-old000001' });
    expect([r.statusCode, r.json()]).toEqual([401, { ok: false, code: 'bad_code', attempts_left: 4 }]);
    const off = setup({ on: false });
    off.store.get('p0-old000001', T0);
    const o = await off.post('/v1/p0/session/claim', { provider: 'email', email: MIA, code: '123456', token: T(3) }, undefined, { 'x-p0-player': 'p0-old000001' });
    expect([o.statusCode, o.json().code]).toEqual([503, 'provider_unavailable']);
  });
});

describe('the account', () => {
  it('lists email among its links, and deleting it drops the address\'s identity', async () => {
    const { start, lastCode, signIn, guest, accounts } = setup();
    await start();
    const player = (await guest((await signIn(lastCode())).json().pending)).json().player;
    const id = accounts.emailId('mia.rose+farm@example.com');
    expect(accounts.byIdentity('email', id)).toBe(player);
    accounts.remove(player);
    expect(accounts.byIdentity('email', id)).toBeUndefined();
  });
});

describe('EmailCodes', () => {
  it('keeps no address and no code: its keys are HMAC under a pepper of its own', () => {
    const a = new EmailCodes(() => T0), b = new EmailCodes(() => T0);
    expect(a.key('mia@example.com')).toMatch(/^[0-9a-f]{24}$/);
    expect(a.key('mia@example.com')).not.toBe(b.key('mia@example.com'));
    a.put('mia@example.com', '123456');
    expect(JSON.stringify([...(a as unknown as { codes: Map<string, unknown> }).codes])).not.toMatch(/mia|123456/);
  });
});
