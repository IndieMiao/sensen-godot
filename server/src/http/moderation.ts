/**
 * 审核管线（D6）+ UGC 四件套的服务端（E1）：前置自动过滤、举报、拉黑、封禁、人工复审队列。
 *
 * 08-30 调研 §5.5「可辩护最小配置」：发布前自动过滤（文本 + 图片）→ 人工复审队列 → 举报 24h SLA。
 * 文本走 OpenAI omni-moderation（免费端点无 SLA）；图片二道 Rekognition 等 SSLAUNCH D5 AWS 开户，
 * 在那之前带图的帖子一律进人工队列（visible 但 pending）。审核服务挂了不阻塞发布，但进队列——
 * 全站不能因为第三方抖动发不出东西，也不能因此漏审。
 */
import type { AccountModule } from './accounts.js';

export type ModerationStatus = 'approved' | 'pending' | 'rejected' | 'hidden';

export interface ModerationVerdict {
  flagged: boolean;
  categories: string[];
  /** 审核服务本身出错（网络 / 限流 / 5xx）；此时 flagged 无意义。 */
  error?: string;
}

export interface TextModerator {
  check(text: string): Promise<ModerationVerdict>;
}

/** 前置过滤的裁决：命中 → 拒发；服务出错 → 放行但进人工队列。 */
export function decide(v: ModerationVerdict): { status: ModerationStatus; categories: string[] } {
  if (v.error) return { status: 'pending', categories: [] };
  return v.flagged ? { status: 'rejected', categories: v.categories } : { status: 'approved', categories: [] };
}

export const OPENAI_MODERATION_URL = 'https://api.openai.com/v1/moderations';

/** omni-moderation：文本 + 图片同一端点；这里先接文本。 */
export class OpenAiModerator implements TextModerator {
  constructor(private readonly apiKey: string, private readonly fetchImpl: typeof fetch = fetch, private readonly url = OPENAI_MODERATION_URL) {}
  async check(text: string): Promise<ModerationVerdict> {
    try {
      const res = await this.fetchImpl(this.url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${this.apiKey}` },
        body: JSON.stringify({ model: 'omni-moderation-latest', input: text }),
      });
      if (!res.ok) return { flagged: false, categories: [], error: `HTTP_${res.status}` };
      const body = await res.json() as { results?: { flagged?: boolean; categories?: Record<string, boolean> }[] };
      const r = body.results?.[0];
      if (!r) return { flagged: false, categories: [], error: 'EMPTY' };
      const categories = Object.entries(r.categories ?? {}).filter(([, v]) => v === true).map(([k]) => k).sort();
      return { flagged: r.flagged === true, categories };
    } catch (e) {
      return { flagged: false, categories: [], error: e instanceof Error ? e.message : String(e) };
    }
  }
}

/** 没配 key 时的占位：什么都不拦，但每条都进人工队列——比「假装审过了」诚实。 */
export class NullModerator implements TextModerator {
  async check(): Promise<ModerationVerdict> { return { flagged: false, categories: [], error: 'NOT_CONFIGURED' }; }
}

// —— 举报 / 拉黑 / 封禁 ——

export const REPORT_REASONS = new Set(['spam', 'harassment', 'sexual', 'violence', 'hate', 'self_harm', 'minor_safety', 'other']);
export const REPORT_TARGETS = new Set(['post', 'comment', 'user', 'message']);
export const REPORT_DETAIL_MAX = 500;
/** 同一目标来自不同人的举报达到这个数就先自动隐藏，等人工——24h SLA 不能全靠人盯。 */
export const REPORT_AUTO_HIDE = 3;

export interface ReportRow {
  id: string;
  reporter_id: string;
  target_type: 'post' | 'comment' | 'user' | 'message';
  target_id: string;
  reason: string;
  detail: string;
  created_at: number;
  status: 'open' | 'resolved';
  resolved_at: number | null;
  resolved_by: string | null;
  action: string | null;
}

export interface BlockRow { blocker_id: string; blocked_id: string; created_at: number }
export interface BanRow { user_id: string; reason: string; created_at: number; by: string }

export interface ModerationStore {
  /** 同一举报人对同一目标只记一条；返回 created 与该目标当前的**不同举报人**数。 */
  addReport(r: Omit<ReportRow, 'status' | 'resolved_at' | 'resolved_by' | 'action'>): Promise<{ report: ReportRow; created: boolean; distinctReporters: number }>;
  report(id: string): Promise<ReportRow | null>;
  openReports(limit: number): Promise<ReportRow[]>;
  resolveReport(id: string, by: string, action: string, now: number): Promise<ReportRow | null>;
  /** 同一目标的全部 open 举报一起结（一次处置）。 */
  resolveTarget(targetType: string, targetId: string, by: string, action: string, now: number): Promise<number>;

  block(blockerId: string, blockedId: string, now: number): Promise<{ created: boolean }>;
  unblock(blockerId: string, blockedId: string): Promise<{ removed: boolean }>;
  /** 任一方向有拉黑。 */
  blockedEither(a: string, b: string): Promise<boolean>;
  /** 我拉黑的 + 拉黑我的（都要从我的时间线里剔掉）。 */
  blockedIdsAround(userId: string): Promise<string[]>;
  blocks(blockerId: string): Promise<BlockRow[]>;

  ban(userId: string, reason: string, by: string, now: number): Promise<void>;
  unban(userId: string): Promise<void>;
  isBanned(userId: string): Promise<boolean>;

  deleteUser(userId: string): Promise<void>;
  exportUser(userId: string): Promise<{ reports_filed: ReportRow[]; blocks: BlockRow[] }>;
}

export type ReportInput = { ok: true; targetType: 'post' | 'comment' | 'user' | 'message'; targetId: string; reason: string; detail: string } | { ok: false; field: string; reason: string };

export function validateReport(body: unknown): ReportInput {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body', reason: 'OBJECT' };
  const b = body as Record<string, unknown>;
  if (typeof b.target_type !== 'string' || !REPORT_TARGETS.has(b.target_type)) return { ok: false, field: 'target_type', reason: 'UNKNOWN' };
  if (typeof b.target_id !== 'string' || !/^[0-9a-f-]{36}$/i.test(b.target_id)) return { ok: false, field: 'target_id', reason: 'FORMAT' };
  if (typeof b.reason !== 'string' || !REPORT_REASONS.has(b.reason)) return { ok: false, field: 'reason', reason: 'UNKNOWN' };
  const detail = typeof b.detail === 'string' ? b.detail.trim() : '';
  if (b.detail !== undefined && typeof b.detail !== 'string') return { ok: false, field: 'detail', reason: 'STRING' };
  if ([...detail].length > REPORT_DETAIL_MAX) return { ok: false, field: 'detail', reason: 'LENGTH' };
  return { ok: true, targetType: b.target_type as 'post' | 'comment' | 'user' | 'message', targetId: b.target_id, reason: b.reason, detail };
}

export const ADMIN_ACTIONS = new Set(['dismiss', 'remove_content', 'ban_user']);

export function reportView(r: ReportRow) {
  return { id: r.id, target_type: r.target_type, target_id: r.target_id, reason: r.reason, detail: r.detail,
    created_at: r.created_at, status: r.status, resolved_at: r.resolved_at, action: r.action };
}

export function moderationAccountModule(store: ModerationStore): AccountModule {
  return {
    name: 'moderation',
    export: (userId) => store.exportUser(userId),
    del: (userId) => store.deleteUser(userId),
  };
}
