/** SGODOT-484: SMTP adapter only. The report writer/outbox is wired separately.
 * Internal report records (including names/player IDs) must never be sent whole. */
import nodemailer from 'nodemailer';

export const REPORT_SMTP_HOST = 'smtpdm-us-east-1.aliyuncs.com';
export const REPORT_MAIL_REASONS = [
  'Offensive name or bio', 'Harassment', 'Offensive voice chat', 'Cheating or bots', 'Something else',
] as const; // Public labels from the account UI specification §7; not HTTP reason IDs.

export interface ReportMailNotice {
  reporter_support: string;
  reported_support: string;
  reason: typeof REPORT_MAIL_REASONS[number];
  place: string;
  room: number;
  at: string;
  channel: 'oss' | 'play' | 'appstore';
}
export interface ReportSmtpConfig {
  host: string; port: number; security: 'ssl' | 'starttls';
  from: string; to: string; user: string; password: string;
}
export interface ReportSmtpMessage { from: string; to: string; subject: string; text: string }
export interface ReportSmtpTransport {
  sendMail(message: ReportSmtpMessage): Promise<unknown>;
  close(): void;
}
export interface ReportSmtpOptions {
  host: string; port: number; secure: boolean; requireTLS: boolean;
  auth: { user: string; pass: string };
  tls: { rejectUnauthorized: boolean; minVersion: 'TLSv1.2' };
  connectionTimeout: number; greetingTimeout: number; socketTimeout: number;
  logger: false; debug: false; disableFileAccess: true; disableUrlAccess: true;
}

const mailbox = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@notify\.gensen\.app$/;
const recipient = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;
const supportCode = /^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$/;
function checkConfig(c: ReportSmtpConfig): void {
  if (c.host !== REPORT_SMTP_HOST
    || !((c.port === 465 && c.security === 'ssl') || (c.port === 80 && c.security === 'starttls'))
    || !mailbox.test(c.from) || !mailbox.test(c.user) || c.from !== c.user || !c.password
    || typeof c.to !== 'string' || !recipient.test(c.to))
    throw new Error('REPORT_MAIL_INVALID_CONFIG'); // Never echo a credential or configuration value.
}

/** Root injects 83's seven-variable env file at deployment; this module never reads that secret file itself.
 * P0_REPORT_MAIL is a separate, default-off delivery switch, even when the SMTP variables are present. */
export function reportSmtpFromEnv(env: Record<string, string | undefined>): ReportSmtpConfig | null {
  const enabled = env.P0_REPORT_MAIL ?? 'off';
  if (enabled === 'off') return null;
  if (enabled !== 'on') throw new Error('P0_REPORT_MAIL must be on or off');
  if (!['465', '80'].includes(env.SMTP_PORT ?? '') || !['ssl', 'starttls'].includes(env.SMTP_SECURITY ?? ''))
    throw new Error('REPORT_MAIL_INVALID_CONFIG');
  const config: ReportSmtpConfig = { host: env.SMTP_HOST ?? '', port: Number(env.SMTP_PORT),
    security: env.SMTP_SECURITY as ReportSmtpConfig['security'],
    from: env.MAIL_FROM ?? '', to: env.MAIL_TO ?? '', user: env.SMTP_USER ?? '', password: env.SMTP_PASS ?? '' };
  checkConfig(config);
  return config;
}

/** Only approved public fields enter the message, even if the caller passes an internal record with extra keys. */
export function reportMailText(notice: ReportMailNotice): string {
  if (!supportCode.test(notice.reporter_support) || !supportCode.test(notice.reported_support)
    || !REPORT_MAIL_REASONS.includes(notice.reason)
    || typeof notice.place !== 'string' || !notice.place.trim() || notice.place.length > 160 || /[\r\n\x00]/.test(notice.place)
    || !Number.isSafeInteger(notice.room) || notice.room < 1
    || typeof notice.at !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(notice.at)
    || !Number.isFinite(Date.parse(notice.at)) || !['oss', 'play', 'appstore'].includes(notice.channel))
    throw new Error('REPORT_MAIL_INVALID_NOTICE');
  return `Reporter support code: ${notice.reporter_support}\nReported support code: ${notice.reported_support}\n`
    + `Reason: ${notice.reason}\nPlace: ${notice.place}\nLayer: ${notice.room}\n`
    + `Time: ${new Date(notice.at).toISOString()}\nChannel: ${notice.channel}\n`;
}

export function createReportMailer(config: ReportSmtpConfig,
  makeTransport: (options: ReportSmtpOptions) => ReportSmtpTransport = options => nodemailer.createTransport(options)) {
  checkConfig(config);
  const { host, port, security, user, password, from, to } = config;
  const transport = makeTransport({ host, port, secure: security === 'ssl', requireTLS: security === 'starttls',
    auth: { user, pass: password }, tls: { rejectUnauthorized: true, minVersion: 'TLSv1.2' },
    connectionTimeout: 10_000, greetingTimeout: 10_000, socketTimeout: 20_000,
    logger: false, debug: false, disableFileAccess: true, disableUrlAccess: true });
  return {
    async send(notice: ReportMailNotice): Promise<void> {
      const message = { from, to, subject: 'Gensen player report', text: reportMailText(notice) };
      try { await transport.sendMail(message); }
      catch { throw new Error('REPORT_MAIL_DELIVERY_FAILED'); } // SMTP errors can contain addresses, auth data or body fragments.
    },
    close(): void { transport.close(); },
  };
}
