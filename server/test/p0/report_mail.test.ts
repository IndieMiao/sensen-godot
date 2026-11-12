import { describe, expect, it, vi } from 'vitest';
import { createReportMailer, reportSmtpFromEnv, type ReportMailNotice, type ReportSmtpOptions } from '../../src/p0/report_mail.js';

const config = { from: 'reports@notify.gensen.app', user: 'reports@notify.gensen.app', password: 'test-only-password' };
const notice: ReportMailNotice = { reporter_support: 'WKRW4-9CH60', reported_support: '55YF1-3C0J8',
  reason: 'Offensive name or bio', place: 'sh_tea_1', room: 2, at: '2026-11-12T11:00:00.000Z', channel: 'appstore' };

describe('484 Direct Mail configuration and isolated fake delivery', () => {
  it('stays disabled by default and requires a verified-domain sender and credentials to enable', () => {
    expect(reportSmtpFromEnv({})).toBeNull();
    expect(reportSmtpFromEnv({ P0_REPORT_MAIL: 'off' })).toBeNull();
    expect(() => reportSmtpFromEnv({ P0_REPORT_MAIL: 'true' })).toThrow('P0_REPORT_MAIL must be on or off');
    expect(() => reportSmtpFromEnv({ P0_REPORT_MAIL: 'on' })).toThrow('REPORT_MAIL_INVALID_CONFIG');
    const env = { P0_REPORT_MAIL: 'on', P0_REPORT_MAIL_FROM: config.from,
      P0_REPORT_SMTP_USER: config.user, P0_REPORT_SMTP_PASSWORD: config.password };
    expect(reportSmtpFromEnv(env)).toEqual(config);
    expect(() => reportSmtpFromEnv({ ...env, P0_REPORT_MAIL_FROM: 'reports@gensen.app' })).toThrow('REPORT_MAIL_INVALID_CONFIG');
    expect(() => reportSmtpFromEnv({ ...env, P0_REPORT_SMTP_USER: 'other@notify.gensen.app' })).toThrow('REPORT_MAIL_INVALID_CONFIG');
  });

  it('uses the approved regional TLS endpoint and never sends private record fields or alternate recipients', async () => {
    const sendMail = vi.fn(async () => ({})), close = vi.fn();
    let options: ReportSmtpOptions | undefined;
    const mailer = createReportMailer(config, opts => { options = opts; return { sendMail, close }; });
    expect(options).toMatchObject({ host: 'smtpdm-us-east-1.aliyuncs.com', port: 465, secure: true,
      tls: { rejectUnauthorized: true, minVersion: 'TLSv1.2' }, logger: false, debug: false,
      disableFileAccess: true, disableUrlAccess: true });
    await mailer.send({ ...notice, reported_name: 'PRIVATE_NAME', reporter: 'private-player-a', reported: 'private-player-b',
      ip: '192.0.2.123', token: 'private-session', to: 'other@example.test', html: 'PRIVATE_HTML' } as ReportMailNotice);
    expect(sendMail).toHaveBeenCalledWith({ from: config.from, to: 'support@gensen.app', subject: 'Gensen player report',
      text: 'Reporter support code: WKRW4-9CH60\nReported support code: 55YF1-3C0J8\nReason: Offensive name or bio\n'
        + 'Place: sh_tea_1\nLayer: 2\nTime: 2026-11-12T11:00:00.000Z\nChannel: appstore\n' });
    mailer.close(); expect(close).toHaveBeenCalledOnce();
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
