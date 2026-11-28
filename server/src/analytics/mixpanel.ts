/**
 * 产品分析上报（C-203）：玩家的关键行为进内存队列，攒够一批或到点后用 Mixpanel 的批量导入接口（/import）发出。
 * 只在服务端上报，用户标识只用自有的 users.id；不传邮箱、IP、经纬度（事件与属性见 events.ts 和 docs/plans/C-203.md）。
 * 每条事件带 ip=0：不带时 Mixpanel 会拿发送方（本服务器）的地址做地理定位，ip=0 让它跳过。
 *
 * 开关：MIXPANEL_PROJECT_TOKEN（项目令牌，Project Token）和 MIXPANEL_API_HOST（数据存放地区的接口地址）都设才启用；都不设整个模块不启用，
 * 不建队列、不起定时器、不发任何外部请求。只设一个、或地址不是 Mixpanel 的三个地区接口之一，进程拒绝启动。
 *
 * 上报永不影响游戏（参照 p0/telemetry.ts）：track 只往内存队列里放，不等网络、不抛错；发送失败（超时、网络错、429、5xx）
 * 最多重试一次，之后丢掉这批并记一行日志；其它 4xx 不重试。队列满了丢新事件并记一次日志。
 *
 * 删号（C-205）：deleteUser 丢掉队列里这个用户还没发出的事件，再用 Mixpanel 的 GDPR 删除接口提交删除任务（删该用户的全部事件和资料）。
 * 这个接口除项目令牌外还要 GDPR OAuth 令牌（MIXPANEL_GDPR_TOKEN，见 docs/plans/C-205.md）；没配就跳过并记日志，由人在 Mixpanel 后台补删。
 * 删除同样不等网络、不抛错，失败只记日志。
 *
 * 关停（C-205）：close 最多等 SHUTDOWN_MS（5 秒），超时就丢掉剩下的事件和删除请求、取消还在路上的请求，保证 docker stop 的 10 秒宽限期内退出。
 */
import { randomUUID } from 'node:crypto';

/** 上报接口。没配置时用 NO_ANALYTICS：什么都不做。 */
export interface Analytics {
  /** userId 为空（游客）时不上报。time 默认现在；insertId 用来去重（同一事件重复上报只算一次），默认随机。 */
  track(event: string, userId: string | null | undefined, props?: Record<string, unknown>, opts?: { time?: number; insertId?: string }): void;
  /** 账号已删除：丢掉这个用户还没发出的事件，并请 Mixpanel 删除按这个 users.id 上报过的数据。不等网络、不抛错。 */
  deleteUser(userId: string): void;
  /** 把队列里的事件发完（测试和关停用）；从不抛错。 */
  flush(): Promise<void>;
  /** 停定时器，在关停时限内发完剩下的事件和删除请求，超时丢弃。 */
  close(): Promise<void>;
}

export const NO_ANALYTICS: Analytics = { track() {}, deleteUser() {}, flush: async () => {}, close: async () => {} };

/** Mixpanel 的三个数据存放地区（美国、欧盟、印度）；项目建在哪个地区就只能用那个地址。 */
export const MIXPANEL_HOSTS = ['https://api.mixpanel.com', 'https://api-eu.mixpanel.com', 'https://api-in.mixpanel.com'] as const;
/** 一批最多几条、最长多久发一次、单次请求多久算超时、失败后隔多久重试、队列最多积压几条。 */
export const BATCH_SIZE = 50;
export const FLUSH_MS = 10_000;
export const TIMEOUT_MS = 10_000;
export const RETRY_DELAY_MS = 2_000;
export const MAX_QUEUE = 10_000;
/** 关停时最后一次发送（含删除请求）总共最多等多久，超时丢弃剩下的（C-205）。 */
export const SHUTDOWN_MS = 5_000;
/** GDPR 删除接口与上报接口同地区：上报地址 → 删除接口所在主机。 */
export const MIXPANEL_GDPR_HOSTS: Readonly<Record<(typeof MIXPANEL_HOSTS)[number], string>> = {
  'https://api.mixpanel.com': 'https://mixpanel.com',
  'https://api-eu.mixpanel.com': 'https://eu.mixpanel.com',
  'https://api-in.mixpanel.com': 'https://in.mixpanel.com',
};

export interface MixpanelConfig {
  token: string;
  host: string;
  /** GDPR 删除接口用的 OAuth 令牌；不设时删号不提交删除，只记日志。 */
  gdprToken?: string;
  shutdownMs?: number;
  batchSize?: number;
  flushMs?: number;
  timeoutMs?: number;
  retryDelayMs?: number;
  maxQueue?: number;
  fetch?: typeof fetch;
  log?: (line: string) => void;
  now?: () => number;
}

/**
 * 不设两项返回 null（不启用）；只设一项或地址不对返回 { invalid: 原因 }，进程入口拒绝启动。
 * MIXPANEL_GDPR_TOKEN 选填，只能在上报开启时设（单独设了也拒绝启动，免得以为删号会同步删除）。
 */
