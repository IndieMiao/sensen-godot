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
 */
import { randomUUID } from 'node:crypto';

/** 上报接口。没配置时用 NO_ANALYTICS：什么都不做。 */
export interface Analytics {
  /** userId 为空（游客）时不上报。time 默认现在；insertId 用来去重（同一事件重复上报只算一次），默认随机。 */
  track(event: string, userId: string | null | undefined, props?: Record<string, unknown>, opts?: { time?: number; insertId?: string }): void;
  /** 把队列里的事件发完（测试和关停用）；从不抛错。 */
  flush(): Promise<void>;
  /** 停定时器并发完剩下的事件。 */
  close(): Promise<void>;
}

export const NO_ANALYTICS: Analytics = { track() {}, flush: async () => {}, close: async () => {} };

/** Mixpanel 的三个数据存放地区（美国、欧盟、印度）；项目建在哪个地区就只能用那个地址。 */
export const MIXPANEL_HOSTS = ['https://api.mixpanel.com', 'https://api-eu.mixpanel.com', 'https://api-in.mixpanel.com'] as const;
/** 一批最多几条、最长多久发一次、单次请求多久算超时、失败后隔多久重试、队列最多积压几条。 */
export const BATCH_SIZE = 50;
export const FLUSH_MS = 10_000;
export const TIMEOUT_MS = 10_000;
export const RETRY_DELAY_MS = 2_000;
export const MAX_QUEUE = 10_000;

export interface MixpanelConfig {
  token: string;
  host: string;
  batchSize?: number;
  flushMs?: number;
  timeoutMs?: number;
  retryDelayMs?: number;
  maxQueue?: number;
  fetch?: typeof fetch;
  log?: (line: string) => void;
  now?: () => number;
}

/** 不设两项返回 null（不启用）；只设一项或地址不对返回 { invalid: 原因 }，进程入口拒绝启动。 */
export function mixpanelConfigFromEnv(env: Record<string, string | undefined>): MixpanelConfig | { invalid: string } | null {
  const token = env.MIXPANEL_PROJECT_TOKEN?.trim() ?? '';
  const host = env.MIXPANEL_API_HOST?.trim().replace(/\/+$/, '') ?? '';
  if (!token && !host) return null;
  if (!token || !host) return { invalid: 'MIXPANEL_PROJECT_TOKEN 和 MIXPANEL_API_HOST 要么都设，要么都不设' };
  if (!(MIXPANEL_HOSTS as readonly string[]).includes(host)) return { invalid: `MIXPANEL_API_HOST 只能是 ${MIXPANEL_HOSTS.join('、')} 之一` };
  return { token, host };
}

interface MixpanelEvent { event: string; properties: Record<string, unknown> }

export class MixpanelAnalytics implements Analytics {
  private queue: MixpanelEvent[] = [];
  private sending: Promise<void> | null = null;
  private timer: ReturnType<typeof setInterval>;
  private queueFullLogged = false;
  private readonly url: string;
  private readonly auth: string;
  private readonly batchSize: number;
  private readonly timeoutMs: number;
  private readonly retryDelayMs: number;
  private readonly maxQueue: number;
  private readonly fetch: typeof fetch;
  private readonly log: (line: string) => void;
  private readonly now: () => number;

  constructor(cfg: MixpanelConfig) {
    this.url = `${cfg.host}/import?strict=1`;
    // /import 接受项目令牌作 Basic 认证的用户名、密码留空（不带 project_id）。
    this.auth = 'Basic ' + Buffer.from(cfg.token + ':').toString('base64');
    this.batchSize = cfg.batchSize ?? BATCH_SIZE;
    this.timeoutMs = cfg.timeoutMs ?? TIMEOUT_MS;
    this.retryDelayMs = cfg.retryDelayMs ?? RETRY_DELAY_MS;
    this.maxQueue = cfg.maxQueue ?? MAX_QUEUE;
    this.fetch = cfg.fetch ?? globalThis.fetch;
    this.log = cfg.log ?? (line => console.warn(line));
    this.now = cfg.now ?? (() => Date.now());
    this.timer = setInterval(() => { void this.flush(); }, cfg.flushMs ?? FLUSH_MS);
    this.timer.unref();
  }

  track(event: string, userId: string | null | undefined, props: Record<string, unknown> = {}, opts: { time?: number; insertId?: string } = {}): void {
    if (!userId) return;
    try {
      if (this.queue.length >= this.maxQueue) {
        if (!this.queueFullLogged) { this.queueFullLogged = true; this.log(`[analytics] queue full (${this.maxQueue}), dropping new events`); }
        return;
      }
      this.queue.push({ event, properties: { ...props, time: opts.time ?? this.now(), distinct_id: userId, $insert_id: opts.insertId ?? randomUUID(), ip: 0 } });
      if (this.queue.length >= this.batchSize) void this.flush();
    } catch { /* 上报永不打断玩家请求 */ }
  }

  flush(): Promise<void> {
    this.sending ??= this.drain().finally(() => { this.sending = null; });
    return this.sending;
  }

  async close(): Promise<void> {
    clearInterval(this.timer);
    await this.flush();
  }

  private async drain(): Promise<void> {
    while (this.queue.length) {
      await this.send(this.queue.splice(0, this.batchSize));
      this.queueFullLogged = false;
    }
  }

  /** 发一批：失败（超时、网络错、429、5xx）最多重试一次；还不行或其它 4xx 就丢掉这批，只记日志。从不抛错。 */
  private async send(batch: MixpanelEvent[]): Promise<void> {
    const body = JSON.stringify(batch);
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt) await new Promise(resolve => setTimeout(resolve, this.retryDelayMs));
      let retry = true;
      try {
        const res = await this.fetch(this.url, { method: 'POST', body, signal: AbortSignal.timeout(this.timeoutMs),
          headers: { 'content-type': 'application/json', accept: 'application/json', authorization: this.auth } });
        if (res.ok) return;
        retry = res.status === 429 || res.status >= 500;
        this.log(`[analytics] mixpanel import answered ${res.status}: ${(await res.text().catch(() => '')).slice(0, 300)}`);
      } catch (error) {
        this.log(`[analytics] mixpanel import failed: ${(error as Error).message}`);
      }
      if (!retry) break;
    }
    this.log(`[analytics] dropped ${batch.length} events`);
  }
}

/** 进程入口用：配置了就建 Mixpanel 上报，否则 NO_ANALYTICS。 */
export const createAnalytics = (cfg: MixpanelConfig | null): Analytics => cfg ? new MixpanelAnalytics(cfg) : NO_ANALYTICS;
