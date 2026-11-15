/** Report v2 → mail projection, per 后裔's SGODOT-484 comment 550d0c5d (2026-11-13).
 * The callback and replay scanner share this projection. Do not infer names, ids or channels missing from old rows. */
import { reportMailText, type ReportMailNotice } from './report_mail.js';

const REASONS = {
  offensive_name: 'Offensive name or bio', harassment: 'Harassment', offensive_voice: 'Offensive voice chat',
  cheating: 'Cheating or bots', other: 'Something else',
} as const;

/** Structural subset of the forthcoming ReportLine; the writer may carry name, but it never leaves this boundary.
 * v1 rows have no stable id: leave them for the existing retention workflow, never invent a backfill id or email. */
export function reportLineNotice(line: Record<string, unknown>): ReportMailNotice | null {
  if (line.kind !== 'voice_report' || line.v !== 2) return null;
  const reason = typeof line.reason === 'string' && Object.hasOwn(REASONS, line.reason)
    ? REASONS[line.reason as keyof typeof REASONS] : REASONS.other;
  const notice = { id: line.id, reporter_support: line.reporter_code, reported_support: line.reported_code,
    reason, place: line.place, room: line.room, at: line.at, channel: line.channel } as ReportMailNotice;
  reportMailText(notice); // Reject malformed v2 records before persistence or SMTP; never log the row itself.
  return notice;
}
