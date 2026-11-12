/** SGODOT-484: SMTP adapter only. The report writer/outbox is wired separately.
 * Internal report records (including names/player IDs) must never be sent whole. */
import nodemailer from 'nodemailer';

export const REPORT_SMTP_HOST = 'smtpdm-us-east-1.aliyuncs.com';
export const REPORT_MAIL_TO = 'support@gensen.app';
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
export interface ReportSmtpConfig { from: string; user: string; password: string }
export interface ReportSmtpMessage { from: string; to: string; subject: string; text: string }
export interface ReportSmtpTransport {
  sendMail(message: ReportSmtpMessage): Promise<unknown>;
  close(): void;
}
export interface ReportSmtpOptions {
  host: string; port: number; secure: boolean;
  auth: { user: string; pass: string };
  tls: { rejectUnauthorized: boolean; minVersion: 'TLSv1.2' };
  connectionTimeout: number; greetingTimeout: number; socketTimeout: number;
  logger: false; debug: false; disableFileAccess: true; disableUrlAccess: true;
}

const mailbox = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@notify\.gensen\.app$/;
const supportCode = /^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$/;
function checkConfig(c: ReportSmtpConfig): void {
  if (!mailbox.test(c.from) || !mailbox.test(c.user) || c.from !== c.user || !c.password)
    throw new Error('REPORT_MAIL_INVALID_CONFIG'); // Never echo a credential or configuration value.
}

/** Deliberately off until the verified sending address and credentials are installed. */
export function reportSmtpFromEnv(env: Record<string, string | undefined>): ReportSmtpConfig | null {
  const enabled = env.P0_REPORT_MAIL ?? 'off';
  if (enabled === 'off') return null;
  if (enabled !== 'on') throw new Error('P0_REPORT_MAIL must be on or off');
  const config = { from: env.P0_REPORT_MAIL_FROM ?? '', user: env.P0_REPORT_SMTP_USER ?? '',
    password: env.P0_REPORT_SMTP_PASSWORD ?? '' };
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
  const transport = makeTransport({ host: REPORT_SMTP_HOST, port: 465, secure: true,
    auth: { user: config.user, pass: config.password }, tls: { rejectUnauthorized: true, minVersion: 'TLSv1.2' },
    connectionTimeout: 10_000, greetingTimeout: 10_000, socketTimeout: 20_000,
    logger: false, debug: false, disableFileAccess: true, disableUrlAccess: true });
  return {
    async send(notice: ReportMailNotice): Promise<void> {
      const message = { from: config.from, to: REPORT_MAIL_TO, subject: 'Gensen player report', text: reportMailText(notice) };
      try { await transport.sendMail(message); }
      catch { throw new Error('REPORT_MAIL_DELIVERY_FAILED'); } // SMTP errors can contain addresses, auth data or body fragments.
    },
    close(): void { transport.close(); },
  };
}