export function mixpanelConfigFromEnv(env: Record<string, string | undefined>): MixpanelConfig | { invalid: string } | null {
  const token = env.MIXPANEL_PROJECT_TOKEN?.trim() ?? '';
  const host = env.MIXPANEL_API_HOST?.trim().replace(/\/+$/, '') ?? '';
  const gdprToken = env.MIXPANEL_GDPR_TOKEN?.trim() ?? '';
  if (!token && !host) return gdprToken ? { invalid: 'MIXPANEL_GDPR_TOKEN 要和 MIXPANEL_PROJECT_TOKEN、MIXPANEL_API_HOST 一起设' } : null;
  if (!token || !host) return { invalid: 'MIXPANEL_PROJECT_TOKEN 和 MIXPANEL_API_HOST 要么都设，要么都不设' };
  if (!(MIXPANEL_HOSTS as readonly string[]).includes(host)) return { invalid: `MIXPANEL_API_HOST 只能是 ${MIXPANEL_HOSTS.join('、')} 之一` };
  return gdprToken ? { token, host, gdprToken } : { token, host };
}

interface MixpanelEvent { event: string; properties: Record<string, unknown> }

export class MixpanelAnalytics implements Analytics {
  private queue: MixpanelEvent[] = [];
  private sending: Promise<void> | null = null;
  /** 删除请求排队一个个发（GDPR 接口限每秒 1 次）。 */
  private deletions: Promise<void> = Promise.resolve();
  private pendingDeletions = 0;
  private closing: Promise<void> | null = null;
  /** 关停超时时取消还在路上的请求和重试等待。 */
  private readonly abort = new AbortController();
  private timer: ReturnType<typeof setInterval>;
  private queueFullLogged = false;
  private readonly url: string;
  private readonly auth: string;
  private readonly deletionUrl: string | null;
  private readonly deletionAuth: string | null;
  private readonly batchSize: number;
  private readonly timeoutMs: number;
  private readonly retryDelayMs: number;
  private readonly maxQueue: number;
  private readonly shutdownMs: number;
  private readonly fetch: typeof fetch;
  private readonly log: (line: string) => void;
  private readonly now: () => number;

  constructor(cfg: MixpanelConfig) {
    this.url = `${cfg.host}/import?strict=1`;
    // /import 接受项目令牌作 Basic 认证的用户名、密码留空（不带 project_id）。
    this.auth = 'Basic ' + Buffer.from(cfg.token + ':').toString('base64');
    // GDPR 删除接口：项目令牌放查询参数，OAuth 令牌放 Bearer 认证。
    const gdprHost = MIXPANEL_GDPR_HOSTS[cfg.host as (typeof MIXPANEL_HOSTS)[number]] ?? cfg.host;
    this.deletionUrl = cfg.gdprToken ? `${gdprHost}/api/app/data-deletions/v3.0/?token=${encodeURIComponent(cfg.token)}` : null;
    this.deletionAuth = cfg.gdprToken ? `Bearer ${cfg.gdprToken}` : null;
    this.batchSize = cfg.batchSize ?? BATCH_SIZE;
    this.timeoutMs = cfg.timeoutMs ?? TIMEOUT_MS;
    this.retryDelayMs = cfg.retryDelayMs ?? RETRY_DELAY_MS;
    this.maxQueue = cfg.maxQueue ?? MAX_QUEUE;
    this.shutdownMs = cfg.shutdownMs ?? SHUTDOWN_MS;
    this.fetch = cfg.fetch ?? globalThis.fetch;
    this.log = cfg.log ?? (line => console.warn(line));
    this.now = cfg.now ?? (() => Date.now());
    this.timer = setInterval(() => { void this.flush(); }, cfg.flushMs ?? FLUSH_MS);
    this.timer.unref();
  }

  track(event: string, userId: string | null | undefined, props: Record<string, unknown> = {}, opts: { time?: number; insertId?: string } = {}): void {
    if (!userId || this.abort.signal.aborted) return;
    try {
      if (this.queue.length >= this.maxQueue) {
        if (!this.queueFullLogged) { this.queueFullLogged = true; this.log(`[analytics] queue full (${this.maxQueue}), dropping new events`); }
        return;
      }
      this.queue.push({ event, properties: { ...props, time: opts.time ?? this.now(), distinct_id: userId, $insert_id: opts.insertId ?? randomUUID(), ip: 0 } });
      if (this.queue.length >= this.batchSize) void this.flush();
    } catch { /* 上报永不打断玩家请求 */ }
  }

