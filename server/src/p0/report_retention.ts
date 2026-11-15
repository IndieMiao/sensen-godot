/** One-year physical retention for the active report JSONL, not backups. One synchronous writer per P0 volume. */
import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { REPORT_KEEP_MS } from './report_outbox.js';

export interface ReportRetentionResult { scanned: number; expired: number; retained: number; invalid: number; changed: boolean }

export function pruneReportFile(file: string, now: number, apply = false): ReportRetentionResult {
  if (!Number.isSafeInteger(now) || now < 0) throw new Error('REPORT_RETENTION_INVALID_TIME');
  const result: ReportRetentionResult = { scanned: 0, expired: 0, retained: 0, invalid: 0, changed: false };
  let input: string;
  try { input = readFileSync(file, 'utf8'); }
  catch (e) { if ((e as NodeJS.ErrnoException)?.code === 'ENOENT') return result; throw new Error('REPORT_RETENTION_READ_FAILED'); }
  const kept: string[] = [];
  // Keep the original bytes of retained/unknown lines, including a last line without a newline.
  for (const line of input.match(/[^\n]*\n|[^\n]+$/g) ?? []) {
    if (!line.trim()) { kept.push(line); continue; }
    result.scanned++;
    let data: Record<string, unknown> | undefined;
    try { data = JSON.parse(line); } catch { /* Keep unverifiable records for admin inspection, never print them. */ }
    const at = data?.at;
    const timestamp = typeof at === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(at) ? Date.parse(at) : NaN;
    const recognized = data?.kind === 'voice_report' && (data.v === undefined || data.v === 1 || data.v === 2);
    if (!recognized || !Number.isFinite(timestamp)) { result.invalid++; result.retained++; kept.push(line); continue; }
    if (timestamp <= now && now - timestamp >= REPORT_KEEP_MS) result.expired++;
    else { result.retained++; kept.push(line); }
  }
  if (apply && result.expired) {
    try { writeFileSync(file + '.retention.tmp', kept.join(''), { mode: 0o600 }); renameSync(file + '.retention.tmp', file); }
    catch { throw new Error('REPORT_RETENTION_WRITE_FAILED'); }
    result.changed = true;
  }
  return result;
}
