/**
 * Sign in with an emailed code (SGODOT-497; contract-accounts v1.5 / v1.6.4; 亚瑟's plan §1; 周瑜): the third sign-in
 * beside Apple and Google, behind P0_EMAIL_LOGIN. session/email/start sends a 6-digit code to any well-formed address
 * and answers every one alike — never whether the address has a farm; session/email takes the code back and signs the
 * address's farm in, or answers no_farm {pending} for NAME, as session/apple|google do. A code lasts 10 minutes, is
 * taken once and stands five wrong tries; a new one voids the one before, and none goes sooner than 60 s after the last.
 * Codes live in memory only, as HMAC under a pepper made at start (a restart forgets them: the player asks again).
 * The address is kept nowhere: the account holds its emailId (HMAC under P0_ACCOUNTS_KEY), the limits and any log line
 * its emailKey (HMAC under the pepper, cut short). The mail goes out by P0_SIGNIN_SMTP_URL (signin@notify.gensen.app);
 * a day's sends are capped well under DirectMail's 2000 a day, which the reports mail shares.
 * Not Journey's email.ts / mailer.ts (SGODOT-304: P0 imports nothing of src/accounts), and never its log mailer, which
 * prints the address and the code.
 */
import { createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import nodemailer from 'nodemailer';
import type { P0Store } from '../store.js';
import { liveOwner, signIn, type PendingSignIns } from './link.js';
import { tokenShapeOk, type EmailLink, type P0Accounts } from './store.js';

export const CODE_TTL_MS = 10 * 60_000;
export const RESEND_MS = 60_000;
export const MAX_TRIES = 5;
const HOUR = 3_600_000, DAY = 24 * HOUR;
/** 亚瑟's plan §1, to be tuned after a week live: an address 1 a minute, 5 an hour, 10 a day; an IP 20 sends and 30
 *  checks an hour; every address together 200 an hour and 1200 a day (the reports mail keeps 800 of the 2000). */
export const EMAIL_LIMITS = { perEmailHour: 5, perEmailDay: 10, perIpHour: 20, checksPerIpHour: 30, allHour: 200, allDay: 1200 };
export type EmailLimits = typeof EMAIL_LIMITS;

/** The address as kept and keyed: trimmed, lower case; Gmail's dots and + kept (each provider has its own rules). */
export function normalizeEmail(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const email = v.trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return null;
  return email;
}
export const codeShapeOk = (v: unknown): v is string => typeof v === 'string' && /^\d{6}$/.test(v);
export const newEmailCode = (): string => String(randomInt(0, 1_000_000)).padStart(6, '0');

// ---------------------------------------------------------------- the mail

export type MailLang = 'en' | 'zh';
/** start's lang (v1.6.4): "zh" or "en", anything else English. */
export const mailLang = (v: unknown): MailLang => (v === 'zh' ? 'zh' : 'en');
export interface SignInMail { subject: string; text: string }
export const SIGNIN_FROM = 'Gensen <signin@notify.gensen.app>';

/** q(323) ⑦ (the user, bot 857) and its note 1 (李白's full text, 不知火舞's Chinese; libai-q323n1 44f596251): the
 *  subject without the code (a lock screen shows it); five paragraphs a blank line apart, the code alone on its line;
 *  plain text — no link, no picture; the support page as words. */
export function signInMail(code: string, lang: MailLang): SignInMail {
  if (lang === 'zh') return { subject: '你的 Gensen 登录验证码',
    text: `你的 Gensen 登录验证码是\n\n${code}\n\n10 分钟内有效。\n\n如果不是你本人申请的，忽略这封邮件即可。没有这个验证码，别人无法登录。\n\nGensen · gensen.app/support\n` };
  return { subject: 'Your Gensen sign-in code',
    text: `Your Gensen sign-in code is\n\n${code}\n\nIt expires in 10 minutes.\n\nIf you didn't ask for this code, you can ignore this email. No one can sign in without it.\n\nGensen · gensen.app/support\n` };
}

export interface Mailer { send(to: string, mail: SignInMail): Promise<void> }
export function smtpMailer(url: string, from: string): Mailer {
  const transport = nodemailer.createTransport(url);
  return { async send(to, m) { await transport.sendMail({ from, to, subject: m.subject, text: m.text }); } };
}
/** P0_SIGNIN_SMTP_URL (smtps://user:pass@host:465, the user's @ written %40; nodemailer reads it whole) and
 *  P0_SIGNIN_MAIL_FROM; none without the URL — then email sign-in is email_unavailable, the server runs on. */
export function signInMailerFromEnv(env: Record<string, string | undefined> = process.env): Mailer | null {
  return env.P0_SIGNIN_SMTP_URL ? smtpMailer(env.P0_SIGNIN_SMTP_URL, env.P0_SIGNIN_MAIL_FROM || SIGNIN_FROM) : null;
}

/** The cap's alert (亚瑟's plan §1: to the team, once a day, by the reports mail's account): P0_ALERT_SMTP_URL,
 *  P0_ALERT_MAIL_TO and P0_ALERT_MAIL_FROM (reports@ by default); none without the URL and the address. */
export function alertMailerFromEnv(env: Record<string, string | undefined> = process.env,
    warn: (line: string) => void = l => console.warn(l)): ((subject: string, text: string) => void) | undefined {
  const url = env.P0_ALERT_SMTP_URL, to = env.P0_ALERT_MAIL_TO;
  if (!url || !to) return undefined;
  const transport = nodemailer.createTransport(url), from = env.P0_ALERT_MAIL_FROM || 'Gensen <reports@notify.gensen.app>';
  return (subject, text) => {
    transport.sendMail({ from, to, subject, text })
      .catch((e: { code?: unknown }) => warn(JSON.stringify({ email_signin: 'alert_failed', error: typeof e?.code === 'string' ? e.code : 'unknown' })));
  };
}

// ---------------------------------------------------------------- codes and limits

/** Times within a sliding window, oldest first. */
const within = (times: number[] | undefined, now: number, ms: number): number[] => (times ?? []).filter(t => now - t < ms);
/** Seconds until a window holding `limit` frees one: its oldest leaves. 0 while under the limit. */
const waitFor = (times: number[], now: number, ms: number, limit: number): number =>
  times.length < limit ? 0 : Math.max(1, Math.ceil((times[times.length - limit] + ms - now) / 1000));

export type Reserved = { ok: true; at: number } | { ok: false; why: 'rate_limited'; retry_in: number } | { ok: false; why: 'full' };
export type Checked = { ok: true } | { ok: false; why: 'rate_limited'; retry_in: number }
  | { ok: false; why: 'bad_code'; attempts_left: number } | { ok: false; why: 'code_expired' };

/**
 * The codes sent and the counts that limit sending and checking, in memory. One process, one thread: a check and the
 * write after it run in one synchronous stretch — a send is reserved before the mail goes, so two at once are one.
 */
export class EmailCodes {
  private pepper = randomBytes(32);
  private codes = new Map<string, { hash: string; at: number; tries: number }>();   // emailKey → the code in force
  private sent = new Map<string, number[]>();        // emailKey → its sends, the last day
  private ipSent = new Map<string, number[]>();      // address → its sends, the last hour
  private ipChecked = new Map<string, number[]>();   // address → its checks, the last hour
  private all: number[] = [];                        // every send, the last day
  private sweptAt = 0;
  constructor(private now: () => number = Date.now, readonly limits: EmailLimits = EMAIL_LIMITS) {}

  /** The address as limits and logs may name it: HMAC under the pepper, 24 hex. */
  key(email: string): string { return createHmac('sha256', this.pepper).update('key:' + email).digest('hex').slice(0, 24); }
  private hash(email: string, code: string): string { return createHmac('sha256', this.pepper).update(`code:${email}:${code}`).digest('hex'); }

  /** A send for this address from this IP held at once, or why not: rate_limited (the address's minute, hour or day,
   *  the IP's hour) with the seconds to wait, or full (every address's hour or day — email_unavailable). */
  reserve(email: string, ip: string): Reserved {
    const now = this.now(), k = this.key(email), L = this.limits;
    this.sweep(now);
    const mine = within(this.sent.get(k), now, DAY), fromIp = within(this.ipSent.get(ip), now, HOUR);
    this.all = within(this.all, now, DAY);
    const last = mine[mine.length - 1];
    const wait = Math.max(last !== undefined && now - last < RESEND_MS ? Math.ceil((last + RESEND_MS - now) / 1000) : 0,
      waitFor(within(mine, now, HOUR), now, HOUR, L.perEmailHour), waitFor(mine, now, DAY, L.perEmailDay),
      waitFor(fromIp, now, HOUR, L.perIpHour));
    if (wait > 0) return { ok: false, why: 'rate_limited', retry_in: wait };
    if (within(this.all, now, HOUR).length >= L.allHour || this.all.length >= L.allDay) return { ok: false, why: 'full' };
    this.sent.set(k, [...mine, now]);
    this.ipSent.set(ip, [...fromIp, now]);
    this.all.push(now);
    return { ok: true, at: now };
  }
  /** A send that did not go gives its place back (a mail that failed takes nothing of anyone's limits). */
  release(email: string, ip: string, at: number): void {
    const drop = (times: number[] | undefined) => { const i = times?.lastIndexOf(at) ?? -1; if (i >= 0) times!.splice(i, 1); };
    drop(this.sent.get(this.key(email)));
    drop(this.ipSent.get(ip));
    drop(this.all);
  }
  /** The code sent: the address's one in force, the one before void. */
  put(email: string, code: string): void { this.codes.set(this.key(email), { hash: this.hash(email, code), at: this.now(), tries: 0 }); }

  /** The code against the address's one in force, which stays until take(): ok, bad_code with the tries left (the
   *  fifth wrong one voids it), code_expired (none, used, voided or past 10 minutes), or rate_limited for an IP past
   *  its checks this hour (`ip` absent: claim's check, which has no request to count). */
  check(email: string, code: string, ip?: string): Checked {
    const now = this.now();
    this.sweep(now);
    if (ip !== undefined) {
      const tries = within(this.ipChecked.get(ip), now, HOUR);
      const wait = waitFor(tries, now, HOUR, this.limits.checksPerIpHour);
      if (wait > 0) return { ok: false, why: 'rate_limited', retry_in: wait };
      this.ipChecked.set(ip, [...tries, now]);
    }
    const k = this.key(email), c = this.codes.get(k);
    if (!c || now - c.at >= CODE_TTL_MS) { this.codes.delete(k); return { ok: false, why: 'code_expired' }; }
    const h = this.hash(email, code);
    if (timingSafeEqual(Buffer.from(h, 'hex'), Buffer.from(c.hash, 'hex'))) return { ok: true };
    c.tries += 1;
    if (c.tries >= MAX_TRIES) this.codes.delete(k);
    return { ok: false, why: 'bad_code', attempts_left: Math.max(0, MAX_TRIES - c.tries) };
  }
  /** The address's code used up (a sign-in it made, once). */
  take(email: string): void { this.codes.delete(this.key(email)); }

  /** Codes past their time and counts out of their windows go, every few minutes (an address or IP seen once must not
   *  stay in memory). */
  private sweep(now: number): void {
    if (now - this.sweptAt < 5 * 60_000) return;
    this.sweptAt = now;
    for (const [k, c] of this.codes) if (now - c.at >= CODE_TTL_MS) this.codes.delete(k);
    for (const [m, ms] of [[this.sent, DAY], [this.ipSent, HOUR], [this.ipChecked, HOUR]] as const)
      for (const [k, t] of m) { const left = within(t, now, ms); if (left.length) m.set(k, left); else m.delete(k); }
  }
}

// ---------------------------------------------------------------- routes

type Refused = { status: number; body: { ok: false; code: string; [k: string]: unknown } };
const refused = (status: number, code: string, extra: Record<string, unknown> = {}): Refused => ({ status, body: { ok: false, code, ...extra } });
const bodyOf = (b: unknown) => (b && typeof b === 'object' && !Array.isArray(b) ? b : {}) as Record<string, unknown>;

export interface EmailRouteDeps {
  /** The sign-in answer's consent note (link.ts consentNote; spec v2 §9): absent, none. */
  consent?: import('./link.js').ConsentNote;
  store: P0Store; accounts: P0Accounts; now: () => number;
  /** The one PendingSignIns of p0_server: no_farm's pending sign-in, which guest takes. */
  pending: PendingSignIns;
  /** P0_EMAIL_LOGIN. Off — or no P0_ACCOUNTS_KEY to keep an emailId with — and both routes answer provider_unavailable. */
  on: boolean;
  codes: EmailCodes;
  /** The sign-in mail (signInMailerFromEnv); none, and start answers email_unavailable. */
  mailer: Mailer | null;
  /** The room hub's kick: a sign-in closes the account's open socket elsewhere (signIn). */
  kick?: (player: string) => void;
  /** Every address's cap reached, once a UTC day: to the team by the reports mail (p0_server). Holds no address. */
  alert?: (subject: string, text: string) => void;
  warn?: (line: string) => void;
}

/** Whether email sign-in can be offered (hello's `email`): switched on, a key for the emailIds, a mail to send. */
export const emailReady = (deps: Pick<EmailRouteDeps, 'on' | 'accounts' | 'mailer'>): boolean =>
  deps.on && deps.accounts.codesOn() && !!deps.mailer;

const checkRefusal = (c: Exclude<Checked, { ok: true }>): Refused =>
  c.why === 'rate_limited' ? refused(429, 'rate_limited', { retry_in: c.retry_in })
    : c.why === 'bad_code' ? refused(401, 'bad_code', { attempts_left: c.attempts_left })
      : refused(410, 'code_expired');

/** claim's check for provider email (contract v1.5: {email, code} in place of id_token / nonce): the address's link, the
 *  code used up, or the refusal. For 亚瑟's claim wiring (p0_server's `verify`). */
export function emailVerifier(deps: Pick<EmailRouteDeps, 'on' | 'accounts' | 'codes'>): (b: Record<string, unknown>) => Promise<EmailLink | Refused> {
  return async b => {
    if (!deps.on || !deps.accounts.codesOn()) return refused(503, 'provider_unavailable');
    const email = normalizeEmail(b.email);
    if (!email || !codeShapeOk(b.code)) return refused(400, 'schema');
    const c = deps.codes.check(email, b.code);
    if (!c.ok) return checkRefusal(c);
    deps.codes.take(email);
    return { sub: deps.accounts.emailId(email) };
  };
}

export function registerEmailRoutes(app: FastifyInstance, deps: EmailRouteDeps): void {
  const { store, accounts, codes } = deps;
  const warn = deps.warn ?? ((line: string) => console.warn(line));
  const on = () => deps.on && accounts.codesOn();
  const send = (reply: { code(n: number): { send(b: unknown): unknown } }, r: Refused) => reply.code(r.status).send(r.body);
  let alertedDay = '';

  /** POST /v1/p0/session/email/start {email, lang?}, no identity: a code mailed (in lang, "zh" or "en"), and
   *  {ok: true, resend_in: 60} for any well-formed address. */
  app.post('/v1/p0/session/email/start', async (req, reply) => {
    if (!on()) return send(reply, refused(503, 'provider_unavailable'));
    const b = bodyOf(req.body);
    const email = normalizeEmail(b.email);
    if (!email) return send(reply, refused(400, 'schema'));
    if (!deps.mailer) return send(reply, refused(503, 'email_unavailable'));
    const r = codes.reserve(email, req.ip);
    if (!r.ok && r.why === 'rate_limited') return send(reply, refused(429, 'rate_limited', { retry_in: r.retry_in }));
    if (!r.ok) {
      const day = new Date(deps.now()).toISOString().slice(0, 10);
      if (alertedDay !== day) {
        alertedDay = day;
        warn(JSON.stringify({ warn: 'email_signin_cap', day }));
        deps.alert?.('Gensen sign-in codes: the cap is reached',
          `The sign-in codes reached their cap (${codes.limits.allHour} an hour, ${codes.limits.allDay} a day) at `
          + `${new Date(deps.now()).toISOString()}. Players asking for a code are told to try later (email_unavailable) `
          + 'until it frees. This is the only such mail today; it holds no address.\n');
      }
      return send(reply, refused(503, 'email_unavailable'));
    }
    const code = newEmailCode();
    try {
      await deps.mailer.send(email, signInMail(code, mailLang(b.lang)));
    } catch (e) {
      codes.release(email, req.ip, r.at);
      // the error's code only: a mail error's message can carry the address
      const x = e as { code?: unknown; responseCode?: unknown };
      warn(JSON.stringify({ email_signin: 'send_failed', key: codes.key(email), error: typeof x?.code === 'string' ? x.code : 'unknown',
        smtp: typeof x?.responseCode === 'number' ? x.responseCode : null }));
      return send(reply, refused(503, 'email_unavailable'));
    }
    codes.put(email, code);
    return { ok: true, resend_in: RESEND_MS / 1000 };
  });

  /** POST /v1/p0/session/email {email, code, token}, no identity: the address's farm signed in on this phone (its other
   *  phones' tokens revoked), or no_farm {pending} for NAME, as session/apple|google. The code is used up by either. */
  app.post('/v1/p0/session/email', async (req, reply) => {
    if (!on()) return send(reply, refused(503, 'provider_unavailable'));
    const b = bodyOf(req.body);
    if (!tokenShapeOk(b.token)) return send(reply, refused(400, typeof b.token === 'string' ? 'token_too_short' : 'schema'));
    const token = String(b.token).toLowerCase();
    const email = normalizeEmail(b.email);
    if (!email || !codeShapeOk(b.code)) return send(reply, refused(400, 'schema'));
    const c = codes.check(email, b.code, req.ip);
    if (!c.ok) return send(reply, checkRefusal(c));
    const sub = accounts.emailId(email);
    const player = liveOwner(store, accounts, 'email', sub, deps.now());
    if (player) {
      const owner = accounts.tokenOwner(token);
      if (owner && owner !== player) return send(reply, refused(400, 'schema'));   // a token is one player's only; the code kept
      codes.take(email);
      return signIn({ accounts, kick: deps.kick, consent: deps.consent }, player, token);
    }
    codes.take(email);
    return reply.code(404).send({ ok: false, code: 'no_farm', pending: deps.pending.create('email', { sub }) });
  });
}