  deleteUser(userId: string): void {
    if (!userId) return;
    try {
      // 还没发出的事件不再发，免得删除之后又把这个人的事件导进去。
      this.queue = this.queue.filter(e => e.properties.distinct_id !== userId);
      if (!this.deletionUrl) {
        this.log(`[analytics] MIXPANEL_GDPR_TOKEN not set, Mixpanel data of deleted user ${userId} was not deleted; delete it in Mixpanel by hand`);
        return;
      }
      if (this.abort.signal.aborted) { this.log(`[analytics] shutting down, Mixpanel deletion for user ${userId} not requested; delete it in Mixpanel by hand`); return; }
      this.pendingDeletions++;
      // 先等正在发的那批落地，删除任务才覆盖到它。
      this.deletions = this.deletions
        .then(() => this.sending)
        .then(() => this.requestDeletion(userId))
        .catch(() => {})
        .finally(() => { this.pendingDeletions--; });
    } catch { /* 删号照常完成 */ }
  }

  flush(): Promise<void> {
    this.sending ??= this.drain().finally(() => { this.sending = null; });
    return this.sending;
  }

  /** 最多等 shutdownMs：到点还没发完就丢掉剩下的事件和删除请求、取消还在路上的请求，只记一行日志。从不抛错。 */
  close(): Promise<void> {
    clearInterval(this.timer);
    this.closing ??= this.shutDown();
    return this.closing;
  }

  private async shutDown(): Promise<void> {
    let deadline: ReturnType<typeof setTimeout> | undefined;
    const timedOut = await Promise.race([
      Promise.all([this.flush(), this.deletions]).then(() => false),
      new Promise<boolean>(resolve => { deadline = setTimeout(() => resolve(true), this.shutdownMs); }),
    ]);
    clearTimeout(deadline);
    if (!timedOut) return;
    const events = this.queue.length;
    this.queue = [];
    this.log(`[analytics] shutdown limit ${this.shutdownMs}ms reached, dropped ${events} queued events and ${this.pendingDeletions} pending deletions`);
    this.abort.abort(new Error('analytics shutdown limit reached'));
  }

  private async drain(): Promise<void> {
    while (this.queue.length) {
      await this.send(this.queue.splice(0, this.batchSize));
      this.queueFullLogged = false;
    }
  }

  /** 发一批：失败（超时、网络错、429、5xx）最多重试一次；还不行或其它 4xx 就丢掉这批，只记日志。从不抛错。 */
  private async send(batch: MixpanelEvent[]): Promise<void> {
    if (!await this.post(this.url, JSON.stringify(batch), this.auth, 'import')) this.log(`[analytics] dropped ${batch.length} events`);
  }

  /** 提交一个 GDPR 删除任务；成功记下任务编号，失败记日志请人补删。从不抛错。 */
  private async requestDeletion(userId: string): Promise<void> {
    const res = await this.post(this.deletionUrl!, JSON.stringify({ distinct_ids: [userId], compliance_type: 'GDPR' }), this.deletionAuth!, 'deletion');
    if (!res) { this.log(`[analytics] Mixpanel deletion for user ${userId} not requested; delete it in Mixpanel by hand`); return; }
    const body = await res.json().catch(() => null) as { results?: { tracking_id?: unknown }[] } | null;
    this.log(`[analytics] Mixpanel deletion requested for user ${userId}, task ${String(body?.results?.[0]?.tracking_id ?? 'unknown')}`);
  }

  /** POST 一次，失败（超时、网络错、429、5xx）最多重试一次；成功回应答，否则回 null 并记日志。关停超时后立即放弃。 */
  private async post(url: string, body: string, authorization: string, what: string): Promise<Response | null> {
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt && !await this.sleep(this.retryDelayMs)) break;
      if (this.abort.signal.aborted) break;
      let retry = true;
      try {
        const res = await this.fetch(url, { method: 'POST', body, signal: AbortSignal.any([AbortSignal.timeout(this.timeoutMs), this.abort.signal]),
          headers: { 'content-type': 'application/json', accept: 'application/json', authorization } });
        if (res.ok) return res;
        retry = res.status === 429 || res.status >= 500;
        this.log(`[analytics] mixpanel ${what} answered ${res.status}: ${(await res.text().catch(() => '')).slice(0, 300)}`);
      } catch (error) {
        this.log(`[analytics] mixpanel ${what} failed: ${(error as Error).message}`);
      }
      if (!retry) break;
    }
    return null;
  }

  /** 等 ms；关停超时就提前结束并回 false。 */
  private sleep(ms: number): Promise<boolean> {
    const signal = this.abort.signal;
    if (signal.aborted) return Promise.resolve(false);
    return new Promise(resolve => {
      const done = () => { clearTimeout(t); resolve(false); };
      const t = setTimeout(() => { signal.removeEventListener('abort', done); resolve(true); }, ms);
      signal.addEventListener('abort', done, { once: true });
    });
  }
}

/** 进程入口用：配置了就建 Mixpanel 上报，否则 NO_ANALYTICS。 */
export const createAnalytics = (cfg: MixpanelConfig | null): Analytics => cfg ? new MixpanelAnalytics(cfg) : NO_ANALYTICS;
