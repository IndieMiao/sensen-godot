import { describe, expect, it } from 'vitest';
import { reportLineNotice } from '../../src/p0/report_notice.js';
import { reportMailText } from '../../src/p0/report_mail.js';

const line = { kind: 'voice_report', v: 2, id: 'R-20261113-0123ABCD', at: '2026-11-13T08:00:00.000Z',
  reporter_code: 'WKRW4-9CH60', reported_code: '55YF1-3C0J8', name: 'PRIVATE_SNAPSHOT',
  reason: 'offensive_name', place: 'sh_tea_1', room: 2, channel: 'appstore' };

describe('484 agreed ReportLine v2 mail projection (550d0c5d)', () => {
  it.each([
    ['offensive_name', 'Offensive name or bio'], ['harassment', 'Harassment'],
    ['offensive_voice', 'Offensive voice chat'], ['cheating', 'Cheating or bots'], ['other', 'Something else'],
    ['', 'Something else'], ['old free text PRIVATE_TEXT', 'Something else'], ['toString', 'Something else'],
  ])('maps reason %s without forwarding arbitrary input', (reason, label) => {
    const notice = reportLineNotice({ ...line, reason, reporter: 'PRIVATE_ID', token: 'PRIVATE_TOKEN' })!;
    expect(notice.reason).toBe(label);
    expect(notice.id).toBe(line.id);
    expect(Object.keys(notice).sort()).toEqual(['id', 'reporter_support', 'reported_support', 'reason', 'place', 'room', 'at', 'channel'].sort());
    expect(reportMailText(notice)).not.toMatch(/PRIVATE_/);
  });

  it('preserves an old package’s empty channel without inventing oss/play/appstore', () => {
    const notice = reportLineNotice({ ...line, name: null, channel: '' })!;
    expect(notice.channel).toBe('');
    expect(reportMailText(notice)).toContain('Channel: \n');
  });

  it('does not backfill or send legacy rows with raw player ids and no stable id', () => {
    expect(reportLineNotice({ kind: 'voice_report', reporter: 'PRIVATE_ID', reason: 'old text' })).toBeNull();
    expect(reportLineNotice({ ...line, v: 1 })).toBeNull();
  });

  it.each([{ id: undefined }, { id: '11111111-1111-4111-8111-111111111111' },
    { channel: 'unknown' }, { reporter_code: undefined }, { at: undefined }])('refuses malformed v2 fields: %j', patch => {
    expect(() => reportLineNotice({ ...line, ...patch })).toThrow('REPORT_MAIL_INVALID_NOTICE');
  });
});
