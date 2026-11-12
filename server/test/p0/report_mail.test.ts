import { describe, expect, it, vi } from 'vitest';
import { createReportMailer, reportSmtpFromEnv, type ReportMailNotice, type ReportSmtpConfig, type ReportSmtpOptions } from '../../src/p0/report_mail.js';

const config: ReportSmtpConfig = { host: 'smtpdm-us-east-1.aliyuncs.com', port: 465, security: 'ssl',
  from: 'reports@notify.gensen.app', to: 'moderator@example.test', user: 'reports@notify.gensen.app', password: 'test-only-password' };
const env = { P0_REPORT_MAIL: 'on', SMTP_HOST: config.host, SMTP_PORT: '465', SMTP_SECURITY: 'ssl',
  SMTP_USER: config.user, SMTP_PASS: config.password, MAIL_FROM: config.from, MAIL_TO: config.to };
const notice: ReportMailNotice = { reporter_support: 'WKRW4-9CH60', reported_support: '55YF1-3C0J8',
  reason: 'Offensive name or bio', place: 'sh_tea_1', room: 2, at: '2026-11-12T11:00:00.000Z', channel: 'appstore' };

describe('484 Direct Mail configuration and isolated fake delivery', () => {
  it('stays disabled by default and requires a verified-domain sender and credentials to enable', () => {
    expect(reportSmtpFromEnv({})).toBeNull();
    expect(reportSmtpFromEnv({ P0_REPORT_MAIL: 'off' })).toBeNull();
    expect(() => reportSmtpFromEnv({ P0_REPORT_MAIL: 'true' })).toThrow('P0_REPORT_MAIL must be on or off');
    expect(() => reportSmtpFromEnv({ P0_REPORT_MAIL: 'on' })).toThrow('REPORT_MAIL_INVALID_CONFIG');
    expect(reportSmtpFromEnv(env)).toEqual(config);
    expect(reportSmtpFromEnv({ ...env, P0_REPORT_MAIL: undefined })).toBeNull();
    expect(() => reportSmtpFromEnv({ ...env, MAIL_FROM: 'reports@gensen.app' })).toThrow('REPORT_MAIL_INVALID_CONFIG');
    expect(() => reportSmtpFromEnv({ ...env, SMTP_USER: 'other@notify.gensen.app' })).toThrow('REPORT_MAIL_INVALID_CONFIG');
    for (const key of ['SMTP_HOST', 'SMTP_PORT', 'SMTP_SECURITY', 'SMTP_USER', 'SMTP_PASS', 'MAIL_FROM', 'MAIL_TO']) {
      expect(() => reportSmtpFromEnv({ ...env, [key]: undefined })).toThrow('REPORT_MAIL_INVALID_CONFIG');
    }
  });

  it.each([
    { SMTP_HOST: 'dm.us-east-1.aliyuncs.com' }, { SMTP_HOST: 'smtpdm.aliyun.com' },
    { SMTP_PORT: '25', SMTP_SECURITY: 'starttls' }, { SMTP_PORT: '465', SMTP_SECURITY: 'starttls' },
    { SMTP_PORT: '80', SMTP_SECURITY: 'ssl' }, { SMTP_PORT: '80', SMTP_SECURITY: 'none' },
    { MAIL_TO: 'one@example.test,two@example.test' }, { MAIL_TO: 'one@example.test\r\nBcc: two@example.test' },
    { MAIL_TO: 'Name <one@example.test>' },
  ])('rejects an unsupported SMTP endpoint, TLS pair or recipient list: %j', patch => {
    expect(() => reportSmtpFromEnv({ ...env, ...patch })).toThrow('REPORT_MAIL_INVALID_CONFIG');
  });

  it.each([
    { port: '465', security: 'ssl', secure: true, requireTLS: false },
    { port: '80', security: 'starttls', secure: false, requireTLS: true },
  ])('uses mandatory regional TLS and configured recipient without private fields: $port/$security', async mode => {
    const sendMail = vi.fn(async () => ({})), close = vi.fn();
    let options: ReportSmtpOptions | undefined;
    const selected = reportSmtpFromEnv({ ...env, SMTP_PORT: mode.port, SMTP_SECURITY: mode.security })!;
    const mailer = createReportMailer(selected, opts => { options = opts; return { sendMail, close }; });
    selected.to = 'changed-after-creation@example.test'; // Recipient is captured from the validated configuration.
    expect(options).toMatchObject({ host: 'smtpdm-us-east-1.aliyuncs.com', port: Number(mode.port),
      secure: mode.secure, requireTLS: mode.requireTLS,
      tls: { rejectUnauthorized: true, minVersion: 'TLSv1.2' }, logger: false, debug: false,
      disableFileAccess: true, disableUrlAccess: true });
    await mailer.send({ ...notice, reported_name: 'PRIVATE_NAME', reporter: 'private-player-a', reported: 'private-player-b',
      ip: '192.0.2.123', token: 'private-session', to: 'other@example.test', html: 'PRIVATE_HTML' } as ReportMailNotice);
    expect(sendMail).toHaveBeenCalledWith({ from: config.from, to: 'moderator@example.test', subject: 'Gensen player report',
      text: 'Reporter support code: WKRW4-9CH60\nReported support code: 55YF1-3C0J8\nReason: Offensive name or bio\n'
        + 'Place: sh_tea_1\nLayer: 2\nTime: 2026-11-12T11:00:00.000Z\nChannel: appstore\n' });
    mailer.close(); expect(close).toHaveBeenCalledOnce();
  });

  it('takes the recipient from MAIL_TO, without choosing either pending production address as a default', async () => {
    for (const to of ['support@gensen.app', 'shaojie@gensen.app']) {
      const sendMail = vi.fn(async () => ({}));
      const mailer = createReportMailer(reportSmtpFromEnv({ ...env, MAIL_TO: to })!, () => ({ sendMail, close() {} }));
      await mailer.send(notice);
      expect(sendMail.mock.calls[0]).toEqual([expect.objectContaining({ to })]);
      mailer.close();
    }
  });

  it.each([
    { reason: 'free text PRIVATE_NAME' }, { reporter_support: 'private-player-a' },
    { room: 0 }, { place: 'sh_tea_1\nBcc: other@example.test' }, { at: 'not a date' }, { channel: 'unrecognized' },
  ])('rejects invalid public notice before invoking the SMTP transport: %j', async patch => {
    const sendMail = vi.fn(async () => ({}));
    const mailer = createReportMailer(config, () => ({ sendMail, close() {} }));
    await expect(mailer.send({ ...notice, ...patch } as ReportMailNotice)).rejects.toThrow('REPORT_MAIL_INVALID_NOTICE');
    expect(sendMail).not.toHaveBeenCalled(); mailer.close();
  });

  it('does not expose SMTP credentials or payload fragments through a delivery failure', async () => {
    const mailer = createReportMailer(config, () => ({
      async sendMail() { throw new Error('remote error contains test-only-password PRIVATE_NAME'); }, close() {},
    }));
    await expect(mailer.send(notice)).rejects.toEqual(new Error('REPORT_MAIL_DELIVERY_FAILED'));
    mailer.close();
  });
});
